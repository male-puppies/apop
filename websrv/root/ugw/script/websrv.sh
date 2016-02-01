#!/bin/sh

if [ -e /etc/config/ad.tgz ]; then 
	if [ ! -e /www/cloudauth ]; then 
		/ugw/script/resetcfg.sh ad
	fi
fi 

diskrom=/www/rom
diskrom4ac=/www/rom4ac

rm -rf $diskrom
rm -rf $diskrom4ac

romdir=/tmp/firmware/rom
rom4acdir=/tmp/firmware/rom4ac

mkdir -p $romdir
mkdir -p $rom4acdir

ln -sf $romdir $diskrom
ln -sf $rom4acdir $diskrom4ac

lua /ugw/apps/userauth/adchk.lua &