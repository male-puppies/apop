local log = require("log")
local js = require("cjson.safe")
local uci = require("muci")
local utl = require("util")
local network = require("network")
local ipc = require("luci.ip")

local function read(path, func)
	func = func and func or io.open
	local fp = func(path, "rb")
	if not fp then 
		return 
	end 
	local s = fp:read("*a")
	fp:close()
	return s
end

local function switch_status(dev)
	local ports = { }
	local str = string.format("swconfig dev %q show | grep link", dev)
	local swc = io.popen(str, "r")
	if swc then
		local l
		repeat
			l = swc:read("*l")
			if l then
				local port, up = l:match("port:(%d+) link:(%w+)")
				if port then
					local speed  = l:match(" speed:(%d+)")
					local duplex = l:match(" (%w+)-duplex")

					ports[#ports+1] = {
						port   = tonumber(port) or 0,
						speed  = tonumber(speed) or 0,
						link   = (up == "up"),
						duplex = (duplex == "full")
					}
				end
			end
		until not l
		swc:close()
	end

	return ports
end

local function get_zone(curs, eth)
	local zone = network.get_firewall_zone(curs)
	if zone[eth] then
		return zone[eth]
	else
		log.debug("error get wan or lan form " .. eth)
		return "lan0"
	end
end

local function get_interface(curs, eth)
	local zone = get_zone(curs, eth)
	local wan = network.new_proto(curs, zone)
	return {
		ipaddr  = wan:ipaddr(),
		gwaddr  = wan:gwaddr(),
		netmask = wan:netmask(),
		dns     = wan:dnsaddrs(),
		uptime  = wan:uptime(),
		proto   = wan:proto(),
		ifname  = wan:ifname(),
		zone	= zone,
	}
end

local function getstatus(group, data)
	local sysinfo = utl.ubus("system", "info", {})
	local boardinfo = utl.ubus("system", "board", {})
	if not (sysinfo and boardinfo) then
		return {status = 1, data = ""}
	end
	
	local conn_max = tonumber((
		read("sysctl net.nf_conntrack_max", io.popen) or
		read("sysctl net.ipv4.netfilter.ip_conntrack_max", io.popen) or
		""):match("%d+")) or 4096

	local conn_count = tonumber((
			read("wc -l /proc/net/nf_conntrack", io.popen) or
			read("wc -l /proc/net/ip_conntrack", io.popen) or
			""):match("%d+")) or 0

	local rv = {
		version		= boardinfo.release.description or "",
		uptime		= sysinfo.uptime or 0,
		times		= os.date("%Y-%m-%d %H:%M:%S"),
		loadavg		= sysinfo.load or { 0, 0, 0 },
		usercount	= read("auth_tool '{\"GetAllUser\":1}' | grep st:1 | wc -l", io.popen),
		cpuidle		= read("/tmp/cpu_idle") or "90",
		memorymax	= sysinfo.memory.total / 1024,
		memorycount	= (sysinfo.memory.total - sysinfo.memory.free - sysinfo.memory.buffered) / 1024,
		connmax		= conn_max,
		conncount	= conn_count,
	}

	return {status = 0, data = rv}
end

local function getethstatus(group, data)
	local curs = uci.cursor()
	local switches = network.get_switches(curs)
	local psta = switch_status(switches[1])
	local switch_vlan = network.get_switch_vlan(curs, switches[1])
	local map = {}
	
	for key, val in pairs(switch_vlan) do
		map[key] = get_interface(curs, val)
	end

	for key, val in pairs(map) do
		for _, v in ipairs(psta) do
			if tonumber(key:match("port(%d+)")) == tonumber(v["port"]) then
				val.speed = v["speed"] or 100
				val.duplex = v["duplex"]
				val.link = v["link"]
			end
		end
		map[key] = val
	end

	return {status = 0, data = map}
end

local function getdhcplease(group, data)
	os.execute("lua /ugw/script/lease.lua")
	local s = read("/tmp/openwrt_leases.json")
	if not s then
		return {status = 1, data = ""}
	end
	local data = js.decode(s) or {}
	return {status = 0, data = data}
end

local function getroutes(group, data)
	local curs = uci.cursor()
	local rtn = {
		[255] = "local",
		[254] = "main",
		[253] = "default",
		[0]   = "unspec"
	}
	local arr = {}
	for _, v in ipairs(ipc.routes({ family = 4, type = 1 })) do
		local rv = {
			dev		= tostring(network.iface_get_network(curs, v.dev) or v.dev),
			dest	= tostring(v.dest or "--"),
			gateway	= tostring(v.gw or "--"),
			metric	= tostring(v.metric or 0),
			table	= tostring(rtn[v.table] or v.table),
		}
		table.insert(arr, rv)
	end
	return {status = 0, data = arr}
end

local function getsyslog(group, data)
	local logs = utl.exec("logread")
	if not logs then
		return {status = 1, data = ""}
	else
		return {status = 0, data = logs}
	end
end

return {
	getstatus = getstatus,
	getethstatus = getethstatus,
	getdhcplease = getdhcplease,
	getroutes = getroutes,
	getsyslog = getsyslog,
}