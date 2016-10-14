-- author: gl

local se = require("se")
local log = require("log")

local modules = {
	fwscrty = require("fwsecurity"),
}

local function main()
	log.setmodule("fws")

	for _, mod in pairs(modules) do
		mod.init()
	end
end

se.run(main)