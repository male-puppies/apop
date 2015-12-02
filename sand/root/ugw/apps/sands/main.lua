local uv = require("luv") 
local sands = require("sands")

local function is_gw_mode()
	local fp, err = io.open("/ugw/apps/cfgmgr")
	if fp then
		return false
	else
		return true
	end
end

local function main(host, port)
	local ins = sands.new()
	ins:start_server(host, port)
	uv.run()
end

local host, port = ...
host = host or "0.0.0.0"
port = port or 61886
if is_gw_mode() then
	host = "127.0.0.1"
end
main(host, port)