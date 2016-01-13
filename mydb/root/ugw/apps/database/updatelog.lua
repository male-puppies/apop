local se = require("se")
local log = require("log")
local lfs = require("lfs")
local js = require("cjson.safe")
local dispatch = require("dispatch")
local rdsparser = require("rdsparser")

local diskdb = "/etc/config/disk.db"
local logpath = "/etc/config/update.log"

local function copy_disk()
	local cmd = string.format([[
		test -d /tmp/db/ || mkdir -p /tmp/db/
		test -e /tmp/db/disk.db && rm -f /tmp/db/disk.db
		test -e %s && cp -f %s /tmp/db/]], diskdb, diskdb)
	os.execute(cmd)
end

local function backup_disk()
	local tmp, del = diskdb .. ".tmp", diskdb .. ".del"
	local cmd = string.format([[
		test -e %s && rm -f %s
		cp /tmp/db/disk.db %s
		test -e %s && rm -f %s
		test -e %s && mv %s %s
		mv %s %s
		rm -f %s
	]], tmp, tmp, tmp, del, del, diskdb, diskdb, del, tmp, diskdb, del)

	local s = se.time()
	local ret, err = os.execute(cmd)
	local d = se.time() - s
	if not (ret == true or ret == 0) then 
		log.fatal("cmd fail %s %s %s", d, cmd, err or "")
	end
	log.debug("backup_disk spends %ss", d)
end

local function do_recover()
	local fp, err = io.open(logpath, "rb")
	local _ = fp or log.fatal("open fail %s %s", logpath, err)

	local decoder = rdsparser.decode_new()

	local error_return = function(msg)
		log.error("decode update.log fail. %s", msg or "")
		decoder:decode_free()
		backup_disk() 
		fp:close()
		os.execute("rm -f " .. logpath)
	end

	while true do
		local data = fp:read(4096)
		if not data then
			if decoder:empty() then 
				return fp:close()
			end
			return error_return("decoder not empty") 
		end
		
		local arr, err = decoder:decode(data)
		if err then
			return error_return("decode fail " .. err)
		end

		for _, narr in ipairs(arr) do
			local ohex, s = narr[1], narr[2]
			if not (ohex and #ohex == 8 and s) then
				return error_return("invalid cmd " .. js.encode(narr))
			end

			local nhex = rdsparser.hex(s)
			if ohex ~= nhex then
				return error_return(string.format("invalid cmd %s %s", nhex, js.encode(narr)))
			end 
			
			local ret, err = dispatch.execute(s)
			local _ = ret or log.fatal("dispatch execute fail %s %s", s, err or "")
		end
	end
end

local function recover()
	copy_disk()

	local attr = lfs.attributes(logpath)
	if not attr then 
		return
	end

	local size = attr.size
	if size == 0 then 
		return
	end

	local ret, err = os.execute("lua /ugw/apps/database/dbinit.lua disk")
	if not (ret == true or ret == 0) then 
		log.fatal("dbinit fail %s", err or "")
	end

	return do_recover()
end

return {
	recover = recover,
}
