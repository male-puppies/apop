-- liuke
local fp = require("fp")
local se = require("se")
local log = require("log")
local pkey = require("key")
local ms = require("moses")
local js = require("cjson.safe")
local const = require("constant")
local common = require("common")

local rds, pcli
local read = common.read

local function errmsg(fmt, ...)
	return string.format(fmt, ...)
end

local function get_status(s, d)
	return {status = s, data = d or "ok"}
end
-- 健康模式数据获取
local function healthy_model_get( )
	se.sleep(0.5)
	local m = js.decode(read("/etc/config/default/m.json"))		assert(m)
	local healthy = js.decode(m.healthy_model)

	for i, t in ipairs(healthy) do
		for k, v in ipairs(healthy[i]) do
			if k == "days" then
				healthy[i][k] = nil
				break
			end
		end
	end

	return healthy and get_status(0, healthy) or get_status(1, "error get")
end

local function validate_id(id)
	if not (id and id > 0 and id <= 32) then
		return nil, "invalid id"
	end

	return true
end

-- 健康模式数据删除
local function healthy_model_del(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 		assert(rds and pcli)

	local h_id = data	assert(h_id)
	local r, e = validate_id(h_id.id)
	if not r then
		return get_status(1, string.format("invalid del cmd : %s", e))
	end

	local res = pcli:modify({cmd = "healthy_model_del", data = {group = group, map = h_id.id}})
	return res and get_status(0) or get_status(1, "modify del fail")
end

local function validate_enable(e)
	if not e then
		return nil, "invalid enable"
	end

	if e ~= 0 and e ~= 1 then
		return nil, "invalid enable value"
	end

	return true
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

-- 健康模式数据设置
local function healthy_model_set(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 		assert(rds and pcli)

	local healthy = data
	if not healthy then
		return get_status(1, "invalid healthy set data, is nil")
	end
	-- 判断时间点设置的合法性,opentime, closetime
	local opentime_hour, opentime_min = validate_time(healthy.opentime)
	local closetime_hour, closetime_min = validate_time(healthy.closetime)
	if not ((opentime_hour >=0 and opentime_hour <= 23) and (closetime_hour >= 0 and closetime_hour <= 23)) then
		return get_status(1, "error time hour set")
	end
	if not ((opentime_min >=0 and opentime_min <= 59) and (closetime_min >= 0 and closetime_min <= 59)) then
		return get_status(1, "error time min set")
	end
	--判断模式的合法性的合法性
	local h_repeat = {"once", "workday", "everyday", "monday", "tuesday", "wednesday", "thursday", "friday", "saterday", "sunday"}
	local r = fp.contains_any(h_repeat, healthy.h_repeat)
	if not r then
		return get_status(1, "error definded h_repeat")
	end
	-- 判断使能标志的合法性
	local r, e = validate_enable(healthy.enable)
	if not r then
		return get_status(1, e)
	end

	local res = pcli:modify({cmd = "healthy_model_set", data = {group = group, map = healthy}})
	return res and get_status(0, res) or get_status(1, "modify set fail")
end

-- 修改使能标志，enable为1时开启网络，enable为0时关闭网络
local function healthy_model_switch(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 		assert(rds and pcli)
	local healthy = data		assert(healthy)
	-- 判断使能标志的合法性
	local r, e = validate_enable(healthy.enable)
	if not r then
		return get_status(1, e)
	end
	-- 判断id号
	local r, e = validate_id(healthy.id)
	if not r then
		return get_status(1, e)
	end

	local res = pcli:modify({cmd = "healthy_model_switch", data = {group = group, map = healthy}})
	return res and get_status(0) or get_status(1, "modify switch fail")
end

return {
	healthy_model_get = healthy_model_get,
	healthy_model_set = healthy_model_set,
	healthy_model_del = healthy_model_del,
	healthy_model_switch = healthy_model_switch,
}