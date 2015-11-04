package.cpath = "./?.so;" .. package.cpath
local se = require("se")
local mon = require("mongoose")
local go, sleep = se.go, se.sleep
local conn_map = {}

local function dispather(conn, ev)
	if ev == 0 then		-- poll
		return 
	end

	local addr = conn:addr()
	if ev == 5 then  	-- close
		conn_map[addr] = nil
		return
	end

	if ev == 100 then 	-- http request
		local hm = conn:http_message()
		local uri = hm:uri()
		if not uri:find("/c.", 1, true) then
			return conn:serve_http()
		end

		-- hm:body_var hm:query_var hm:http_header 
		go(function()
			sleep(5)
			conn:send('{"a":1}')
			conn:send_close()
			conn_map[addr] = nil
		end)
		
		return
	end
end


local function main()
	local serv = mon.create_server("www/webui", "8000", dispather)
	while true do
		serv:poll(10)
		se.sleep(0.001)
	end
end

se.run(main)
