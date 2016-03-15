local se = require("se")
local log = require("log")
local md5 = require("md5") 
local usr = require("user")
local common = require("common")
local js = require("cjson.safe")
local request = require("request") 
local kernelop = require("kernelop") 
local dispatcher = require("dispatcher")
local userlist = require("userlist")
local onlinelist = require("onlinelist")
local send_sms = require("send_sms")

local read = common.read

local wx_param = {}
local wx_auth_timeout = 20
local wx_wait = {queue = {}, ext_map = {}}
local authopt = {sms = 0, wx = 0, adtype = "local"}

local tcp_addr = "tcp://127.0.0.1:9989"

local function cursec()
	return math.floor(se.time())
end

local function set_timeout(timeout, again, cb)
	se.go(function()
		se.sleep(timeout)
		while true do 
			local _ = cb(), se.sleep(again)
		end
	end)
end

local cmd_map = {}
cmd_map["/cloudonline"] = function(map)
	return {status = 0, data = authopt}
end 

cmd_map["/authopt"] = function(map)
	local ip, mac = map.ip, map.mac
	if not (ip and mac) then 
		return {status = 1, data = "invalid param"}
	end
	if authopt.wx and authopt.wx ~= 0 then
		kernelop.bypass_mac(ip, mac)
	end
	return {wx = authopt.wx, sms = authopt.sms}
end

cmd_map["/wxlogin2info"] = function(map)
	if authopt.adtype == "local" and authopt.wx ~= 1 then 
		return {status = 1, data = "not support wx"}
	end

	local ip, mac, now = map.ip, map.mac, map.now 
	if not (ip and mac and now) then 
		return {status = 1, data = "logical error"}
	end
	
	local sec, n = cursec(), wx_param
	local extend = table.concat({ip, mac, sec}, ",")
	local appid, timestamp, shop_id, authurl, ssid, bssid, sk = n.appid, now, n.shop_id, "http://10.10.10.10/weixin2_login", n.ssid, "", n.sk
	local arr = {appid, extend, timestamp, shop_id, authurl, mac, ssid, bssid, sk}
	local sign = md5.sumhexa(table.concat(arr))
	local res = {
		AppID = appid,
		Extend = extend,
		TimeStamp = timestamp,
		Sign = sign,
		ShopID = shop_id,
		AuthUrl = authurl,
		Mac = mac,
		SSID = ssid,
		BSSID = bssid,
	}

	print("cache", extend, sec, mac)
	wx_wait.ext_map[mac] = extend
	table.insert(wx_wait.queue, {extend = extend, mac = mac, active = sec})
	
	return res
end 

local openid_map = {}
local function add_wx_user(openid)
	openid_map[openid] = 1 
end

local function save_wx_user()
	local del, arr = {}, {}
	for openid in pairs(openid_map) do 
		local user = {
			name = openid,
			pwd = "123456",
			desc = "微信认证用户",
			enable = 1,
			multi = 0,
			bind = "none",
			maclist = {},
			expire = {0, os.date("%Y%m%d") .. " 000000"},
			remain = {0, 0},
		}
		table.insert(arr, user)
		table.insert(del, openid)
	end

	if #del == 0 then 
		return 
	end 

	for _, openid in ipairs(del) do 
		assert(openid)
		openid_map[openid] = nil
	end 

	dispatcher.user_add({group = "default", data = arr}, true)
end

cmd_map["/weixin2_login"] = function(map)  
	local extend, openid = map.extend, map.openid
	if not (extend and openid) then 
		return {status = 1, data = "invalid param"}
	end

	local ip, mac = extend:match("(.-),(.-),")
	if not (ip and mac) then 
		return {status = 1, data = "invalid param1"}
	end

	local item = wx_wait.ext_map[mac]
	if not item then 
		return {status = 1, data = "invalid param2"}
	end
	wx_wait.ext_map[mac] = nil

	add_wx_user(openid)

	print("wx auth ok", ip, mac)
	dispatcher.login_success(mac, ip, openid)
	return {status = 0, data = "ok"}
end

cmd_map["/cloudlogin"] = function(map)  
	return dispatcher.auth(map)	 
end

