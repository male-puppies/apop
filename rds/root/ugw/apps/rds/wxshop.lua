local log = require("log") 
local js = require("cjson.safe")
local common = require("common")
local defaultcfg = require("defaultcfg")

local cloudpath = "/etc/config/cloud.json"
local wxshoppath = "/etc/config/wx_config.json"
local read, save, save_safe = common.read, common.save, common.save_safe

local function read_config()
	local s = read(cloudpath)
	local map = js.decode(s)
	if map and map.ac_host then 
		return map 
	end 
	
	return defaultcfg.default_cloud()
end

local function read_wxshop()
	local s = read(wxshoppath)
	local map = js.decode(s)
	if map and map.shop_id then 
		return map
	end 
	
	return defaultcfg.default_wxshop()
end

local function wxshoplist(conn, account, data)
	local cloud = read_config()
	local wxshop = read_wxshop()
	wxshop.switch = cloud.switch
	return {status = 0; data = wxshop}
end

--[[
SSID: WXGUILIN
shopId: 7699460
appId: wx3ae592d54767e201
secretKey: 51c3e8536f6cfcc0987ab4538091181e
]]
local function validate(n)
	local appid, shop_name, shop_id, ssid, secretkey = n.appid, n.shop_name, n.shop_id, n.ssid, n.secretkey
	if not (#shop_id == 7 and #appid == 18 and #secretkey == 32) then 
		return false 
	end

	if tonumber(shop_id) == nil then 
		return false 
	end 

	return true 
end

local function wxshopset(conn, account, data)
	local n = js.decode(data)
	if not n then 
		return {status = 1, data = "invalid param"}
	end 
	
	local appid, shop_name, shop_id, ssid, secretkey = n.appid, n.shop_name, n.shop_id, n.ssid, n.secretkey
	if not (appid and shop_name and shop_id and ssid and secretkey) then
		return {status = 1, data = "invalid param"}
	end

	local cloud = read_config()
	if tonumber(cloud.switch) == 1 then 
		return {status = 0, data = "ok"}	
	end

	if not validate(n) then 
		return {status = 1, data = "invalid param"}
	end 
	
	local nmap = {
		appid = appid,
		shop_name = shop_name,
		shop_id = shop_id,
		ssid = ssid,
		secretkey = secretkey,
	}
	local o, change = read_wxshop(), false
	for k, ov in pairs(o) do 
		local nv = nmap[k]
		if ov ~= nv then 
			change = true
			log.debug("wxshop %s %s->%s", k, ov, nv)
		end 
	end 

	if not change then 
		return {status = 0, data = "ok"}	
	end

	local s = js.encode(nmap) 
	save_safe(wxshoppath, s)
	local cmd = string.format('PATH="/ugw/bin:$PATH" LUA_CPATH="/ugw/lib/?.so;$LUA_CPATH" LUA_PATH="/ugw/share-sc/?.lua;$LUA_PATH" lua /ugw/sh/init_scripts/reset_wx2cfg.lua')
	os.execute(cmd)
	os.execute("/ugw/sh/init_scripts/resetcfg.sh dev &")
	return {status = 0, data = "ok"}
end


return {
	wxshopset = wxshopset,
	wxshoplist = wxshoplist,
}