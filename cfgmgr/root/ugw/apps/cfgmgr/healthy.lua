-- liuke
--require("global")
local se = require("se")
local log = require("log")
local pkey = require("key")
local online = require("online")
local js = require("cjson.safe")
local const = require("constant")
local dispatch = require("dispatch")
local cfgmgr = require("cfgmanager")

local keys = const.keys

local function cfgset(g, k, v)
	return cfgmgr.ins(g):set(k, v)
end

local function cfgget(g, k)
	return cfgmgr.ins(g):get(k)
end

local function get_healthy_data(group)
	local s = cfgget(group, keys.u_healthy)		assert(s)
	return s
end

local function healthy_model_del(map)
	local group, id = map.group, map.map	assert(group and id)
	local aparr = js.decode(cfgget(group, keys.c_ap_list))	assert(aparr)
	local healthy = js.decode(get_healthy_data(group))		assert(healthy)

	for key, r in ipairs(healthy) do
		if id == r.id then
			healthy[key] = nil
		end
	end

	local new_healthy = {}
	for k, v in pairs(healthy) do
		table.insert(new_healthy, healthy[k])
	end

	new_healthy = js.encode(new_healthy)
	cfgset(group, keys.u_healthy, new_healthy)

	local apid_map = {}
	for _, apid in ipairs(aparr) do
		apid_map[apid] = dispatch.find_ap_config(group, apid)
	end

	return apid_map
end

local function healthy_model_set(map)
	local group, new_healthy = map.group, map.map 	assert(group and new_healthy)
	local aparr = js.decode(cfgget(group, keys.c_ap_list))	assert(aparr)
	local healthy = js.decode(get_healthy_data(group))		assert(healthy)

	-- 添加id号
	local id_map = {}
	for i = 1, 32 do
		id_map[i] = false
	end
	for k, v in ipairs(healthy) do
		id_map[v.id] = true
	end

	new_healthy.id = 0
	for k, v in ipairs(id_map) do
		if not v then
			new_healthy.id = k
			break
		end
	end

	-- 添加星期
	local days_keys = {"monday", "tuesday", "wednesday", "thursday", "friday", "saterday", "sunday"}
	local days = {monday = 0, tuesday = 0, wednesday = 0, thursday = 0, friday = 0, saterday = 0, sunday = 0}
	if new_healthy.h_repeat[1] == "once" then -- 执行一次
		local day = tonumber(os.date("%w"))
		days[days_keys[day]] = 1
		new_healthy.days = days
	end

	if new_healthy.h_repeat[1] == "workday" then -- 工作日模式
		for i = 1, 5 do
			days[days_keys[i]] = 1
		end
		new_healthy.days = days
	end

	if new_healthy.h_repeat[1] == "everyday" then -- 每天
		for k, v in ipairs(days_keys) do
			days[days_keys[k]] = 1
		end
		new_healthy.days = days
	end

	if not (new_healthy.h_repeat[1] == "once" and new_healthy.h_repeat[1] == "workday" and new_healthy.h_repeat[1] == "everyday") then
		for _, keys in ipairs(days_keys) do -- 自定义模式
			for k, v in ipairs(new_healthy.h_repeat) do
				if keys == new_healthy.h_repeat[k] then
					-- 说明是自定义的模式
					days[keys] = 1
				end
			end
		end
		new_healthy.days = days
	end

	table.insert(healthy, new_healthy)
	healthy = js.encode(healthy)
	cfgset(group, keys.u_healthy, healthy)

	local apid_map = {}
	for _, apid in ipairs(aparr) do
		apid_map[apid] = dispatch.find_ap_config(group, apid)
	end

	return apid_map
end

local function healthy_model_switch(map)
	local group, data = map.group,  map.map 	assert(group and data)
	local id, enable = data.id, data.enable

	local aparr = js.decode(cfgget(group, keys.c_ap_list))	assert(aparr)
	local healthys = js.decode(get_healthy_data(group))		assert(healthys)

	for  k, value in ipairs(healthys) do -- 修改对应规则的使能标志
		if value.id == id then
			healthys[k].enable = enable
			break
		end
	end

	healthys = js.encode(healthys)
	cfgset(group, keys.u_healthy, healthys)

	local apid_map = {}
	for _, apid in ipairs(aparr) do
		apid_map[apid] = dispatch.find_ap_config(group, apid)
	end

	return apid_map
end


