#!/bin/sh 
opt=$1 
reset_ad() {
	local adpath=/etc/config/ad.tgz
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
	#echo "done" > $adpath #TODO open
}

reset_dev() { 
	/etc/init.d/userauth restart
}

cloud_switch() {
	rm /tmp/invalid_account 
	/etc/init.d/base restart
	/etc/init.d/cloudcli restart
	/etc/init.d/userauth restart
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

