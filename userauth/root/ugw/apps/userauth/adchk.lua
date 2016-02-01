local lfs = require("lfs")
local common = require("common")
local js = require("cjson.safe")

local read, save, save_safe = common.read, common.save, common.save_safe

local cloud_path = "/etc/config/cloud.json"
local local_webdir = "/www/webui"
local cloud_webdir = "/www/cloudauth"
local adtype_path = "/tmp/www/adtype"

local function copy_webui(srcdir)
	local s = read(adtype_path)
	if s and s:find(srcdir) then 
		print("nothing change")
		return 
	end 

	local cmd = string.format([[ 
		wwwdir=/tmp/www
		tmpwww=$wwwdir.tmp
		webdir=$tmpwww/webui
		rm -rf $tmpwww
		mkdir $tmpwww
		cp -rf %s $tmpwww/webui
		echo '%s' > $tmpwww/adtype
		deldir=$wwwdir.del
		rm -rf $deldir
		test -e $wwwdir && mv $wwwdir $deldir
		mv $tmpwww $wwwdir
		webdir=$wwwdir/webui
		ln -sf /tmp/firmware/rom $webdir/rom 
		ln -sf /tmp/firmware/rom4ac $webdir/rom4ac 
		rm -rf $deldir
	]], srcdir, srcdir) 
	os.execute(cmd)
end

local s = read(cloud_path)
local map = js.decode(s)
if not map then 
	print("invalid", cloud_path)
	return copy_webui(local_webdir)
end

if tonumber(map.switch) ~= 1 then 
	print("cloud switch not 1")
	return copy_webui(local_webdir)
end

if not lfs.attributes(cloud_webdir) then 
	print("not find", cloud_webdir)
	return copy_webui(local_webdir)
end

return copy_webui(cloud_webdir)
