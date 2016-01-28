local log = require("log") 
local js = require("cjson.safe")
local common = require("common")
local defaultcfg = require("defaultcfg")

local cloudpath = "/etc/config/cloud.json"
local read, save, save_safe = common.read, common.save, common.save_safe

local function read_config()
	local s = read(cloudpath)
	local map = js.decode(s)
	if map and map.ac_host then 
		return map 
	end 
	
	return defaultcfg.default_cloud()
end

local function accountlist(conn, account, data)
	local map = read_config()
	map.state = (function()
		local s = read("/tmp/memfile/cloudcli.json")
		local m = js.decode(s or "{}") or {}
		return m.state and m or {state = 0}
	end)()
	return {status = 0; data = map}
end

local function accountset(conn, account, data) 
	local n = js.decode(data)
	if not n then 
		return {status = 1, data = "invalid param"}
	end

	local account, switch, descr, ac_host, ac_port = n.account, n.switch, n.descr, n.ac_host, n.ac_port
	if not (account and switch and descr and ac_host and ac_port) then
		return {status = 1, data = "invalid param"}
	end

	local n = {
		account = account,
		switch = switch,
		descr = descr,
		ac_host = ac_host,
		ac_port = ac_port
	}

	local omap, change = read_config(), false
	for k, ov in pairs(omap) do 
		local nv = n[k]
		if nv ~= ov then 
			change = true
			log.debug("cloud %s %s->%s", k, ov, nv)
		end
	end

	if not change then 
		return {status = 0, data = "ok"}
	end 

	local s = js.encode(n):gsub('","', '",\n"')
	save_safe(cloudpath, s)
	local cmd = string.format("/ugw/script/resetcfg.sh cloud_switch &") 
	os.execute(cmd)
	return {status = 0, data = "ok"}
end

return {
	accountset = accountset,
	accountlist = accountlist,
}