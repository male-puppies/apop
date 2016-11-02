local log = require("log")
local luasql = require("luasql.sqlite3")

local g_db, g_env
local function connect(sourcename)
	g_env = luasql.sqlite3()
	local conn, err = g_env:connect(sourcename)
	local _ = conn or log.fatal("connect %s fail %s", sourcename, err or "")
	g_db = conn
end

local function close()
	local _ = g_db:close(), g_env:close()
	g_db, g_env = nil, nil
end

local function myexecute(sql)
	return g_db:execute(sql)
end

local function select_cb_common(sql, cb)
	local s = os.time()
	local cur, err = myexecute(sql)
	if not cur then
		return nil, err
	end

	local row = cur:fetch({}, "a")
	while row do
		cb(row)
		row = cur:fetch(row, "a")	-- reusing the table of results
	end
	cur:close()

	return true
end

local function select(sql)
	local arr = {}
	local ret, err = select_cb_common(sql, function(row)
		local nmap = {}
		for k, v in pairs(row) do
			nmap[k] = v
		end
		table.insert(arr, nmap)
	end)
	local _ = ret or log.fatal("sql fail %s %s", sql, err)
	return arr
end

local function promise(sql)
	local ret, err = myexecute(sql)
	local _ = ret or log.fatal("sql fail %s %s", sql, err)
end

return {
	connect = connect,
	close = close,
	execute = myexecute,
	select = select,
	promise = promise,
}