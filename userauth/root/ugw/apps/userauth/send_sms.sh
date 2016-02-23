#!/bin/sh
url=$1
sec=$2
rpath=$3

msg=`timeout -t $sec curl -s "$url" 2>&1`
if [ $? -eq 0 ]; then
	echo "0 $msg" > $rpath
	exit 0
fi

echo "1 $msg" > $rpath
 