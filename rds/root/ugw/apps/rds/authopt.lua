local log = require("log") 
local js = require("cjson.safe")
local common = require("common") 
local read, save_safe = common.read, common.save_safe

local authoptpath = "/etc/config/authopt.json"

local function get_authopt() 
	return js.decode((read(authoptpath))) or {}
end

local function authoptlist(conn, account, data)
	return {status = 0, data = get_authopt() or {redirect = ""}
end

local function authoptset(conn, account, map) 
	if not (map and map.redirect) then 
		return {status = 1, data = "invalid param"}
	end

	local authopt, nredirect = get_authopt(), map.redirect
	if (authopt.redirect == nredirect) then 
		return {status = 0, data = "nothing change"}
	end 

	authopt.redirect = map.redirect
	save_safe(authoptpath, js.encode(authopt))
	os.execute("/ugw/script/resetcfg.sh dev &")
	return {status = 0, data = "ok"}
end

return {authoptset = authoptset, authoptlist = authoptlist}
