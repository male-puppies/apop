#!/bin/sh

ps | grep cloudcli/main.lua | grep -v grep >/dev/null 
test $? -eq 0 && exit 0

errorfile=/tmp/ugw/log/apmgr.error 

tmppath=/root/.ssh/id_dropbear
if [ ! -e $tmppath ]; then
	mkdir -p /root/.ssh
	cp /ugw/default/id_dropbear /root/.ssh/
	chmod 600 $tmppath
fi

test -d /tmp/ugw/log/ || mkdir -p /tmp/ugw/log/ 
cd /ugw/apps/cloudcli/
while :; do 
	lua /ugw/apps/cloudcli/main.lua >/dev/null 2>>$errorfile
	sleep 2
done

