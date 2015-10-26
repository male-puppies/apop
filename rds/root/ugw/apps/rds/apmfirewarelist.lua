local log = require("log")
local lfs = require("lfs")
local log = require("log")
local pkey = require("key") 
local js = require("cjson.safe")  

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
	local romdir = "/tmp/www/webui/rom"
	if not lfs.attributes(romdir) then 
		return {status = 0, data = {}}	
	end 

	local vers = {}
	for filename in lfs.dir(romdir) do 
		local version = filename:match("(.+%.%d%d%d%d%d%d%d%d%d%d%d%d)")
		local _ = version and table.insert(vers, version)
	end
	return {status = 0, data = vers}	
end

local function apmfirewaredownload(conn, group, data)
	assert(conn and conn.rds and group)
	rds, pcli = conn.rds, conn.pcli
	
	local ver_arr = data
	if type(ver_arr) ~= "table" then 
		return {status = 1, data = "error"}
	end

	local arr = {"lua", "/ugw/script/checkaprom.lua", "download", "default"}
	for _, v in ipairs(ver_arr) do 
		table.insert(arr, v)
	end 
	table.insert(arr, "&")
	local cmd = table.concat(arr, " ")
	log.debug("cmd %s", cmd)
	os.execute(cmd)
	return {status = 0, data = "ok"}	
end

-- local function newest_version(conn, group, data) 
-- 	local data = {host = "default", arr = {"QM1439", "QM1438"}}
-- 	local map = data 
-- 	local host, arr = map.host, map.arr 
-- 	if not (host and arr and #arr > 0) then 
-- 		return {status = 1, data = "invalid param"}	 
-- 	end 

-- 	local narr = {"version", host}
-- 	for _, v in ipairs(arr) do 
-- 		table.insert(narr, v)
-- 	end 

-- 	local cmd = string.format("timeout -t 4 lua /ugw/script/checkaprom.lua %s", table.concat(narr, " "))
-- 	print("TODO cmd", cmd)
-- 	-- os.execute(cmd)
-- 	local fp = io.open("/tmp/ap.version", "r")
-- 	if not fp then 
-- 		return {status = 1, "check version fail"}
-- 	end 

-- 	local narr = {}
-- 	for line in fp:lines() do 
-- 		table.insert(narr, line)
-- 	end 
-- 	fp:close()

-- 	return {status = 0, data = line}
-- end

return { 
	-- newest_version = newest_version,
	apmfirewarelist = apmfirewarelist,
	apmupdatefireware = apmupdatefireware,
	apmfirewaredownload = apmfirewaredownload,
}

 