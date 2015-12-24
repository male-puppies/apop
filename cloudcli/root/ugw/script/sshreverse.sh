#!/bin/sh 
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

ps | grep 'ssh -N -f -R' | grep -v grep | awk '{print $1}' | xargs kill -15

rm -f $path

echo "$footprint" > /root/.ssh/known_hosts
timeout -t 30 -s 15 ssh -N -f -R $cloudport:localhost:$localport $username@$remote_ip -p $remote_port
touch $path
echo "ssh -N -f -R 0:localhost:$localport $username@$remote_ip -p $remote_port finish"
