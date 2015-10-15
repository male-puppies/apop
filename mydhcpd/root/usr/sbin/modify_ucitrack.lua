#!/usr/bin/lua
local trackpath = "/etc/config/ucitrack"
local fp = io.open(trackpath, "rb")
if fp then 
	local s = fp:read("*a")
	fp:close()
	if s:find("'dnsmasq'") then 
		s = s:gsub("'dnsmasq'", "'dhcpd'")
		local tmp = "/tmp/tmp_ucitrack"
		local fp = io.open(tmp, "wb")
		fp:write(s)
		fp:flush()
		fp:close()
		os.execute(string.format("mv %s %s", tmp, trackpath))
	end 
end 

