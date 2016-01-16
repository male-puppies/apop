local se = require("se")
local log = require("log")
local js = require("cjson.safe")
local dc = require("dbcommon")
local ud = require("updatelog")
local dispatch = require("dispatch")

local function main()
	ud.recover()
	ud.init()
	

end

log.setdebug(true)

se.run(main)
