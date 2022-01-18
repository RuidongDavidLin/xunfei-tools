#!/bin/bash

# Copyright (c) 2019, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#  * Neither the name of NVIDIA CORPORATION nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# This is a script to generate the SD card flashable image for
# jetson-nano platform

set -e

function usage()
{
	if [ -n "${1}" ]; then
		echo "${1}"
	fi

	echo "Usage:"
	echo "${script_name} -o <sd_blob_name> -s <sd_blob_size> -r <revision>"
	echo "	sd_blob_name	- valid file name"
	echo "	sd_blob_size	- can be specified with G/M/K/B"
	echo "			- size with no unit will be B"
	echo "	revision	- SKU revision number"
	echo "Example:"
	echo "${script_name} -o sd-blob.img -s 4G -r 100"
	echo "${script_name} -o sd-blob.img -s 4096M -r 200"
	exit 1
}

function cleanup() {
	set +e
	if [ -n "${tmpdir}" ]; then
		umount "${tmpdir}"
		rmdir "${tmpdir}"
	fi

	if [ -n "${loop_dev}" ]; then
		losetup -d "${loop_dev}"
	fi
}
trap cleanup EXIT

function check_pre_req()
{
	this_user="$(whoami)"
	if [ "${this_user}" != "root" ]; then
		echo "ERROR: This script requires root privilege" > /dev/stderr
		usage
		exit 1
	fi

	while [ -n "${1}" ]; do
		case "${1}" in
		-h | --help)
			usage
			;;
		-o | --outname)
			[ -n "${2}" ] || usage "Not enough parameters"
			sd_blob_name="${2}"
			shift 2
			;;
		-r | --revision)
			[ -n "${2}" ] || usage "Not enough parameters"
			rev="${2}"
			shift 2
			;;
		-s | --size)
			[ -n "${2}" ] || usage "Not enough parameters"
			sd_blob_size="${2}"
			shift 2
			;;
		*)
			usage "Unknown option: ${1}"
			;;
		esac
	done

	case "${rev}" in
	"100")
		dtb_id="a01"
		;;
	"200")
		dtb_id="a02"
		;;
	"300")
		dtb_id="b00"
		;;
	*)
		usage "Incorrect Revision - Supported revisions - 100, 200, 300"
		;;
	esac

	if [ "${sd_blob_name}" == "" ]; then
		echo "ERROR: Invalid SD blob image name" > /dev/stderr
		usage
	fi

	if [ "${sd_blob_size}" == "" ]; then
		echo "ERROR: Invalid SD blob size" > /dev/stderr
		usage
	fi

	if [ ! -f "${l4t_dir}/flash.sh" ]; then
		echo "ERROR: ${l4t_dir}/flash.sh is not found" > /dev/stderr
		usage
	fi

	if [ ! -d "${bootloader_dir}" ]; then
		echo "ERROR: ${bootloader_dir} directory not found" > /dev/stderr
		usage
	fi

	if [ ! -d "${rfs_dir}" ]; then
		echo "ERROR: ${rfs_dir} directory not found" > /dev/stderr
		usage
	fi
}

function create_raw_image()
{
	echo "${script_name} - creating ${sd_blob_name} of ${sd_blob_size}..."
	dd if=/dev/zero of="${sd_blob_name}" bs=1 count=0 seek="${sd_blob_size}"
}

function create_signed_images()
{
	echo "${script_name} - creating signed images"

	# Generate flashcmd.txt for signing images
	BOARDID="3448" FAB="${rev}" "${l4t_dir}/flash.sh" "--no-flash" "--no-systemimg" "p3448-0000-sd" "mmcblk0p1"

	if [ ! -f "${bootloader_dir}/flashcmd.txt" ]; then
		echo "ERROR: ${bootloader_dir}/flashcmd.txt not found" > /dev/stderr
		exit 1
	fi

	# Generate signed images
	sed -i 's/flash; reboot/sign/g' "${l4t_dir}/bootloader/flashcmd.txt"
	pushd "${bootloader_dir}" > /dev/null 2>&1
	bash ./flashcmd.txt
	popd > /dev/null

	if [ ! -d "${signed_image_dir}" ]; then
		echo "ERROR: ${bootloader_dir}/signed directory not found" > /dev/stderr
		exit 1
	fi
}

