local se = require("se")
local log = require("log")
local pkey = require("key")
local js = require("cjson.safe")
local const = require("constant")
local adjchannel = require("adjchannel")
local cfgmgr = require("cfgmanager")

local keys = const.keys
local rds

local function cfgget(g, k)
	return cfgmgr.ins(g):get(k)
end

-- 获取所有AP
local function aplist(group)
	local s = cfgget(group, keys.c_ap_list) or "{}"
	local arr = js.decode(s)	assert(arr)
	return arr
end

-- 获取在线AP
local function get_online(group, aparr)
	local hkey = "ol/" .. group
	local varr = rds:hmget(hkey, aparr)

	local olmap = {}
	for i = 1, #aparr do
		local k, v = aparr[i], varr[i]
		v = v == false and 0 or v
		olmap[k] = v
	end
	return olmap
end

-- 处理AP上传的数据
local function apinfo(group, aparr)	
	local apid_map = {}
	if #aparr == 0 then
		return apid_map
	end

	local olmap = get_online(group, aparr)
	local opt_time = 1
	local t = false

	while opt_time <= 10 do
		for apid, v in pairs(olmap) do
			local karr = {keys.c_chidinfo}
			local hkey = pkey.state_hash(apid)	assert(hkey)
			local varr = rds:hmget(hkey, karr)	-- 获取AP上传数据
			if js.encode(varr) ~= "{}" then
				apid_map[apid] = varr
			end

			t = v and true or false
		end
		
		if t then
			break
		end

		opt_time = opt_time + 1
		se.sleep(3)
	end

	return apid_map, t
end

local function opt_chan(map)
	local hkey = keys.c_chidswitch	assert(hkey)
	rds:set(hkey, "1")	-- 发送使能位给status
	
	local en = false
	local group, num = map.group
	local aparr = aplist(group)
	local apid_map, t = apinfo(group, aparr)
	rds:expire(hkey, 30)	--- 有效期30秒将使能位关闭

	if not t then	-- 没有拿到AP的数据
		num = string.format("%d%%", math.random(10, 20))
		en = true
	end

	local map_chid = {}
	if not en then
		num = string.format("%d%%", math.random(20, 30))
		if js.encode(apid_map) ~= "{}" then
			map_chid = adjchannel.decide(apid_map)	-- 调用算法函数将 apid_map 传进去
		end
		if map_chid then
			num = string.format("%d%%", math.random(20, 50))
		end
	end

	hkey = keys.c_chidvalue	assert(hkey)
	local v = {code = "2", extdata = num}
	rds:set(hkey, js.encode(v))	-- 设置优化数据

	return map_chid
end

local function set_rds(r)
	rds = r
end

return {
	set_rds = set_rds,
	opt_chan = opt_chan,
}
