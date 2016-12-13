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
local g_devid = {}

local auth_step1 = 1
local auth_step2 = 2
local tcp_addr = "tcp://127.0.0.1:9989"
local host_addr_path = "/etc/config/ac_host_cloud.json"
local cloud_config_file = "/tmp/www/webui/auth_config.conf"
local cloud_adconf = { newad = false, opt_map = {}}

local function read_id()
	local id = read("ifconfig eth0 | grep HWaddr | awk '{print $5}'", io.popen)
	id = id:gsub("[ \t\n]", ""):lower()
	assert(#id == 17)
	g_devid = id
end

local function get_cloud_config()
	local f = read(cloud_config_file)
	local map = {}
	if f then
		map = js.decode(f)
		if map and map.authtype then
			return true, map
		end
	end
	return false, nil
end

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

local function get_mac(ip)
	local s = read("/proc/net/arp")
	if not s then
		return nil
	end

	s = s .. "\n"
	local smap = {}
	for line in string.gmatch(s, "(.-)\n") do
		local lip, lmac = line:match("(%d+.%d+.%d+.%d+).-(%w%w:%w%w:%w%w:%w%w:%w%w:%w%w).-")
		if lip and lmac then
			smap[lip] = lmac
		end
	end

	return smap[ip] or nil
end

local cmd_map = {}
cmd_map["/push_to_bind"] = function(map) -- liuke
	read_id()
	map.devid = js.encode(g_devid)
	local urlfmt = string.format("http://%s/wwxkeybind/onekey_bind?openid=%s&devid=%s", map.host_uri, map.openid, map.devid)
	local url = string.format("curl '%s'", urlfmt)
	local rs = read(url, io.popen) assert(rs)
	local m = js.decode(rs)

	if m.status == 1 and type(m.message) == "table" then
		local parrm = {
			ac_port = 61886,
			switch = 0,
			descr = map.openid,
			ac_host = map.host_uri,
			account = map.openid,
		}
		os.remove("/etc/config/cloud.json")
		local cmd = string.format("echo '%s' > /etc/config/cloud.json", js.encode(parrm))
		local r = read(cmd, io.popen)	assert(r)

		local course_cmd = string.format("/etc/init.d/base restart;/etc/init.d/cloudcli restart")
		local r = read(course_cmd, io.popen)
		if string.find(r, "^stop") and (#r == 24) then
			-- restart success
			return {status = "redirect"}
		end

		return  {status = "error", data = 6}
	end

	if m.status == 2 or m.status == 3 or m.status == 4 or m.status == 5 or m.status == 6 then
		-- user bind fail or user device already binded
		return {status = "error", data = m.status}
	end
end

cmd_map["/cloudonline"] = function(map)
	return {status = 1, data = authopt}
end

cmd_map["/authopt"] = function(map)
	local ip, mac = map.ip, map.mac
	if not (ip and mac) then
		return {status = 1, data = "invalid param"}
	end
	-- if authopt.wx and authopt.wx ~= 0 then
	-- 	kernelop.bypass_mac(ip, mac, auth_step1)
	-- end
	return {wx = authopt.wx, sms = authopt.sms}
end

cmd_map["/bypass_host"] = function(map)
	local ip, mac = map.ip, map.mac
	if not (ip and mac) then
		return {status = 1, data = "invalid param"}
	end

	kernelop.bypass_mac(ip, mac, auth_step1)
	return {status = 0, data = "ok"}
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

	wx_wait.ext_map[mac] = extend
	table.insert(wx_wait.queue, {extend = extend, mac = mac, active = sec})
	kernelop.bypass_mac(map.ip, map.mac, auth_step2)
	return res
end

local function add_wx_user(openid)
	local ul = userlist.ins()
	if ul:exist(openid)  then
		return
	end
	local arr = {}
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
	dispatcher.user_add({group = "default", data = arr}, true)
end

local function add_auto_user(name)
	local ul = userlist.ins()
	if ul:exist(name)  then
		return
	end
	local arr = {}
	local user = {
			name = name,
			pwd = "123456",
			desc = "一键认证用户",
			enable = 1,
			multi = 0,
			bind = "none",
			maclist = {},
			expire = {0, os.date("%Y%m%d") .. " 000000"},
			remain = {0, 0},
		}
	table.insert(arr, user)
	dispatcher.user_add({group = "default", data = arr}, true)
end

local function add_qrcode_user(name)
	local ul = userlist.ins()
	if ul:exist(name)  then
		return
	end
	local arr = {}
	local user = {
			name = name,
			pwd = "123456",
			desc = "二维码认证用户",
			enable = 1,
			multi = 0,
			bind = "none",
			maclist = {},
			expire = {0, os.date("%Y%m%d") .. " 000000"},
			remain = {0, 0},
		}
	table.insert(arr, user)
	dispatcher.user_add({group = "default", data = arr}, true)
end

local function add_passwd_user(name, password)
	local ul = userlist.ins()
	if ul:exist(name)  then
		return
	end
	local arr = {}
	local user = {
			name    = name,
			pwd     = password,
			desc    = "密码认证",
			enable  = 1,
			multi   = 0,
			bind    = "none",
			maclist = {},
			expire  = {0, os.date("%Y%m%d") .. " 000000"},
			remain  = {0, 0},
		}
	table.insert(arr, user)
	dispatcher.user_add({group = "passwd_group", data = arr}, true)
end

function encodeURI(s)
    s = string.gsub(s, "([^%w%.%- ])", function(c) return string.format("%%%02X", string.byte(c)) end)
    return string.gsub(s, " ", "+")
end

local function http_post_request(url, data, filename)
	if filename == nil then filename ="/tmp/urlreturn" end
	local cmd = string.format("rm -f %s; curl -o %s \"%s\" -d \"%s\" &", filename, filename, url, data)
	print("http_post_request cmd->", cmd)
	os.execute(cmd)
	for i = 1, 100 do
		se.sleep(0.1)
		local result = read(filename)
		if result then
			print("http_post_request result->", result)
			return result
		end
	end
	return nil, "timeout"
end

local cloud_file = "/etc/config/cloud.json"
local function get_cloud_host()
	local cloud_host = ""
	local account = ""
	local f = read(cloud_file)

	if f then
		local map = js.decode(f)
		if map and map.ac_host and map.ac_host ~= "" then
			cloud_host = map.ac_host
			account = map.account
		end
	end
	return cloud_host, account
end


local function send_authtype_stat(authtype, ip, mac, username)
	if not (ip and mac and username) then
		return false
	end

	local cloud_host,_ = get_cloud_host()
	if cloud_host == "" then
		return false
	end

	if not cloud_adconf.opt_map then
		return false
	end

	local map = cloud_adconf.opt_map
	local url = string.format("http://%s/statistics/add_stat_type?", cloud_host)
	local data = string.format("authtype=%s&shop_id=%s&account_id=%s&ip=%s&mac=%s&devid=%s&username=%s", authtype, map.shop_id, map.account_id, ip, mac, g_devid, username)

	local result = http_post_request(url, data, "/tmp/authtype_stat")
	if result then
		local map = js.decode(result)
		if map and map.r == 0 then
			return true
		end
	end
	return false
end

local function openid_is_funs(openid)
	local res = true
	local cloud_host, _ = get_cloud_host()

	local appid = wx_param.appid
	if appid and cloud_host ~= "" then
		local url = string.format("http://%s/admin/ci/wxcgi?cmd=GetWxuserInfo", cloud_host)
		local data_url = string.format("openid=%s&appid=%s", openid, appid)
		local result = http_post_request(url, data_url)
		print("GetWxuserInfo: ", result)
		if result then
			local map = js.decode(result)
			if map and map.sub and map.sub == "unsubscribe"
				then res = false
			end
		end
	end
	return res
end
----------------------------------------------------------------

cmd_map["/weixin2_login"] = function(map)
	local flag = 0
	local extend, openid = map.extend, map.openid
	if not (extend and openid) then
		return {status = 1, data = "invalid param"}
	end

	local ip, mac = extend:match("(.-),(.-),")
	if not (ip and mac) then
		return {status = 1, data = "invalid param1"}
	end
	if string.find(extend, "wx_scan") then
		flag = 1
	else
		local item = wx_wait.ext_map[mac]
		if not item then
			print("invalid param2")
			return {status = 1, data = "invalid param2"}
		end
		wx_wait.ext_map[mac] = nil
		flag = 1
	end

	if flag == 1 then
		add_wx_user(openid)

		if cloud_adconf.newad then
			if  wx_param.force and wx_param.force == 1 and not openid_is_funs(openid) then
				dispatcher.login_success(mac, ip, openid, 180)
			else
				dispatcher.login_success(mac, ip, openid, cloud_adconf.opt_map.expiretime)
			end
			send_authtype_stat(1, ip, mac, openid)
		else
			dispatcher.login_success(mac, ip, openid)
		end

		local s = read("/etc/config/authopt.json")
		if s then
			local map = js.decode(s)
			if map and map.redirect and map.redirect ~= "" then
				return {status = 0, data = map.redirect}
			end
		end
		return {status = 0, data = "ok"}
	end
end

cmd_map["/auto_login"] = function(map)
	local ads_config = read("/tmp/www/webui/ads_config.json")

	if not ads_config and not cloud_adconf.newad then
		return {status = 1, data = "配置错误 file err"}
	end

	local g_map, g_redirect = js.decode(ads_config), ""
	local enable = 0

	if  (g_map and g_map.auth and g_map.auth.auto == "true") then
		enable =1
		g_redirect = g_map.g_redirect or ""
		--return {status = 1, data = "未开启一键认证"}
	end
	if cloud_adconf.newad and cloud_adconf.opt_map.authtype:find("2") then
		enable = 1
	end
	if enable == 0 then
		return {status = 1, data = "auto off 未开启一键认证"}
	end

	local ip, mac, username = map.ip, map.mac, map.username
	if not ip then
		return {status = 1, data = "invallid 无效参数"}
	end

	if not mac then
		mac = get_mac(ip)
	end
	if not mac then
		return {status = 1, data = "mac err 未找到的MAC地址"}
	end

	if not username then
		username = "auto-" .. mac
	end
	add_auto_user(username)

	if cloud_adconf.newad and cloud_adconf.opt_map.authtype:find("2") then
		dispatcher.login_success(mac, ip, username, cloud_adconf.opt_map.expiretime)
		send_authtype_stat(2, ip, mac, username)
	else
		dispatcher.login_success(mac, ip, username)
	end

	if g_redirect and g_redirect ~= "" then
		return {status = 0, data = g_redirect}
	end

	local s = read("/etc/config/authopt.json")
	if s then
		local map = js.decode(s)
		if map and map.redirect and map.redirect ~= "" then
			return {status = 0, data = map.redirect}
		end
	end
	return {status = 0, data = "ok"}
end

cmd_map["/qr_login_action"] = function(map)
	local ip, times, sign, onlinetime = map.ip, map.times, map.sign, map.onlinetime
	if not (ip and times and sign) then
		return {status = 1, data = "参数错误"}
	end

	local qr_config = read("/etc/config/qr_config.json")
	if not qr_config then
		return {status = 1, data = "配置错误"}
	end

	local qr_map = js.decode(qr_config)
	if not onlinetime or onlinetime == "" then
		onlinetime = qr_map.onlinetime
	end

	if not (qr_map and onlinetime and qr_map.qr_key and qr_map.expiry) then
		return {status = 1, data = "未开启二维码认证"}
	end

	local msign = md5.sumhexa(qr_map.qr_key .. "qrcode" .. times .. onlinetime)
	msign = msign:sub(1, 8)
	if sign ~= msign then
		return {status = 1, data = "二维码错误"}
	end

	if tonumber(qr_map.expiry) ~= 0 and (os.time() - times) > (tonumber(qr_map.expiry) * 60) then
		return {status = 1, data = "二维码已过期"}
	end

	local mac = get_mac(ip)
	if not mac then
		return {status = 1, data = "请检查是否连接正确wifi"}
	end

	local username = "qrcode-" .. mac
	add_qrcode_user(username)
	dispatcher.login_success(mac, ip, username, (onlinetime * 60))

	local ads_config, g_redirect = read("/tmp/www/webui/ads_config.json")
	if ads_config then
		local g_map = js.decode(ads_config)
		if g_map and g_map.g_redirect then
			g_redirect = g_map.g_redirect
		end
	end

	if g_redirect then
		return {status = 0, data = g_redirect}
	end

	local s = read("/etc/config/authopt.json")
	if s then
		local map = js.decode(s)
		if map and map.redirect and map.redirect ~= "" then
			return {status = 0, data = map.redirect}
		end
	end
	return {status = 0, data = "ok"}
end

cmd_map["/get_qrcode"] = function(map)
	local times, onlinetime = map.times, map.onlinetime
	if not times then
		return {status = 1, data = "参数错误"}
	end

	local qr_config = read("/etc/config/qr_config.json")
	if not qr_config then
		return {status = 1, data = "配置错误"}
	end

	local qr_map = js.decode(qr_config)
	if not (qr_map and qr_map.qr_key and qr_map.onlinetime) then
		return {status = 1, data = "未开启二维码认证"}
	end
	if not onlinetime or onlinetime == "" then
		onlinetime = qr_map.onlinetime
	end
	local str = qr_map.qr_key .. "qrcode" .. times .. onlinetime
	local cmd = string.format("echo -n '%s' | md5sum | cut -d ' ' -f1", str)
	local sign = read(cmd, io.popen)
	if not sign then
		return {status = 1, data = ""}
	end

	local s = sign:sub(1, 8)

	local url = string.format("http://10.10.10.10/qr_login?t=%s&s=%s&o=%s", times, s, onlinetime)
	return {status = 0, data = url}
end

cmd_map["/cloudlogin"] = function(map)
	local expire
	if authopt.adtype == "cloud" and cloud_adconf.newad and cloud_adconf.opt_map.authtype:find("5") then
		expire = cloud_adconf.opt_map.expiretime
	end

	local ret = dispatcher.auth(map, expire)
	if ret.status == 0 and authopt.adtype == "cloud" then
		send_authtype_stat(5, map.ip, map.mac, map.username)
	end

	return ret
end

local function save_sms_user(phoneno, password, expire)
	local expire_a = {}
	if not expire then
		expire_a = {0, os.date("%Y%m%d") .. " 000000"}
	else
		expire_a = {1, expire}
	end
	local user = {
		name = phoneno,
		pwd = password,
		desc = "短信认证用户",
		enable = 1,
		multi = 0,
		bind = "none",
		maclist = {},
		expire  = expire_a,
		remain  = {0, 0},
	--	utype = usr.UT_SMS,
	}
	dispatcher.user_add({group = "default", data = {user}}, true)
end

local last_sms_map, sms_interval = {}, 120
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

local function sms_user_login(map)
	print("map", js.encode(map))
	local phoneno, ip, mac, sms_code = map.phoneno, map.ip, map.mac, map.sms_code 	assert(phoneno and ip and mac)

	local expire = cloud_adconf.opt_map.expiretime
	save_sms_user(phoneno, sms_code)
	dispatcher.login_success(mac, ip, phoneno, expire)
	send_authtype_stat(4, ip, mac, phoneno)

	if g_redirect and g_redirect ~= "" then
		return {status = 0, data = g_redirect}
	end

	local s = read("/etc/config/authopt.json")
	if s then
		local map = js.decode(s)
		if map and map.redirect and map.redirect ~= "" then
			return {status = 0, data = map.redirect}
		end
	end
	return {status = 0, data = "ok"}
end

cmd_map["/sms_send"] = function (map)
	if not cloud_adconf.newad or not (cloud_adconf.opt_map.authtype and cloud_adconf.opt_map.authtype:find("4")) then
		return {status = 1, data = "未启用短信认证"}
	end

	local account_id, shop_id, phoneno, ip, mac = map.account_id, map.shop_id, map.phoneno, map.ip, map.mac
	if not (account_id and shop_id and phoneno) then
		return  {status = 1, data = "非法参数"}
	end

	local mac_b = get_mac(ip)
	if not mac_b or mac_b ~= mac then
		return {status = 1, data = "请检查是否连接正确wifi"}
	end

	local cloud_host, _ = get_cloud_host()
	if cloud_host == "" then
		return {status = 1, data = "请配置云端地址"}
	end

	local ol = onlinelist.ins()
	if ol:exist_user(phoneno) then
		return {status = 1, data = "该用户已上线，请重新检查手机号是否正确"}
	end

	local last, now = last_sms_map[phoneno], cursec()
	if last and now - last <= sms_interval then
		return {status = 1, data = "一个号码,2分钟之内,只允许注册一次,请注意查收短信"}
	end
	last_sms_map[phoneno] = now


	local url = string.format("http://%s/sms/sms_send", cloud_host)
	local data = string.format('phoneno=%s&shop_id=%s&account_id=%s',phoneno, shop_id, account_id)

	local res = http_post_request(url, data)
	if res then
		print("sms_send:", res)
		local map = js.decode(res)
		if map and map.r and map.r == 1 then
			return {status = 0 , data = map.d}
		end
		if map and map.r and map.r == 0 then
			return {status = 1 , data = map.d}--"发送短信失败，请重试"}
		end
	end

	return {status = 1 , data = "网络错误，请重试"}
end

cmd_map["/sms_check"] = function(map)
	local account_id, shop_id, phoneno, sms_code, ip, mac = map.account_id, map.shop_id, map.phoneno, map.sms_code, map.ip, map.mac
	assert(account_id and shop_id and phoneno and sms_code)

	local cloud_host, _ = get_cloud_host()
	if cloud_host == "" then
		return {status = 1, data = "请配置云端地址"}
	end

	local ol = onlinelist.ins()
	if ol:exist_user(phoneno) then
		return {status = 1, data = "该用户已上线，请重新检查手机号是否正确"}
	end

	local url = string.format("http://%s/sms/check_sms_code", cloud_host)
	local data = string.format('phoneno=%s&shop_id=%s&account_id=%s&sms_code=%s',phoneno, shop_id, account_id,sms_code)

	local res = http_post_request(url, data)
	if res then
		print("sms_check:", res)
		local res_map = js.decode(res)
		if res_map and res_map.r and res_map.r == 1 then
			return sms_user_login(map)
		end

		if res_map and res_map.r and res_map.r == 0 then
			return {status = 1 , data = res_map.d}--"smscode 验证码错误，请重新输入"}
		end
	end
	return {status = 1 , data ="网络错误，请重试"}
