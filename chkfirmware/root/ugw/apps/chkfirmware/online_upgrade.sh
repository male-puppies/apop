#!/bin/sh

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

version_file=/www/rom4ac/AC1032.version
test -e $version_file || err_exit "not find $version_file"

image=/www/rom4ac/`head -1 $version_file`
test -e $image || err_exit "missing $image"
nickname=/tmp/upgrade.img
mv $image $nickname
/sbin/sysupgrade -T $nickname >> $errlog 2>&1
test $? -eq 0 || err_exit "invalid image $image"
touch /tmp/sysupgrade
/ugw/script/stop_all.sh
/sbin/sysupgrade $nickname >> $errlog 2>&1
reboot
