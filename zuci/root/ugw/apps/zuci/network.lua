local js = require("cjson.safe")
local log = require("log") 
local utl = require("util")
local uci = require("muci")
local ipc = require("luci.ip")

local function get_interface(curs, sid, opt)
	assert(curs)
	local v = curs:get("network", sid, opt)
	if type(v) == "table" then
		return table.concat(v, " ")
	end
	return v or ""
end

local function is_empty(curs, sid)
	assert(curs)
	local rv = true
	if (get_interface(curs, sid, "ifname") or ""):match("%S+") then
		rv = false
	end
	return rv
end

local function delete_all_option(curs, config, section)
	assert(curs)
	
	if section and config then
		local map = curs:get_all(config, section)
		local del = {}
		for key, val in pairs(map) do
			if not (key:find("%.") == 1) then
				if not curs:delete(config, section, key) then
					return false
				end
			end
		end
	else
		return false
	end
	
	return true
end

local function get_switches(curs)
	assert(curs)
	local switches = {}
	curs:foreach("network", "switch", 
		function(x)
			if x.name then
				switches[#switches+1] = x.name
			end
		end
	)
	
	if #switches == 0 then
		switches[#switches+1] = "switch0"
	end
	
	return switches
end

local function iface_get_network(curs, iface)
	assert(curs)
	local link = ipc.link(tostring(iface))
	if link.master then
		iface = link.master
	end

	local dump = utl.ubus("network.interface", "dump", { })
	if dump then
		local _, net
		for _, net in ipairs(dump.interface) do
			if net.l3_device == iface or net.device == iface then
				-- cross check with uci to filter out @name style aliases
				local uciname = curs:get("network", net.interface, "ifname")
				if not uciname or uciname:sub(1, 1) ~= "@" then
					return net.interface
				end
			end
		end
	end
end

local function get_firewall_zone(curs)
	assert(curs)
	local zone = {}
	curs:foreach("firewall", "zone",
		function(s)
			local str = s.network or ""
			for val in string.gmatch(str .. " ", "(%w+)%s*") do
				if val then
					local ifname = curs:get("network", val, "ifname")
					if ifname then
						zone[ifname] = val
					end
				end
			end
		end
	)

	return zone
end

local function get_firewall_dis(curs, dis)
	assert(curs)
	local arr = {}
	curs:foreach("firewall", "zone",
		function(s)
			if s.name and s.name == dis then
				local str = s.network or ""
				for val in string.gmatch(str .. " ", "(%w+)%s*") do
					if val then
						local ifname = curs:get("network", val, "ifname")
						if ifname then
							table.insert(arr, val)
						end
					end
				end
			end
		end
	)

	return arr
end

local function get_switch_vlan(curs, sw)
	assert(curs)
	local svlan = {}
	curs:foreach("network", "switch_vlan",
		function(s)
			if s.vlan and s.device == sw and s.ports ~= "6t" then
				local str = s.ports or ""
				str = string.gsub(str, "6t", "")

				for val in string.gmatch(str .. " ", "(%d+)%s*") do
					svlan["port" .. val] = "eth0." .. s.vlan
				end
			end
		end
	)
	return svlan
end

local function del_switch_vlan(curs)
	assert(curs)
	curs:delete_all("network", "switch_vlan",
		function(s) return (s.device == "switch0") end)
	
	local map = nil
	curs:foreach("network", "switch_vlan",
		function(s)
			if s then
				map = s
			end
		end
	)
	
	return map
end

local function set_switch_vlan(curs, data)
	assert(curs)
	
	local wan_arr, lan_arr = {}, {}
	if data["wan0"] then
		for key, val in pairs(data) do
			if key:find("wan") == 1 then
				table.insert(wan_arr, key)
			else
				return false
			end
		end
		lan_arr = get_firewall_dis(curs, "lan")
	elseif data["lan0"] then
		for key, val in pairs(data) do
			if key:find("lan") == 1 then
				table.insert(lan_arr, key)
			else
				return false
			end
		end
		wan_arr = get_firewall_dis(curs, "wan")
		if (5 - #wan_arr < #lan_arr) then
			return false
		end
	else
		return false
	end

	local vlan = {}
	for i = 0, 4 do
		if i < (5 - #wan_arr) and i >= #lan_arr then
			local tmp = vlan["vlan1"] or ""
			tmp = tmp .. i .. " "
			vlan["vlan1"] = tmp
		else
			local tmp = vlan["vlan" .. (i + 1)] or ""
			tmp = tmp .. i .. " "
			vlan["vlan" .. (i + 1)] = tmp
		end
	end
	
	if not del_switch_vlan(curs) then
		for k, v in pairs(vlan) do
			local switches = get_switches(curs)
			local vid = k:match("vlan(%d)")
			local mark = curs:section("network", "switch_vlan", nil,
				{
					device = switches[1],
					vlan = vid,
					vid = vid,
					ports = v .. "6t"
				}
			)
		end
	else
		return false
	end

	return true
end

local function get_config(curs, zone)
	assert(curs)
	local wan = get_firewall_dis(curs, zone)
	local map = {}
	for _, val in ipairs(wan) do
		local options = curs:get_all("network", val)
		map[val] = options
	end
	
	return map
end

local function del_network(curs, n, bool)
	assert(curs)
	
	local r = curs:delete("network", n)
	if r and bool then
		curs:delete_all("network", "alias",
			function(s) return (s.interface == n) end)

		curs:delete_all("network", "route",
			function(s) return (s.interface == n) end)

		curs:delete_all("network", "route6",
			function(s) return (s.interface == n) end)

	end
	return r
	
	
	
	
	-- local iface;
	-- local curs = cursor or uci.cursor()
	-- for i = 0, 3 do
		-- local r = curs:delete("network", zone .. i)
		-- iface = zone .. i
		-- if r then
			-- curs:delete_all("network", "alias",
				-- function(s) return (s.interface == zone .. i) end)

			-- curs:delete_all("network", "route",
				-- function(s) return (s.interface == zone .. i) end)

			-- curs:delete_all("network", "route6",
				-- function(s) return (s.interface == zone .. i) end)
			
			-- local cmd = string.format("env -i /sbin/ifdown %q >/dev/null 2>/dev/null", iface)
			-- utl.call(cmd)
		-- end
	-- end
	
	-- local map = nil
	-- for k = 0, 3 do
		-- local ss  = curs:get("network", zone .. k)
		-- if ss then
			-- map = ss
		-- end
	-- end

	-- return map
end

local function get_mod_arr(wans, lans)
	local arr = {}
	arr["wan0"] = 1
	arr["lan0"] = 1
	for i = 1, 3 do
		local wan = "wan" .. i
		local lan = "lan" .. i
		
		if utl.in_table(wan, wans) then
			arr[wan] = 1
		else
			arr[wan] = 0
		end
		if utl.in_table(lan, lans) then
			arr[lan] = 1
		else
			arr[lan] = 0
		end
	end
	return arr
end

local function modify_network(curs, newarr, oldarr, data)
	assert(curs)

	local mark, del = true, {}
	for keys, vals in pairs(newarr) do
		if vals == 1 then
			if oldarr[keys] == 1 then
				--修改
				if data[keys] and del_network(curs, keys) then
					if not curs:section("network", "interface", keys, data[keys]) then
						log.debug("error modify_network mod " .. keys)
						mark = false
					end
				end
			else
				--添加
				if data[keys] then
					if not curs:section("network", "interface", keys, data[keys]) then
						log.debug("error modify_network add " .. keys)
						mark = false
					end
				end
			end
		else
			if oldarr[keys] == 1 then
				--删除
				if del_network(curs, keys, true) then
					table.insert(del, keys)
				else
					log.debug("error modify_network delete " .. keys)
					mark = false
				end
			end
		end
	end
	return mark, del
end

local function set_wan_network(curs, data)
	assert(curs)
	local wan_arr = get_firewall_dis(curs, "wan") or {}
	local lan_arr = get_firewall_dis(curs, "lan") or {}
	local wan_new = {}
	
	for k, _ in pairs(data) do
		if k:find("wan") == 1 then
			table.insert(wan_new, k)
		else
			log.debug("error parameter " .. k)
			return false
		end
	end
	
	local oldarr = get_mod_arr(wan_arr, lan_arr)
	local newarr = get_mod_arr(wan_new, lan_arr)

	for key, val in pairs(data) do
		local num = key:match("wan(%d)")
		if num then
			local lan = "lan" .. (4 - num)
			for _, v in ipairs(lan_arr) do
				local lan = "lan" .. (4 - num)
				if lan == v then
					newarr[v] = 0
				end
			end
		end
	end
	
	local mark, has_delete = modify_network(curs, newarr, oldarr, data)
	if mark then
		for _, del in ipairs(has_delete) do
			local cmd = string.format("env -i /sbin/ifdown %q >/dev/null 2>/dev/null", del)
			utl.call(cmd)
		end
		return true
	else
		log.debug("error modify_network...")
		return false
	end
end

local function set_lan_network(curs, data)
	assert(curs)
	
	local wan_arr = get_firewall_dis(curs, "wan") or {}
	local lan_arr = get_firewall_dis(curs, "lan") or {}
	local lan_new = {}
	
	for k, _ in pairs(data) do
		if k:find("lan") == 1 then
			table.insert(lan_new, k)
		else
			log.debug("error parameter " .. k)
			return false
		end
	end
	
	local oldarr = get_mod_arr(wan_arr, lan_arr)
	local newarr = get_mod_arr(wan_arr, lan_new)

	for key, val in pairs(data) do
		local num = key:match("lan(%d)")
		if num then
			local wan = "wan" .. (4 - num)
			if utl.in_table(wan, wan_arr) then
				log.debug("error collide with " .. wan)
				return false
			end
		end
	end
	
	local mark, has_delete = modify_network(curs, newarr, oldarr, data)
	if mark then
		for _, del in ipairs(has_delete) do
			local cmd = string.format("env -i /sbin/ifdown %q >/dev/null 2>/dev/null", del)
			utl.call(cmd)
		end
		return true
	else
		log.debug("error modify_network...")
		return false
	end
end


local mt_proto = {}
mt_proto.__index = {
	_ubus = function(self, field)
		local ubus, str = {}, string.format("network.interface.%s", self.sid)
		ubus[self.sid] = utl.ubus(str, "status", { })
		if not ubus[self.sid] then
			return nil
		end
		if field then
			return ubus[self.sid][field]
		end
		return ubus[self.sid]
	end,

	ipaddr = function(self)
		local addrs = self:_ubus("ipv4-address")
		return addrs and #addrs > 0 and addrs[1].address or "--"
	end,
	
	netmask = function(self)
		local addrs = self:_ubus("ipv4-address")
		if addrs and #addrs > 0 then
			local str = string.format("0.0.0.0/%d", addrs[1].mask)
			return ipc.IPv4(str):mask():string()
		else
			return "--"
		end
		
		
	end,
	
	gwaddr = function(self)
		local _, route
		for _, route in ipairs(self:_ubus("route") or { }) do
			if route.target == "0.0.0.0" and route.mask == 0 then
				return route.nexthop
			end
		end
		return "--"
	end,
	
	dnsaddrs = function(self)
		local dns = { }
		local _, addr
		for _, addr in ipairs(self:_ubus("dns-server") or { }) do
			if not addr:match(":") then
				dns[#dns+1] = addr
			end
		end
		return dns
	end,
	
	uptime = function(self)
		return self:_ubus("uptime") or 0
	end,
	
	proto = function(self)
		return self:_ubus("proto") or "none"
	end,
	
	ifname = function(self)
		local curs = self.curs or uci.cursor()
		return self:_ubus("device") or "eth0.?"
	end,
}

local function new_proto(cursor, name)
	local obj = {sid = name, curs = cursor}
	setmetatable(obj, mt_proto)
	return obj
end

local function getwanconfig(group, data)
	local curs = uci.cursor()
	local wan_map = get_config(curs, "wan")
	local lan_arr = get_firewall_dis(curs, "lan")
	wan_map["lan"] = lan_arr
	return {status = 0, data = wan_map}
end

local function setwanconfig(group, data)
	local curs = uci.cursor()
	if type(data) ~= "table" then
		log.debug("error setwanconfig %s", data);
		return {status = 1, data = "参数错误"} 
	end
	
	if set_switch_vlan(curs, data) then
		if not set_wan_network(curs, data) then
			return {status = 1, data = "修改network失败"}
		end
	else
		return {status = 1, data = "修改vlan失败"}
	end
	
	local mit = curs:commit("network")
	if mit then
		utl.call("/etc/init.d/network restart")
		-- utl.call("env -i /bin/ubus call network restart >/dev/null 2>/dev/null")
		return {status = 0, data = ""}
	else
		log.debug("error setwanconfig commit")
		return {status = 1, data = ""}
	end
end

local function getlanconfig(group, data)
	local curs = uci.cursor()
	local lan_map = get_config(curs, "lan")
	local wan_arr = get_firewall_dis(curs, "wan")
	local lan_arr = get_firewall_dis(curs, "lan")
	local map = {}
	for _, val in ipairs(lan_arr) do
		local options = curs:get_all("dhcp", val)
		map[val] = options
	end
	
	lan_map["wan"] = wan_arr
	lan_map["dhcp"] = map
	return {status = 0, data = lan_map}
end

local function setdhcpconfig(curs, data)
	local _ = assert(type(data) == "table") and assert(curs)

	for key, _ in pairs(data) do
		if not key:find("lan") then
			log.debug("error setdhcpconfig " .. key)
			return false
		end
	end

	local tosec = true
	for k, v in pairs(data) do
		if curs:get("dhcp", k, "interface") then
			--mod
			if delete_all_option(curs, "dhcp", k) then
				if not curs:tset("dhcp", k, v) then
					tosec = false
				end
			else
				tosec = false
			end
		else
			--add
			if not curs:section("dhcp", "dhcp", k, v) then
				tosec = false
			end
		end
	end
	
	if not tosec then
		log.debug("error uci mod dhcpconfig")
		return false
	end
	
	local mit = curs:commit("dhcp")
	if mit then
		-- utl.call("/etc/init.d/network restart")
		return true
	else
		log.debug("error setdhcpconfig commit")
		return false
	end
end

local function setlanconfig(group, data)
	local curs = uci.cursor()
	if type(data) ~= "table" and type(data.dhcp) ~= "table" then
		log.debug("error setlanconfig %s", data);
		return {status = 1, data = "参数错误"} 
	end
	
	local map, dhcp = {}, {}
	
	for key, val in pairs(data) do
		if key == "dhcp" then
			dhcp = val
		else
			map[key] = val
		end
	end
	
	if set_switch_vlan(curs, map) then
		if not set_lan_network(curs, map) then
			return {status = 1, data = "修改network失败"}
		end
	else
		return {status = 1, data = "修改vlan失败"}
	end
	
	local mit = curs:commit("network")
	local mark = setdhcpconfig(curs, dhcp)
	if mit and mark then
		utl.call("/etc/init.d/network restart")
		-- utl.call("env -i /bin/ubus call network restart >/dev/null 2>/dev/null")
		return {status = 0, data = ""}
	else
		log.debug("error setlanconfig commit")
		return {status = 1, data = ""}
	end
end

local function getstaroutes(group, data)
	local curs = uci.cursor()
	
	local map = {}
	curs:foreach("network", "route", 
		function(x)
			table.insert(map, x)
		end
	)

	return {status = 0, data = map}
end

local function getinterface(group, data)
	local curs = uci.cursor()

	local map = get_firewall_zone(curs) or {}
	return {status = 0, data = map}
end

local function addroutes(group, data)
	local curs = uci.cursor()
	if type(data) ~= "table" then
		log.debug("error addroutes %s", data);
		return {status = 1, data = "参数错误"} 
	end
	
	for key, val in pairs(data) do
		if not (key == "interface" or key == "target" or key == "netmask" or key == "gateway" or key == "metric" or key == "mtu") then
			log.debug("error addroutes %s", key)
			return {status = 1, data = "参数错误"}
		end
	end
	
	local mark = curs:section("network", "route", nil, data)
	if not mark then
		log.debug("error addroutes section")
		return {status = 1}
	end
	
	local mit = curs:commit("network")
	if mit then
		utl.call("/etc/init.d/network restart")
		-- utl.call("env -i /bin/ubus call network restart >/dev/null 2>/dev/null")
		return {status = 0, data = ""}
	else
		log.debug("error addroutes commit")
		return {status = 1, data = ""}
	end
	
end

local function updateroutes(group, data)
	local curs = uci.cursor()
	if type(data) ~= "table" then
		log.debug("error updateroutes %s", data);
		return {status = 1, data = "参数错误"} 
	end
	
	if not data[".name"] then
		log.debug("error updateroutes lost .name")
		return {status = 1, data = ".name缺失"}
	else
		if curs:get("network", data[".name"]) ~= "route" then
			log.debug("error updateroutes invalid .name")
			return {status = 1, data = "无效的接口名"}
		end
	end
	
	for key, val in pairs(data) do
		if not (key == ".name" or key == "interface" or key == "target" or key == "netmask" or key == "gateway" or key == "metric" or key == "mtu") then
			log.debug("error updateroutes %s", key)
			return {status = 1, data = "参数错误"}
		end
	end
	
	if not delete_all_option(curs, "network", data[".name"]) then
		log.debug("error delete_all_option network %s", data[".name"])
		return {status = 1, data = ""}
	end
	
	local mark = curs:tset("network", data[".name"], data)
	if not mark then
		log.debug("error updateroutes section")
		return {status = 1, data = ""}
	end
	
	local mit = curs:commit("network")
	if mit then
		utl.call("/etc/init.d/network restart")
		return {status = 0, data = ""}
	else
		log.debug("error updateroutes commit")
		return {status = 1, data = ""}
	end
end

local function deleteroutes(group, data)
	local curs = uci.cursor()
	if type(data) ~= "table" then
		log.debug("error deleteroutes %s", data);
		return {status = 1, data = "参数错误"} 
	end
	
	if not data[".name"] then
		log.debug("error deleteroutes lost .name")
		return {status = 1, data = ".name缺失"}
	else
		if curs:get("network", data[".name"]) ~= "route" then
			log.debug("error deleteroutes invalid .name")
			return {status = 1, data = "无效的接口名"}
		end
	end
	
	local mark = curs:delete("network", data[".name"])
	if not mark then
		log.debug("error updateroutes section")
		return {status = 1, data = "无效的接口名"}
	end
	
	local mit = curs:commit("network")
	if mit then
		utl.call("/etc/init.d/network restart")
		return {status = 0, data = ""}
	else
		log.debug("error updateroutes commit")
		return {status = 1, data = ""}
	end
end

local function diag_command(cmd, addr)
	if addr and addr:match("^[a-zA-Z0-9%-%.:_]+$") then
		local cmds = string.format(cmd, addr)
		local data = utl.exec(cmds) or "error"
		return data
	else
		return "Bad address"
	end
end

local function diagping(group, data)
	if not (type(data) == "string") then
		return {status = 1, data = "参数错误"}	
	end
	
	local str = diag_command("ping -c 5 -W 1 %q 2>&1", data)
	
	return {status = 0, data = str}
end

local function diagtraceroute(group, data)
	if not (type(data) == "string") then
		return {status = 1, data = "参数错误"}	
	end
	
	local str = diag_command("traceroute -q 1 -w 1 -n %q 2>&1", data)
	
	return {status = 0, data = str}
end

local function diagnslookup(group, data)
	if not (type(data) == "string") then
		return {status = 1, data = "参数错误"}	
	end
	
	local str = diag_command("nslookup %q 2>&1", data)
	
	return {status = 0, data = str}
end

local function getmwan(group, data)
	local curs = uci.cursor()

	local map = {}
	curs:foreach("mwan3", "interface", function(s)
		local name = s[".name"]
		local tmp = map["interface"] or {}
		tmp[name] = s
		map["interface"] = tmp
	end)
	
	curs:foreach("mwan3", "member", function(s)
		local name = s[".name"]
		local tmp = map["member"] or {}
		tmp[name] = s
		map["member"] = tmp
	end)
	
	curs:foreach("mwan3", "policy", function(s)
		local name = s[".name"]
		local tmp = map["policy"] or {}
		tmp[name] = s
		map["policy"] = tmp
	end)
	
	curs:foreach("mwan3", "rule", function(s)
		local name = s[".name"]
		local tmp = map["rule"] or {}
		tmp[name] = s
		map["rule"] = tmp
	end)

	return {status = 0, data = map}
end

local function delete_all_mwan(curs, arr)
	assert(curs)
	local mark = true

	for _, v in ipairs(arr) do
		curs:delete_all("mwan3", v)
		if curs:get_first ("mwan3", v) then
			mark = false
		end
	end

	return mark
end

local function setmwan(group, data)
	local curs = uci.cursor()	
	if not (type(data) == "table") then
		return {status = 1, data = "参数错误"}	
	end
	
	local arr = {"interface", "member", "policy", "rule"}
	if data["delete"] and data["delete"] == "all" then
		if delete_all_mwan(curs, arr) and curs:commit("mwan3") then
			return {status = 0, data = ""}
		else
			log.debug("error setmwan commit fail")
			return {status = 1, data = ""}
		end
	end

	if not data.interface or not data.member or not data.policy or not data.rule then
		log.debug("setmwan invalid parameter")
		return {status = 1, data = "参数错误"}	
	end

	local del = delete_all_mwan(curs, arr)
	local mark = true
	if del then
		for _, val in ipairs(arr) do
			for k, v in pairs(data[val]) do
				if not curs:section("mwan3", val, k, v) then
					mark = false
				end
			end
		end
	else
		log.debug("error setmwan del")
		return {status = 1, data = ""}
	end
	
	if mark and curs:commit("mwan3") then
		return {status = 0, data = ""}
	else
		log.debug("error setmwan section fail")
		return {status = 1, data = ""}
	end
end

return {
	get_switches = get_switches,
	iface_get_network = iface_get_network,
	get_firewall_zone = get_firewall_zone,
	get_switch_vlan = get_switch_vlan,
	new_proto = new_proto,
	getwanconfig = getwanconfig,
	setwanconfig = setwanconfig,
	getlanconfig = getlanconfig,
	setlanconfig = setlanconfig,
	getstaroutes = getstaroutes,
	getinterface = getinterface,
	addroutes = addroutes,
	updateroutes = updateroutes,
	deleteroutes = deleteroutes,
	diagping = diagping,
	diagtraceroute = diagtraceroute,
	diagnslookup = diagnslookup,
	-- getdhcpconfig = getdhcpconfig,
	-- setdhcpconfig = setdhcpconfig,
	getmwan = getmwan,
	setmwan = setmwan,
}