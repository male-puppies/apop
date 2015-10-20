local json = require "cjson.safe"

-- TODO heavy cpu consume 
local function load()
	local fp = io.open("/tmp/dhcpd.leases")
	if not fp then 
		return {}
	end
	local s = fp:read("*a")
	fp:close()

	local map = {}
	for part in s:gmatch("(lease.-})") do  
		local ip, et, mac = part:match("lease (%d+.-) {.-ends.-(%d+).-ethernet (.-);")
		if ip then
			local et = tonumber(et)
			local now = os.time()

			local seconds = et - now 
			local t = {}
			for _, item in ipairs({{s = 86400, d = "d"}, {s = 3600, d = "h"}, {s = 60, d = "m"}, {s = 1, d = "s"}}) do 
				local res = math.floor(seconds / item.s)
				if res > 0 then 
					table.insert(t, string.format("%d%s", res, item.d))
				end
				seconds = seconds - res * item.s
			end
			local hostname = part:match('hostname "(.-)"') or ""
			map[ip] = {expires = table.concat(t, " "), hostname = hostname, macaddr = mac, ipaddr = ip} 
		end
	end 

	local arr = {}
	for _, v in ipairs(map) do 
		table.insert(arr, v)
	end 
	return arr  
end


local leases = load()
local out = "/tmp/openwrt_leases.json"
local tmp = out .. ".tmp"
local fp = io.open(tmp, "wb")
fp:write(json.encode(leases))
fp:flush()
fp:close()
local cmd = string.format("sh -c \"mv %s %s\"", tmp, out)
os.execute(cmd)
