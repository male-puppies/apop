require("global")
local pkey  	= require("key")
local js 		= require("cjson.safe")
local dispatch  = require("dispatch")
local cfgmgr    = require("cfgmanager")
local defaultchanel={1,3,6,8,11,13}


--д���ݵ������ļ�
local function cfgset(g, k, v)
	return cfgmgr.ins(g):set(k, v)
end

--���������ļ�
local function cfgget(g, k)
	return cfgmgr.ins(g):get(k)
end

--�޸�ap�ŵ���Э��ʹ���Ȳ�����apidΪmac��ַ,channelΪ��Ҫ�޸ĵ��ŵ�
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
	cfgmgr.ins(group):save()--��������
	
	if apid and group then
		apid_map[apid] = dispatch.find_ap_config(group,apid)
	end

	return	apid_map

end

--��ȡ{1,3,6,8,11,13}���û�������С���ŵ�
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

--������ĸ��Ӧ������
local function numtochar(num)

	local index = {"one","two","three","four","five","six","seven","eight","night","ten","eleven","twelve","thirteen"}

	return index[num]
end


--����mac��ȡmap�е�ap��Ϣ
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

--����1~13 �����ŵ�ssid����,����1~13�ŵ����ŵ���ssid����
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



--����get_ssid��ȡ1��3,6,8,11,13��Сssid,�������ڵ��ŵ�
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

--���������ڱ��е�λ��
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

--ѡ����ʵ��ŵ���wlanΪmap,apinfoΪmap.wlan_info,apidΪmac��ַ
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

--�������ڣ�mapΪ���������
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


