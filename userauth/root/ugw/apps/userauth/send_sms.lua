local log = require("log")
local socket = require("socket")
local url = require("socket.url")
local common = require("common")
local js = require("cjson.safe")


local read, save_safe = common.read, common.save_safe
local content_fmt
local opt

--[[
	local opt = {
		type = 4,
		sno = "LLYD",
		pwd = "LLYD2015",
		msg = "prefix",
		sign = "sign",
		expire = 1,	-- min
	}
]]

local send_type_map = {}
send_type_map[4] = function(phoneno, username, password, content)
	print(phoneno, username, password, content)
	return true, "ok+"
end 

local function send_sms(phoneno, username, password, content)
	local urlfmt = "http://120.132.132.102/WS/BatchSend2.aspx?CorpID=%s&Pwd=%s&Mobile=%s&Content=%s"
	local url = string.format(urlfmt, url.escape(username), url.escape(password), url.escape(phoneno), url.escape(content))
	print(url)
end

local function send(phoneno, password)
	if not opt then 
		return nil, "非法短信发送配置"
	end

	local func = send_type_map[opt.type]
	if not func then 
		return nil, "非法短信服务类型"
	end 

	return func(phoneno, opt.sno, opt.pwd, string.format(content_fmt, password, opt.expire))
end

local function init()
	local path = "/etc/config/sms_config.json"
	local s = read(path)
	if not s then 
		return
	end 
	
	local map = js.decode(s)
	if not (map and map.type and map.sno and map.pwd and map.msg and map.sign and map.expire) then 
		log.error("decode %s fail %s", path, s)
		return 
	end 

	opt = map

	local s = string.format("%s 您的上网验证码是[%%s]，有效期[%%d]分钟。【%s】", opt.msg, opt.sign)
	
	-- TODO convert to gbk 
	content_fmt = s
	return true
end

local function get_expire()
	return opt.expire
end

return {init = init, send = send, get_expire = get_expire}