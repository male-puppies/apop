local se = require("se")
local log = require("log")
local lfs = require("lfs")
local js = require("cjson.safe")

local function execute(s)
	-- print(s)
	return true
end


return {
	execute = execute,
}
