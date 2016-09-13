local log = require("log")
local pkey = require("key")
local js = require("cjson.safe")
local const = require("constant")

local rds, pcli
local keys = const.keys

local function get_status(s, d)
	return {status = s, data = d or "ok"}
end

local function get_chidstatus()
	local hkey = keys.c_chidvalue	assert(hkey)
	local varr = rds:get(hkey)

	return varr
end

local function wifiadj(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(rds and pcli)

	local optstatus = get_chidstatus()
	optstatus = js.decode(optstatus)
	local hkey = keys.c_chidvalue	assert(hkey)

	if not optstatus then
		optstatus = {code = "optimizing"}
		rds:set(hkey, js.encode(optstatus))
		rds:expire(hkey, 31)
		pcli:modify({cmd = "wifiadj", data = {group = group}})	

		return get_status(0, optstatus)
	end

	if optstatus.code == "optimizing" then
		return get_status(0, optstatus)
	end

	if optstatus.code == "sucess" then
		optstatus.code = "optimal"
		rds:set(hkey, js.encode(optstatus))
		rds:expire(hkey, 600)
		local save_ret = {code = "sucess", extdata = optstatus.extdata}
		return get_status(0, save_ret)
	end

	if optstatus.code == "optimal" then
		return get_status(0, optstatus)
	end

	return get_status(0, {code = "optimal"})
end

return {wifiadj = wifiadj}