end


cmd_map["/passwd_login"] = function(map)
	if not (cloud_adconf.opt_map.authtype and cloud_adconf.opt_map.authtype:find("3") and cloud_adconf.opt_map.value["3"]) then
		return {status = 1, data = "未启用密码认证"}
	end

	local password, ip, mac = map.password, map.ip, map.mac
	if not(password and ip and mac) then
		return {status = 1, data = "参数错误"}
	end

	local mac_b = get_mac(ip)
	if not mac_b or mac_b ~= mac then
		return {status = 1, data = "请检查是否连接正确wifi"}
	end

	-- local a = {}
	-- if type(cloud_adconf.opt_map.value) == "string" then
	-- 	a = js.decode(cloud_adconf.opt_map.value)
	-- else
	-- 	a = cloud_adconf.opt_map.value
	-- end
	local a = cloud_adconf.opt_map.value["3"]
	if not (a.password and a.password == password) then
		return {status = 1, data = "密码错误"}
	end

	local expire = cloud_adconf.opt_map.expiretime
	add_passwd_user(mac, password)
	dispatcher.login_success(mac, ip, mac, expire)
	send_authtype_stat(3, ip, mac, mac)

	if g_redirect and g_redirect ~= "" then
		return {status = 0, data = g_redirect}
	end

	local s = read("/etc/config/authopt.json")
	if s then
		local map = js.decode(s)
		if map and map.redirect and map.redirect ~= "" then
			return {status = 0, data = map.redirect}
		end
	end

	return {status = 0, data = "ok"}
end

-------------------------------------------------

cmd_map["/webui/login.html"] = function(map)
	--kernelop.bypass_mac(map.ip, map.mac, auth_step1)
	--if authopt.wx and authopt.wx ~= 0 then
	--	kernelop.bypass_mac(map.ip, map.mac, auth_step1)
	--end
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

	local init_cloudopt = function ()
		if authopt.adtype == "cloud" then
			local ret, map = get_cloud_config()
			if not ret then
				return
			end

			cloud_adconf.newad = true
			cloud_adconf.opt_map = map
			cloud_adconf.opt_map.expiretime = cloud_adconf.opt_map.expiretime * 60
			if map.authtype and map.authtype:find("1") and map.value and  map.value["1"]then
				local a = map.value["1"]
				wx_param = {appid = a.appid, shop_id = a.wxshopid, sk = a.secretkey, ssid = a.ssid, force = a.force, initid = a.initid}
			end
			read_id()
		end
	end

	local _ = init_authopt(), init_wechat(), init_sms(), init_cloudopt()
	dispatcher.set_authopt(authopt)
end

local function run()
	se.go(start_server)
	send_sms.run()
	math.randomseed(os.time())
	set_timeout(5, 5, clear_wx_wait)
end

return {run = run, init = init}
