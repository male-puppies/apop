#!/bin/sh
mkdir -p /tmp/www/webui/
mkdir -p /tmp/firmware/rom
mkdir -p /tmp/firmware/rom4
ln -s /tmp/firmware/rom /tmp/www/webui/rom
ln -s /tmp/firmware/rom4 /tmp/www/webui/rom4ac
ln -s /tmp/firmware/rom /www/rom
ln -s /tmp/firmware/rom4 /www/rom4ac
