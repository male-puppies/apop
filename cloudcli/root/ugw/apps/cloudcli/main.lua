require("global")
local se = require("se")
local log = require("log")
local lfs = require("lfs")
local js = require("cjson.safe")
local sandc = require("sandclient")
local common = require("common")

local cfgpath = "/etc/config/cloud.json"
local read, save, save_safe = common.read, common.save, common.save_safe
local g_kvmap, g_devid = {}

local mqtt 

local function read_id()
	local id = read("ifconfig eth0 | grep HWaddr | awk '{print $5}'", io.popen)
	id = id:gsub("[ \t\n]", ""):lower()
	assert(#id == 17)
	g_devid = "wx" .. id
end

local function upload()
	local register_topic = "a/ac/cfgmgr/register"
	local request = function(data)
		while true do 
			local res = mqtt:request(register_topic, data)
			if res ~= nil then 
				return res
			end
			log.error("register fail %s", js.encode(data))
			se.sleep(10)
		end
	end

	local cmd = {cmd = "check", data = {g_devid, g_kvmap.account, g_kvmap.version}}
	local res = request(cmd)
	if res == 1 then 
		log.debug("alread register %s %s", g_devid, g_kvmap.account)
		return 
	end 

	local cmd = {cmd = "upload", data = {g_devid, g_kvmap.account, g_kvmap}}
	local res = request(cmd)
	if res ~= 1 then 
		log.error("upload config fail %s", js.encode(g_kvmap))
		se.sleep(10)
		os.exit(-1)
	end 
end

local function set_default()
	g_kvmap = {
		account = "default",
		ac_host = "192.168.0.213", -- TODO
		ac_port = "61886",
		descr = "default",
		version = "0000-00-00 00:00:00",
	}
	-- print(js.encode(g_kvmap))
end

local function load() 
	if not lfs.attributes(cfgpath) then
		return set_default()
	end 
	local s = read(cfgpath)
	local map = js.decode(s)
	if not map then 
		os.remove(cfgpath)
		return set_default()
	end 
	g_kvmap = map
end

local cmd_map = {}
function cmd_map.replace(map)
	local field_map = {account = 1, ac_host = 1, ac_port = 1, descr = 1, version = 1,}	
	for k in pairs(map) do 
		if not field_map[k] then 
			log.error("invalid replace %s", js.encode(map))
			return 
		end
	end
	
	local change, need_exit = false, false
	local check_field = {account = 1, ac_host = 1, ac_port = 1}
	for k, v in pairs(map) do 
		local ov = g_kvmap[k]
		if v ~= ov then 
			change = true
			if check_field[k] then 
				need_exit = true 
			end 
			log.debug("%s change %s->%s", k, ov, v)
		end
	end

	if not change then 
		return 
	end 

	g_kvmap = map 

	do return end 
	local s = js.encode(g_kvmap)
	save_safe(cfgpath, s)
	if need_exit then 
		os.execute("killstr 'base/main.lua'")
		os.exit(0)
	end
end

local sshreverse_running = false
function cmd_map.ssh(map) 
	if sshreverse_running then 
		log.error("sshreverse is already running")
		return 
	end

	local respath = "/tmp/sshresult.txt"
	local cmd = string.format("/ugw/script/sshreverse.sh '%s' '%s' '%s' '%s' '%s' '%s' '%s' &", map.username, map.cloudport, map.localport, map.remote_ip, map.remote_port, map.footprint, respath)
	
	se.go(function()
		if sshreverse_running then 
			return 
		end 

		os.remove(respath)
		os.execute(cmd)

		local start = se.time()
		sshreverse_running = true
		while true do 
			if lfs.attributes(respath) then 
				os.remove(respath)
				log.debug("sshreverse use time %s", se.time() - start)
				break
			end
			if se.time() - start > 30 then 
				log.error("sshreverse timeout")
				
				break
			end 
			se.sleep(0.3)
		end
		sshreverse_running = false
	end)
end

local function on_message(map)
	local cmd, data = map.cmd, map.data 
	if not (cmd and data) then 
		log.error("invalid message %s", js.encode(map))
		return 
	end 

	local func = cmd_map[cmd]
	if not func then 
		log.error("invalid message %s", js.encode(map))
		return
	end 

	func(data)
end

local function connect_mqtt()
	mqtt = sandc.new()
	mqtt:set_callback("on_message", on_message)
	mqtt:run()
end

local function check_cfg_change()
	local lasttime
	local check_field = {account = 1, ac_host = 1, ac_port = 1}
	while true do
		local attr = lfs.attributes(cfgpath)
		if attr then
			if not lasttime then 
				lasttime = attr.modification
			else
				lasttime = attr.modification
				local s = read(cfgpath)
				local map = js.decode(s) 	assert(map)
				for k, v in pairs(map) do 
					if check_field[k] and v ~= g_kvmap[k] then  
						log.debug("field change %s %s %s. kill base, exit and reload", k, g_kvmap[k], v)
						os.execute("killstr 'base/main.lua'")
						os.exit(0)
					end
				end
			end
		end
		se.sleep(1)
	end 
end

local function main()
	read_id()
	connect_mqtt()
	load()
	upload()
	se.go(check_cfg_change)
end 

log.setmodule("cm")
log.setdebug(true)
se.run(main)
