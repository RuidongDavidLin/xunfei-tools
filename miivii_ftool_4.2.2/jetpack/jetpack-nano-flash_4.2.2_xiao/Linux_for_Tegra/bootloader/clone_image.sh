#!/bin/bash

NVIDIA_USB_ID=0955:7f21

# log path
LOGPATH=../../../../logs/

# create a folder for saving log
PID=$$
mkdir -p ${LOGPATH}${PID}
echo "start clone xiao"
echo "start clone with PID=${PID}"

## clone first device in background
##lsusb -d ${NVIDIA_USB_ID} | if IFS= read -r line
#lsusb -d ${NVIDIA_USB_ID}
dev_type=`lsusb -d ${NVIDIA_USB_ID}`
if [ -z "$dev_type" ]; then
    echo "******************************************************************" 
    echo "devices type mismatch or the devices did not enter recovery mode"
    echo "******************************************************************" 
    exit 1
fi
lsusb -d ${NVIDIA_USB_ID} > lsusb.txt 
if IFS= read -r line
then
	BUS=`echo $line | awk '{print $2}'`
	DEV=`echo $line | awk '{print $4}' | cut -d ':' -f 1`
	USB_INSTANCE=`echo /dev/bus/usb/${BUS}/${DEV}`
	rm -f ${LOGPATH}${PID}/clone_${BUS}_${DEV}.log
	CLONECMD=`cat clonecmd.txt`
	CMD="${CLONECMD} --cmd 'read APP $1.raw;' ; ./mksparse -v --fillpattern=0 '$1.raw' $1;rm -rf '$1.raw';"
	(eval ${CMD} > ${LOGPATH}${PID}/clone_${BUS}_${DEV}.log) &
	PROCESS_ID=$!
	echo ${PROCESS_ID} >>${LOGPATH}${PID}/pid.log
	echo "start cloning device: ${USB_INSTANCE}, process ID: ${PROCESS_ID}"
	TIMEOUT=0
	DEV_LOG=${LOGPATH}${PID}/clone_${BUS}_${DEV}.log
	while [ ${TIMEOUT} -lt 6 ]
	do
		cat ${LOGPATH}${PID}/clone_${BUS}_${DEV}.log | grep $1 2>&1 >/dev/null
		if [ $? == 0 ]; then
			sleep 4
			break;
		else
			sleep 1
			let "TIMEOUT=TIMEOUT+1"
		fi
	done
fi < lsusb.txt
 
## exit if pid file is not generated
if [ ! -e ${LOGPATH}${PID}/pid.log ]
then
	echo "no ongoing clone, exit"
	exit 1
fi

## print process info
PROCESS_NUM=`cat $LOGPATH$PID/pid.log | wc -l`
echo -n "${PROCESS_NUM} clone processes ongoing: "
while read process
do
	echo -n " ${process}"
	RESULT_LOG=`tail -n 5 $DEV_LOG`
	RESULT_ERROR1="Cannot Open USB"
	if [[ $RESULT_LOG =~ $RESULT_ERROR1 ]]
	then
  	 	echo "******************************************************************"
  	 	echo "clone processe "$PROCESS_ID":Clone failed"
   	 	echo "******************************************************************"
		exit 1
        fi
done < ${LOGPATH}${PID}/pid.log
echo

## wait clone processes done
PROCESS_NUM=`cat $LOGPATH$PID/pid.log | wc -l`
P_DONE=0
while [ ${P_DONE} -lt ${PROCESS_NUM} ]
do
	let "P_DONE=0"
	sleep 5
	echo -n "onging processes:"
	while read process
	do
		if [ -e /proc/${process} ]
		then
			echo -n " ${process}"
		else
			let "P_DONE=P_DONE+1"
		fi
	done < ${LOGPATH}${PID}/pid.log
	echo -n "......["`date +%T`"]"
	echo
done
RESULT_LOG=`tail -n 3 $DEV_LOG`
RESULT_COMPLETED="100%"
if [[ $RESULT_LOG =~ $RESULT_COMPLETED ]]
then
    echo "******************************************************************"
    echo "clone processe "$PROCESS_ID":Clone completed"
    echo "******************************************************************"
else
    echo "******************************************************************"
    echo "clone processe "$PROCESS_ID":Clone failed"
    echo "******************************************************************"
fi
owner=$SUDO_UID":"$SUDO_GID
chown $owner $1 
echo "md5sum............................"
md5sum $1 > $1".md5"
echo "$1 Clone Done,exit"
echo