-- 时间规范
local function validate_time(time)
	if not time then
		return nil, "invalid time"
	end

	local hour_pattern = string.format("^[0-2][0-9]")
	local min_pattern = string.format("[0-5][0-9]$")
	local hour = tonumber(string.sub(time, string.find(time, hour_pattern)))
	local min = tonumber(string.sub(time, string.find(time, min_pattern)))

	return hour, min
end

local function judge_time(now, open, close)
	if not (now and open and close) then
		return nil, "invalid time"
	end

	local now_time_hour, now_time_min = validate_time(now)
	local open_time_hour, open_time_min = validate_time(open)
	local close_time_hour, close_time_min = validate_time(close)

	if ((now_time_hour > open_time_hour) or (now_time_hour == open_time_hour and now_time_min >= open_time_min)) and ((now_time_hour < close_time_hour) or (now_time_hour == close_time_hour and now_time_min < close_time_min)) then
		log.info("--open-wifi--")
		return "open"
	end
	log.info("--close--wifi--")
	return "close"
end

local function time_size(opentime, closetime)
	local open_time_hour, open_time_min = validate_time(opentime)
	local close_time_hour, close_time_min = validate_time(closetime)
	if open_time_hour > close_time_hour or (open_time_hour == close_time_hour and open_time_min > close_time_min) then
		return open_time_hour, open_time_min
	end

	return close_time_hour, close_time_min
end
--[[
	ver_bswitch_go():
	wifi和bswitch的处理
	修改对应bswitch和版本号
]]
local function ver_bswitch_go(group, val)
	local aparr = js.decode(cfgget(group, keys.c_ap_list))	assert(aparr)
	local ver = os.date("%Y%m%d %H%M%S")

	local change_map = { }
	for _, band in ipairs({"2g", "5g"}) do
		for _, apid in ipairs(aparr) do
			local version = pkey.version(apid)
			local bswitch = pkey.switch(apid, band)
			change_map[bswitch] = val
			change_map[version] = ver
		end
	end

	for k, v in pairs(change_map) do
		cfgset(group, k, v)
	end

	return true
end

-- once模式的判断与失能
local function once_disenable(now_time, v)
	if not v then
		return nil, "miss h_repeat"
	end

	local now_time_hour, now_time_min = validate_time(now_time)

	if v.h_repeat[1] == "once" then
		local hour, min = time_size(v.opentime, v.closetime)
		if now_time_hour >= hour and now_time_min >= min then
			v.enable = 0
			return true
		end

	end

	return false
end

-- 时间判断处理函数：循环执行规则数组里的规则
local function healthy_handler(group, flag_map)
	local v_days = {"monday", "tuesday", "wednesday", "thursday", "friday", "saterday", "sunday"}
	local healthy =  js.decode(cfgget(group, keys.u_healthy))	assert(healthy)
	local aparr = js.decode(cfgget(group, keys.c_ap_list))	assert(aparr)
	local ver = os.date("%Y%m%d %H%M%S")

	local now_day = os.date("%w")
	local now_time = os.date("%H:%M")

	for k,  v in ipairs(healthy) do
		if v.enable == 1 then -- 规则可用
			local flag1 = once_disenable(now_time, healthy[k])
			if flag1 then
				healthy = js.encode(healthy)
				cfgset(group, keys.u_healthy, healthy)
			end

			if v.days[v_days[tonumber(now_day)]] == 1 then -- 当天可执行规则
				local open_time = v.opentime
				local close_time = v.closetime
				local r, e = judge_time(now_time, open_time, close_time)
				if not r then
					return nil, e
				end

				if r == "open" and (not flag_map.open) then
					-- 应该为开启状态
					local e = ver_bswitch_go(group, 1)
					if not e then
						return nil, "open fail"
					end
					log.info("------opened------true")
					flag_map.open = true
					flag_map.close = false
					break
				end
				if r == "close" and (not flag_map.close) then
					-- 应该为关闭状态
					local r = ver_bswitch_go(group, 0)
					if not r then
						return nil, "close fail"
					end
					log.info("------closed------true")
					flag_map.open = false
					flag_map.close = true
					break
				end
			end
		end
	end
end

local function run_healthy( )
	log.info("run healthy")
	local group = "default"
	se.sleep(1)
	local flag_map = { open = false, close = false}
	while true do
		healthy_handler(group, flag_map)
		se.sleep(60)
	end
end

return {
	run_healthy = run_healthy,
	healthy_model_set = healthy_model_set,
	healthy_model_del = healthy_model_del,
	healthy_model_switch = healthy_model_switch
 }
