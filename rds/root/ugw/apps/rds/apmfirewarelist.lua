local log = require("log")
local lfs = require("lfs")
local log = require("log")
local pkey = require("key") 
local js = require("cjson.safe")  
local common = require("common")
local read = common.read

local rds, pcli 

local function apmupdatefireware(conn, group, data)
	assert(conn and conn.rds and group)
	rds, pcli = conn.rds, conn.pcli
	
	local apid_arr = data
	if type(apid_arr) ~= "table" then 
		return {status = 1, data = "error"}
	end

	pcli:modify({cmd = "upgrade", data = {group = "default", arr = apid_arr}})
	return {status = 0, data = ""}
end

local function apmfirewarelist(conn, group, data) 
	local narr = {}
	local dir = "/www/rom/"
	if not lfs.attributes(dir) then 
		return {status = 0, data = narr}
	end

	local aptype_map = {}
	for filename in lfs.dir(dir) do 
		local aptype = filename:match("(.+)%.version$")
		if aptype then  
			local map = aptype_map[aptype] or {}
			map.old = read(dir .. "/" .. filename):match("(.-)\n")
			aptype_map[aptype] = map
		end
	end
	--thin_version.json存在decode失败的可能性
	local map = js.decode(read("/etc/config/thin_version.json") or "{}") or {}
	for aptype, item in pairs(map) do 
		local map = aptype_map[aptype] or {}
		map.new = item.version
		aptype_map[aptype] = map
	end
	
	for k, item in pairs(aptype_map) do 
		table.insert(narr, {cur = item.old, new = item.new})
	end 

	return {status = 0, data = narr}	
end

local function apmfwdownload()
	os.execute("touch /tmp/download_ap_firmware; /etc/init.d/chkfirmware restart")
	return {status = 0, data = "Downloading"}
end

return {  
	apmfirewarelist = apmfirewarelist,
	apmupdatefireware = apmupdatefireware,
	apmfwdownload = apmfwdownload,
}

 
