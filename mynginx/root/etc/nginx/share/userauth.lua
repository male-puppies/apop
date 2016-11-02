local query = require("query")
local js = require("cjson.safe")

local uri = ngx.var.uri
local host, port = "127.0.0.1", 9989
local ip_pattern = "^[0-9]+%.[0-9]+%.[0-9]+%.[0-9]+$"
local mac_pattern = "^[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]$"


local function read(path)
	local fp, s = io.open(path)
	if fp then
		s = fp:read("*a")
		fp:close()
		return s
	else
		return nil, err
	end
end

local function reply_str(str)
	assert(type(str) == "string")
	ngx.say(str)
	return true
end

local function reply(st, v)
	return reply_str(js.encode({status = st, data = v}))
end

local uri_map = {}
uri_map["/push_to_bind"] = function() -- liuke
	local args = ngx.req.get_uri_args()
	local openid = args.openid 	assert(openid)
	local host_uri = args.host	assert(host_uri)
	if #openid < 20 then
		reply(1, "error openid")
	end

	local param = {
		cmd = uri,
		openid = openid,
		host_uri = host_uri,
	}
	local res, err = query.query(host, port, param)
	res = js.decode(res)

	if #res.status == 8 then
		local timestamp = os.date("%Y%m%d %H%M%S")
		ngx.redirect(string.format("http://%s/wx/keybind/success.html?openid=%s&timestamp=%s", host_uri, openid, timestamp))
	end

	ngx.redirect(string.format("http://%s/wx/keybind/warning.html?status=%s&openid=%s", host_uri, res.data, openid))
	local _ = res and reply_str(res.data) or reply(1, err)
end

uri_map["/cloudonline"] = function()
	local remote_ip = ngx.var.remote_addr
	local param = {
		cmd = uri,
		ip = remote_ip,
	}
	local res, err = query.query(host, port, param)
	local _ = res and reply_str(res) or reply(1, err)
end

