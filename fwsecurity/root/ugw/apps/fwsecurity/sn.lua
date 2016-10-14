-- author@tgb

--[[
	sn:"devid-uuid-seq"
	devid: all hexadecimal digits with out "-" or ":",such as "1A2B3DC4D5E6F"
	uuid:all characters and numbers
	seq: all characters and numbersc
]]
local pattern_map = {
	devid	= {min = 12, max = 12, pattern = "^%x+$"},
	uuid 	= {min = 32, max = 32, pattern = "^%w+$"},
	seq 	= {min = 8,	 max = 8,  pattern = "^%w+$"},
	sn 		= {min = 54, max = 54, pattern = "^%x+%-%w+%-%w+$"},
}

local function read(path, func)
	func = func and func or io.open
	local fp, err = func(path, "r")
	if not fp then
		return nil, err
	end
	local s = fp:read("*a")
	fp:close()
	return s
end

local function gen_validate_str(min, max, pattern)
	return function(v)
		if not (#v >= min and #v <= max) then
			return nil
		end
		if pattern then
			if not v:find(pattern) then
				return nil
			end
		end
		return v
	end
end

local sn_m = pattern_map.sn
local devid_m, uuid_m, seq_m = pattern_map.devid, pattern_map.uuid, pattern_map.seq
local v_sn = gen_validate_str(sn_m.min, sn_m.max, sn_m.pattern)
local v_devid = gen_validate_str(devid_m.min, devid_m.max, devid_m.pattern)

local function get_devid()
	local cmd = "ugw_factory_mac -read | grep -A1 MAC | grep -v MAC"
	local devid = read(cmd, io.popen)
	if not devid then
			return nil, "get devid failed"
	end

	devid = devid:gsub("[%:\n ]", ""):lower()
	if not (devid and #devid == 12) then
		return nil, "get devid failed"
	end

	return devid
end

local function check_sn(sn)
	if not (sn and type(sn) == "string") then
		return nil, "invalid sn"
	end

	if not v_sn(sn) then
		return nil, "ivnalid sn"
	end

	return true
end

local function get_sn()
	local cmd = "/usr/sbin/fw_printenv sn 2>/dev/null"
	local s = read(cmd, io.popen)
	if not s then
		return nil, "get sn failed"
	end
	assert(type(s) == "string")
	local sn = v_sn(string.match(s, "sn=(.+)\n") or "")
	if not sn then
		return nil, "get sn failed"
	end
	return sn
end

local function get_default_sn()
	local devid = get_devid()
	if not devid then
		return nil, "get default_sn failed"
	end
	local pad = "00000000"
	local def_sn = string.format("%s-%s%s%s%s-%s", devid, pad, pad, pad, pad, pad)
	return def_sn
end

local function set_sn(sn)
	if not check_sn(sn) then
		return nil, "invalid sn"
	end

	local cmd = string.format("/usr/sbin/fw_setenv sn '%s' 2>/dev/null", sn)
	local s = read(cmd, io.popen)
	if not s then
		return nil, "set sn failed"
	end

	return true
end

return {
	get_sn		= get_sn,
	set_sn		= set_sn,
	check_sn	= check_sn,
	get_devid	= get_devid,
	get_default_sn = get_default_sn,
}
