-- author: gl

local js		= require("cjson.safe")
local log		= require("log")
local se		= require("se")
local fwlib		= require("fwlib")
local snlib		= require("sn")
local common	= require("common")
local dlcode	= require("dlcode")


local timeout = 40
local REQ_URL = "register/api"
local REQ_HOST = "https://safe.trylong.cn"
local CACERT_PATH = "/etc/ssl/certs/puppies.pem"
local FACTORY_MAC = "78d38dc3857e"

local action
local cmd_map = {}
local REG_PATH = "/etc/config/register"
local FILE_PATH = "/tmp/Download"
local valid_get_pars, get_sn = fwlib.valid_get_pars, fwlib.get_sn
local read, save, file_exist = common.read, common.save_safe, common.file_exist
local get_html, gen_tm_offset = fwlib.get_html, fwlib.gen_tm_offset
local gen_url, check_valid_reg = fwlib.gen_url, fwlib.check_valid_reg

-- 获取对应命令需要的参数
-- @cmd：命令
-- @map：回应时需要的参数
local function gen_post_pars(cmd, map)
	if not cmd then
		return nil, "cmd was nil"
	end

	local sn = get_sn()
	if not sn then
		return nil, "get sn fail"
	end

	if cmd == "register_check" then
		local devid = snlib.get_devid()
		if not devid then
			return nil, "get devid fail"
		end

		local cmd = "cat /proc/uptime | awk '{print $1}'"
		local uptime = read(cmd, io.popen)
		if not uptime then
			return nil, "get uptime fail"
		end
		uptime = uptime:match("%d+%.")
		if not string.find(uptime, "%d+") then
			return nil, "uptime was no number"
		end

		uptime = tonumber(uptime) % 86400

		cmd = "cat /etc/openwrt_version"
		local version = read(cmd, io.popen)
		if not version then
			return nil, "get version fail"
		end
		version = version:gsub("\n", "")
		cmd = "cat /etc/openwrt_release | grep 'DISTRIB_ID'| awk -F '=' '{print $2}'"
		local release = read(cmd, io.popen)
		if not release then
			return nil, "get release fail"
		end
		release = release:gsub("['\n]", "")
		local ext = {
			version = version,
			release = release,
		}

		if not action then
			return nil, "action was nil"
		end

		local pars_map = {
			sn		= sn,
			devid	= devid,
			tm		= uptime,
			status	= action,
			ext		= ext,
		}

		return pars_map
	end

	if cmd == "reply_ack" then
		local result, err = valid_get_pars(cmd, map)
		if not result then
			return nil, err
		end

		local pars_map = {
			sn = sn,
			id = map.detail.id,
		}

		return pars_map
	end
end

-- 给云端回应
local function reply_ack(map)
	local pars_map, err = gen_post_pars("reply_ack", map)				-- 对应命令需要的参数表
	if not pars_map then
		return false, err
	end

	local url, err = gen_url(REQ_URL, REQ_HOST, "reply_ack", pars_map, timeout, CACERT_PATH)
	if not url then
		return false, err
	end

	local result, err = get_html(url)
	if not result then
		return false, err
	end
	log.debug("reply_ack success")

	return true
end

--[[
	获取锁定标志状态
	{
		status= "authd/unauthd',
		data = {action = "conservative（保守）/radical（激进）/normal（正常）" ,}
	 }
]]
local function register_get()
	-- 如果文件不存在就创建一个默认的
	if not file_exist(REG_PATH) then
		local register = {status = "authd", data = {action = "normal"}}
		save(REG_PATH, js.encode(register))
	end

	local data = read(REG_PATH)
	if not data then
		return nil, "load register failed"
	end

	local map = js.decode(data)
	local result, err = check_valid_reg(map)
	if not result then
		return nil, err
	end

	action = result
	log.debug("get action: %s", action)

	return action
end

-- 设定锁定标志状态
local function register_set(status, par_action)
	local register = {status = status, data = {action = par_action}}
	save(REG_PATH, js.encode(register))

	action = par_action
	log.debug("set action: %s", action)

	return action
end

-- 执行脚本并删除
-- @file_name: 存放脚本文件夹路径
local function process_dlcode(file_name)
	local timeout, cnt, intval = 240, 0, 2
	local finish, failed = 0, 0
	local file = "/tmp/" .. file_name
	local finish_flag = file .. "." .. "finish_flag"
	local failed_flag = file .. "." .. "failed_flag"
	while cnt <= timeout do
		if lfs.attributes(finish_flag) then
			os.execute("rm "..finish_flag)
			finish = 1
			break
		elseif lfs.attributes(failed_flag) then
			os.execute("rm "..failed_flag)
			failed = 1
			break
		end

		cnt = cnt + intval
		se.sleep(intval)
	end

	if finish == 1 then
		local run_sh = FILE_PATH .. "/run.sh"
		if not lfs.attributes(run_sh) then
			return false, "sh file not exist"
		end
		os.execute("sh " .. run_sh)
		os.execute("rm -r " .. FILE_PATH)
		log.debug("sh and rm success")

		return true
	end

	if (finish == 0 and failed == 0) or failed == 1 then
		return false, "process_dlcode fail"
	end
end

-- 运行外部lua进程下载文件
-- @url:下载地址
-- @file_name:下载文件名
local function process_cmd(url, file_name)
	if not (url and file_name) then
		return nil, "url or file_name was nil"
	end

	se.go(dlcode.run, url, file_name)
	se.sleep(1)	-- 防止标志文件删除前先执行了process_dlcode

	return process_dlcode(file_name)