uri_map["/cloudlogin"] = function()
	local remote_ip = ngx.var.remote_addr
	local args = ngx.req.get_uri_args()
	local mac, ip = args.mac, args.ip

	ngx.req.read_body()
	local map = ngx.req.get_post_args()
	local username, password = map.username or map.UserName, map.password or map.Password
	if not (ip and mac and username and password) then
		return reply(1, "invalid param ")
	end

	if not (#username > 0 and #username <= 16 and #password >= 4 and #password <= 16) then
		return reply(1, "invalid param 1")
	end

	if not (mac:find(mac_pattern) and ip:find(ip_pattern)) then
		return reply(1, "invalid param 2")
	end

	if remote_ip ~= ip then
		return reply(1, "invalid param 3")
	end

	local param = {
		cmd = uri,
		ip = ip,
		mac = mac,
		username = username,
		password = password,
	}

	local res, err = query.query(host, port, param)
	local _ = res and reply_str(res) or reply(1, err)
end

uri_map["/wxlogin2info"] = function()
	local remote_ip = ngx.var.remote_addr
	local args = ngx.req.get_uri_args()
	local mac, ip = args.mac, args.ip
	if not (mac and ip) then
		return reply(1, "invalid param 1")
	end

	if not (mac:find(mac_pattern) and ip:find(ip_pattern)) then
		return reply(1, "invalid param 2")
	end

	if remote_ip ~= ip then
		return reply(1, "invalid param 3")
	end

	local now = args.now
	if not now then
		ngx.req.read_body()
		local map = ngx.req.get_post_args()
		now = map.now
	end

	if not now then
		return reply(1, "invalid param 4")
	end

	local param = {
		cmd = uri,
		ip = ip,
		mac = mac,
		now = now,
	}

	local res, err = query.query(host, port, param)
	local _ = res and reply_str(res) or reply(1, err)
end

uri_map["/weixin2_login"] = function()
	local remote_ip = ngx.var.remote_addr

	local map = ngx.req.get_uri_args()
	local extend, openid = map.extend, map.openId
	if not extend then
		ngx.req.read_body()
		local map = ngx.req.get_post_args()
		extend, openid = map.extend, map.openId
	end

	if not (extend and openid) then
		ngx.exit(ngx.HTTP_FORBIDDEN)
		return
	end

	local param = {
		cmd = uri,
		ip = remote_ip,
		extend = extend,
		openid = openid,
	}

	local res, err = query.query(host, port, param)
	local _ = res and reply_str(res) or reply(1, err)
end

uri_map["/auto_login"] = function()
	local remote_ip = ngx.var.remote_addr
	local args = ngx.req.get_uri_args()
	local mac, ip, username = args.mac, args.ip , args.username
	if not ip then
		ip = remote_ip
	end

	local param = {
		cmd = uri,
		ip = ip,
	}

	if mac then
		param["mac"] = mac
	end

	if username then
		param["username"] = username
	end

	local res, err = query.query(host, port, param)
	local _ = res and reply_str(res) or reply(1, err)
end

uri_map["/qr_login"] = function()
	local args = ngx.req.get_uri_args()
	local str = ngx.encode_args(args)
	if str ~= "" then
		str = "?" .. str
	end
	ngx.redirect("/admin/login/admin_login/qrlogin.html" .. str)
end

uri_map["/qr_login_action"] = function()
	local remote_ip = ngx.var.remote_addr
	local args = ngx.req.get_uri_args()
	local times, sign, onlinetime = args.t, args.s, args.o

	local param = {
		cmd = uri,
		ip = remote_ip,
		times = times,
		sign = sign,
		onlinetime = onlinetime,
	}

	local res, err = query.query(host, port, param)
	local _ = res and reply_str(res) or reply(1, err)
end

uri_map["/get_qrcode"] = function()
	local args = ngx.req.get_uri_args()
	local times, onlinetime = args.t, args.o
	local param = {
		cmd = uri,
		times = times,
		onlinetime = onlinetime,
	}

	local res, err = query.query(host, port, param)
	local _ = res and reply_str(res) or reply(1, err)
end

uri_map["/authopt"] = function()
	local remote_ip = ngx.var.remote_addr

	local map = ngx.req.get_uri_args()
	local ip, mac = map.ip, map.mac
	if not (ip and mac and mac:find(mac_pattern) and ip:find(ip_pattern)) then
		return reply(1, "invalid param 2")
	end

	if remote_ip ~= ip then
		return reply(1, "invalid param 3")
	end

	local param = {
		cmd = uri,
		ip = remote_ip,
		mac = mac,
	}

	local res, err = query.query(host, port, param)
	local _ = res and reply_str(res) or reply(1, err)
end

uri_map["/bypass_host"] = function()
	local remote_ip = ngx.var.remote_addr

	local map = ngx.req.get_uri_args()
	local ip, mac = map.ip, map.mac
	if not (ip and mac and mac:find(mac_pattern) and ip:find(ip_pattern)) then
		return reply(1, "invalid param 2")
	end

	if remote_ip ~= ip then
		return reply(1, "invalid param 3")
	end

	local param = {
		cmd = uri,
		ip = remote_ip,
		mac = mac,
	}

	local res, err = query.query(host, port, param)
	local _ = res and reply_str(res) or reply(1, err)
end

uri_map["/PhoneNo"] = function()
	local remote_ip = ngx.var.remote_addr
	local args = ngx.req.get_uri_args()
	local mac, ip = args.mac, args.ip
	if not (ip and mac and mac:find(mac_pattern) and ip:find(ip_pattern)) then
		return reply(1, "invalid param 2")
	end

	ngx.req.read_body()
	local map = ngx.req.get_post_args()
	local username = map.UserName

	if not (username and #username > 8) then
		return reply(1, "invalid param phone no")
	end

	local param = {
		cmd = uri,
		ip = ip,
		mac = mac,
		UserName = username,
	}
	local res, err = query.query(host, port, param)
	local _ = res and reply_str(res) or reply(1, err)
end

uri_map["/sms_send"] = function()
	local args = ngx.req.get_uri_args()
	local account_id, shop_id, mac, ip , phoneno = args.account_id, args.shop_id, args.mac, args.ip , args.phoneno
	if not (ip and mac and phoneno) then
		return reply(1, "invalid param ")
	end

	if not (ip and mac and mac:find(mac_pattern) and ip:find(ip_pattern)) then
		return reply(1, "invalid param 2")
	end

	if not (phoneno and #phoneno > 8) then
		return reply(1, "invalid param phone no")
	end

	local param = {
		cmd = uri,
		account_id = account_id,
		shop_id = shop_id,
		ip = ip,
		mac = mac,
		phoneno = phoneno,
	}
	local res, err = query.query(host, port, param)
	local _ = res and reply_str(res) or reply(1, err)
end

uri_map["/sms_check"] = function()
	local args = ngx.req.get_uri_args()
	local account_id, shop_id, mac, ip , phoneno, sms_code = args.account_id, args.shop_id, args.mac, args.ip , args.phoneno, args.sms_code
	if not (ip and mac and phoneno) then
		return reply(1, "invalid param ")
	end

	if not (ip and mac and mac:find(mac_pattern) and ip:find(ip_pattern)) then
		return reply(1, "invalid param 2")
	end

	if not (phoneno and #phoneno > 8 and sms_code) then
		return reply(1, "invalid param phone no or sms_code")
	end

	local param = {
		cmd = uri,
		account_id = account_id,
		shop_id = shop_id,
		ip = ip,
		mac = mac,
		phoneno = phoneno,
		sms_code = sms_code,
	}
	local res, err = query.query(host, port, param)
	local _ = res and reply_str(res) or reply(1, err)
end

uri_map["/passwd_login"] = function()
	local args = ngx.req.get_uri_args()
	local mac, ip, password = args.mac, args.ip, args.password

	if not (ip and mac and password) then
		return reply(1, "invalid param ")
	end
	if not (#password >= 1 and #password <= 10) then
		return reply(1, "invalid param 1")
	end

	if not (ip and mac and mac:find(mac_pattern) and ip:find(ip_pattern)) then
		return reply(1, "invalid param 2")
	end

	local param = {
		cmd = uri,
		ip = ip,
		mac = mac,
		password = password,
	}
	local res, err = query.query(host, port, param)
	local _ = res and reply_str(res) or reply(1, err)
end

uri_map["/turntoads"] = function()
	ngx.redirect("http://10.10.10.10/tmp/www/webui/index.html?flag=wx&url=http://10.10.10.10/tmp/www/webui/login.html")
end

uri_map["/webui/login.html"] = function()
	local remote_ip = ngx.var.remote_addr
	local args = ngx.req.get_uri_args()
	local mac, ip = args.mac, args.ip
	if not (ip and mac and mac:find(mac_pattern) and ip:find(ip_pattern)) then
		return reply(1, "invalid param 1 " .. string.format("%s %s ---", ip, mac))
	end

	local param = {
		cmd = uri,
		ip = ip,
		mac = mac,
	}

	query.query(host, port, param)
	local fp, s = io.open("/tmp/www/webui/login.html")
	if fp then
		s = fp:read("*a")
		fp:close()
	else
		s = "error"
	end
	reply_str(s)
end

local cloud_config_file = "/tmp/www/webui/auth_config.conf"
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

uri_map["/guanzhu"] = function()
	local function jump(adtype)
		if adtype == "local" then
			local file, str = io.open("/tmp/www/webui/ads_config.json")
			if not file then
				return nil
			end

			str = file:read("*a")
			file:close()
			local fmap = js.decode(str)
			if fmap and fmap.g_redirect then
				return fmap.g_redirect
			end
		end
		if adtype == "cloud" then
			return "http://10.10.10.10/turntoads"
		end

		return nil
	end

	local function sethtml(origin_id, jump_href)
		local html = "<!DOCTYPE html><html class='no-js'><head><meta charset='utf-8'><meta name='viewport' content='initial-scale=1.0, maximum-scale=1.0, user-scalable=no'><script>"
		if origin_id then
			html = html .. "var origin_id='" .. origin_id .. "';"
		end

		if jump_href then
			html = html .. "var jump_href='".. jump_href .."';"
		end

		html = html .. "var href;var timestamp=new Date().getTime();if(typeof origin_id!='undefined'){if(typeof jump_href!='undefined'&&jump_href.indexOf('http')!=-1){href='http://open.weixin.qq.com/auto-portal-subscribe.html?origin_id='+origin_id+'&jump_href='+jump_href+'&timestamp='+timestamp;}else{href='http://open.weixin.qq.com/auto-portal-subscribe.html?origin_id='+origin_id+'&jump_href=closeWindow&timestamp='+timestamp;}}else{if(typeof jump_href!='undefined'&&jump_href.indexOf('http')!=-1){href=jump_href;}else{href='http://open.weixin.qq.com/auto-portal-subscribe.html?&jump_href=closeWindow&timestamp='+timestamp;}}window.location.href=href;</script></head><body></body></html>"

		return html
	end

	local adtype = "local"
	local s = read("/tmp/www/adtype")
	if s and s:find("cloudauth") then
		adtype = "cloud"
	end

	local href = jump(adtype) or "closeWindow"

	if adtype == "local" then
		local fp, s = io.open("/etc/config/wx_config.json")
		if not fp then
			return reply_str(sethtml(nil, href))
		end
		s = fp:read("*a")
		fp:close()

		local map = js.decode(s)
		if not map and not map.origin_sw and not map.origin_id then
			return reply_str(sethtml(nil, href))
		end

		if tonumber(map.origin_sw) ~= 1 then
			return reply_str(sethtml(nil, href))
		end

		return reply_str(sethtml(map.origin_id, href))
	end
	if adtype == "cloud" then
		local ret, map = get_cloud_config()
		if not ret then
			return reply_str(sethtml(nil, href))
		end

		if map.authtype and map.authtype == 1 and map.value then
			local a = {}
			if type(map.value) == "string" then
					a = js.decode(map.value)
			else
					a = map.value
			end

			if a and a.force == 1 and a.initid then
				return reply_str(sethtml(a.initid, href))
			end
		end
	end
	return reply_str(sethtml(nil, href))
end

local func = uri_map[uri]
if not func then
	return reply(1, "invalid uri")
end

return func()
