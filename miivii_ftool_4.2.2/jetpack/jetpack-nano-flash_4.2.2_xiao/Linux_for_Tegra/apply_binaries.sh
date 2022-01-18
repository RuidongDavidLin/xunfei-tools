#!/bin/bash

# Copyright (c) 2011-2019, NVIDIA CORPORATION. All rights reserved.
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


#
# This script applies the binaries to the rootfs dir pointed to by
# LDK_ROOTFS_DIR variable.
#

set -e

# show the usages text
function ShowUsage {
    local ScriptName=$1

    echo "Use: $1 [--bsp|-b PATH] [--root|-r PATH] [--deb] [--help|-h]"
cat <<EOF
    This script installs tegra binaries
    Options are:
    --bsp|-b PATH
                   bsp location (bsp, readme, installer)
    --root|-r PATH
                   install toolchain to PATH
    --deb
                   only copy debian packages and scripts to rootfs
                   do not untar NVIDIA packages
    --help|-h
                   show this help
EOF
}

function ShowDebug {
    echo "SCRIPT_NAME     : $SCRIPT_NAME"
    echo "DEB_SCRIPT_NAME : $DEB_SCRIPT_NAME"
    echo "LDK_ROOTFS_DIR  : $LDK_ROOTFS_DIR"
    echo "BOARD_NAME      : $TARGET_BOARD"
}

function ReplaceText {
	sed -i "s/$2/$3/" $1
	if [ $? -ne 0 ]; then
		echo "Error while editing a file. Exiting !!"
		exit 1
	fi
}
# if the user is not root, there is not point in going forward
THISUSER=`whoami`
if [ "x$THISUSER" != "xroot" ]; then
    echo "This script requires root privilege"
    exit 1
fi

# script name
SCRIPT_NAME=`basename $0`

# apply .deb script name
DEB_SCRIPT_NAME="nv-apply-debs.sh"

# empty root and no debug
DEBUG=

# parse the command line first
TGETOPT=`getopt -n "$SCRIPT_NAME" --longoptions help,bsp:,debug,deb,root: -o b:dhr:b:t: -- "$@"`

if [ $? != 0 ]; then
    echo "Terminating... wrong switch"
    ShowUsage "$SCRIPT_NAME"
    exit 1
fi

eval set -- "$TGETOPT"

while [ $# -gt 0 ]; do
    case "$1" in
	-r|--root) LDK_ROOTFS_DIR="$2"; shift ;;
	-h|--help) ShowUsage "$SCRIPT_NAME"; exit 1 ;;
	-d|--debug) DEBUG="true" ;;
	--deb) DEBIAN="true" ;;
	-b|--bsp) BSP_LOCATION_DIR="$2"; shift ;;
	--) shift; break ;;
	-*) echo "Terminating... wrong switch: $@" >&2 ; ShowUsage "$SCRIPT_NAME"; exit 1 ;;
    esac
    shift
done

