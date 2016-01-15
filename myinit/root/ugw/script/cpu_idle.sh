#!/usr/bin/lua
local function resource_info()
	local exec = function(cmd)
		local fp = io.popen(cmd, "r")
		if not fp then 
			return nil
		end
		local content = fp:read("*a")
		fp:close()
		return content
	end
	local idle = exec("mpstat 1 2 | grep Average | grep all |  awk '{print $11}'") or "90.0"
	idle = idle:gsub("[ \t\r\n]", "")
	idle = tonumber(idle) or 90.0
	return idle
end

local function monitor()
	local s = resource_info()
	local fp = io.open("/tmp/cpu_idle.tmp", "wb")
	fp:write(s)
	fp:close()
	os.execute("mv /tmp/cpu_idle.tmp /tmp/cpu_idle")
end

while true do
	monitor()
end 
 