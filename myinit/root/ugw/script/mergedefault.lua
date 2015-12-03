local js = require("cjson.safe")

local current_file = "/etc/config/default/m.json"
local default_file = "/etc/default_config.json"

local function parse_json(file)
	local fp, err = io.open(file, "rb")

	if not fp then 
		return nil 
	end 
	local s = fp:read("*a")
	fp:close()
	local map, err = js.decode(s)
	local _ = map or print("decode fail", file, err)
	return map
end

local function save_current(file, current)
	local tmpfile = "/tmp/tmp_config.json"
	local fp = io.open(tmpfile, "wb")
	fp:write(js.encode(current))
	fp:close()
	local cmd = string.format("mv %s %s", tmpfile, file)
	print(cmd)
	local _ = os.execute(cmd) ~= 0 and print("cmd fail", cmd)
end

local current = parse_json(current_file)
local default = parse_json(default_file)

if not (current and default) then 
	print("missing ", current and "" or current_file, default and "" or default_file)
	os.exit(0)
end

local change = false
for nk, nv in pairs(default) do
	if not current[nk] then
		print("new", nk, nv)
		current[nk], change = nv, true
	end
end

local _ = change or os.exit(0)
local s = js.encode(current)
save_current(current_file, current)
