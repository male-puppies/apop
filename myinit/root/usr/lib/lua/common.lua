local lfs = require("lfs")

local function read(path, func)
	func = func and func or io.open
	local fp, err = func(path, "r")
	if not fp then
		return nil, err
	end
	local s = fp:read("*a")
	fp:close()
	return s
end

local function save(path, s)
	local fp, err = io.open(path, "w") 	assert(fp, err)
	fp:write(s)
	fp:flush()
	fp:close()
end

local function save_safe(path, s)
	local tmp = path .. ".tmp"
	save(tmp, s)

	local cmd = string.format("mv %s %s", tmp, path)
	os.execute(cmd)
end


local function file_exist(file)
	if file and lfs.attributes(file, "mode") then
		return true
	end
	return false
end

return {read = read, save = save, save_safe = save_safe, file_exist = file_exist}