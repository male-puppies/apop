local se = require("se")
local log = require("log")
local pkey = require("key")
local js = require("cjson.safe")
local const = require("constant")
local dispatch  = require("dispatch")
local cfgmgr = require("cfgmanager")

local opt_req
local keys = const.keys
local rds
local update_ap

local function set_update_ap(update)
	update_ap = update
end

--写内容到配置文件
local function cfgset(g, k, v)
	return cfgmgr.ins(g):set(k, v)
end

--读出配置文件
local function cfgget(g, k)
	return cfgmgr.ins(g):get(k)
end

--修改ap信道，协议和带宽等参数，apid为mac地址,channel为将要修改的信道
local function modapchannel(apid, channel)
	local version_k
	local apid_map
	local wlan_belong_k = pkey.chanid(apid, "2g")
	local ver = os.date("%Y%m%d %H%M%S")
	local group = "default"

	version_k = pkey.version(apid)
	cfgset(group, wlan_belong_k, channel)

	local bandwidth = pkey.bandwidth(apid, "2g")
	if cfgget(group, bandwidth) ~= "20" then
		cfgset(group, bandwidth, "20")
	end

	local proto = pkey.proto(apid, "2g")
	if cfgget(group, proto) ~= "bgn" then
		cfgset(group, proto, "bgn")
	end

	cfgset(group, version_k, ver)

	if apid and group then
		apid_map = dispatch.find_ap_config(group, apid)
	end

	return apid_map
end

--获取{1,3,6,8,11,13}中用户数量最小的信道
local function get_min_ssid(wlan, defaultchanel)
	local minvalue = 99
	local tmp, pos
	local i = defaultchanel[1]

	while i < #defaultchanel do
		tmp = defaultchanel[i]
		if wlan[tmp] <= minvalue then
			minvalue = wlan[tmp]
			pos = defaultchanel[i]
		end

		i = i + 1
	end

	return pos
end

--根据mac提取map中的ap信息
local function get_wlan_info(data,apid)
	for k, v in pairs(data) do
		if js.encode(v) == "{}" then
			return false
		end
	end

	local dat = js.decode(data[apid][1])

	return dat and dat or nil
end

--计算1~13 各个信道ssid数量,返回1~13信道各信道的ssid数量
local function get_ssid(data)
	local count
	local ssidchannel  = {}
	local returnchanel = {}
	local dat = data.wlan_info

	for i = 1, 13 do
		local tmp = string.format("chid%s", i)
		if dat[tmp] then
			count = #dat[tmp]
			ssidchannel[i] = count
		else
			ssidchannel[i] = 0
		end
	end

	for i = 1,#ssidchannel do
		if not ssidchannel[i-1]	then
			returnchanel[i] = ssidchannel[i] + ssidchannel[i+1] + ssidchannel[i+2]

		end

		if not ssidchannel[i+1] then
			returnchanel[i] = ssidchannel[i-1] + ssidchannel[i] + ssidchannel[i-2]

		end

		if ssidchannel[i+1] and ssidchannel[i-1] then
			returnchanel[i] = ssidchannel[i] + ssidchannel[i-1] + ssidchannel[i+1]
		end
	end

	return returnchanel and returnchanel
end

local function get_wlan_info(data,apid)
	for k, v in pairs(data) do
		if js.encode(v) == "{}" then
			return false
		end
	end

	local dat = js.decode(data[apid][1])

	return dat and dat or nil
end

--根据get_ssid获取1，3,6,8,11,13最小ssid,返回所在的信道
local function getminssid(data, chanelcollect)
	local tmp, pos
	local channel = {}

	local i = 1
	while i <= #chanelcollect do
		tmp = chanelcollect[i]
		table.insert(channel, data[tmp])
		i = i + 1
	end

	local minssid = channel[1]
	for i = 2, #channel do
		if channel[i] <= minssid then
			minssid = channel[i]
			pos = i
		end
	end

	return pos and chanelcollect[pos] or nil
end

--查找数据在表中的位置
local function findpos(wlan, tmp)
	local pos

	for i = 1,#wlan do
		if wlan[i] == tmp then
			pos = i
			break
		end
	end

	return pos and pos or nil
end

local function exist_judge(data, find)
	local ifexist = false

	for _, v in ipairs(data) do
		if v == find then
			ifexist = true
		end
	end

	return ifexist

