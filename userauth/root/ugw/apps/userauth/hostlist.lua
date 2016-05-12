local log = require("log") 
local js = require("cjson.safe")
local common = require("common") 
local lfs = require("lfs")

local read, save_safe, file_exist = common.read, common.save_safe, common.file_exist

local blacklist = "blacklist"
local whitelist = "whitelist"
local alllist = "allist"
local hostlist = "/etc/config/hostlist.json"
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
	return map[list_type] or {}
end

local function hostlist_set(list_type, list)
	local new_map = {}
	local old_map = hostlist_get(allist)
	new_map[blacklist] = old_map[blacklist] or {}
	new_map[whitelist] = old_map[whitelist] or {}
	new_map[list_type] = list
	save_safe(hostlist, js.encode(new_map) or {})
	return true
end

local function whitelist_get() 
	return hostlist_get(whitelist)
end

local function blacklist_get() 
	return hostlist_get(blacklist)
end


local function whitelist_set(host_list) 
	hostlist_set(whitelist, host_list or {})
	return {status = 0, data = "ok"}
end

local function blacklist_set(host_list) 
	hostlist_set(blacklist, host_list or {})
	return {status = 0, data = "ok"}
end


local function get_bypassurl()
	local bypassurl = {}
	local whitelist = whitelist_get()
	if whitelist and #whitelist > 0 then
		for _, host in ipairs(whitelist) do
			if host and #host > 3 then
				local info1 = {["host"] = host, ["uri"] = "", ["action"] = 1, ["step"] = auth_step1}
				local info2 = {["host"] = host, ["uri"] = "", ["action"] = 1, ["step"] = auth_step2}
				table.insert(bypassurl, info1)
				table.insert(bypassurl, info2)
			end
		end
	end
	return bypassurl
end


return {
	whitelist_set = whitelist_set, 
	whitelist_get = whitelist_get,
	blacklist_set = blacklist_set, 
	blacklist_get = blacklist_get,
	get_bypassurl = get_bypassurl,
}

