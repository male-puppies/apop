require("global")
local se = require("se")
local log = require("log")
local js = require("cjson.safe")
local common = require("common")
local read, save_safe = common.read, common.save_safe

local errlog = "/tmp/ugw/log/apmgr.error"
local firmware_path = "/etc/config/firmware.json"
local cloud_cfg = "/etc/config/cloud.json"
local ac_version = "/etc/config/ac_version.json"
local thin_version = "/etc/config/thin_version.json"
local new_version = "/tmp/memfile/new_version.txt"
local host, port, actype = "cloud.trylong.cn", 80, "7621"
local current_version = "/etc/openwrt_release"
local function get_current_version()
	local s = read(current_version)
	local tp = s:match("DISTRIB_ID='(.-)'"):gsub("%s", "")
	local ver = s:match("DISTRIB_RELEASE='(.-)'"):gsub("%s", "")
	return string.format("%s-%s", tp, ver)
end

local function nslookup(host)
	local ip = host
	local pattern = "^%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?$"
	if not host:find(pattern) then
		local cmd = string.format("timeout nslookup '%s' | grep -A 1 'Name:' | grep Addr | awk '{print $3}'", host)
		ip = read(cmd, io.popen)
		if not ip then
			return
		end
		ip = ip:gsub("[ \t\r\n]", "")
		if not ip:find(pattern) then
			return
		end
	end
	return ip
end

local function get_config()
	local h, p, t

	local s = read(firmware_path)	print(s)
	local fmap = js.decode(s)
	t = fmap and fmap.actype or actype

	local s = read(cloud_cfg)
	local cmap = js.decode(s)
	h = cmap and cmap.ac_host or host
	p = 80
	return h, p, t
end

local function check_firmware()
	local trans = function(h, p, at)
		local ip = nslookup(h)
		local _ = ip or log.fatal("nslookup fail %s %s", h, p)
		log.debug("nslookup %s %s", h, p)
		host, port, actype = ip, p, at
	end

	local h, p, a = get_config()
	return trans(h, p, a)
end

local function chkap(param)
	os.execute(string.format("./download.sh apver %s %s %s", param.actype, host, port))
end

local function chkac(param)
	local cmd = string.format("./download.sh acver %s %s %s", param.actype, host, port)
	os.execute(cmd)
end

local function download_ap_firmware(actype)
	local lfs = require("lfs")
	local flag = "/tmp/download_ap_firmware"
	if not lfs.attributes(flag) then
		return
	end

	os.remove(flag)
	log.debug("start to download ap firmware")

	local s = read(thin_version)
	local map = js.decode(s)
	if not map then
		return
	end

	local do_download = function(aptype, item)
		local md5, patharr = item.md5, item.path
		if not (md5 and patharr and #patharr > 0) then
			return
		end
		local cmd = string.format("./download.sh apdl %s %s %s %s %s ", aptype, host, port, item.version, md5)
		local narr = {}
		for _, v in ipairs(patharr) do
			table.insert(narr, "'" .. v .. "'")
		end
		cmd = cmd .. table.concat(narr, " ")
		os.execute(cmd)
	end

	local arr = {}
	for aptype, item in pairs(map) do
		local path = string.format("/www/rom/%s.version", aptype)
		local s = read(path)
		if not s then
			local patharr = item.path
			if patharr and #patharr > 0 then
				do_download(aptype, item)
			end
		else
			local over = s:match("(.-)\n")
			if item.version and item.version > over then
				do_download(aptype, item)
			else
				print("no need to download", item.version, over)
			end
		end
	end
end

local function download_ac_firmware(actype)
	local lfs = require("lfs")
	local flag = "/tmp/download_ac_firmware"
	if not lfs.attributes(flag) then
		return os.remove(flag)
	end

	log.debug("start to download ac firmware")

	local s = read(ac_version)
	local map = js.decode(s)
	if not map then
		return os.remove(flag)
	end

	local version, md5, paths = map.version, map.md5, map.path
	if not (version and md5 and paths) then
		return os.remove(flag)
	end

	local curver = get_current_version()
	if version <= curver then
		return os.remove(flag)
	end

	local path = string.format("/www/rom4ac/%s.version", actype)
	local s = read(path)
	if s then
		local over = s:match("(.-)\n")
		if version <= over then
			print("no need to download", version, over)
			os.remove(flag)
			return
		end
	end

	os.remove(new_version)
	local cmd = string.format("./download.sh acdl %s %s %s %s %s ", actype, host, port, version, md5)
	local narr = {}
	for _, v in ipairs(paths) do
		table.insert(narr, "'" .. v .. "'")
	end
	cmd = cmd .. table.concat(narr, " ")
	os.execute(cmd)
	os.remove(flag)
end

local function chk_new_ac()
	local s = read(ac_version)
	local map = js.decode(s)
	if not (map and map.version) then
		return os.remove(ac_version)
	end

	local curver = get_current_version()
	os.remove(new_version)
	if map.version <= curver then
		print("not find", map.version, curver)
		return
	end

	save_safe(new_version, map.version)
end

local function loop_check(func, idle, interval, param)
	se.sleep(idle)
	while true do
		func(param)
		se.sleep(interval)
	end
end

local function main()
	check_firmware()
	download_ap_firmware(actype)
	download_ac_firmware(actype)
	se.go(loop_check, chkap, 0.1, 3600, {actype = actype})
	se.go(loop_check, chkac, 0.1, 3600, {actype = actype})
	se.go(loop_check, chk_new_ac, 10, 20)
end

log.setmodule("cf")
log.setdebug(true)
se.run(main)
