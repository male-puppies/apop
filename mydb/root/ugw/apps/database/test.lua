local parser = require("rdsparser")
local js = require("cjson.safe")
local common = require("common")

local arr = {}

local map = {
	cmd = "authuser_set",
	data = {username = "username", password = "password"}
}
local s = js.encode(map)
local s = parser.encode({parser.hex(s), s})
table.insert(arr, s)

local map = {
	cmd = "authuser_set",
	data = {username = "username2", password = "password2"}
}
local s = js.encode(map)
local s = parser.encode({parser.hex(s), s})
table.insert(arr, s)

local s = table.concat(arr)
common.save("/tmp/update.log", s)

