local se = require("se")
local log = require("log")
local md5 = require("md5")
local auth = require("auth")
local sandc = require("sandc")
local js = require("cjson.safe")
local common = require("common")
local request = require("request")
local kernelop = require("kernelop")
local dispatcher = require("dispatcher")


local mqtt
local read, save, save_safe = common.read, common.save, common.save_safe

local function cursec()
	return math.floor(se.time())
end

local function send_response_cloud(cmd, data)
	local map = {
			out_topic = "a/cloud/wxrds",
			data = {
				mod = "a/local/wxuser",
				deadline = math.floor(se.time()) + 5,
				pld = {cmd = cmd, key = data},
			},
		}
	print("send: ",js.encode(map))
	mqtt:publish("a/ac/proxy", js.encode(map))
end

local cmd_map = {
	user_set = dispatcher.user_set,
	user_del = dispatcher.user_del,
	user_add = dispatcher.user_add,
	user_get = dispatcher.user_get,

	policy_set = dispatcher.policy_set,
	policy_add = dispatcher.policy_add,
	policy_del = dispatcher.policy_del,
	policy_adj = dispatcher.policy_adj,
	policy_get = dispatcher.policy_get,

	online_del = dispatcher.online_del,
	online_get = dispatcher.online_get,
	wxuser_deal = dispatcher.wxuser_deal,   --add by php
	whitelist_set = dispatcher.whitelist_set,
	whitelist_get = dispatcher.whitelist_get,
	macwhitelist_get = dispatcher.macwhitelist_get,
	macwhitelist_set = dispatcher.macwhitelist_set,
	macblacklist_get = dispatcher.macblacklist_get,
	macblacklist_set = dispatcher.macblacklist_set,
	wechatwhitelist_set = dispatcher.wechatwhitelist_set,
	wechatwhitelist_get = dispatcher.wechatwhitelist_get,
}

local function on_message(topic, data)
	print("topic->",topic," data->",data)
	local map = js.decode(data)
	if not (map and map.pld) then
		print("invalid data 1", data)
		return
	end

	local cmd = map.pld
	local func = cmd_map[cmd.cmd]
	if not func then
		print("invalid data 2", data)
		return
	end

	if cmd.cmd == "wxuser_deal" then
		local a = js.decode(cmd.data)
		local deviceinfo = a.deviceinfo
		send_response_cloud("wxuser_deal", deviceinfo)
	end
	local res = func(cmd.data)
	if map.mod and map.seq then
		local res = mqtt:publish(map.mod, js.encode({seq = map.seq, pld = res}), 0, false)
		local _ = res or log.fatal("publish %s fail", map.mod)
	end
end

local function timeout_save()
	dispatcher.save()
end

local adtype_path = "/tmp/www/adtype"
local cloud_path = "/etc/config/cloud.json"
local function chk_adtype()
	if not lfs.attributes(adtype_path) then
		log.error("missing %s", adtype_path)
		return
	end

	local s = read(adtype_path) 					assert(s)
	local cur_switch = s:find("webui") and 0 or 1

	if not lfs.attributes(cloud_path) then
		return
	end

	local map = js.decode((read(cloud_path)))
	if not map then
		log.error("invalid %s", cloud_path)
		return
	end

	local cfg_switch = tonumber(map.switch) 	assert(cfg_switch)
	if cfg_switch ~= cur_switch then
		log.error("why switch not match %s %s", cur_switch, cfg_switch)
		os.exit(1)
	end
end

local function create_mqtt()
	local auth_module = "a/ac/userauth"
	local mqtt = sandc.new(auth_module)
	mqtt:set_auth("ewrdcv34!@@@zvdasfFD*s34!@@@fadefsasfvadsfewa123$", "1fff89167~!223423@$$%^^&&&*&*}{}|/.,/.,.,<>?")
	mqtt:pre_subscribe(auth_module)
	local ret, err = mqtt:connect("127.0.0.1", 61886)
	local _ = ret or log.fatal("connect fail %s", err)
	mqtt:set_callback("on_message", on_message)
	mqtt:set_callback("on_disconnect", function(...)
		print("on_disconnect", ...)
		log.fatal("mqtt disconnect")
	end)

	mqtt:run()

	return mqtt
end

local function set_timeout(timeout, again, cb)
	se.go(function()
		se.sleep(timeout)
		while true do
			local _ = cb(), se.sleep(again)
		end
	end)
end

local function init()
	local ret = os.execute("lua adchk.lua")
	log.info("init web %s", tostring(ret))
	kernelop.reset()
	auth.init()
end

local function main()
	init()
	auth.run()
	mqtt = create_mqtt()
	set_timeout(10, 10, timeout_save)
	-- set_timeout(5, 5, kernelop.check_network)
	set_timeout(120, 120, dispatcher.update_user)
	set_timeout(1, 20, dispatcher.update_online)
	set_timeout(0.1, 30, dispatcher.adjust_elapse)
	set_timeout(0.1, 60, dispatcher.adjust_offtime)
	set_timeout(30, 30, kernelop.check_ip_route)
	set_timeout(10, 10, chk_adtype)
end

log.setdebug(true)
log.setmodule("ua")

se.run(main)

