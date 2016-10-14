#!/bin/sh

ps | grep fwsecurity/main.lua | grep -v grep >/dev/null
test $? -eq 0 && exit 0

errorfile=/tmp/ugw/log/apmgr.error

test -d /tmp/ugw/log/ || mkdir -p /tmp/ugw/log/
cd /ugw/apps/fwsecurity/
while :; do
	lua /ugw/apps/fwsecurity/main.lua >/dev/null 2>>$errorfile
	sleep 2
done