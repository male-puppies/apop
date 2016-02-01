#!/bin/sh 
HOME=/root
username=$1
cloudport=$2
localport=$3

remote_ip=$4
remote_port=$5

footprint=$6
path=$7

usage() {
	echo "usage $0 username cloudport localport remote_ip remote_port footprint path"
	exit 1
}

test "$username" == "" && usage
test "$remote_ip" == "" && usage
test "$remote_port" == "" && usage
test "$footprint" == "" && usage
test "$path" == "" && usage

ps w | grep -- '-N -f -R' | grep "localhost:$localport" | grep -v grep | awk '{print $1}' | xargs kill -15

rm -f $path

target_rsa="/root/.ssh/id_dropbear"
if [ ! -e $target_rsa ]; then 
	source_rsa=/ugw/default/id_dropbear
	mkdir -p /root/.ssh/
	cp -a $source_rsa $target_rsa 
	chmod 600 $target_rsa
fi

echo "$footprint" > /root/.ssh/known_hosts
timeout -t 30 -s 15 ssh -i $target_rsa -N -f -R $cloudport:localhost:$localport $username@$remote_ip -p $remote_port
touch $path
echo "ssh -i $target_rsa -N -f -R $cloudport:localhost:$localport $username@$remote_ip -p $remote_port"
