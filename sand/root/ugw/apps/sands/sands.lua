local uv = require("luv") 
local sandutil = require("sandutil")
local parser = require("redis.parser")

local st_new = 0
local st_auth = 1

local tomap, toarr, checkarr = sandutil.tomap, sandutil.toarr, sandutil.checkarr

local function fatal(fmt, ...)
	io.stderr:write(string.format(fmt, ...))
	os.exit(-1)
end

local method = {}
local mt = {__index = method}
function method.start_server(ins, host, port)
	local server = uv.new_tcp() 
	uv.tcp_bind(server, host, port)
	local ret, err = uv.listen(server, 128, function(err)
		if err then 
			print("server error", err)
			return 
		end 

		local client = uv.new_tcp()
		uv.accept(server, client)
		ins:on_connection(client)
	end) 
	local _ = ret or fatal("server listen fail %s", err)

	-- 忽略sigpipe
	local sig = uv.new_signal()
	local ret, err = uv.signal_start(sig, "sigpipe", function(...)
		print("cache sigpipe", ...)
	end)
	local _ = ret or fatal("cache sigpipe fail %s", err)
end

function method.on_connection(ins, client)
	local fd = uv.fileno(client) 				assert(not ins.clientmap[fd])
	
	local ret, err = uv.read_start(client, function(err, data)
		if err or not data then
			return ins:close_client(fd, err or "close")
		end
		ins:on_client_data(fd, data) 
	end)

	local _ = ret or fatal("client read_start fail %s", err)

	-- keepalive timeout, just close the connection
	local timeout_cb = function()
		ins:close_client(fd, "timeout")
	end

	local timer, err = uv.new_timer() 	 	
	local _ = timer or fatal("new_timer fail %s", err)

	-- it has 30s before client sends the connect command 
	local ret, err = uv.timer_start(timer, 30 * 1000, 0, timeout_cb)
	local _ = ret or fatal("client read_start fail %s", err)

	ins.clientmap[fd] = {
		data = "", 
		param = nil,
		state = st_new,
		timer = timer,  			-- need free
		client = client,  			-- need free 
		timeout_cb = timeout_cb,
	}
end

function method.close_client(ins, fd, err)
	assert(err)
	
	local climap = ins.clientmap[fd] 	
	if not climap then 
		print(fd, "already close")
		return 
	end 
	
	-- uv.timer_stop(climap.timer)  	-- stop keepalive timer 
	uv.close(climap.timer) 			-- free timer  
	climap.timer = nil 

	uv.close(climap.client) 		-- free client 
	climap.client = nil
	ins.clientmap[fd] = nil 		-- fd has beed close and free, delete from client map

	local param = climap.param 		-- this param may be nil before connect command pass
	if not param then 
		print("close client", fd, err)
		return
	end 

	print("close client", param.cd, fd, err)
	for _, tp in ipairs(type(param.tp) == "table" and param.tp or {}) do 
		local tmap = ins.topic2client[tp] 	-- unregister topic map to this connection(fd)
		if tmap and tmap[fd] then 
			tmap[fd] = nil
		end
	end 

	ins.clientid2fd[param.cd] = nil 		-- unregister clientid to this connection(fd)
	if param.wt and #param.wt > 0 and param.wp and #param.wp then 
		ins:do_publish(param.wt, param.wp)	-- notify all clients who listen to will topic
	end
end 

-- function method.show_client(ins, msg)
-- 	print("----------------show client", msg)
-- 	for fd, climap in pairs(ins.clientmap) do 
-- 		print(fd, js.encode(climap.param))
-- 	end
-- end

-- function method.show_topic(ins, msg)
-- 	print("----------------show topic", msg)
-- 	for tp, fds in pairs(ins.topic2client) do 
-- 		local arr = {}
-- 		for k in pairs(fds) do table.insert(arr, k) end 
-- 		print("tp", tp, js.encode(arr))
-- 	end
-- end

function method.do_publish(ins, topic, payload) 
	local tmap = ins.topic2client[topic]
	if not tmap then 	
		return 						-- no subscriber
	end 

	local exist = false 
	for fd in pairs(tmap) do
		exist = true 
		break
	end 

	if not exist then 
		return  					-- no subscriber
	end 

	local s = parser.build_query(toarr({id = "pb", tp = topic, pl = payload}))
	for fd in pairs(tmap) do
		local climap = ins.clientmap[fd] 	assert(climap)		
		local ret, err = uv.write(climap.client, s)
		local _ = ret or ins:close_client(fd, err)  		-- close client if write fail
	end
end

local cmd_map = {}
local function publish_connack(client, st, msg)
	local s = parser.build_query(toarr({id = "ca", st = st, da = msg}))
	local ret, err = uv.write(client, s)
	if not ret then 
		return nil, err 
	end
	return true 
end

local function check_version(version)
	return true 
end

