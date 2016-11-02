local se = require("se")
local lfs = require("lfs")
local log = require("log")
local socket = require("socket")
local url = require("socket.url")
local common = require("common")
local js = require("cjson.safe")

local opt, sms_counter
local sms_enable = false
local read, save_safe = common.read, common.save_safe
local sms_counter_path = "/etc/config/sms_counter.json"

-- 	local opt = {
-- 		type = 4,
-- 		sno = "LLYD",
-- 		pwd = "LLYD2015",
-- 		msg = "prefix",
-- 		sign = "sign",
-- 		expire = 1,	-- min
-- 	}

-- print(js.encode(opt))
local function inc_counter(ok)
	if ok then
		sms_counter.success = sms_counter.success + 1
	else
		sms_counter.fail = sms_counter.fail + 1
	end
	return true
end

local function sms_result(b, s)
	if b then
		return inc_counter(true)
	end
	log.error("send sms fail %s", s)
	return inc_counter()
end

local seq = 0
local send_type_map = {}

local function utf8_to_gbk(content)
	local cmd = string.format("echo '%s' | iconv -s -f utf-8 -t gbk", content)
	local content = read(cmd, io.popen)
	if not (content and #content > 0) then
		log.error("cmd fail %s", cmd)
		return nil, "iconv fail"
	end
	return content
end

send_type_map[1] = function(phoneno, username, password, content)
	local content, err = utf8_to_gbk(content)
	if not content then
		return nil, err
	end

	local urlfmt = "http://service.winic.org:8009/sys_port/gateway/?id=%s&pwd=%s&to=%s&content=%s&time="
	local url = string.format(urlfmt, username, password, phoneno, url.escape(content))
	local path = string.format("/tmp/sms/%d.txt", seq)
	seq = seq + 1

	local timeout = 10
	local cmd = string.format("./send_sms.sh '%s' '%d' '%s' &", url, timeout, path)
	local ret = os.execute(cmd)
	if not (ret == true or ret == 0) then
		return nil, "发送短信失败：1"
	end

	local start = se.time()
	while se.time() - start <= timeout do
		se.sleep(0.1)
		if lfs.attributes(path) then
			local s = read(path)

			if s:find("^0 000") then
				return sms_result(true)
			end
			sms_result(false, s)
			break
		end
	end

	return nil, "发送短信失败：2"
end

send_type_map[4] = function(phoneno, username, password, content)
	local content, err = utf8_to_gbk(content)
	if not content then
		return nil, err
	end

	local urlfmt = "http://120.132.132.102/WS/BatchSend2.aspx?CorpID=%s&Pwd=%s&Mobile=%s&Content=%s"
	local url = string.format(urlfmt, url.escape(username), url.escape(password), url.escape(phoneno), url.escape(content))

	local path = string.format("/tmp/sms/%d.txt", seq)
	seq = seq + 1

	local timeout = 10
	local cmd = string.format("./send_sms.sh '%s' '%d' '%s' &", url, timeout, path)
	local ret = os.execute(cmd)
	if not (ret == true or ret == 0) then
		return nil, "发送短信失败：1"
	end

	local start = se.time()
	while se.time() - start <= timeout do
		se.sleep(0.1)
		if lfs.attributes(path) then
			local s = read(path)

			if s:find("^0 (%d+)") then
				return sms_result(true)
			end
			sms_result(false, s)
			break
		end
	end

	return nil, "发送短信失败：2"
end
-- local function main()
-- 	print(send_type_map[4]("15914180656", "LLYD", "LLYD2015", "尼玛 您的上网验证码是[1234], 有效期[5]分钟。【全民上网】"))
-- end
-- se.run(main)
local function send(phoneno, password)
	if not opt then
		return nil, "非法短信发送配置"
	end

	local func = send_type_map[opt.type]
	if not func then
		return nil, "非法短信服务类型"
	end

	local content_fmt = string.format("%s 您的上网验证码是[%%s]，有效期[%%d]分钟。【%s】", opt.msg, opt.sign)
	return func(phoneno, opt.sno, opt.pwd, string.format(content_fmt, password, opt.expire))
end

local function get_expire()
	return opt.expire
end

local function init()
	local path = "/etc/config/sms_config.json"
	local map = js.decode((read(path)))
	if not (map and map.type and map.sno and map.pwd and map.msg and map.sign and map.expire) then
		log.error("decode %s fail", path)
		return
	end

	map.redirect = map.redirect and map.redirect or ""
	opt = map

	os.execute("test -e /tmp/sms/ || mkdir -p /tmp/sms/; rm -rf /tmp/sms/*")

	local map = js.decode((read(sms_counter_path)))
	if not (map and map.success and map.fail) then
		log.info("invalid %s, reset", sms_counter_path)
		sms_counter = {success = 0, fail = 0}
	else
		sms_counter = map
	end

	sms_enable = true

	return true
end

local function new_timeout_save_sms_counter()
	local last = {success = sms_counter.success, fail = sms_counter.fail}
	return function()
		while true do
			se.sleep(1)
			-- print(js.encode(last), js.encode(sms_counter))
			if not (last.success == sms_counter.success and last.fail == sms_counter.fail) then
				local nmap = js.decode((read(sms_counter_path))) or {success = 0, fail = 0}
				if nmap.success == 0 and nmap.fail == 0 then
					log.info("user reset counter to 0")
					sms_counter.fail = sms_counter.fail > 0 and 1 or 0
					sms_counter.success = sms_counter.success > 0 and 1 or 0
				end
				save_safe(sms_counter_path, js.encode(sms_counter))
				last.success, last.fail = sms_counter.success, sms_counter.fail
			end
		end
	end
end

local function run()
	if not sms_enable then
		print("sms disabled")
		return
	end
	se.go(new_timeout_save_sms_counter())
end

return {init = init, run = run, send = send, get_expire = get_expire}