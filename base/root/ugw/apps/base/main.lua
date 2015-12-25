require("global")
local se = require("se")
local lfs = require("lfs")
local log = require("log")
local js = require("cjson.safe")
local sandc = require("sandc")
local common = require("common")

local remote_mqtt, local_mqtt
local cfgpath = "/etc/config/cloud.json"
local read, save, save_safe = common.read, common.save, common.save_safe

local g_kvmap, g_devid = {}


local function read_id()
	local id = read("ifconfig eth0 | grep HWaddr | awk '{print $5}'", io.popen)
	id = id:gsub("[ \t\n]", ""):lower()
	assert(#id == 17)
	g_devid = "wx" .. id
end

local function remote_topic()
	return "a/devid/" .. g_devid
end

local function try_connect(host, port)
	local ip = host
	local pattern = "^%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?$"
	if not host:find(pattern) then
		local cmd = string.format("timeout nslookup '%s' | grep -A 1 'Name:' | grep Addr | awk '{print $3}'", host)
		ip = read(cmd, io.popen)
		if not ip then 
			log.error("%s fail", cmd)
			return false
		end
		ip = ip:gsub("[ \t\r\n]", "")
		if not ip:find(pattern) then
			log.error("%s fail", cmd)
			return false
		end
	end
	
	local addr = string.format("tcp://%s:%s", ip, tostring(port))

	for i = 1, 3 do 	
		local cli = se.connect(addr, 3)
		if cli then 
			log.debug("connect %s ok", addr)
			se.close(cli)
			return true
		end
		
		se.sleep(1)
	end

	log.debug("connect %s fail", addr)		
end

local function get_active_addr()
	while true do 
		local host, port = g_kvmap.ac_host, g_kvmap.ac_port
		if host and port and try_connect(host, port) then
			return host, port 
		end

		local host, port = "121.41.41.7", 61886 	-- TODO
		if host and port and try_connect(host, port) then
			return host, port 
		end

		se.sleep(1)
	end
end

local function read_connect_payload()
	local account = g_kvmap.account
	local map = {group = account, apid = g_devid, data = {}} 
	return account, map
end

local function start_remote()
	local host, port = get_active_addr()
	
	local unique = remote_topic()
	print("remote", unique)
	local mqtt = sandc.new(unique)
	mqtt:set_auth("ewrdcv34!@@@zvdasfFD*s34!@@@fadefsasfvadsfewa123$", "1fff89167~!223423@$$%^^&&&*&*}{}|/.,/.,.,<>?")
	mqtt:pre_subscribe(unique)
	local account, connect_data = read_connect_payload()
	mqtt:set_connect("a/ac/query/connect", js.encode({pld = connect_data}))
	mqtt:set_will("a/ac/query/will", js.encode({apid = g_devid, group = account}))
	mqtt:set_callback("on_message", function(topic, payload) 
		print(topic, payload)
		if not local_mqtt then 
			log.error("local mqtt not ready")
			print("skip", topic, payload)
			return 
		end 

		local map = js.decode(payload)
		if not (map and map.mod and map.pld) then 
			return 
		end 

		local_mqtt:publish(map.mod, payload)
	end)

	mqtt:set_callback("on_disconnect", function(st, err) 
		log.fatal("remote mqtt disconnect %s %s", st, err)
	end)

	local ret, err = mqtt:connect(host, port)
	local _ = ret or log.fatal("connect fail %s", err)

	log.debug("connect %s %s %s ok", account, host, port) 

	mqtt:run()
	remote_mqtt = mqtt
end

local function local_topic()
	return "a/ac/proxy"
end

local function start_local()
	local  unique = local_topic()
	local mqtt = sandc.new(unique)
	mqtt:set_auth("ewrdcv34!@@@zvdasfFD*s34!@@@fadefsasfvadsfewa123$", "1fff89167~!223423@$$%^^&&&*&*}{}|/.,/.,.,<>?")
	mqtt:pre_subscribe(unique)
	mqtt:set_callback("on_message", function(topic, payload)
		if not remote_mqtt then 
			log.error("remote mqtt not ready")
			print("skip", topic, payload)
			return
		end

		local map = js.decode(payload) 
		if not (map and map.data and map.out_topic) then 
			return 
		end
		
		map.data.tpc = remote_topic()
		remote_mqtt:publish(map.out_topic, js.encode(map.data))
	end)
	mqtt:set_callback("on_disconnect", function(st, err) 
		log.fatal("remote mqtt disconnect %s %s", st, err)
	end)

	local host, port = "127.0.0.1", 61886
	local ret, err = mqtt:connect(host, port)
	local _ = ret or log.fatal("connect fail %s", err)
	log.debug("connect %s %s ok", host, port) 
	mqtt:run()
	local_mqtt = mqtt
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

local function main()
	read_id()
	load()
	se.go(start_remote)
	se.go(start_local)
end 

log.setmodule("bs")
log.setdebug(true)
se.run(main)
