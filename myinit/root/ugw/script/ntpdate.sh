#!/bin/sh

STEP_SERVERS="ntp.api.bz s2b.time.edu.cn s2k.time.edu.cn s2m.time.edu.cn s1a.time.edu.cn 0.openwrt.pool.ntp.org 1.openwrt.pool.ntp.org 2.openwrt.pool.ntp.org"
TIMEOUT="10"

while :; do 
	for s in $STEP_SERVERS ; do
		/usr/sbin/ntpdate -s -b -u -t "$TIMEOUT" "$s" && break
	done
	sleep 5
done
