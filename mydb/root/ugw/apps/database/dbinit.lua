local log = require("log")
local dc = require("dbcommon")

local diskmap = {}
function diskmap.authuser()
	local sql = [[
		create table if not exists authuser (
			uid integer primary key autoincrement,
			name 	varchar(64) 	not null unique default '',
			desc 	varchar(64) 	not null default '',
			usertype varchar(16) 	not null default 'web',
			switch 	char(2)   		not null default '1',
			multi 	char(2)			not null default '0'
		)
	]]
	dc.promise(sql)
end
--[[
111 	mac 	00:00:00:00:00:00
111 	mac 	00:00:00:00:00:01
111 	ip 		192.168.0.55
111 	expire 	2016-01-02 00:01:02
111 	remain 	999
]]
function diskmap.userprop()
	local sql = [[
		create table if not exists userprop (
			uid 	integer 		not null,
			type 	varchar(16)		not null default '',
			value 	varchar(128)	not null default ''
		)
	]]
	dc.promise(sql)
end

function diskmap.policy()
	local sql = [[
		create table if not exists policy (
			uid integer primary key autoincrement,
			name 	varchar(64) 	not null unique default '',
			type	varchar(8)		not null default 'web',
			ip1 	varchar(24)		not null default '',
			ip2		varchar(24)		not null default ''
		)
	]]
	dc.promise(sql)
end

local memory_map = {}
function memory_map.oluser()
	local sql = [[
		create table if not exists oluser (
			mac 	varchar(64)		primary key not null,
			ip 		varchar(24)		not null default '',
			name 	varchar(64) 	not null default '',
			elapse 	char(16)		not null default '0',
			jf 		char(16)		not null default '0'
		)
	]]
	dc.promise(sql)
end

local dbmap = {}
function dbmap.disk()
	os.execute("mkdir -p /tmp/db/")
	dc.connect("/tmp/db/disk.db")
	for _, func in pairs(diskmap) do
		func()
	end
end

function dbmap.recover()
	os.execute("rm -rf /tmp/recover; mkdir -p /tmp/recover/")
	dc.connect("/tmp/recover/disk.db")
	for _, func in pairs(diskmap) do
		func()
	end
end

function dbmap.memory()
	os.execute("mkdir -p /tmp/db/")
	dc.connect("/tmp/db/memory.db")
	for _, func in pairs(memory_map) do
		func()
	end
end

local function main(database)
	local func = dbmap[database]
	local _ = func and func()
end

log.setdebug(true)
main(...)
