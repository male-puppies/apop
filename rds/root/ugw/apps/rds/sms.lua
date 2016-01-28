local log = require("log") 
local js = require("cjson.safe")

local function smslist(conn, account, data)

	return {status = 1, msg = "not implement"}
end

local function smsset(conn, account, data)

	return {status = 1, msg = "not implement"}
end

return {
	smsset = smsset,
	smslist = smslist,
}