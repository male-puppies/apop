local log = require("log") 
local js = require("cjson.safe")
local common = require("common")
local defaultcfg = require("defaultcfg")
local read, save_safe = common.read, common.save_safe

local cloudpath = "/etc/config/cloud.json"
local authoptpath = "/etc/config/authopt.json"
local sms_config_path = "/etc/config/sms_config.json" 
local sms_counter_path = "/etc/config/sms_counter.json"

local function read_config() 
	local map = js.decode((read(cloudpath)))
	if map and map.ac_host then 
		return map 
	end
	
	return defaultcfg.default_sms()
end

local function read_sms() 
	local map = js.decode((read(sms_config_path)))
	if map and map.sno then 
		return map
	end 
	
	return defaultcfg.default_sms()
end

local function read_sms_counter()
	return js.decode((read(sms_counter_path))) or {success = 0, fail = 0}
end

local function get_sms_switch() 
	return js.decode((read(authoptpath)))
end

local function smslist(conn, account, data)
	local sms = read_sms()
	local cloud = read_config()
	sms.switch = cloud.switch
	local authopt = get_sms_switch()
	sms.sms = authopt and authopt.sms or 0
	sms.counter = read_sms_counter()
	return {status = 0, data = sms}
end

local function smsresetcounter(conn, account, data)
	save_safe(sms_counter_path, js.encode({success = 0, fail = 0}))
	return {status = 0, data = "ok"}
end

local function validate(n)
	local tp, sno, pwd, msg, sign, expire, sms_switch = tonumber(n.type), n.sno, n.pwd, n.msg, n.sign, tonumber(n.expire), tonumber(n.sms)
	if not (#pwd > 0 and #msg > 0 
		and #msg < 200 and #sign > 0 and #sign < 32 and expire >= 0 and (sms_switch == 0 or sms_switch == 1)) then
		return false 
	end

	return true 
end

local function smsset(conn, account, n)
	local tp, sno, pwd, msg, sign, expire, sms_switch = tonumber(n.type), n.sno, n.pwd, n.msg, n.sign, tonumber(n.expire), tonumber(n.sms)
	if not (tp and sno and pwd and msg and sign and expire and sms_switch) then 
		return {status = 1, data = "invalid param1"}
	end

	local cloud = read_config()
	if tonumber(cloud.switch) == 1 then 
		return {status = 0, data = "ok"}	
	end

	if not validate(n) then 
		return {status = 1, data = "invalid param"}
	end

	local nmap = {
		type = tp,
		sno = sno,
		pwd = pwd,
		msg = msg,
		sign = sign,
		expire = expire,
	}

	local o, change = read_sms(), false
	for k, ov in pairs(o) do 
		local nv = nmap[k]
		if ov ~= nv then 
			change = true
			log.debug("sms %s %s->%s", k, ov, nv)
		end 
	end

	local authopt = get_sms_switch()
	if not authopt then
		authopt, change = {sms = sms_switch}, true
	elseif authopt.sms ~= sms_switch then
		authopt.sms, change = sms_switch, true
		log.debug("sms %s->%s", authopt.sms, sms_switch)
	end

	if not change then 
		return {status = 0, data = "ok+"}	
	end

	local s = js.encode(nmap) 
	save_safe(sms_config_path, s)
	save_safe(authoptpath, js.encode(authopt))

	os.execute("/ugw/script/resetcfg.sh dev &")
	return {status = 0, data = "ok"}
end

return {
	smsset = smsset,
	smslist = smslist,
	smsresetcounter = smsresetcounter,
}
