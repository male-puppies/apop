local se = require("se") 
local summary = require("summary")
local backupcfg = require("backupcfg")
local watchubus = require("watchubus")


local function read(path, func)
	func = func and func or io.open
	local fp = func(path, "r")
	if not fp then 
		return 
	end 
	local s = fp:read("*a")
	fp:close()
	return s
end

local function clear_log()
	local path = "/tmp/backup/essential.log"
	local n = tonumber(read(string.format("wc -l %s | awk '{print $1}'", path), io.popen)) or 0

	local max = 2000
	if n < max then 
		return 
	end 

	local cmd = string.format("tail -%d %s > /tmp/essential.log; cat /tmp/essential.log > %s", math.floor(max/3*2), path, path)
	os.execute(cmd)
end

local function main()
	clear_log()
	summary.run()
	watchubus.run()
	backupcfg.run() 
end

se.run(main)