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
	
	local ret = get_chidstatus()
	ret = js.decode(ret)
	local hkey = keys.c_chidvalue	assert(hkey)
	if not ret then
		local ret = {code = "1"}
		rds:set(hkey, js.encode(ret))

		pcli:modify({cmd = "wifiadj", data = {group = group}})	
		return get_status(0, ret)
	end
	if ret.code == "1" then
		return get_status(0, ret)
	end
	if ret.code == "2" then
		ret.code = "3"
		rds:set(hkey, js.encode(ret))
		rds:expire(hkey, 600)	-- 10分钟有效期,最优情况

		local save_ret = {code = "2", extdata = ret.extdata}
		return get_status(0, save_ret)
	end
	if ret.code == "3" then
		return get_status(0, ret)
	end

	return
end

return {wifiadj = wifiadj}