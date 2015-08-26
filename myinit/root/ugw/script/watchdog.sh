#!/bin/sh

logfile=/tmp/ugw/log/apmgr.error
log() {
	echo `date` $* >> $logfile
	test -f /ugw/etc/sh_debug || return 
	echo $*
}

mkdir -p /tmp/ugw/log/ 

process_running() {
	process=$1
	for i in 1 2 3; do 
		ps | grep $process | grep -v grep >/dev/null
		if [ $? -eq 0 ]; then  
			return 0
		fi
	done 
	return 1
}

watch_common() {
	local sc=$1
	local path=$2
	while :; do 
		process_running $sc
		if [ $? -ne 0 ]; then 
			log "start $sc"
			$path >> $logfile 2>&1 &
		fi
		sleep 3
	done
}

watch_chkubus() {
	watch_common chkubus.sh /ugw/script/chkubus.sh
}

watch_chkubus & 