local sdb = require("sdb")


-- open test.db 
-- execute 
-- close 

--[[
mod = {
	mod1 = {
		db = {
			db1 = 1
			db2 = 1,
		}
	}
}

cmd = {
	mod = xxx, 
	seq = yyy,
	pld = {
		id = open,
		db = test,
	}
}

cmd = {
	mod = xxx, 
	seq = yyy,
	pld = {
		id = exec,
		sql = sql,
	}
}

]]