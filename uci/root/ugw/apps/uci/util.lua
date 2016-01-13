local _ubus = require("ubus")

local function class(base)
	return setmetatable({}, {
		__call  = _instantiate,
		__index = base
	})
end

local function call(...)
	return os.execute(...) / 256
end

function in_table(value, tbl)
	for _, v in ipairs(tbl) do
		if v == value then
			return true
		end
	end
	return false
end

local function exec(command)
	local pp   = io.popen(command)
	local data = pp:read("*a")
	pp:close()

	return data
end

local function execi(command)
	local pp = io.popen(command)

	return pp and function()
		local line = pp:read()

		if not line then
			pp:close()
		end

		return line
	end
end

-- Deprecated
local function execl(command)
	local pp   = io.popen(command)
	local line = ""
	local data = {}

	while true do
		line = pp:read()
		if (line == nil) then break end
		data[#data+1] = line
	end
	pp:close()

	return data
end

local function contains(table, value)
	for k, v in pairs(table) do
		if value == v then
			return k
		end
	end
	return false
end

local function ubus(object, method, data)
	local _ubus_connection = _ubus.connect()
	
	if object and method then
		if type(data) ~= "table" then
			data = { }
		end
		return _ubus_connection:call(object, method, data)
	elseif object then
		return _ubus_connection:signatures(object)
	else
		return _ubus_connection:objects()
	end
end

return {
	class = class,
	call = call,
	in_table = in_table,
	exec = exec,
	execi = execi,
	execl = execl,
	ubus = ubus,
	contains = contains,
}