local function check_password(username, password)
	return true 
end

-- command connect
function cmd_map.cn(ins, fd, map)
	local climap = ins.clientmap[fd] 		assert(climap)
	if climap.state ~= st_new then 
		local err = "invalid state"
		publish_connack(climap.client, 1, err)
		return nil, err
	end
	
	climap.param = map
	local m = climap.param
	m.kp = tonumber(m.kp)
	if not (m.cd and #m.cd > 0 and m.vv and #m.vv > 0 and m.un and #m.un > 0 
		and m.pw and #m.pw > 0 and m.kp and m.kp >= 5 and m.tp and #m.tp > 0) then
		local err = "invalid param"
		publish_connack(climap.client, 1, err)
		return nil, err
	end

	if not check_version(m.vv) then  
		local err = "invalid version"
		publish_connack(climap.client, 1, err)
		return nil, err
	end 

	if not check_password(m.un, m.pw) then
		local err = "invalid authorization"
		publish_connack(climap.client, 1, err)
		return nil, err
	end

	local s, count, topics = map.tp .. "\t", 0, {}
	for part in s:gmatch("(.-)\t") do 
		if #part == 0 then
			count = 0
			break 
		end
		table.insert(topics, part)
		local tmap = ins.topic2client[part] or {}
		tmap[fd], count = 1, count + 1
		ins.topic2client[part] = tmap
	end

	if count == 0 then
		local err = "invalid topics"
		publish_connack(climap.client, 1, err)
		return nil, err
	end
	
	m.tp = topics
	if ins.clientid2fd[m.cd] then 
		local err = "already exist " .. m.cd
		publish_connack(climap.client, 1, err)
		return nil, err
	end

	
	ins.clientid2fd[m.cd] = fd 

 	-- notify clients who subscribe connect_topic
 	if m.ct and #m.ct > 0 and m.cp and #m.cp > 0 then 
 		ins:do_publish(m.ct, m.cp)
 	end

 	climap.state = st_auth
	return publish_connack(climap.client, 0, "ok")
end

-- command disconnect
function cmd_map.dc(ins, fd, map)
	ins:close_client(fd, "user disconnect")
	return nil, "disconnect" 
end

function cmd_map.pb(ins, fd, map)
	local climap = ins.clientmap[fd] 		assert(climap)
	if climap.state ~= st_auth then 
		return nil, "no auth yet"
	end 

	local topic, payload = map.tp, map.pl 
	if not (topic and payload) then 
		return nil, "invalid publish param"
	end

	ins:do_publish(topic, payload)
	return true
end

-- command ping
function cmd_map.pi(ins, fd, map)
	local climap = ins.clientmap[fd] 	assert(climap)
	if climap.state ~= st_auth then 
		return nil, "no auth yet"
	end 
	local s = parser.build_query(toarr({id = "po"}))
	uv.write(climap.client, s)
	return true 
end

function method.on_client_data(ins, fd, data)
	local climap = ins.clientmap[fd] 		assert(climap)
	climap.data = climap.data .. data

	while #climap.data > 0 do
		-- check whether a whole message is prepared. TODO may be proved
		local ret, p = parser.parse_ready(climap.data)
		if not ret then
			return p and ins:close_client(fd, p) 		-- parse error
		end 

		-- parse data 
		local arr = parser.parse_reply(climap.data)
		if not checkarr(arr) then 
			return ins:close_client(fd, "invalid data")
		end

		climap.data = climap.data:sub(p + 1) 			-- trim data had been parsed

		local climap = tomap(arr)
		local id = climap.id 							-- command id 
		if not id then 
			return ins:close_client(fd, "miss id")
		end 

		local func = cmd_map[id]
		if not func then 
			return ins:close_client(fd, "no " .. id)
		end

		local ret, err = func(ins, fd, climap)
		if not ret then
			return ins:close_client(fd, err)
		end 
	end

	local ret, err = uv.timer_stop(climap.timer)
	local _ = ret or fatal("client timer_stop fail %s", err)

	local ret, err = uv.timer_start(climap.timer, climap.param.kp * 2.1 * 1000, 0, climap.timeout_cb)
	local _ = ret or fatal("client read_start fail %s", err)
end

local function new()
	local obj = {
		clientmap = {},
		clientid2fd = {},
		topic2client = {},
	}	
	setmetatable(obj, mt)
	return obj
end

return {new = new}
--[[
local ins = new()
ins:start_server("0.0.0.0", 61234)

local timer, err = uv.new_timer() 	 
local countx = function(t)
	local c = 0
	for  k in pairs(t) do 
		c = c + 1 
	end 
	return c
end
local ret, err = uv.timer_start(timer, 2 * 1000, 5 * 1000, function()
	print(os.date(), countx(ins.clientmap), countx(ins.clientid2fd), countx(ins.topic2client))

end)

uv.run()
--]]