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

echo 1
# TODO upgrade
