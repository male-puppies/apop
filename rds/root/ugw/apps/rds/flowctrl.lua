local log = require("log")
local js = require("cjson")
local path = "/etc/config/tc.json"

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

local function save_file(path, map)
	local tmp = path .. ".tmp"
	local s = js.encode(map)
	s = string.gsub(s, "{}", "[]")
	s = string.gsub(s, '"Enabled":"true"', '"Enabled":true')
	s = string.gsub(s, '"Enabled":"false"', '"Enabled":false')
	local fp = io.open(tmp, "wb")

	fp:write(s)
	fp:flush()
	fp:close()

	local cmd = string.format("mv %s %s", tmp, path)
	os.execute(cmd)

	local cmd = "lua /usr/sbin/settc.lua /etc/config/tc.json | cat > /sys/module/tbq/tbq"
	os.execute(cmd)

	local cmd = "echo 1 > /sys/module/tbq/tbq"
	os.execute(cmd)
end

local function getflow(conn, group, data)
	local s = read(path)
	if not s then
		return {status = 1, data = ""}
	end
	
	local data = js.decode(s)
	if not data then
		return {status = 1, data = ""}
	end
	
	return {status = 0, data = data}
end

local function setglobal(conn, group, data)
	local data = data 							assert(data)

	local s = read(path)
	if not s then
		return {status = 1, data = ""}
	end
	
	local map = js.decode(s)
	if not map then
		return {status = 1, data = ""}
	end
	
	for k, v in pairs(data) do
		map[k] = v
	end
	save_file(path, map)
	return {status = 0}
end

local function insrules(conn, group, data)
	local data = data 							assert(data)
	local s = read(path)
	if not s then
		return {status = 1, data = ""}
	end
	
	local map = js.decode(s)
	if not map then
		return {status = 1, data = ""}
	end
	
	local f = true
	for _, v in ipairs(map["Rules"]) do
		if v["Name"] == data["Name"] then
			f = false
			break
		end
	end

	if f == true then
		table.insert(map["Rules"], data)
		save_file(path, map)
		return {status = 0}
	else
		return {status = 1}
	end
end

local function updaterules(conn, group, data)
	local data = data 							assert(data)
	local s = read(path)
	if not s then
		return {status = 1, data = ""}
	end
	
	local map = js.decode(s)
	if not map then
		return {status = 1, data = ""}
	end
	
	local f = false
	local arr = {}
	for _, v in ipairs(map["Rules"]) do
		if v["Name"] == data["Name"] then
			for key, val in pairs(data) do
				v[key] = data[key]
			end
			table.insert(arr, v)
			f = true
		else
			table.insert(arr, v)
		end
	end

	if f == true then
		map["Rules"] = arr
		save_file(path, map)
		return {status = 0}
	else
		return {status = 1}
	end
end

local function deleterules(conn, group, data)
	local data = data 							assert(data)
	local s = read(path)
	if not s then
		return {status = 1, data = ""}
	end
	
	local map = js.decode(s)
	if not map then
		return {status = 1, data = ""}
	end
	
	local arr = {}
	for _, v in ipairs(map["Rules"]) do
		local f = true
		for _, name in ipairs(data) do
			if v["Name"] == name then
				f = false
			end
		end
		if f == true then
			table.insert(arr, v)
		end
	end

	if (#map["Rules"] - #data) == #arr then
		map["Rules"] = arr
		save_file(path, map)
		return {status = 0}
	else
		return {status = 1}
	end
end

return {
	getflow = getflow,
	setglobal = setglobal,
	insrules = insrules,
	updaterules = updaterules,
	deleterules = deleterules,
}