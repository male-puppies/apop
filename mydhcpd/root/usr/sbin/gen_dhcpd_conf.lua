#!/usr/bin/lua

bit={
	data32={
		2147483648,1073741824,536870912,268435456,134217728,67108864,33554432,16777216,8388608,4194304,2097152,1048576,524288,262144,131072,65536,32768,16384,8192,4096,2048,1024,512,256,128,64,32,16,8,4,2,1
	}
}

function bit:d2b(arg)
	local   tr={}
	for i=1,32 do
		if arg >= self.data32[i] then
			tr[i]=1
			arg=arg-self.data32[i]
		else
			tr[i]=0
		end
	end
	return   tr
end   --bit:d2b

function    bit:b2d(arg)
	local   nr=0
	for i=1,32 do
		if arg[i] ==1 then
			nr=nr+2^(32-i)
		end
	end
	return  nr
end   --bit:b2d

function    bit:_xor(a,b)
	local   op1=self:d2b(a)
	local   op2=self:d2b(b)
	local   r={}
	for i=1,32 do
		if op1[i]==op2[i] then
			r[i]=0
		else
			r[i]=1
		end
	end
	return  self:b2d(r)
end --bit:xor

function    bit:_and(a,b)
	local   op1=self:d2b(a)
	local   op2=self:d2b(b)
	local   r={}

	for i=1,32 do
		if op1[i]==1 and op2[i]==1  then
			r[i]=1
		else
			r[i]=0
		end
	end
	return  self:b2d(r)
end --bit:_and

function    bit:_or(a,b)
	local   op1=self:d2b(a)
	local   op2=self:d2b(b)
	local   r={}

	for i=1,32 do
		if  op1[i]==1 or   op2[i]==1   then
			r[i]=1
		else
			r[i]=0
		end
	end
	return  self:b2d(r)
end --bit:_or

function    bit:_not(a)
	local   op1=self:d2b(a)
	local   r={}

	for i=1,32 do
		if  op1[i]==1   then
			r[i]=0
		else
			r[i]=1
		end
	end
	return  self:b2d(r)
end --bit:_not

function    bit:_rshift(a,n)
	local   op1=self:d2b(a)
	local   r=self:d2b(0)

	if n < 32 and n > 0 then
		for i=1,n do
			for i=31,1,-1 do
				op1[i+1]=op1[i]
			end
			op1[1]=0
		end
		r=op1
	end
	return  self:b2d(r)
end --bit:_rshift

function    bit:_lshift(a,n)
	local   op1=self:d2b(a)
	local   r=self:d2b(0)

	if n < 32 and n > 0 then
		for i=1,n   do
			for i=1,31 do
				op1[i]=op1[i+1]
			end
			op1[32]=0
		end
		r=op1
	end
	return  self:b2d(r)
end --bit:_lshift


function    bit:print(ta)
	local   sr=""
	for i=1,32 do
		sr=sr..ta[i]
	end
	print(sr)
end


local DHCP_FILE = "/var/etc/dhcpd.conf"

--local B=require("bit")
local B=bit

dhcpd_conf_header = "#dhcpd configure\n\nauthoritative;\ndb-time-format local;\n\n"
dhcpd_conf_node = "subnet %s netmask %s {\n    default-lease-time 86400;\n    max-lease-time %d;\n    option routers %s;\n    option domain-name-servers %s;\n    pool {\n        range %s %s;\n        allow all clients;\n    }\n}\n\n"
dhcpd_conf_host = "host %s {\n  hardware ethernet %s;\n  fixed-address %s;\n}\n"
--print(dhcpd_conf_header)
local dhcpd_conf_str = dhcpd_conf_header

function ip2int(ipstr)
	local i = 0
	local ta = string.split(ipstr, ".")
	i = B:_or(B:_lshift(i, 8), tonumber(ta[1]))
	i = B:_or(B:_lshift(i, 8), tonumber(ta[2]))
	i = B:_or(B:_lshift(i, 8), tonumber(ta[3]))
	i = B:_or(B:_lshift(i, 8), tonumber(ta[4]))
	return i
end

function int2ip(ip)
	return string.format("%d.%d.%d.%d", B:_and(B:_rshift(ip, 24), 255), B:_and(B:_rshift(ip, 16), 255), B:_and(B:_rshift(ip, 8), 255), B:_and(ip, 255))
end

local l = require("luci.cbi")
--[[for k, v in pairs(l) do
	print(k, v)
end]]

local network = l.Map("network", "", "")
local dhcp = l.Map("dhcp", "", "")

dhcp.uci:foreach("dhcp", "dhcp", function(d)                                                                    
	--print(d.interface, d.ignore)
	if d.ignore == nil then
		network.uci:foreach("network", "interface", function(n)
			--print("ifname", n[".name"])
			if d.interface == n[".name"] then
				--print("meet", d.interface, n.ipaddr, n.netmask, d.start, d.limit, d.leasetime, d.dhcp_option)
				local iface = d.interface
				local ipaddr = n.ipaddr
				local netmask = n.netmask
				local start = d.start or "100"
				local limit = d.limit or "150"
				local leasetime = d.leasetime or "12h"
				local dhcp_option = d.dhcp_option or "6,8.8.8.8,8.8.4.4"
				--print("get", iface, ipaddr, netmask, start, limit, leasetime, dhcp_option)
				local ip = ip2int(ipaddr)
				local mask = ip2int(netmask)
				local net = B:_and(ip, mask)
				local range_start = net + tonumber(start)
				local range_end = range_start + tonumber(limit) - 1
				local lease_time = 24 * 60 * 60

				if string.find(leasetime, "h") then
					lease_time = string.gsub(leasetime, "h", "")
					lease_time = tonumber(lease_time) * 60 * 60
				elseif string.find(leasetime, "m") then
					lease_time = string.gsub(leasetime, "m", "")
					lease_time = tonumber(lease_time) * 60
				end

				--print("lease_time=", lease_time)
				dhcp_option = string.gsub(dhcp_option, "^6,", "")
				dhcpd_conf_str = dhcpd_conf_str .. string.format(dhcpd_conf_node, int2ip(net), int2ip(mask), lease_time, int2ip(ip), dhcp_option, int2ip(range_start), int2ip(range_end))
			end
		end)
	end
end) 


dhcp.uci:foreach("dhcp", "host", function(h)                                                                    
	--print(h.mac, h.ip)
	dhcpd_conf_str = dhcpd_conf_str .. string.format(dhcpd_conf_host, h.ip, h.mac, h.ip)
end)

--[[network.uci:foreach("network", "interface", function(s)
	print("ifname", s.ifname)
end)]]

--print(dhcpd_conf_str)

local conf = io.open(DHCP_FILE, "w+")
io.output(conf)
io.write(dhcpd_conf_str)
io.close(conf)

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
		os.execute("sleep 10; reboot")
	end 
end 

