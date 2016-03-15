#!/bin/sh

firmware_path=/etc/config/firmware.json
errlog="/tmp/ugw/log/apmgr.error" 

log() {
	echo `uptime | awk -F, '{print $1}'` "$*"
	echo `uptime | awk -F, '{print $1}'` "$*" >>$errlog
}

err_exit() {
	log "$*" 
	exit 1
}

flag=/tmp/download_ac_firmware
touch $flag

/etc/init.d/chkfirmware restart 

while :; do 
	sleep 1
	test -e $flag || break
	log "wait $flag to be deleted"
done

log "$flag was deleted, check firmware"

actype=`cat $firmware_path | grep actype | awk -F: '{print $2}' | awk -F\" '{print $2}'`
if [ $? -ne 0 ]; then 
	log "read firmware.json to get actype fail"
	exit 1
fi
version_file=/www/rom4ac/$actype.version
test -e $version_file || err_exit "not find $version_file"

image=/www/rom4ac/`head -1 $version_file`
test -e $image || err_exit "missing $image"
nickname=/tmp/upgrade.img
mv $image $nickname

mkdir -p /tmp/UploadBrush
tar -zxf $nickname -C /tmp/UploadBrush/

image_tmp=/tmp/UploadBrush/UploadBrush-bin.img
txt_tmp=/tmp/UploadBrush/bin_random.txt
test -e $image_tmp || err_exit "missing $image_tmp"
test -e $txt_tmp || err_exit "missing $txt_tmp"

bin_img=`md5sum $image_tmp | awk '{print $1}'`
if [ $? -ne 0 ]; then 
	log "md5sum $image_tmp fail"
	exit 1
fi

str_rdm=`cat /etc/binrandom.json | grep bin_random | awk -F: '{print $2}' | awk -F\" '{print $2}'`
if [ $? -ne 0 ]; then 
	log "read binrandom.json to get bin_random fail"
	exit 1
fi
bin_rdm=`echo -n $str_rdm | md5sum | awk '{print $1}'`
if [ $? -ne 0 ]; then 
	log "md5sum $str_rdm fail"
	exit 1
fi

bin2=${bin_img}${bin_rdm}
bin_random1=`echo -n $bin2 | md5sum | awk '{print $1}'`
if [ $? -ne 0 ]; then 
	log "md5sum $bin_random1 fail"
	exit 1
fi
bin_random2=`cat $txt_tmp`

if [ "$bin_random1" != "$bin_random2" ]; then
	err_exit "Not equal md5sum, invalid image $image"
fi

/sbin/sysupgrade -T $image_tmp >> $errlog 2>&1
test $? -eq 0 || err_exit "invalid image $image"
touch /tmp/sysupgrade
/ugw/script/stop_all.sh
/sbin/sysupgrade $image_tmp >> $errlog 2>&1
reboot