end
--选择合适的信道，wlan为map,apinfo为map.wlan_info,apid为mac地址
local function choicechannel(wlan, apid, defaultchanel)
	local channel, datmp, copy_chanel
	copy_chanel = {1, 3, 6, 8, 11, 13}

	datmp = get_ssid(wlan)
	if wlan.usage >= 50 then   --信道利用率大于50才进行信道优化
		channel = getminssid(datmp, defaultchanel)

		if wlan.child ~= channel then
			table.remove(defaultchanel, findpos(defaultchanel, channel))
		else
			if wlan.flowrate > 1000 then
				table.remove(defaultchanel, findpos(defaultchanel, channel))
			else
				local channeltmp = defaultchanel
				table.remove(channeltmp, findpos(channeltmp, channel))
				channel = getminssid(datmp, channeltmp)
				table.remove(defaultchanel, findpos(defaultchanel, channel))
			end
		end
	else
		--如果利用率小于50，需要分清当前ap信道是否在1, 3, 6, 8, 11, 13
		if exist_judge(copy_chanel, wlan.child)  then
			if exist_judge(defaultchanel, wlan.child) then
				channel = wlan.child
				table.remove(defaultchanel, findpos(defaultchanel, channel))
			else
				local channeltmp = defaultchanel
				table.remove(channeltmp, findpos(channeltmp, channel))
				channel = getminssid(datmp, channeltmp)
				table.remove(defaultchanel, findpos(defaultchanel, channel))
			end
		else
			channel = wlan.child
		end
	end

	return channel
end

--程序的入口，map为传入的数据
local function decide(map)
	local returnmap, apinfo, channel = {}
	local maclist = {}
	local defaultchanel = {1, 3, 6, 8, 11, 13}

	if map then
		for i, v in pairs(map) do
			table.insert(maclist, i)
		end

		if #maclist > 6 then	-- 超过6个ap不需要判断
			return nil
		end

		for _, v in ipairs(maclist) do
			apinfo = get_wlan_info(map, v)
			if apinfo then
				channel = choicechannel(apinfo, v, defaultchanel)
				if channel >= 1 and channel <= 13 then
					returnmap[v] = modapchannel(v, channel)
				end
			end
		end
	end

	return returnmap
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
		if v == "1" then
			olmap[k] = v
		end
	end

	return olmap
end

-- 处理AP上传的数据
local function apinfo(group, aparr)
	if #aparr == 0 then
		return nil, "no ap"
	end

	local apid_map = {}
	local olmap = get_online(group, aparr)
	if not next(olmap) then
		return nil, "no ap"
	end

	local opt_time, cnt = 1, 0
	while opt_time <= 10 do
		local count = 0
		for apid, v in pairs(olmap) do
			local karr = {keys.c_chidinfo}
			local hkey = pkey.state_hash(apid)	assert(hkey)
			local varr = rds:hmget(hkey, karr)	-- 获取AP上传数据
			count = count + 1

			if js.encode(varr) ~= "{}" then
				cnt = cnt + 1
				apid_map[apid] = varr
			end
		end

		if cnt == count then
			break
		end

		cnt = 0
		opt_time = opt_time + 1
		se.sleep(3)
	end

	return cnt > 0 and apid_map or nil, "no data"
end

local function opt_chan(map)
	local group = map.group
	local hkey = keys.c_chidswitch	assert(hkey)
	rds:set(hkey, "1")	-- 发送使能位给status
	rds:expire(hkey, 60)	-- 有效期60秒将使能位关闭

	local aparr = aplist(group)
	local map_chid = {}
	local opt_time, num = tonumber(os.date("%S"))
	local opt_time = opt_time < 10 and opt_time + 10 or opt_time
	opt_time = opt_time > 50 and opt_time - 30 or opt_time
	opt_time = opt_time > 30 and opt_time - 20 or opt_time
	local save_num = opt_time
	local apid_map, err = apinfo(group, aparr)
	if not apid_map then
		num = err == "no ap" and "0" or save_num	-- 没有AP 返回0, 没有数据返回10-30
	end

	if apid_map then
		map_chid = decide(apid_map)	-- 调用算法函数将 apid_map 传进去
		opt_time = opt_time < 20 and opt_time + 20 or opt_time
		opt_time = opt_time > 50 and opt_time - 10 or opt_time	-- 优化值为 20-50

		num = map_chid and opt_time or save_num
		map_chid = map_chid and map_chid or {}
	end

	num = string.format("%s%%", num)
	hkey = keys.c_chidvalue	assert(hkey)
	local opt = {code = "sucess", extdata = num}
	rds:set(hkey, js.encode(opt))	-- 设置优化数据

	update_ap(map_chid)
	return true
end


local function set_rds(r)
	rds = r
end

local function set_opt_req(map)
	opt_req = map
end

local function init()
	while true do
		if opt_req then
			opt_chan(opt_req)
			opt_req = false
		end
		se.sleep(5)
	end
end

return {
	init = init,
	set_rds = set_rds,
	opt_chan = opt_chan,
	set_update_ap = set_update_ap,
	set_opt_req = set_opt_req,
}