end

-- 执行命令
local function run_cmd(cmd, map)
	local result, err = valid_get_pars(cmd, map)
	if not result then
		return nil, err
	end
	log.debug("valid_get_pars pass")

	local url = map.detail.url
	local file_name = string.match(url, ".+/([^/]*%.%w+)$")
	if not file_name then
		return nil, "file_name was nil"
	end
	log.debug("package name:%s", file_name)

	result, err = process_cmd(url, file_name)
	if not result then
		return nil, err
	end

	return true
end

-- 保持当前状态
cmd_map["keep"] = function(map)
	log.debug("cmd was keep")
	return true
end

-- 执行加锁脚本并设置状态
cmd_map["lock"] = function(map)
	local result, err = run_cmd("lock", map)
	if not result then
		return nil, err
	end

	return register_set("unauthd", map.detail.locktype)
end

-- 执行解锁脚本并设置状态
cmd_map["unlock"] = function(map)
	local result, err = run_cmd("unlock", map)
	if not result then
		return nil, err
	end

	return register_set("authd", "normal")
end

-- 更新sn并给云端回应
cmd_map["update"] = function(map)
	local result, err = valid_get_pars("update", map)
	if not result then
		return nil, err
	end

	local new_sn = map.detail.sn
	result, err = snlib.check_sn(new_sn)
	if not result then
		return nil, err
	end

	local local_sn = get_sn()
	if local_sn and local_sn ~= new_sn then
		local result, reason = snlib.set_sn(new_sn)
		if not result then
			return nil, "update fail: "..reason
		end
	end

	log.debug("update success: %s", new_sn)
	return reply_ack(map)
end

-- 执行扩展命令
cmd_map["extend"] = function(map)
	local result, err = run_cmd("extend", map)
	if not result then
		return nil, err
	end

	return true
end

-- 和云端通信检测
local function register_check()
	local pars_map, url, map, err

	pars_map, err = gen_post_pars("register_check")
	if not pars_map then
		return false, err
	end

	url, err = gen_url(REQ_URL, REQ_HOST, "register_check", pars_map, timeout, CACERT_PATH)
	if not url then
		return false, err
	end

	map, err = get_html(url)
	if not map then
		return false, err
	end

	local cmd, body = valid_get_pars("register_check", map)
	if not (cmd and body) then
		return false, "cmd or body was nil"
	end

	-- 执行云端传回的命令
	local func = cmd_map[cmd]
	if not func then
		return false, "unknow cmd: "..cmd
	end

	return func(body)
end

-- 根据devid后六位生成睡眠时间
local function gen_time()
	local devid, err = snlib.get_devid()
	if not devid then
		return nil, err
	end

	local s, m, h = string.match(devid, "%x%x%x%x%x%x(%x%x)(%x%x)(%x%x)")

	local hour, min, sec = gen_tm_offset(8, tonumber(h, 16), tonumber(m, 16), tonumber(s, 16))

	-- 获取当前时间的表
	-- {"hour":7,"min":27,"wday":5,"day":30,"month":9,"year":2016,"sec":7,"yday":273,"isdst":false}
	local now_sec = os.time()
	local tar = os.date("*t", now_sec)
	log.debug("now date %s", js.encode(tar))

	tar.hour, tar.min, tar.sec = hour, min, sec

	local tar_sec = os.time(tar)
	-- 当前时间大于检测时间则在下一天检测
	if now_sec > tar_sec then
		tar.day = tar.day + 1
		tar_sec = os.time(tar)
	end

	log.debug("sleep to %s", js.encode(tar))

	local sleeptime = os.difftime(tar_sec, now_sec)
	if not (sleeptime and sleeptime >= 0) then
		return nil, "gen_time fail"
	end

	return sleeptime
end

-- 睡眠到生成的时间后和云端通信检测
local function check_loop()
	local gen_sleeptime = function()
		local sleeptime
		while not sleeptime do
			sleeptime, err = gen_time()
			if not sleeptime then
				log.debug(err)
				se.sleep(3600)
			end
		end
		return sleeptime
	end
	local sleeptime, result, err
	while true do
		sleeptime = gen_sleeptime()
		local _ = sleeptime > 0 and se.sleep(sleeptime)

		result, err = register_check()
		if not result then
			log.debug(err)
		end
		se.sleep(2)							-- 防止一秒钟内检测多次
	end
end

-- 当sn不存在且devid不为工厂的时候设置为默认
local function set_default_sn()
	local sn = snlib.get_sn()
	if sn then
		return nil, "sn was exist"
	end

	local devid = snlib.get_devid()
	if not devid then
		return nil, "set default_sn failed"
	end

	if devid == FACTORY_MAC then
		return nil, "devid was default of factory"
	end

	local pad = "00000000"
	local def_sn = string.format("%s-%s%s%s%s-%s", devid, pad, pad, pad, pad, pad)
	log.debug("Will set_default_sn")

	return snlib.set_sn(def_sn)
end

-- 启动执行
local function init()
	local result, err = register_get()		-- 检测状态文件
	if not result then
		log.debug(err)
	end

	result, err = set_default_sn()			-- 检测sn是否为默认
	if not result then
		log.debug(err)
	end

	local _ = se.go(check_loop)				-- 获取状态,启动定时检测
end

return {init = init}