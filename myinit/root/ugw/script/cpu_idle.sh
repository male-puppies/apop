#!/bin/sh

while :; do
	cpuidle=`mpstat 1 2 | grep Average | grep all |  awk '{print $11}'`
	echo $cpuidle >/tmp/cpu_idle
done
