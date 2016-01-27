#!/bin/sh
opt=$1 
devtype=$2
host=$3 
port=$4

tmpdir=/tmp/download
errlog=/tmp/ugw/log/apmgr.error 
diskdir=/www/rom

usage() {
	echo "$0 opt devtype host port"
	exit 1
}

log() {
	echo `uptime | awk -F, '{print $1}'` "$*" >>$errlog
}

err_exit() {
	log "$*"
	rm -f $tmpfile
	exit 1
}

get_version_common() {
	local mempath=$1
	local formal=$2
	local httppath=$3

	rm -f $mempath 
	echo wget -q -O $mempath "$httppath"
	wget -q -O $mempath "$httppath"
	test $? -ne 0 && err_exit "download $mempath fail $host $port $devtype" 
	local nmd5=`md5sum $mempath | awk '{print $1}'`
	local omd5=`md5sum $formal | awk '{print $1}'`
	test "$nmd5" = "$omd5" && err_exit "not find new version"
	local tmppath=$formal.tmp
	mv $mempath $tmppath || err_exit "mv $mempath $tmppath fail"
	mv $tmppath $formal || err_exit "mv $tmppath $formal fail"
	log "download new $formal ok"
}

get_acversion() { 
	get_version_common $tmpdir/ac_version.json /etc/config/ac_version.json "http://$host:$port/rom/$devtype.json"
	exit 0
}

get_apversion() {
	get_version_common $tmpdir/thin_version.json /etc/config/thin_version.json "http://$host:$port/rom/thin/$devtype.json"
	exit 0
}

trypath() {
	local filename=$1
	local md5=$2
	local path=$3
	local tmpfile=$tmpdir/$devtype.bin
	
	test "$diskdir" = "" && exit 1

	rm -f $tmpfile
	
	wget -q -O $tmpfile "$path" 2>>$errlog
	if [ $? -ne 0 ]; then 
		log "download fail"
		return 0
	fi

	# local size=`ls -l $tmpfile | awk '{print $5}'`
	# test $? -ne 0 && err_exit "get size $tmpfile fail"
	# if [ $size -lt 2048 ]; then 
	# 	cat $tmpfile | grep "server is busy" >/dev/null 2>&1 
	# 	if [ $? -eq 0 ]; then 
	# 		log "server busy $path. wait and try again"
	# 		return 1
	# 	fi
	# 	return 0
	# fi 

	nmd5=`md5sum $tmpfile | awk '{print $1}'`
	test $? -ne 0 && err_exit "md5sum $tmpfile fail"

	if [ "$md5" != "$nmd5" ]; then 
		log "md5 not match $md5 $nmd5"
		return 0
	fi

	test -e $diskdir || mkdir -p $diskdir
	local disktmp=$diskdir/$filename.tmp
	local formal=$diskdir/$filename

	rm -f $diskdir/$devtype*
	mv $tmpfile $disktmp || err_exit "mv $tmpfile $disktmp fail"
	mv $disktmp $formal || err_exit "mv $disktmp $formal fail"
	cd $diskdir
	md5sum $filename | awk '{print $2"\n"$1}' > $devtype.version

	log "download $filename ok"
	return 2
}

test "$devtype" = "" && usage
test "$host" = "" && usage
test "$port" = "" && port=80

test -e $tmpdir || mkdir -p $tmpdir

case $opt in 
	"apver")
		get_apversion;;
	"acver")
		get_acversion;; 
	"apdl")
		# ./download.sh apdl QM1439 121.41.41.7 80 QM1439.160115114410 86df1d0210b0f74c0ef8081a5add5ff9 'path2' 'http://192.168.0.213/rom/QM1439.160115114410'
		filename=$5
		md5=$6
		test "$filename" = "" && exit 1
		test "$md5" = "" && exit 1
		shift; shift; shift; shift; shift; shift;
		for path in $*; do  
			trypath $filename $md5 $path
			if [ $? -eq 2 ]; then 
				break
			fi
		done
		;;
	"acdl")
		# ./download.sh acdl AC1064 121.41.41.7 80 AC1064-1601141258 86df1d0210b0f74c0ef8081a5add5ff9 'http://192.168.0.213/rom/QM1439.160115114410'
		filename=$5
		md5=$6
		test "$filename" = "" && exit 1
		test "$md5" = "" && exit 1
		shift; shift; shift; shift; shift; shift;

		diskdir=/www/rom4ac
		for path in $*; do  
			trypath $filename $md5 $path
			if [ $? -eq 2 ]; then 
				break
			fi
		done 
		;;
	*)
		usage;;
esac
