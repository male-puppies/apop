package.path = "./?.lua;" .. package.path

require("global")
local se = require("se")
local lfs = require("lfs")
local log = require("log")
local js = require("cjson.safe")
local sandc = require("sandc")
local sandc1 = require("sandc1")
local common = require("common")
local defaultcfg = require("defaultcfg")

local remote_mqtt, local_mqtt
local cfgpath = "/etc/config/cloud.json"
local read, save, save_safe = common.read, common.save, common.save_safe

local g_kvmap, g_devid = {}

local function read_id()
	local id = read("ifconfig eth0 | grep HWaddr | awk '{print $5}'", io.popen)
	id = id:gsub("[ \t\n]", ""):lower()
	assert(#id == 17)
	g_devid = id
end

local function remote_topic()
	return "a/dev/" .. g_devid
end

local function try_connect(host, port)
	local ip = host
	local pattern = "^%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?$"
	if not host:find(pattern) then
		local cmd = string.format("timeout nslookup '%s' | grep -A 1 'Name:' | grep Addr | awk '{print $3}'", host)
		ip = read(cmd, io.popen)
		if not ip then
			log.error("%s fail", cmd)
			return
		end
		ip = ip:gsub("[ \t\r\n]", "")
		if not ip:find(pattern) then
			log.error("%s fail", cmd)
			return
		end
	end

	local addr = string.format("tcp://%s:%s", ip, tostring(port))

	for i = 1, 3 do
		local cli = se.connect(addr, 3)
		if cli then
			print("connect ok", addr)
			se.close(cli)
			return ip, port
		end

		log.debug("try connect %s fail", addr)
		se.sleep(3)
	end

	log.debug("connect %s fail", addr)
end

local function get_active_addr()

	while true do
		local host, port = try_connect(g_kvmap.ac_host, g_kvmap.ac_port)
		if host then
			return host, port
		end

		log.debug("try connect %s %s fail", g_kvmap.ac_host or "", g_kvmap.ac_port or "")
		se.sleep(3)
	end
end

local function read_connect_payload()
	local account = g_kvmap.account
	local map = {account = account, devid = g_devid}
	return account, map
end

local function save_status(st, host, port)
	local m = {state = st, host = host, port = port}
	save_safe("/tmp/memfile/cloudcli.json", js.encode(m))
end

local function start_remote()
	local host, port = get_active_addr()

	local unique = remote_topic()

	local mqtt = sandc1.new(unique)
	mqtt:set_auth("ewrdcv34!@@@zvdasfFD*s34!@@@fadefsasfvadsfewa123$", "1fff89167~!223423@$$%^^&&&*&*}{}|/.,/.,.,<>?")
	mqtt:pre_subscribe(unique)
	local account, connect_data = read_connect_payload()
	mqtt:set_connect("a/ac/query/connect", js.encode({pld = connect_data}))
	mqtt:set_will("a/ac/query/will", js.encode({devid = g_devid, account = account}))
	mqtt:set_extend(js.encode({account = account, devid = g_devid}))
	mqtt:set_callback("on_message", function(topic, payload)
		if not local_mqtt then
			log.error("skip %s %s", topic, payload)
			return
		end

		local map = js.decode(payload)
		if not (map and map.mod and map.pld) then
			log.error("invalid message %s %s", topic, payload)
			return
		end

		local_mqtt:publish(map.mod, payload)
	end)

	mqtt:set_callback("on_connect", function(st, err) save_status(1, host, port) end)
	mqtt:set_callback("on_disconnect", function(st, err)
		save_status(0, host, port)
		os.execute("killstr cloudcli/main.lua")
		log.fatal("remote mqtt disconnect %s %s. restart cloudcli", st, err)
	end)
	mqtt:set_callback("on_encode_type", function(n, o)
		mqtt:set_encode_type(n)
		log.info("encode type change %s->%s", o, n)
	end)


	local ret, err = mqtt:connect(host, port)
	local _ = ret or log.fatal("connect fail %s %s %s", host, port,  err)

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
			log.error("skip %s %s", topic, payload)
			return
		end

		local map = js.decode(payload)
		if not (map and map.data and map.out_topic) then
			log.error("invalid payload %s %s", topic, payload)
			return
		end

		map.data.tpc = remote_topic()
		local topic, payload = map.out_topic, js.encode(map.data)
		remote_mqtt:publish(topic, payload)
	end)

	mqtt:set_callback("on_disconnect", function(st, err) log.fatal("remote mqtt disconnect %s %s", st, err) end)

	local host, port = "127.0.0.1", 61886
	local ret, err = mqtt:connect(host, port)
	local _ = ret or log.fatal("connect fail %s", err)
	log.debug("connect %s %s ok", host, port)
	mqtt:run()
	local_mqtt = mqtt
end

local function set_default()
	g_kvmap = defaultcfg.default_cloud()
end

local function load()
	if not lfs.attributes(cfgpath) then
		return set_default()
	end

	local map = js.decode(read(cfgpath))
	if not map then
		os.remove(cfgpath)
		log.error("invalid %s %s, remove", cfgpath, s or "")
		return set_default()
	end
	g_kvmap = map
end

local function main()
	save_status(0)
	local _ = read_id(), load()
	if not lfs.attributes("/tmp/invalid_account") then
		se.go(start_local)
		while g_kvmap.ac_host == "" do
			se.sleep(1)
		end
		se.go(start_remote)
	end
	local _ = lfs.attributes("/tmp/invalid_account") and log.error("invalid account")
	while true do
		se.sleep(1)
	end
end

log.setmodule("bs")
log.setdebug(true)
se.run(main)
