/etc/init.d/essential stop
killall watchdog.sh
killall lua
sync
mtd erase /dev/mtd6
mtd erase /dev/mtd7
reboot