function create_partitions()
{
	echo "${script_name} - create partitions"

	partitions=(\
		'part_num=2;part_name=TBC;part_size=131072;part_file=nvtboot_cpu.bin.encrypt' \
		'part_num=3;part_name=RP1;part_size=458752;part_file=tegra210-p3448-0000-p3449-0000-${dtb_id}.dtb.encrypt' \
		'part_num=4;part_name=EBT;part_size=589824;part_file=cboot.bin.encrypt' \
		'part_num=5;part_name=WB0;part_size=65536;part_file=warmboot.bin.encrypt' \
		'part_num=6;part_name=BPF;part_size=196608;part_file=sc7entry-firmware.bin.encrypt' \
		'part_num=7;part_name=TOS;part_size=589824;part_file=tos-mon-only.img.encrypt' \
		'part_num=8;part_name=EKS;part_size=65536;part_file=eks.img' \
		'part_num=9;part_name=LNX;part_size=655360;part_file=boot.img.encrypt' \
		'part_num=10;part_name=DTB;part_size=458752;part_file=tegra210-p3448-0000-p3449-0000-${dtb_id}.dtb.encrypt' \
		'part_num=11;part_name=RP4;part_size=131072;part_file=rp4.blob' \
		'part_num=12;part_name=BMP;part_size=81920;part_file=bmp.blob' \
		'part_num=1;part_name=APP;part_size=0;part_file='
	)

	part_type=8300 # Linux Filesystem

	sgdisk -og "${sd_blob_name}"
	for part in "${partitions[@]}"; do
		eval "${part}"
		part_size=$((${part_size} / 512)) # convert to sectors
		sgdisk -n "${part_num}":0:+"${part_size}" \
			-c "${part_num}":"${part_name}" \
			-t "${part_num}":"${part_type}" "${sd_blob_name}"
	done
}

function write_partitions()
{
	echo "${script_name} - write partitions"
	loop_dev="$(losetup --show -f -P "${sd_blob_name}")"
	tmpdir="$(mktemp -d)"

	for part in "${partitions[@]}"; do
		eval "${part}"
		target_file=""
		if [ "${part_name}" = "APP" ]; then
			echo "${script_name} - writing rootfs image"
			mkfs.ext4 -j "${loop_dev}p${part_num}"
			mount "${loop_dev}p${part_num}" "${tmpdir}"
			cp -a "${rfs_dir}"/* "${tmpdir}"
			umount "${tmpdir}"
		elif [ -e "${signed_image_dir}/${part_file}" ]; then
			target_file="${signed_image_dir}/${part_file}"
		elif [ -e "${bootloader_dir}/${part_file}" ]; then
			target_file="${bootloader_dir}/${part_file}"
		fi

		if [ "${target_file}" != "" ] && [ "${part_file}" != "" ]; then
			echo "${script_name} - writing ${target_file}"
			sudo dd if="${target_file}" of="${loop_dev}p${part_num}"
		fi
	done

	rmdir "${tmpdir}"
	losetup -d "${loop_dev}"
	tmpdir=""
	loop_dev=""
}

sd_blob_name=""
sd_blob_size=""
script_name="$(basename "${0}")"
l4t_dir="$(cd "$(dirname "${0}")" && pwd)"
if [ -z "${ROOTFS_DIR}" ]; then
	rfs_dir="${l4t_dir}/rootfs"
else
	rfs_dir="${ROOTFS_DIR}"
fi
bootloader_dir="${l4t_dir}/bootloader"
signed_image_dir="${bootloader_dir}/signed"
dtb_id="a02"
loop_dev=""
tmpdir=""

echo "********************************************"
echo "     Jetson-Nano SD Image Creation Tool     "
echo "********************************************"

check_pre_req "${@}"
create_raw_image
create_signed_images
create_partitions
write_partitions

echo "********************************************"
echo "   Jetson-Nano SD Image Creation Complete   "
echo "********************************************"
