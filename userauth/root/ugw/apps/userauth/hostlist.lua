local log = require("log")
local js = require("cjson.safe")
local common = require("common")
local lfs = require("lfs")

local read, save_safe, file_exist = common.read, common.save_safe, common.file_exist

local blacklist = "blacklist"
local whitelist = "whitelist"
local macwhitelist = "mac_whitelist"
local macblacklist = "mac_blacklist"
local wechatblacklist = "wechat_blacklist"
local wechatwhitelist = "wechat_whitelist"
local alllist = "allist"
local hostlist = "/etc/config/hostlist.json"
local cloud_whitelist_file = "/tmp/www/webui/url_config.conf"
local cloud_mac_file = "/tmp/www/webui/auth_config.conf"
local auth_step1 = 1
local auth_step2 = 2

local function hostlist_get(list_type)
	if not file_exist(hostlist) then
		return {}
	end
	local s, err = read(hostlist)
	if not s then
		return {}
	end
	local map = js.decode(s) or {}
	if list_type == allist then
		return map
	end
	return map[list_type] or {}
end

local function hostlist_set(list_type, list)
	local new_map = {}
	local old_map = hostlist_get(allist)
	new_map[blacklist] = old_map[blacklist] or {}
	new_map[whitelist] = old_map[whitelist] or {}
	new_map[macwhitelist] = old_map[macwhitelist] or {}
	new_map[macblacklist] = old_map[macblacklist] or {}
	new_map[wechatblacklist] = old_map[wechatblacklist] or {}
	new_map[wechatwhitelist] = old_map[wechatwhitelist] or {}
	new_map[list_type] = list
	save_safe(hostlist, js.encode(new_map) or {})
	return true
end

local function get_cloud_whlist(filepath)
	local s = read("/tmp/www/adtype")
	if not (s and s:find("cloudauth")) then
		return false, nil
	end

	local f = read(filepath)
	local map = {}
	if f then
		map = js.decode(f)
		if map then
			return true, map
		end
	end
	return false, nil
end

local function whitelist_get()
	return hostlist_get(whitelist)
end

local function wechatwhitelist_get()
	return hostlist_get(wechatwhitelist)
end

local function blacklist_get()
	return hostlist_get(blacklist)
end

local function wechatwhitelist_get()
	return hostlist_get(wechatwhitelist)
end

local function macwhitelist_get()
	return hostlist_get(macwhitelist)
end

local function macblacklist_get()
	return hostlist_get(macblacklist)
end

local function whitelist_set(host_list)
	hostlist_set(whitelist, host_list or {})
	return {status = 0, data = "ok"}
end

local function blacklist_set(host_list)
	hostlist_set(blacklist, host_list or {})
	return {status = 0, data = "ok"}
end

local function wechatwhitelist_set(host_list)
	hostlist_set(wechatwhitelist, host_list or {})
	return {status = 0, data = "ok"}
end

local function macwhitelist_set(mac_list)
	hostlist_set(macwhitelist, mac_list  or {})
	return {status = 0, data = "ok"}
end

local function macblacklist_set(mac_list)
	hostlist_set(macblacklist, mac_list  or {})
	return {status = 0, data = "ok"}
end

local function get_wechat_bypassurl()
	local bypassurl = {}
	--local whitelist = wechatwhitelist_get()
	local whitelist = whitelist_get()
	if whitelist and #whitelist > 0 then
		for _, host in ipairs(whitelist) do
			if host and string.len(host) > 3 then
				local info1 = {["host"] = host, ["uri"] = "", ["action"] = 1, ["step"] = auth_step1}
				local info2 = {["host"] = host, ["uri"] = "", ["action"] = 1, ["step"] = auth_step2}
				table.insert(bypassurl, info1)
				table.insert(bypassurl, info2)
			end
		end
	end
	return bypassurl
end

local function get_bypassurl()
	local bypassurl = {}
	local ret, cloud_whlist = get_cloud_whlist(cloud_whitelist_file)
	if ret and #cloud_whlist ~= 0 then
		for _,host in ipairs(cloud_whlist) do
			if host and string.len(host) > 3 then
				local host_a = host
				if host:find("http") then 
					host_a = string.match(host, "//(.-)/")
				elseif host:find("/") then
					host_a = string.match(host, "(.-)/")
				end
				print("xxx", host,host_a)
				table.insert(bypassurl, {["host"] = host_a})

			end
		end
	end
	return bypassurl
end
-- whitemac action:1 and blackmac action:0  DON'T MOVE BLACK WHITE OREDER !!!!
local function get_mac_bypassinfo()
	local bypassmac = {}
	local macblacklist = macblacklist_get()
	if macblacklist and #macblacklist > 0 then
		for _, mac in ipairs(macblacklist) do
			if mac and (string.len (mac) == 17) then
				table.insert(bypassmac, {["mac"] = mac, ["action"] = 0})
			end
		end
	end
	local ret, map = get_cloud_whlist(cloud_mac_file)
		if ret and map.blacklist then
			local maclist = {}
			if type(map.blacklist) == "string" then
				maclist = js.decode(map.blacklist)
			else
				maclist = map.blacklist
			end

			if (maclist and maclist[1]) then
				for _,v in ipairs(maclist) do
					if v and (string.len (v) == 17) then
					table.insert(bypassmac, {["mac"] = v, ["action"] = 0})
					end
				end
			end
	end

	local macwhitelist = macwhitelist_get()
	if macwhitelist and #macwhitelist > 0 then
		for _, mac in ipairs(macwhitelist)do
			if mac and (string.len (mac) == 17) then
				table.insert(bypassmac, {["mac"] = mac, ["action"] = 1})
			end
		end
	end

	local ret, map = get_cloud_whlist(cloud_mac_file)
	if ret and map.whitelist then
		local maclist = {}
		if type(map.whitelist) == "string" then
			maclist = js.decode(map.whitelist)
		else
			maclist = map.whitelist
		end

		if not (maclist and maclist[1]) then
			return bypassmac
		end

		for _,v in ipairs(maclist) do
			if v and (string.len (v) == 17) then
				table.insert(bypassmac, {["mac"] = v, ["action"] = 1})
			end
		end
	end

	return bypassmac
end

return {
	hostlist_get  = hostlist_get,
	whitelist_set = whitelist_set,
	whitelist_get = whitelist_get,
	blacklist_set = blacklist_set,
	blacklist_get = blacklist_get,
	get_bypassurl = get_bypassurl,
	macwhitelist_set = macwhitelist_set,
	macwhitelist_get = macwhitelist_get,
	macblacklist_set = macblacklist_set,
	macblacklist_get = macblacklist_get,
	get_mac_bypassinfo = get_mac_bypassinfo,
	wechatwhitelist_set = wechatwhitelist_set,
	wechatwhitelist_get = wechatwhitelist_get,
	get_wechat_bypassurl = get_wechat_bypassurl,
}

