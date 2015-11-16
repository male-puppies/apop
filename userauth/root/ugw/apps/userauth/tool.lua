local uci = require("uci")
local js = require("cjson.safe") 
local myutil = require("myutil")

local read, write = myutil.read, myutil.write

--[[
local function get_firewall()
	local ret = uci.load("firewall")
	if not ret then 
		return
	end 

	local cursor = uci.cursor()
	local iface = {}
	cursor:foreach("firewall", "zone", function(sec)
		local name, network = sec.name, sec.network
		if type(network) == "string" then
			local s = network .. " "
			local arr = {}
			for part in s:gmatch("(%S-)%s") do 
				table.insert(arr, part) 
			end 
			network = arr
		end

		iface[name] = network
	end)
	return iface
end

local function get_network()
	local ret = uci.load("network")
	if not ret then 
		return
	end 
	local cursor = uci.cursor() 
	local netw = {}
	cursor:foreach("network", "interface", function(sec)
		local name, ifname = sec[".name"], sec.ifname
		if sec.type == "bridge" then 
			ifname = "br-" .. name
		elseif sec.proto == "pppoe" then
			ifname = "pppoe-" .. name
		end
		netw[name] = ifname
	end)
	return netw
end

local cmd_map = {}

function cmd_map.iface(arg)
	local firewall_map, network_map = get_firewall(), get_network()
	if not (firewall_map and network_map) then 
		io.stderr:write("read firewall or network fail\n")
		os.exit(-1)
	end 

	local type_map = {wan = 1, lan = 0}
	local arr = {}
	for ftype, network in pairs(firewall_map) do 
		for _, network_name in ipairs(network) do 
			local ifname = network_map[network_name]
			if ifname then 
				table.insert(arr, {
					InterfaceName = ifname,
					InterfaceType = type_map[ftype],
				})
			end 
		end 
	end 

	local s = js.encode(arr)
	print(s)
end 
--]]
local cmd_map = {}

local function toarr(map)
	local arr = {}
	for k in pairs(map) do 
		table.insert(arr, k)
	end 
	return arr 
end

local function get_iface()
	local s = read("ip ro", io.popen)
	s = s .. "\n"

	local wan, lan, all = {}, {}, {}
	for part in s:gmatch("(.-)\n") do 
		local ifname = part:match("dev%s+(.-)%s")
		if ifname and not wan[ifname] then 
			all[ifname] = 1

			local iswlan = part:find("^default")
			if iswlan then 
				wan[ifname] = 1
			end
		end
	end

	for ifname in pairs(all) do 
		if not wan[ifname] then 
			lan[ifname] = 1
		end
	end 

	return lan, wan 
end

function cmd_map.iface(arg)
	local lan, wan = get_iface() 
	local arr = {}

	for ifname in pairs(lan) do 
		table.insert(arr, {
			InterfaceName = ifname,
			InterfaceType = 0,
		})
	end 

	for ifname in pairs(wan) do 
		table.insert(arr, {
			InterfaceName = ifname,
			InterfaceType = 1,
		})
	end 

	local s = js.encode(arr)
	-- write("/tmp/memfile/userauth_config.json", s)
	print(s)
end

local arg = {...}
local cmd = table.remove(arg, 1)
cmd_map[cmd](arg)


