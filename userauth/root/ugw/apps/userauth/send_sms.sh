#!/bin/sh
url=$1
sec=$2
rpath=$3

msg=`timeout -t $sec curl "$url" 2>&1`
if [ $? -eq 0 ]; then
	echo "0" > $rpath
	exit 0
fi

echo "1 $msg" > $rpath
 