if [ $# -gt 0 ]; then
    ShowUsage "$SCRIPT_NAME"
    exit 1
fi

# done, now do the work, save the directory
LDK_DIR=$(cd `dirname $0` && pwd)

# use default rootfs dir if none is set
if [ -z "$LDK_ROOTFS_DIR" ]; then
    LDK_ROOTFS_DIR="${LDK_DIR}/rootfs"
fi

echo "Using rootfs directory of: ${LDK_ROOTFS_DIR}"

install -o 0 -g 0 -m 0755 -d "${LDK_ROOTFS_DIR}"

# get the absolute path, for LDK_ROOTFS_DIR.
# otherwise, tar behaviour is unknown in last command sets
TOP=$PWD
cd "$LDK_ROOTFS_DIR"
LDK_ROOTFS_DIR="$PWD"
cd "$TOP"

if [ ! `find "$LDK_ROOTFS_DIR/etc/passwd" -group root -user root` ]; then
	echo "||||||||||||||||||||||| ERROR |||||||||||||||||||||||"
	echo "-----------------------------------------------------"
	echo "1. The root filesystem, provided with this package,"
	echo "   has to be extracted to this directory:"
	echo "   ${LDK_ROOTFS_DIR}"
	echo "-----------------------------------------------------"
	echo "2. The root filesystem, provided with this package,"
	echo "   has to be extracted with 'sudo' to this directory:"
	echo "   ${LDK_ROOTFS_DIR}"
	echo "-----------------------------------------------------"
	echo "Consult the Development Guide for instructions on"
	echo "extracting and flashing your device."
	echo "|||||||||||||||||||||||||||||||||||||||||||||||||||||"
	exit 1
fi

# assumption: this script is part of the BSP
#             so, LDK_DIR/nv_tegra always exist
LDK_NV_TEGRA_DIR="${LDK_DIR}/nv_tegra"
LDK_KERN_DIR="${LDK_DIR}/kernel"
LDK_BOOTLOADER_DIR="${LDK_DIR}/bootloader"

if [ "${DEBIAN}" = "true" ]; then
	if [ -f "${LDK_NV_TEGRA_DIR}/${DEB_SCRIPT_NAME}" ]; then
		echo "${LDK_NV_TEGRA_DIR}/${DEB_SCRIPT_NAME}";
		eval "${LDK_NV_TEGRA_DIR}/${DEB_SCRIPT_NAME} -r ${LDK_ROOTFS_DIR}";
	else
		echo "The --deb option is currently not supported"
		exit 1
	fi
else
	echo "Extracting the NVIDIA user space components to ${LDK_ROOTFS_DIR}"
	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
	tar -I lbzip2 -xpmf ${LDK_NV_TEGRA_DIR}/nvidia_drivers.tbz2

	# On t210ref create sym-links for gpu fw loading. On < k4.4 it used
	#    /lib/firmware/tegra21x/
	# but on k4.4 and later it is using:
	#    /lib/firmware/gm20b/
	# T186 doesn't have this problem as we only supported from k4.4 forward
	# but we'll need to keep this section for the l4t binaries on t210
	if [ -d "lib/firmware/tegra21x/" ]; then
		echo "Creating t210 gm20b symbolic links..."
		GM20B_DIR="${LDK_ROOTFS_DIR}/lib/firmware/gm20b/"
		install -o 0 -g 0 -m 0755 -d "${GM20B_DIR}"
		pushd "${GM20B_DIR}" > /dev/null 2>&1
		ln -sf "../tegra21x/acr_ucode.bin" "acr_ucode.bin"
		ln -sf "../tegra21x/gpmu_ucode.bin" "gpmu_ucode.bin"
		ln -sf "../tegra21x/gpmu_ucode_desc.bin" \
				"gpmu_ucode_desc.bin"
		ln -sf "../tegra21x/gpmu_ucode_image.bin" \
				"gpmu_ucode_image.bin"
		ln -sf "../tegra21x/gpu2cde.bin" \
				"gpu2cde.bin"
		ln -sf "../tegra21x/NETB_img.bin" "NETB_img.bin"
		ln -sf "../tegra21x/fecs_sig.bin" "fecs_sig.bin"
		ln -sf "../tegra21x/pmu_sig.bin" "pmu_sig.bin"
		ln -sf "../tegra21x/pmu_bl.bin" "pmu_bl.bin"
		ln -sf "../tegra21x/fecs.bin" "fecs.bin"
		ln -sf "../tegra21x/gpccs.bin" "gpccs.bin"
		popd > /dev/null
	fi
	popd > /dev/null 2>&1

	echo "Extracting the BSP test tools to ${LDK_ROOTFS_DIR}"
	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
	tar -I lbzip2 -xpmf ${LDK_NV_TEGRA_DIR}/nv_tools.tbz2
	popd > /dev/null 2>&1

	echo "Extracting the NVIDIA gst test applications to ${LDK_ROOTFS_DIR}"
	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
	tar -I lbzip2 -xpmf ${LDK_NV_TEGRA_DIR}/nv_sample_apps/nvgstapps.tbz2
	popd > /dev/null 2>&1

	echo "Extracting Weston to ${LDK_ROOTFS_DIR}"
	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
	tar -I lbzip2 -xpmf "${LDK_NV_TEGRA_DIR}/weston.tbz2"
	popd > /dev/null 2>&1

	echo "Extracting the configuration files for the supplied root filesystem to ${LDK_ROOTFS_DIR}"
	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
	tar -I lbzip2 -xpmf ${LDK_NV_TEGRA_DIR}/config.tbz2
	popd > /dev/null 2>&1

	echo "Extracting graphics_demos to ${LDK_ROOTFS_DIR}"
	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
	tar -I lbzip2 -xpmf "${LDK_NV_TEGRA_DIR}/graphics_demos.tbz2"
	popd > /dev/null 2>&1

	echo "Extracting the firmwares and kernel modules to ${LDK_ROOTFS_DIR}"
	( cd "${LDK_ROOTFS_DIR}" ; tar -I lbzip2 -xpmf "${LDK_KERN_DIR}/kernel_supplements.tbz2" )

	echo "Extracting the kernel headers to ${LDK_ROOTFS_DIR}/usr/src"
	# The kernel headers package can be used on the target device as well as on another host.
	# When used on the target, it should go into /usr/src and owned by root.
	# Note that there are multiple linux-headers-* directories; one for use on an
	# x86-64 Linux host and one for use on the L4T target.
	EXTMOD_DIR=ubuntu18.04_aarch64
	KERNEL_HEADERS_A64_DIR="$(tar tf "${LDK_KERN_DIR}/kernel_headers.tbz2" | grep "${EXTMOD_DIR}" | head -1 | cut -d/ -f1)"
	KERNEL_VERSION="$(echo "${KERNEL_HEADERS_A64_DIR}" | sed -e "s/linux-headers-//" -e "s/-${EXTMOD_DIR}//")"
	KERNEL_SUBDIR="kernel-$(echo "${KERNEL_VERSION}" | cut -d. -f1-2)"
	install -o 0 -g 0 -m 0755 -d "${LDK_ROOTFS_DIR}/usr/src"
	pushd "${LDK_ROOTFS_DIR}/usr/src" > /dev/null 2>&1
	# This tar is packaged for the host (all files 666, dirs 777) so that when
	# extracted on the host, the user's umask controls the permissions.
	# However, we're now installing it into the rootfs, and hence need to
	# explicitly set and use the umask to achieve the desired permissions.
	(umask 022 && tar -I lbzip2 --no-same-permissions -xmf "${LDK_KERN_DIR}/kernel_headers.tbz2")
	# Link to the kernel headers from /lib/modules/<version>/build
	KERNEL_MODULES_DIR="${LDK_ROOTFS_DIR}/lib/modules/${KERNEL_VERSION}"
	if [ -d "${KERNEL_MODULES_DIR}" ]; then
		echo "Adding symlink ${KERNEL_MODULES_DIR}/build --> /usr/src/${KERNEL_HEADERS_A64_DIR}/${KERNEL_SUBDIR}"
		[ -h "${KERNEL_MODULES_DIR}/build" ] && unlink "${KERNEL_MODULES_DIR}/build" && rm -f "${KERNEL_MODULES_DIR}/build"
		[ ! -h "${KERNEL_MODULES_DIR}/build" ] && ln -s "/usr/src/${KERNEL_HEADERS_A64_DIR}/${KERNEL_SUBDIR}" "${KERNEL_MODULES_DIR}/build"
	fi
	popd > /dev/null

	if [ -e "${LDK_KERN_DIR}/zImage" ]; then
		echo "Installing zImage into /boot in target rootfs"
		install --owner=root --group=root --mode=644 -D "${LDK_KERN_DIR}/zImage" "${LDK_ROOTFS_DIR}/boot/zImage"
	fi

	if [ -e "${LDK_KERN_DIR}/Image" ]; then
		echo "Installing Image into /boot in target rootfs"
		install --owner=root --group=root --mode=644 -D "${LDK_KERN_DIR}/Image" "${LDK_ROOTFS_DIR}/boot/Image"
	fi

	echo "Installing the board *.dtb files into /boot in target rootfs"
	install -o 0 -g 0 -m 0755 -d "${LDK_ROOTFS_DIR}"/boot
	cp -a "${LDK_KERN_DIR}"/dtb/*.dtb "${LDK_ROOTFS_DIR}/boot"
fi

echo "Creating a symbolic link nvgstplayer pointing to nvgstplayer-1.0"
pushd "${LDK_ROOTFS_DIR}/usr/bin/" > /dev/null 2>&1
if [ -h "nvgstplayer" ] || [ -e "nvgstplayer" ]; then
	rm -f nvgstplayer
fi
ln -s "nvgstplayer-1.0" "nvgstplayer"
popd > /dev/null

echo "Creating a symbolic link nvgstcapture pointing to nvgstcapture-1.0"
pushd "${LDK_ROOTFS_DIR}/usr/bin/" > /dev/null 2>&1
if [ -h "nvgstcapture" ] || [ -e "nvgstcapture" ]; then
	rm -f nvgstcapture
fi
ln -s "nvgstcapture-1.0" "nvgstcapture"
popd > /dev/null

ARM_ABI_DIR=

if [ -d "${LDK_ROOTFS_DIR}/usr/lib/arm-linux-gnueabihf/tegra" ]; then
	ARM_ABI_DIR_ABS="usr/lib/arm-linux-gnueabihf"
elif [ -d "${LDK_ROOTFS_DIR}/usr/lib/arm-linux-gnueabi/tegra" ]; then
	ARM_ABI_DIR_ABS="usr/lib/arm-linux-gnueabi"
elif [ -d "${LDK_ROOTFS_DIR}/usr/lib/aarch64-linux-gnu/tegra" ]; then
	ARM_ABI_DIR_ABS="usr/lib/aarch64-linux-gnu"
else
	echo "Error: None of Hardfp/Softfp Tegra libs found"
	exit 4
fi

ARM_ABI_DIR="${LDK_ROOTFS_DIR}/${ARM_ABI_DIR_ABS}"
ARM_ABI_TEGRA_DIR="${ARM_ABI_DIR}/tegra"
VULKAN_ICD_DIR="${LDK_ROOTFS_DIR}/etc/vulkan/icd.d"
LIBGLVND_EGL_VENDOR_DIR="${LDK_ROOTFS_DIR}/usr/share/glvnd/egl_vendor.d"

# Create symlinks to satisfy applications trying to link unversioned libraries during runtime
pushd "${ARM_ABI_TEGRA_DIR}" > /dev/null 2>&1
echo "Adding symlink libcuda.so --> libcuda.so.1.1 in target rootfs"
ln -sf "libcuda.so.1.1" "libcuda.so"
echo "Adding symlink libnvbuf_utils.so --> libnvbuf_utils.so.1.0.0 in target rootfs"
ln -sf "libnvbuf_utils.so.1.0.0" "libnvbuf_utils.so"
echo "Adding symlink libnvid_mapper.so --> libnvid_mapper.so.1.0.0 in target rootfs"
ln -sf "libnvid_mapper.so.1.0.0" "libnvid_mapper.so"
echo "Adding symlink libnvbufsurface.so --> libnvbufsurface.so.1.0.0 in target rootfs"
ln -sf "libnvbufsurface.so.1.0.0" "libnvbufsurface.so"
echo "Adding symlink libnvbufsurftransform.so --> libnvbufsurftransform.so.1.0.0 in target rootfs"
ln -sf "libnvbufsurftransform.so.1.0.0" "libnvbufsurftransform.so"
popd > /dev/null

pushd "${ARM_ABI_DIR}" > /dev/null 2>&1
echo "Adding symlink libcuda.so --> tegra/libcuda.so in target rootfs"
ln -sf "tegra/libcuda.so" "libcuda.so"
popd > /dev/null

pushd "${ARM_ABI_DIR}" > /dev/null 2>&1
echo "Adding symlink ${ARM_ABI_DIR}/libdrm_nvdc.so --> ${ARM_ABI_TEGRA_DIR}/libdrm.so.2"
ln -sf "tegra/libdrm.so.2" "libdrm_nvdc.so"
popd > /dev/null

install -o 0 -g 0 -m 0755 -d "${VULKAN_ICD_DIR}"
echo "Adding symlink nvidia_icd.json --> /etc/vulkan/icd.d/nvidia_icd.json in target rootfs"
pushd "${VULKAN_ICD_DIR}" > /dev/null 2>&1
ln -sf "../../../${ARM_ABI_DIR_ABS}/tegra/nvidia_icd.json" "nvidia_icd.json"
popd > /dev/null

sudo mkdir -p "${LIBGLVND_EGL_VENDOR_DIR}"
echo "Adding symlink nvidia.json --> /usr/share/glvnd/egl_vendor.d/10_nvidia.json in target rootfs"
pushd "${LIBGLVND_EGL_VENDOR_DIR}" > /dev/null 2>&1
sudo ln -sf "../../../../${ARM_ABI_DIR_ABS}/tegra-egl/nvidia.json" "10_nvidia.json"
popd > /dev/null

echo "Creating symlinks for weston, wayland-demos, libinput and wayland-ivi-extention modules"
install -o 0 -g 0 -m 0755 -d "${ARM_ABI_DIR}/weston/"
pushd "${ARM_ABI_DIR}/weston/" > /dev/null 2>&1
if [ -e "../tegra/weston/desktop-shell.so" ]; then
	ln -sf "../tegra/weston/desktop-shell.so" "desktop-shell.so"
fi

if [ -e "../tegra/weston/gl-renderer.so" ]; then
	ln -sf "../tegra/weston/gl-renderer.so" "gl-renderer.so"
fi

if [ -e "../tegra/weston/drm-backend.so" ]; then
	ln -sf "../tegra/weston/drm-backend.so" "drm-backend.so"
fi

if [ -e "../tegra/weston/eglstream-backend.so" ]; then
	ln -sf "../tegra/weston/eglstream-backend.so" "eglstream-backend.so"
fi

if [ -e "../tegra/weston/hmi-controller.so" ]; then
	ln -sf "../tegra/weston/hmi-controller.so" "hmi-controller.so"
fi

if [ -e "../tegra/weston/ivi-controller.so" ]; then
	ln -sf "../tegra/weston/ivi-controller.so" "ivi-controller.so"
fi

if [ -e "../tegra/weston/ivi-shell.so" ]; then
	ln -sf "../tegra/weston/ivi-shell.so" "ivi-shell.so"
fi

if [ -e "../tegra/weston/wayland-backend.so" ]; then
	ln -sf "../tegra/weston/wayland-backend.so" "wayland-backend.so"
fi

popd > /dev/null

pushd "${ARM_ABI_DIR}" > /dev/null 2>&1
if [ -e "tegra/weston/libilmClient.so.2.0.0" ]; then
	ln -sf "tegra/weston/libilmClient.so.2.0.0" "libilmClient.so.2.0.0"
fi

if [ -e "tegra/weston/libilmCommon.so.2.0.0" ]; then
	ln -sf "tegra/weston/libilmCommon.so.2.0.0" "libilmCommon.so.2.0.0"
fi

if [ -e "tegra/weston/libilmControl.so.2.0.0" ]; then
	ln -sf "tegra/weston/libilmControl.so.2.0.0" "libilmControl.so.2.0.0"
fi

if [ -e "tegra/weston/libilmInput.so.2.0.0" ]; then
	ln -sf "tegra/weston/libilmInput.so.2.0.0" "libilmInput.so.2.0.0"
fi

if [ -e "tegra/weston/libinput.so.10.10.1" ]; then
	ln -sf "tegra/weston/libinput.so.10.10.1" "libinput.so.10.10.1"
fi
popd > /dev/null

install -o 0 -g 0 -m 0755 -d "${LDK_ROOTFS_DIR}/usr/lib/weston"
pushd "${LDK_ROOTFS_DIR}/usr/lib/weston" > /dev/null 2>&1
if [ -e "../../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-desktop-shell" ]; then
	ln -sf "../../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-desktop-shell" "weston-desktop-shell"
fi

if [ -e "../../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-keyboard" ]; then
	ln -sf "../../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-keyboard" "weston-keyboard"
fi

if [ -e "../../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-screenshooter" ]; then
	ln -sf "../../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-screenshooter" "weston-screenshooter"
fi
popd > /dev/null

pushd "${LDK_ROOTFS_DIR}/usr/bin/" > /dev/null 2>&1
if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/EGLWLInputEventExample" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/EGLWLInputEventExample" "EGLWLInputEventExample"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/EGLWLMockNavigation" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/EGLWLMockNavigation" "EGLWLMockNavigation"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/LayerManagerControl" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/LayerManagerControl" "LayerManagerControl"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/spring-tool" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/spring-tool" "spring-tool"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston" "weston"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-calibrator" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-calibrator" "weston-calibrator"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-clickdot" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-clickdot" "weston-clickdot"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-cliptest" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-cliptest" "weston-cliptest"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-dnd" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-dnd" "weston-dnd"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-eventdemo" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-eventdemo" "weston-eventdemo"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-flower" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-flower" "weston-flower"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-fullscreen" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-fullscreen" "weston-fullscreen"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-image" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-image" "weston-image"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-info" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-info" "weston-info"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-ivi-shell-user-interface" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-ivi-shell-user-interface" "weston-ivi-shell-user-interface"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-launch" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-launch" "weston-launch"
	chmod "+s" "weston-launch"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-multi-resource" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-multi-resource" "weston-multi-resource"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-resizor" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-resizor" "weston-resizor"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-scaler" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-scaler" "weston-scaler"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-simple-egl" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-simple-egl" "weston-simple-egl"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-simple-shm" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-simple-shm" "weston-simple-shm"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-simple-touch" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-simple-touch" "weston-simple-touch"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-smoke" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-smoke" "weston-smoke"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-stacking" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-stacking" "weston-stacking"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-subsurfaces" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-subsurfaces" "weston-subsurfaces"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-terminal" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-terminal" "weston-terminal"
fi

if [ -e "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-transformed" ]; then
	ln -sf "../../${ARM_ABI_DIR_ABS}/tegra/weston/weston-transformed" "weston-transformed"
fi
popd > /dev/null

if [ -e "${ARM_ABI_DIR}/libglfw.so.3.3" ]; then
	pushd "${ARM_ABI_DIR}" > /dev/null 2>&1
	echo "Adding symlink libglfw.so --> libglfw.so.3.3"
	ln -sf "libglfw.so.3.3" "libglfw.so"
	echo "Adding symlink libglfw.so.3 --> libglfw.so.3.3"
	ln -sf "libglfw.so.3.3" "libglfw.so.3"
	popd > /dev/null
fi

if [ -e "${LDK_ROOTFS_DIR}/usr/share/lightdm/lightdm.conf.d/50-ubuntu.conf" ]; then
	pushd "${LDK_ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants" > /dev/null 2>&1
	if [ -f ${LDK_ROOTFS_DIR}/etc/systemd/system/nvpmodel.service ]; then
		ln -sf "../nvpmodel.service" "nvpmodel.service"
	fi
	popd > /dev/null
fi

echo "Adding symlinks for NVIDIA systemd services"
install -o 0 -g 0 -m 0755 -d "${LDK_ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants"
pushd "${LDK_ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants" > /dev/null 2>&1
ln -sf "/opt/nvidia/l4t-usb-device-mode/nv-l4t-usb-device-mode.service" "nv-l4t-usb-device-mode.service"
if [ -f "${LDK_ROOTFS_DIR}/opt/nvidia/l4t-bootloader-config/nv-l4t-bootloader-config.service" ]; then
	ln -sf "/opt/nvidia/l4t-bootloader-config/nv-l4t-bootloader-config.service" "nv-l4t-bootloader-config.service"
fi
if [ -h "isc-dhcp-server.service" ]; then
	rm -f "isc-dhcp-server.service"
fi
if [ -h "isc-dhcp-server6.service" ]; then
	rm -f "isc-dhcp-server6.service"
fi
ln -sf "../nvargus-daemon.service" "nvargus-daemon.service"
ln -sf "../nvs-service.service" "nvs-service.service"
ln -sf "../nvfb.service" "nvfb.service"
ln -sf "../nvfb-early.service" "nvfb-early.service"
ln -sf "../nv.service" "nv.service"
if [ -f "../nv_update_verifier.service" ]; then
	ln -sf "../nv_update_verifier.service" "nv_update_verifier.service"
fi
ln -sf "../nvphs.service" "nvphs.service"
if [ -f "../nvresizefs.service" ]; then
	ln -sf "../nvresizefs.service" "nvresizefs.service"
fi
if [ -f "../nvuser.service" ]; then
	ln -sf "../nvuser.service" "nvuser.service"
fi
if [ -f "../nvgetty.service" ]; then
	ln -sf "../nvgetty.service" "nvgetty.service"
fi
if [ -f "../nvmemwarning.service" ]; then
	ln -sf "../nvmemwarning.service" "nvmemwarning.service"
fi
if [ -f "../nvweston.service" ]; then
	ln -sf "../nvweston.service" "nvweston.service"
fi
if [ -f "../nvzramconfig.service" ]; then
	ln -sf "../nvzramconfig.service" "nvzramconfig.service"
fi
popd > /dev/null
install -o 0 -g 0 -m 0755 -d "${LDK_ROOTFS_DIR}/etc/systemd/system/getty.target.wants"
pushd "${LDK_ROOTFS_DIR}/etc/systemd/system/getty.target.wants" > /dev/null 2>&1
ln -sf "/lib/systemd/system/serial-getty@.service" "serial-getty@ttyGS0.service"
popd > /dev/null
pushd "${LDK_ROOTFS_DIR}/etc/systemd/system" > /dev/null 2>&1
ln -sf "/opt/nvidia/l4t-usb-device-mode/nv-l4t-usb-device-mode.service" "nv-l4t-usb-device-mode.service"
ln -sf "/opt/nvidia/l4t-usb-device-mode/nv-l4t-usb-device-mode-runtime.service" "nv-l4t-usb-device-mode-runtime.service"
popd > /dev/null


# Enable Unity by default for better user experience [2332219]
echo "Rename ubuntu.desktop --> ux-ubuntu.desktop"
if [ -d "${LDK_ROOTFS_DIR}/usr/share/xsessions" ]; then
	pushd "${LDK_ROOTFS_DIR}/usr/share/xsessions" > /dev/null 2>&1
	if [ -f "ubuntu.desktop" ]; then
		mv "ubuntu.desktop" "ux-ubuntu.desktop"
	fi
	popd > /dev/null
fi

if [ -e "${LDK_ROOTFS_DIR}/usr/share/lightdm/lightdm.conf.d/50-ubuntu.conf" ]; then
	ReplaceText "${LDK_ROOTFS_DIR}/usr/share/lightdm/lightdm.conf.d/50-ubuntu.conf" \
			"autologin-user=ubuntu" "autologin-user=nvidia";
	if [ -e "${LDK_ROOTFS_DIR}/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf" ]; then
		ReplaceText "${LDK_ROOTFS_DIR}/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf" \
			"ubuntu" "nvidia";
	fi

	if [ -e "${LDK_ROOTFS_DIR}/etc/systemd/system/serial-getty@ttyTCU0.service.d/autologin.conf" ]; then
		ReplaceText "${LDK_ROOTFS_DIR}/etc/systemd/system/serial-getty@ttyTCU0.service.d/autologin.conf" \
			"ubuntu" "nvidia";
	fi

	grep -q -F 'allow-guest=false' \
		"${LDK_ROOTFS_DIR}/usr/share/lightdm/lightdm.conf.d/50-ubuntu.conf" \
		|| echo 'allow-guest=false' \
		>> "${LDK_ROOTFS_DIR}/usr/share/lightdm/lightdm.conf.d/50-ubuntu.conf"
fi

# test if installation comes with systemd-gpt-auto-generator. If so, disable it
# this is a WAR for https://bugs.launchpad.net/ubuntu/+source/systemd/+bug/1783994
# systemd spams log with "Failed to dissect: Input/output error" on systems with mmc
if [ -e "${LDK_ROOTFS_DIR}/lib/systemd/system-generators/systemd-gpt-auto-generator" ]; then
	if [ ! -d "${LDK_ROOTFS_DIR}/etc/systemd/system-generators" ]; then
		mkdir "${LDK_ROOTFS_DIR}/etc/systemd/system-generators"
	fi
	# this is the way to disable systemd unit auto generators by
	# symlinking the generator to null in corresponding path in /etc
	ln -sf /dev/null "${LDK_ROOTFS_DIR}/etc/systemd/system-generators/systemd-gpt-auto-generator"
fi

echo "Copying USB device mode filesystem image to ${LDK_ROOTFS_DIR}"
install -o 0 -g 0 -m 0755 -d "${LDK_ROOTFS_DIR}/opt/nvidia/l4t-usb-device-mode"
cp "${LDK_NV_TEGRA_DIR}/l4t-usb-device-mode-filesystem.img" "${LDK_ROOTFS_DIR}/opt/nvidia/l4t-usb-device-mode/filesystem.img"

# Disabling NetworkManager-wait-online.service for Bug 200290321
echo "Disabling NetworkManager-wait-online.service"
if [ -h "${LDK_ROOTFS_DIR}/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service" ]; then
	rm "${LDK_ROOTFS_DIR}/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service"
fi

echo "Disable the ondemand service by changing the runlevels to 'K'"
for file in "${LDK_ROOTFS_DIR}"/etc/rc[0-9].d/; do
	if [ -f "${file}"/S*ondemand ]; then
		mv "${file}"/S*ondemand "${file}/K01ondemand"
	fi
done

# Remove the spawning of ondemand service
if [ -h "${LDK_ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/ondemand.service" ]; then
	rm -f "${LDK_ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/ondemand.service"
fi

# If default target does not exist and if rootfs contains gdm, set default to nv-oem-config target
if [ ! -e "${LDK_ROOTFS_DIR}/etc/systemd/system/default.target" ] && \
   [ -d "${LDK_ROOTFS_DIR}/etc/gdm3/" ]; then
	mkdir -p "${LDK_ROOTFS_DIR}/etc/systemd/system/nv-oem-config.target.wants"
	pushd "${LDK_ROOTFS_DIR}/etc/systemd/system/nv-oem-config.target.wants" > /dev/null 2>&1
	ln -sf /lib/systemd/system/nv-oem-config.service nv-oem-config.service
	ln -sf "/etc/systemd/system/nvfb-early.service" "nvfb-early.service"
	popd > /dev/null 2>&1
	pushd "${LDK_ROOTFS_DIR}/etc/systemd/system" > /dev/null 2>&1
	ln -sf /lib/systemd/system/nv-oem-config.target nv-oem-config.target
	ln -sf nv-oem-config.target default.target
	popd > /dev/null 2>&1

	extra_groups="EXTRA_GROUPS=\"audio video gdm weston-launch\""
	sed -i "/\<EXTRA_GROUPS\>=/ s/^.*/${extra_groups}/" \
		"${LDK_ROOTFS_DIR}/etc/adduser.conf"
	sed -i "/\<ADD_EXTRA_GROUPS\>=/ s/^.*/ADD_EXTRA_GROUPS=1/" \
		"${LDK_ROOTFS_DIR}/etc/adduser.conf"
fi

# Set default Autologin to 'nvidia' user for GDM3 display manager.
if [ -e "${LDK_ROOTFS_DIR}/etc/gdm3/custom.conf" ]; then
	sed -i "/WaylandEnable=false/ s/^#//" "${LDK_ROOTFS_DIR}/etc/gdm3/custom.conf"
fi

if [ -f "${LDK_BOOTLOADER_DIR}/extlinux.conf" ]; then
	echo "Installing extlinux.conf into /boot/extlinux in target rootfs"
	mkdir -p "${LDK_ROOTFS_DIR}/boot/extlinux/"
	install --owner=root --group=root --mode=644 -D "${LDK_BOOTLOADER_DIR}/extlinux.conf" "${LDK_ROOTFS_DIR}/boot/extlinux/"
fi

# Remove any 'asound.state' because this file will be device/board specific and so
# should not be populated. Furthermore, this file will be automatically created by
# the systemd ALSA restore service on shutdown.
if [ -f "${LDK_ROOTFS_DIR}/var/lib/alsa/asound.state" ]; then
	rm -f "${LDK_ROOTFS_DIR}/var/lib/alsa/asound.state"
fi

echo "Success!"
