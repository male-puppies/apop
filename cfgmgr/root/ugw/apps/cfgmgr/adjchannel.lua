require("global")
local pkey  	= require("key")
local js 		= require("cjson.safe")
local dispatch  = require("dispatch")
local cfgmgr    = require("cfgmanager")
local defaultchanel={1,3,6,8,11,13}


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
	local apid_map = {}
	local wlan_belong_k = pkey.chanid(apid,"2g")
	local ver   = os.date("%Y%m%d %H%M%S")
	local group = "default"

	version_k = pkey.version(apid)
	cfgset(group,wlan_belong_k,channel)

	local bandwidth = pkey.bandwidth(apid,"2g")
	if cfgget(group,bandwidth) ~= "2g" then
		cfgset(group, bandwidth,"2g")
	end

	local proto = pkey.proto(apid,"2g")
	if	cfgget(group,proto) ~= "bgn" then
		cfgset(group, proto,"bgn")
	end

	cfgset(group, version_k, ver)
	cfgmgr.ins(group):save()--保存配置
	
	if apid and group then
		apid_map[apid] = dispatch.find_ap_config(group,apid)
	end

	return	apid_map

end

--获取{1,3,6,8,11,13}中用户数量最小的信道
local function get_min_ssid(wlan, defaultchanel)
	local minvalue = 99
	local tmp,pos
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

--返回字母对应的数字
local function numtochar(num)

	local index = {"one","two","three","four","five","six","seven","eight","night","ten","eleven","twelve","thirteen"}

	return index[num]
end


--根据mac提取map中的ap信息
local function get_wlan_info(data,apid)
	for k, v in pairs(data) do
		if js.encode(v) == "{}" then
			return false
		end
	end
	local dat
	dat=data[apid][1]
	dat=js.decode(dat)

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

	for i = 1,13 do
		if dat[numtochar(i)] then
			count = #dat[numtochar(i)]
			ssidchannel[i] = count
		else
			ssidchannel[i] = 0

		end

	end

	for i = 1,#ssidchannel do
		if not ssidchannel[i-1]	then
			returnchanel[i] = ssidchannel[i]+ssidchannel[i+1]+ssidchannel[i+2]

		end

		if not ssidchannel[i+1] then
			returnchanel[i] = ssidchannel[i-1]+ssidchannel[i]+ssidchannel[i-2]

		end

		if ssidchannel[i+1] and ssidchannel[i-1] then
			returnchanel[i] = ssidchannel[i]+ssidchannel[i-1]+ssidchannel[i+1]
		end
	end

	if returnchanel then
		return returnchanel
	end

end



--根据get_ssid获取1，3,6,8,11,13最小ssid,返回所在的信道
local function getminssid(data, chanelcollect)

	local tmp,pos
	local minssid = 99
	local channel = {}

	local i = 1
	while i <= #chanelcollect do
		tmp=chanelcollect[i]
		table.insert(channel,data[tmp])
		i = i+1
	end

	for i = 1,#channel do
		if channel[i] <=	minssid then
			minssid=channel[i]
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

--选择合适的信道，wlan为map,apinfo为map.wlan_info,apid为mac地址
local function choicechannel(wlan, apid)
	local channel,datmp

	if wlan.usage >= 50 then
		datmp=get_ssid(wlan)
		channel = getminssid(datmp,defaultchanel)

		if wlan.child ~= channel then
			table.remove(defaultchanel,findpos(defaultchanel,channel))
		else

			if wlan.flowrate > 1000 then
				table.remove(defaultchanel,findpos(defaultchanel,channel))
			else
				table.remove(defaultchanel,findpos(defaultchanel,channel))
			end

		end


	end

	if channel then
		return channel
	end

end

--程序的入口，map为传入的数据
local function decide(map)

	local apinfo
	local returnmap
	local channel
	local maclist = {}

	if map then
		for i,v in pairs(map) do
			table.insert(maclist,i)
		end

		for _, v in ipairs(maclist) do
			apinfo = get_wlan_info(map, v)
			if  apinfo then
				channel=choicechannel(apinfo,v)
				returnmap=modapchannel(v,channel)
			end

		end

	end
	defaultchanel={1,3,6,8,11,13}
	return returnmap
end

return{decide = decide,}


