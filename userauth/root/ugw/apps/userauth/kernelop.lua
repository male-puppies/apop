local log = require("log")
local common = require("common")
local js = require("cjson.safe") 
local policy = require("policy")
local memfile = require("memfile")
local policies = require("policies")

local auth_step1 = 1
local auth_step2 = 2

local last_iface_count
local read, save, save_safe = common.read, common.save, common.save_safe
local userauth_config = "/tmp/memfile/userauth_config.json"

local function get_iface()
	local cmd = "lua /ugw/apps/userauth/tool.lua iface"
	local s, err = read(cmd, io.popen)
	local _ = s or log.error("cmd fail %s %s", cmd, err or "")
	return js.decode(s) or {}
end

local function get_policy()
	local pols = policies.ins():data()
	local pri, polarr = 100, {}
	for _, item in ipairs(pols) do 
		local authtype = item:get_type() == "web" and 0 or 1
		local map = {
			AuthPolicyName = item:get_name(),
			Enable = 1, 
			PolicyType = 1,
			Timeout = 0,
			AuthType = authtype,
			Priority = pri,
			IpRange = {{Start = item:get_ip1(), End = item:get_ip2()}},
			Step = auth_step2,
		}
		table.insert(polarr, map)
		pri = pri - 1 	assert(pri >= 0)
	end 
	return polarr
end

local function get_global()
	return {CheckOffline = 60, RedirectUrl = "http://10.10.10.10/webui"}
end

local function get_bypassurl()
	local url = {}
	table.insert(url, {["host"] = string.lower("*apple.com"), ["uri"]= "/hotspot-detect.html", ["action"] = 1, ["step"] = auth_step1})
	table.insert(url, {["host"] = string.lower("*apple.com"), ["uri"]= "/hotspot-detect.html", ["action"] = 1, ["step"] = auth_step2})
	table.insert(url, {["host"] = string.lower("*weixin.qq.com*"), ["uri"] ="/resources", ["action"] = 1, ["step"] = auth_step2})
	table.insert(url, {["host"] = string.lower("*weixin.qq.com*"), ["uri"] ="/operator", ["action"] = 1, ["step"] = auth_step2})
	table.insert(url, {["host"] = string.lower("*weixin.qq.com*"), ["uri"] ="/cgi-bin", ["action"] = 1, ["step"] = auth_step2})
	return url
end

local function reset(iface_arr)
	local iface_arr = iface_arr and iface_arr or get_iface()
	last_iface_count = #iface_arr

	local cfg = {
		AuthPolicy = get_policy(),
		InterfaceInfo = iface_arr,
		GlobaleAuthOption = get_global(),
		BypassUrl = get_bypassurl(),
	}
	
	local cmd = string.format("auth_tool '%s' >/dev/null 2>&1 &", js.encode(cfg))
	log.debug("%s", cmd)
	read(cmd, io.popen)
end

local function update_user_status(mac_arr, action)
	local st_arr = {}
	for _, mac in ipairs(mac_arr) do 
		table.insert(st_arr, {UserMac = mac, Action = action})
	end
	local cmd = string.format("auth_tool '%s'", js.encode({UpdateUserStatus = st_arr}))
	print(cmd)
	read(cmd, io.popen)
end

local function online(mac)
	update_user_status({mac}, 1)
end

local function offline(mac_arr)
	update_user_status(mac_arr, 0)
end

local function get_all_user()
	local cmd = string.format("auth_tool '%s' 2>/dev/null", js.encode({GetAllUser = 1}))
	local s = read(cmd, io.popen)
	s = s .. "\n"

	local user = {}
	for part in s:gmatch(".-\n") do 
		local ip, st, jf, mac, tp = part:match("ip:(.-) st:(%d) jf:(%d+) mac:(%S+) type:(%d)")
		if ip then 
			user[mac] = {ip = ip, st = tonumber(st), jf = tonumber(jf), tp = tonumber(tp)}
		end
	end

	return user
end

local function bypass_mac(ip, mac, step)
	local auth_step 
	local map = {}
	map.AuthPolicy = {
			{
				AuthPolicyName = "bp" .. ip, 
				AuthType = 1, 
				PolicyType = 1, 
				Timeout = 25, 
				Enable = 1, 
				Priority = 10, 
				IpRange = {{Start = ip, End = ip}},
				Step = step,
			}
		}
	local cmd = string.format("auth_tool '%s'", js.encode(map))
	read(cmd, io.popen)
end

--[[
local function check_modify(path)
	local attr = lfs.attributes(path)
	if not attr then 
		return 
	end 

	local size, mtime = attr.size, attr.modification
	local ins = memfile.ins("authnetwork")
	local map = ins:get(path) or ins:set(path, {size = 0, mtime = 0}):get(path)
	local change = false 
	if not (map.size == size and map.mtime == mtime) then 
		map.size, map.mtime, change = size, mtime, true
		ins:set(path, map):save()
		log.debug("network change %s", path)
	end 
	return change
end

local files = {"/etc/config/firewall", "/etc/config/network"}
local function check_network()
	local change = false 
	for _, path in ipairs(files) do 
		change = check_modify(path) and true or change
	end
	local _ = change and reset()
end
]]

local function check_ip_route()
	local iface_arr = get_iface()
	if last_iface_count ~= #iface_arr then 
		log.debug("io route reset %s %s", last_iface_count, #iface_arr)
		reset()
	end 
end

return {
	reset = reset, 
	online = online, 
	offline = offline, 
	bypass_mac = bypass_mac,
	get_all_user = get_all_user, 
	-- check_network = check_network,
	check_ip_route = check_ip_route,
}