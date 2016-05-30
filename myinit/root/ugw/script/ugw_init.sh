#!/bin/sh
mkdir -p /tmp/www/webui/
mkdir -p /tmp/firmware/rom
mkdir -p /tmp/firmware/rom4ac
ln -s /tmp/firmware/rom /tmp/www/webui/rom
ln -s /tmp/firmware/rom4ac /tmp/www/webui/rom4ac
ln -s /tmp/firmware/rom /www/rom
ln -s /tmp/firmware/rom4ac /www/rom4ac
