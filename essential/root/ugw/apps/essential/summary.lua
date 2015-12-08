local se = require("se")
local lfs = require("lfs")
local struct = require("struct")
local js = require("cjson.safe")
local common = require("common")
local read, save, save_safe = common.read, common.save, common.save_safe 
local ac_info_path = "/www/rom/ac"
local host, port = "cloud.i-wiwi.com", 61884

local function get_mac()
	local eth0mac = read("ifconfig eth0 | grep HWaddr | awk '{print $5}'", io.popen)
	if not eth0mac then 
		return 
	end 

	eth0mac = eth0mac:gsub("[ \t\r\n]", ""):lower()
	if #eth0mac ~= 17 then 
		return 
	end 

	return eth0mac
end

local function get_remote(h)
	local cloud_host = "/tmp/memfile/cloud_host.txt"
	if lfs.attributes(cloud_host) then 
		return read(cloud_host)
	end

	local cmd = string.format("timeout -t 120 nslookup '%s' | grep -A 1 '%s' | grep Address | awk '{print $3}'", h, h)
	local ip = read(cmd, io.popen)
	if not ip then 
		return 
	end 

	ip = ip:gsub("[ \r\t\n]", "")
	if not ip:find("%d+%.%d+%.%d+%.%d+") then 
		return
	end 

	save_safe(cloud_host, ip)

	return ip
end


local function send_report(h, p, s)
	local ip, port = get_remote(h), p
	if not ip then
		return 
	end 
	local addr = string.format("tcp://%s:%s", ip, port)

	local client = se.connect(addr)
	if not client then
		return
	end

	local data = struct.pack("<I", #s) .. s
	se.write(client, data)
	se.close(client)
end

local function report_now(s)
	local mac = get_mac()
	if not mac then 
		return
	end 

	local map = {m = mac, e = s}
	local s = js.encode(map)

	send_report(host, port, s)
end

local function gen_summary()
	local cmd = [[
		ifconfig eth0 | grep HWaddr | awk '{print $5}'
		test $? -ne 0 && exit 1 
		cat /etc/openwrt_release | grep DISTRIB_DESCRIPTION | awk -F= '{print $2}' 
		test $? -ne 0 && exit 2
		cfgpath=/etc/config/default/m.json
		if [ ! -e $cfgpath ]; then 
			echo -e "0\n0\n0\n"
			exit 0
		fi
		n25=`cat $cfgpath | grep -F '#barr":"[\"2g\",\"5g\"]' | wc -l 2>/dev/null`
		n2=`cat $cfgpath | grep -F '#barr":"[\"2g\"]' | wc -l 2>/dev/null` 
		n5=`cat $cfgpath | grep -F '#barr":"[\"5g\"]' | wc -l 2>/dev/null` 
		echo -e "$n2\n$n5\n$n25\n"
	]]
	local s = read(cmd, io.popen)

	local arr = {}
	for part in s:gmatch("(.-)\n") do 
		local tt = part:gsub("[ \t]$", "")
		if #tt > 0 then 
			table.insert(arr, tt)
		end
	end

	if #arr ~= 5 then 
		print("cmd fail", #arr, cmd, s)
		return 
	end

	local map = {
		m = arr[1]:lower(),
		d = {
			ct = "7621 " .. arr[2]:gsub("'", ""),
			n2 = tonumber(arr[3]),
			n5 = tonumber(arr[4]),
			n25 = tonumber(arr[5]),
		},
		h = host,
		p = port,
	}
	
	local s = js.encode(map)
	save_safe(ac_info_path, s)
	print("gen_summary ok", ac_info_path)
end

local function send_summary()
	if not lfs.attributes(ac_info_path) then 
		return
	end 
	local s = read(ac_info_path)
	local map = js.decode(s)
	if not map then 
		return 
	end 

	local hh, pp = map.h, map.p 
	local nmap = {
		m = map.m, 
		d = map.d,
	}
	send_report(hh, pp, js.encode(nmap))
	print("send_report finish")
end

local function main()
	se.sleep(300)
	while true do 
		gen_summary()
		send_summary() 
		se.sleep(7200 * 3)
	end
end

local function run()
	se.go(main)
end

return {run = run, report_now = report_now}
