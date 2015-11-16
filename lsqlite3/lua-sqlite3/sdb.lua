local slte = require("lsqlite3")
--[[
local db, err = slte.open("/tmp/test.db") assert(db, err)
local ret, err = db:exec("create table if not exists tb1 (id int, name text)") 	assert(ret, err)
local ret, err = db:exec(string.format("insert into tb1 values(%s, '%s');", os.time(), os.date()))
local ret, err = db:exec(string.format("insert into tb1 values(%s, '%s');", os.time(), "hello world"))
local t, err = db:exec("select * from tb1", true)
for k, v in ipairs(t) do 
	print(k, v[1], v[2])
end
db:close()
--]]


