#!/bin/sh 
opt=$1 
local enable_flag=/ugw/etc/wac/enable_cloud_ads
get_switch() {
	path=/ugw/etc/wac/cloud.json 
	cat $path | grep '"switch":"1"' >/dev/null 2>&1
	test $? -eq 0 && return 1
	return 0
}

reset_ad() {
	local adpath=/ugw/etc/wac/ad.tgz
	local cloudpath=/www/cloudauth
	local tmpdir=$cloudpath".tmp"
	local deldir=$cloudpath".del"

	test -e $adpath || return
	rm -rf $tmpdir
	mkdir -p $tmpdir

	tar -xzf $adpath -C $tmpdir
	test $? -ne 0 && return 

	test -e $cloudpath && mv $cloudpath $deldir
	mv $tmpdir $cloudpath
	rm -rf $deldir 
}

reset_dev() { 
	UGW_BASE=/ugw 
	PATH=$UGW_BASE/bin/:$PATH LD_LIBRARY_PATH=$UGW_BASE/lib/:$LD_LIBRARY_PATH LUA_PATH="$UGW_BASE/share-sc/?.lua;$LUA_PATH" LUA_CPATH="$UGW_BASE/lib/?.so;$LUA_CPATH" lua /ugw/sh/init_scripts/reset_wx2cfg.lua
	appctl restart userauthd 
}

cloud_switch() {
	/etc/init.d/base restart
	/etc/init.d/cloudcli restart
	rm /tmp/invalid_account 
}

case $opt in 
	dev)
		reset_dev
		;;
	ad)
		reset_ad
		;;
	cloud_switch)
		cloud_switch
		;;
	*)
		echo "invalid type"
		;;
esac		