local function save_sms_user(phoneno, password, expire)
	local user = {
		name = phoneno,
		pwd = password,
		desc = "短信认证用户",
		enable = 1,
		multi = 0,
		bind = "none",
		maclist = {},
		expire = {1, expire},
		remain = {0, 0},
	--	utype = usr.UT_SMS,
	}
	dispatcher.user_add({group = "default", data = {user}}, true)
end 

local last_sms_map, sms_interval = {}, 300
cmd_map["/PhoneNo"] = function(map)   
	if authopt.adtype == "local" and authopt.sms ~= 1 then 
		return {status = 1, data = "authopt disable"}	
	end

	local phoneno, ip, mac = map.UserName, map.ip, map.mac 	assert(phoneno and ip and mac)
	local ul, ol = userlist.ins(), onlinelist.ins()
	if ol:exist_mac(mac) then
		return {status = 0, data = "already online"}
	end

	local last, now = last_sms_map[phoneno], cursec()
	if last and now - last <= sms_interval then 
		return {status = 1, data = string.format("一个号码,5分钟之内,只允许注册一次,请注意查收短信", sms_interval)}
	end
	last_sms_map[phoneno] = now

	local password = "" .. math.random(1000, 9999)
	
	local ret, err = send_sms.send(phoneno, password) 
	if not ret then 
		return {status = 1, data = err}
	end

	local expire = os.date("%Y%m%d %H%M%S", os.time() + send_sms.get_expire() * 60)
	local user = ul:get(phoneno)
	if not user then
		save_sms_user(phoneno, password, expire)
	else
		ul:set(phoneno, user:set_pwd(password):set_expire({1, expire}))
		ul:save()
	end
	
	return {status = 0, data = "ok"}
end

cmd_map["/webui/login.html"] = function(map)  
	if authopt.wx and authopt.wx ~= 0 then
		kernelop.bypass_mac(map.ip, map.mac)
	end
	return {status = 0, data = "ok"}
end


local function clear_wx_wait()
	local max, now = 0, cursec()
	for i, item in ipairs(wx_wait.queue) do
		if now - item.active <= wx_auth_timeout then 
			break 
		end
		max = i

		local mac = item.mac
		local extend = wx_wait.ext_map[mac]
		if item.extend == extend then 
			print("delete timeout", extend)
			wx_wait.ext_map[mac] = nil
		end
	end

	for i = 1, max do 
		table.remove(wx_wait.queue, 1)
	end
end

local function start_server()
	local function dispatcher(data)
		local map = js.decode(data)
		if not (map and map.cmd and cmd_map[map.cmd]) then 
			return {status = 1, data = "invalid cmd"}
		end

		return cmd_map[map.cmd](map)
	end

	local serv, err = se.listen(tcp_addr) 
	local _ = serv or log.fatal("listen %s fail %s", tcp_addr, err)
	while true do
		local cli = se.accept(serv)
		local _ = cli and request.new(cli, dispatcher):run() 
	end
end

local function init() 
	local init_authopt = function()
		local s = read("/tmp/www/adtype")
		if s and s:find("cloudauth") then 
			authopt.adtype = "cloud"
		end
		
		local s = read("/etc/config/authopt.json")
		local map = js.decode(s) or {}
		local sms, wx = tonumber(map.sms or "0") or 0, tonumber(map.wx or "0") or 0
		authopt.sms, authopt.wx, authopt.redirect = sms, wx, map.redirect
	end 

	local init_wechat = function()
		local s = read("/etc/config/wx_config.json")
		local map = js.decode(s)
		if not map then 
			authopt.wx = 0
			log.error("invalid wx config, reset wx to 0")
			return
		end 

		local shop_id, appid, sk, ssid = map.shop_id, map.appid, map.secretkey, map.ssid
		if not (shop_id and appid and sk and ssid) then 
			authopt.wx = 0
			log.error("invalid wx config, %s", s)
			return
		end 

		wx_param = {appid = appid, shop_id = shop_id, sk = sk, ssid = ssid}
	end 

	local init_sms = function()
		if not send_sms.init() then 
			log.info("send_sms.init fail. reset authopt.sms = 0")
			authopt.sms = 0
		end
	end 

	local _ = init_authopt(), init_wechat(), init_sms()
	dispatcher.set_authopt(authopt)
end

local function run()
	se.go(start_server)
	send_sms.run()
	math.randomseed(os.time())
	set_timeout(5, 5, clear_wx_wait)
	set_timeout(5, 5, save_wx_user)
end

return {run = run, init = init}
