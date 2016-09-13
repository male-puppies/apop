local se = require("se")
local log = require("log")
local pkey = require("key")
local js = require("cjson.safe")
local const = require("constant")
local dispatch  = require("dispatch")
local cfgmgr = require("cfgmanager")

local keys = const.keys
local rds

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
	local ver   = os.date("%Y%m%d %H%M%S")
	local group = "default"

	version_k = pkey.version(apid)
	cfgset(group, wlan_belong_k, channel)

	local bandwidth = pkey.bandwidth(apid, "2g")
	if cfgget(group, bandwidth) ~= "20" then
		cfgset(group, bandwidth, "20")
	end

	local proto = pkey.proto(apid, "2g")
	if	cfgget(group, proto) ~= "bgn" then
		cfgset(group, proto, "bgn")
	end

	cfgset(group, version_k, ver)

	if apid and group then
		apid_map = dispatch.find_ap_config(group, apid)
	end

	return	apid_map
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
		i = i+1
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

	local dat
	dat = js.decode(data[apid][1])


	if dat  then
		return dat
	end

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

	if returnchanel then
		return returnchanel
	end

end

local function get_wlan_info(data,apid)
	for k, v in pairs(data) do
		if js.encode(v) == "{}" then
			return false
		end
	end

	local dat
	dat = js.decode(data[apid][1])


	if dat then
		return dat
	end

end

--根据get_ssid获取1，3,6,8,11,13最小ssid,返回所在的信道
local function getminssid(data, chanelcollect)

	local tmp, pos
	local minssid = 99
	local channel = {}

	local i = 1
	while i <= #chanelcollect do
		tmp = chanelcollect[i]
		table.insert(channel, data[tmp])
		i = i+1
	end

	for i = 1,#channel do
		if channel[i] <= minssid then
			minssid = channel[i]
			pos = i
		end
	end

   if pos then

	return chanelcollect[pos]
   end

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

	if pos then
		return pos
	end

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
	if wlan.usage  >= 50 then   --信道利用率大于50才进行信道优化
		--datmp = get_ssid(wlan)
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

		for _, v in ipairs(maclist) do
			apinfo = get_wlan_info(map, v)
			if  apinfo then
				channel = choicechannel(apinfo, v, defaultchanel)
				returnmap[v] = modapchannel(v, channel)
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
	while opt_time <= 3 do
		for apid, v in pairs(olmap) do
			local karr = {keys.c_chidinfo}
			local hkey = pkey.state_hash(apid)	assert(hkey)
			local varr = rds:hmget(hkey, karr)	-- 获取AP上传数据

			if js.encode(varr) ~= "{}" then
				cnt = cnt + 1
				apid_map[apid] = varr
			end
		end

		if cnt > 0 then
			break
		end

		opt_time = opt_time + 1
		se.sleep(1)
	end

	return cnt > 0 and apid_map or nil, "no data"
end

local function opt_chan(map)
	local group = map.group

	local hkey = keys.c_chidswitch	assert(hkey)
	rds:set(hkey, "1")	-- 发送使能位给status
	rds:expire(hkey, 60)	--- 有效期30秒将使能位关闭

	local aparr = aplist(group)
	local apid_map, err = apinfo(group, aparr)
	local map_chid, num = {}
	if not apid_map then
		num = err == "no ap" and "0%" or string.format("%d%%", math.random(10, 20))	-- 没有AP 返回0 没有数据返回10-20
	end

	if apid_map then
		map_chid = decide(apid_map)	-- 调用算法函数将 apid_map 传进去
		local opt_time = tonumber(os.date("%S"))	-- 优化值20-50
		opt_time = opt_time <= 20 and opt_time + 20 or opt_time
		opt_time = opt_time >= 50 and opt_time - 10 or opt_time

		num = map_chid and opt_time or string.format("%d%%", math.random(20, 30))
		map_chid = map_chid and map_chid or {}
	end

	hkey = keys.c_chidvalue	assert(hkey)
	local opt = {code = "sucess", extdata = num}
	rds:set(hkey, js.encode(opt))	-- 设置优化数据

	return map_chid
end

local function set_rds(r)
	rds = r
end

return {
	set_rds = set_rds,
	opt_chan = opt_chan,
}
