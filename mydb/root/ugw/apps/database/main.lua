local se = require("se")
local log = require("log")
local js = require("cjson.safe")
local dc = require("dbcommon")
local ud = require("updatelog")

local function main()
	-- recover from log.sql and the last disk.db
	ud.recover()

	-- backup disk.db and remove log.sql

	-- promise database

	-- connect mqtt and start service 

end

log.setdebug(true)

se.run(main)
