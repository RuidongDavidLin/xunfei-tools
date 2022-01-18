#!/bin/bash

NVIDIA_USB_ID=0955:7f21

# log path
LOGPATH=../../../../logs/

# create a folder for saving log
PID=$$
mkdir -p ${LOGPATH}${PID}
echo "start flash with XIAO jetpack"
echo "start flash with PID=${PID}"

## flash all devices in background
#lsusb -d ${NVIDIA_USB_ID} | while IFS= read -r line
dev_type=`lsusb -d ${NVIDIA_USB_ID}`
if [ -z "$dev_type" ]; then
    echo "******************************************************************" 
    echo "devices type mismatch or the devices did not enter recovery mode"
    echo "******************************************************************"
    exit 1 
fi
lsusb -d ${NVIDIA_USB_ID} > lsusb.txt
COUNT=0
while IFS= read -r line
do
	BUS=`echo $line | awk '{print $2}'`
	DEV=`echo $line | awk '{print $4}' | cut -d ':' -f 1`
	USB_INSTANCE=`echo /dev/bus/usb/${BUS}/${DEV}`
	rm -f ${LOGPATH}${PID}/flash_${BUS}_${DEV}.log
	FLASHCMD=`cat flashcmd.txt`
	CMD="${FLASHCMD} --instance ${USB_INSTANCE}"
	(eval ${CMD} > ${LOGPATH}${PID}/flash_${BUS}_${DEV}.log) &
	PROCESS_ID=$!
	echo ${PROCESS_ID} >>${LOGPATH}${PID}/pid.log
	echo "start flashing device: ${USB_INSTANCE}, process ID: ${PROCESS_ID}"
	TIMEOUT=0
	dev_arry[$COUNT]=${LOGPATH}${PID}/flash_${BUS}_${DEV}.log
	pid_arry[$COUNT]=${PROCESS_ID}
 	COUNT=$COUNT+1
	while [ ${TIMEOUT} -lt 6 ]
	do
		cat ${LOGPATH}${PID}/flash_${BUS}_${DEV}.log | grep "system.img" 2>&1 >/dev/null
		if [ $? == 0 ]; then
			sleep 4
			break;
		else
			sleep 1
			let "TIMEOUT=TIMEOUT+1"
		fi
	done
done < lsusb.txt

## exit if pid file is not generated
if [ ! -e ${LOGPATH}${PID}/pid.log ]
then
	echo "no ongoing flash, exit"
	exit 1
fi

## print process info
PROCESS_NUM=`cat $LOGPATH$PID/pid.log | wc -l`
echo -n "${PROCESS_NUM} flash processes ongoing: "
while read process
do
	echo -n " ${process}"
done < ${LOGPATH}${PID}/pid.log
echo

## wait all flash processes done
PROCESS_NUM=`cat $LOGPATH$PID/pid.log | wc -l`
P_DONE=0
while [ ${P_DONE} -lt ${PROCESS_NUM} ]
do
	let "P_DONE=0"
	sleep 3
	echo -n "onging processes:"
	while read process
	do
		if [ -e /proc/${process} ]
		then
			echo -n " ${process}"
			for(( i=0;i<${#pid_arry[@]};i++)) do
				if [ ${pid_arry[i]} -eq ${process} ]
				then 
					DEV_LOG=${dev_arry[i]}
					break
				fi
			done
			RESULT_LOG=`tail -n 25 $DEV_LOG`
			RESULT_ERROR1="Cannot Open USB"
			if [[ $RESULT_LOG =~ $RESULT_ERROR1 ]]
			then
				#echo "******************************************************************"
				echo "flash processe "${process}":Flashing failed 1"
				#echo "******************************************************************"
				kill -9 ${process}
				break
			fi
		else
			let "P_DONE=P_DONE+1"
		fi
	done < ${LOGPATH}${PID}/pid.log
	echo -n "......["`date +%T`"]"
	echo
done

success_num=0
for(( i=0;i<${#dev_arry[@]};i++)) do
      RESULT_LOG=`tail ${dev_arry[i]}`
      RESULT_COMPLETED="Flashing completed"
      REBOOT_LOG="Coldbooting the device"
      if [[ $RESULT_LOG =~ $RESULT_COMPLETED ]] || [[ $RESULT_LOG =~ $REBOOT_LOG ]]
      then
          echo "******************************************************************"
          echo "flash processe "${pid_arry[i]}":Flashing completed"
          echo "******************************************************************"
          let success_num++
      else
          echo "******************************************************************"
          echo "flash processe "${pid_arry[i]}":Flashing failed 2"
          echo "******************************************************************"
      fi
done

if [ $success_num -eq 0 ]
then
  exit 1
fi
echo "All Flash Done, exit!"
echo
