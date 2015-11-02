local slte = require("lsqlite3")

local db, err = slte.open(":memory:") assert(db, err)
local ret, err = slte.exec(db, "create table if not exists tb1 (id int, name text)") 	assert(ret, err)
local ret, err = slte.exec(db, string.format("insert into tb1 values(%s, '%s');", os.time(), os.date()))
local t, err = slte.exec(db, "select * from tb1", true)
for k, v in ipairs(t) do 
	print(k, v[1], v[2])
end
slte.close(db)
