local se = require("se")
local log = require("log")
local encrypt = require("encrypt")
local sandutil = require("sandutil")
local parser = require("redis.parser")

local encode, decode, header = encrypt.encode, encrypt.decode, encrypt.header
local tomap, toarr, checkarr = sandutil.tomap, sandutil.toarr, sandutil.checkarr

local st_new, st_run, st_stop = "new", "run", "stop"
local function fatal(fmt, ...)
	io.stderr:write(string.format(fmt, ...))
	os.exit(-1)
end

local method = {}
local mt = {__index = method}

function method.set_auth(ins, username, password)
	ins.param.username, ins.param.password = username, password
end

function method.set_will(ins, topic, payload)
	ins.param.will_topic, ins.param.will_payload = topic, payload
end

function method.set_connect(ins, topic, payload)
	ins.param.connect_topic, ins.param.connect_payload = topic, payload
end

function method.pre_subscribe(ins, ...)
	ins.param.topics = {...}
end

function method.set_keepalive(ins, s)
	ins.param.keepalive = s
end

function method.set_extend(ins, s)
	ins.param.extend = s
end

function method.running(ins)
	return ins.state ~= st_stop
end

local function close_client(ins, err)
	print("close on error", err, ins.param.clientid)
	se.close(ins.client)
	ins.client, ins.state = nil, st_stop
	ins.on_disconnect(1, err)
end

function method.publish(ins, topic, payload)
	assert(ins and topic and payload)
	if not ins:running() then
		return false
	end

	local pl_str, err = encode(ins.encode_type, payload) 	assert(not err, err)
	local tpmap = {id = "pt", tp = topic, pl = #pl_str}
	local tp_str, err = encode(ins.encode_type, parser.build_query(toarr(tpmap))) 	assert(not err, err)

	for _, s in ipairs({tp_str, pl_str}) do
		local err = se.write(ins.client, s)
		if err then
			close_client(ins, err)
			return false
		end
	end

	return true
end

function method.disconnect(ins)
	if ins.state ~= st_run then
		return
	end

	local s = parser.build_query(toarr({id = "dc"}))
	local s1, err = encode(ins.encode_type, s) 		assert(not err, err)
	se.write(ins.client, s1)
	se.close(ins.client)
	ins.client = nil
	ins.state = st_stop
	ins.on_disconnect(0, "close by user")
end

function method.connect(ins, host, port)
	local addr = string.format("tcp://%s:%s", host, port)
	local cli, err = se.connect(addr)
	if not cli then
		return nil, err
	end

	local m = ins.param
	if not (m.clientid and #m.clientid > 0 and m.username and #m.username > 0 and m.password and #m.password > 0
		and m.version and #m.version > 0 and m.keepalive and m.keepalive >= 5 and #m.topics > 0) then
		return nil, "invalid param"
	end

	local _ = (m.will_topic or m.will_payload) and assert(#m.will_topic > 0 and #m.will_payload > 0)
	local _ = (m.connect_topic or m.connect_payload) and assert(#m.connect_topic > 0 and #m.connect_payload > 0)

	local map = {
		id = "cn",
		cd = m.clientid,
		vv = m.version,
		un = m.username,
		pw = m.password,
		kp = m.keepalive,
		tp = table.concat(m.topics, "\t"),
		ct = m.connect_topic,
		cp = m.connect_payload,
		wt = m.will_topic,
		wp = m.will_payload,
		ex = m.extend,
	}

	local s = parser.build_query(toarr(map))
	local s1 = encode(ins.encode_type, s)
	local err = se.write(cli, s1)
	if err then
		se.close(cli)
		ins.state = st_stop
		return nil, err
	end

	ins.client = cli
	ins.state = st_run
	return true
end

function method.set_callback(ins, name, cb)
	assert(ins[name])
	ins[name] = cb
end

function method.set_encode_type(ins, tp)
	ins.encode_type = tp
end

local function timeout_ping(ins)
	local last_active = se.time()
	local s = parser.build_query(toarr({id = "pi"}))
	local keepalive = ins.param.keepalive
	while ins:running() do
		while ins:running() do
			local now = se.time()

			-- send ping every $keepalive seconds
			if now - last_active >= keepalive then
				break
			end

			local d = now - ins.active
			local _ = d > keepalive + 30 and log.info("diff %s %s", d, ins.param.clientid)
			-- if d >= keepalive * 3.2 then
			-- 	return close_client(ins, string.format("timeout %s %s", d, keepalive * 2.2))
			-- end

			se.sleep(3)
		end

		local now = se.time()
		last_active, ins.ping_start = now, now
		if not ins:running() then
			log.error("sandc not running")
			break
		end

		-- send ping
		local s1, err = encode(ins.encode_type, s) 		assert(not err, err)
		local err = se.write(ins.client, s1)
		if err then
			return close_client(ins, err)
		end
	end
end

local cmd_map = {}
function cmd_map.pb(ins, map)
	ins.on_message(map.tp, map.pl)
	return true
end

function cmd_map.ca(ins, map)
	if not (map.st and tonumber(map.st) == 0 and map.da) then
		return nil, map.data or "undefined"
	end
	ins.on_connect()
	return true
end

function cmd_map.po(ins, map)
	local d = se.time() - ins.ping_start
	local _ = d > 5 and log.info("pong %s %s", ins.param.clientid, d)
	return true
end

function cmd_map.pt(ins, map)
	if not (map and map.tp and map.pl) then
		return nil, "invalid pt"
	end
	local pbcache = ins.pbcache
	if pbcache then
		return nil, "why exists pbcache " .. pbcache.topic
	end
	ins.pbcache = {topic = map.tp, paylen = tonumber(map.pl)}
	return true
end

function cmd_map.pp(ins, data)
	local payload, err = decode(data)
	if not payload then
		local len, tp = header(data)
		log.error("--%s %s %s %s %s", err, #data, len, tp, data)
		return nil, err
	end

	local topic = ins.pbcache.topic
	ins.pbcache = nil
	ins.on_message(topic, payload)
	return true
end

function method.dispatch(ins, map)
	local id = map.id
	if not id then
		return true
	end

	local func = cmd_map[id]
	if not func then
		print("no " .. id)
		return true
	end

	return func(ins, map)
end

function method.get_payload(ins)
	local data = ins.data
	local datalen = #data
	local pbcache = ins.pbcache 			assert(pbcache.topic and pbcache.paylen)
	local paylen = pbcache.paylen
	if datalen < paylen then
		return nil, "lack"
	end
	local payload = data:sub(1, paylen)
	ins.data = data:sub(paylen + 1)
	return cmd_map["pp"](ins, payload)
end

function method.parse_normal(ins)
	local data = ins.data
	if #data < 4 then
		return nil, "lack"
	end

	local len, ntp = header(data)
	if len > #data then
		return nil, "lack"
	end

	local es = data:sub(1, len)
	ins.data = data:sub(len + 1)

	local ds, err = encrypt.decode(es)
	if not ds then
		log.error("--%s %s %s %s %s", err, #es, len, ntp, es)
		return nil, err
	end

	-- parse data
	local arr = parser.parse_reply(ds)
	if not checkarr(arr) then
		return nil, "data error"
	end

	-- trim data parsed
	local ret, err = ins:dispatch(tomap(arr))
	if not ret then
		return nil, err
	end

	local _ = (ntp == ins.encode_type) or ins.on_encode_type(ntp, ins.encode_type)

	return true
end

local function run_internal(ins)
	local on_recv = function()
		while #ins.data > 0 do
			if ins.pbcache then
				local ret, err = ins:get_payload()
				if not ret then
					if err == "lack" then
						print("get_payload", "lack", #ins.data)
						return
					end
					return nil, err
				end
			else
				local ret, err = ins:parse_normal()
				if not ret then
					if err == "lack" then
						print("parse_normal", "lack", #ins.data)
						return
					end
					return nil, err
				end
			end
		end

		return true
	end

	while ins:running() do
		local data, rerr = se.read(ins.client, 8192, 0.01)
		if data then
			local now = se.time()
			ins.active = now 				-- recv data, update active time
			ins.data = ins.data .. data 	-- cache data

			local ret, err = on_recv() 		-- process data
			if err then
				close_client(ins, err)
				break
			end
		end

		-- check recv error
		if rerr and rerr ~= "TIMEOUT" then
			close_client(ins, rerr)
			break
		end
	end
end

function method.run(ins)
	se.go(timeout_ping, ins) 			-- ping routine
	se.go(run_internal, ins)
end

local function numb() end
local function new(clientid)
	assert(clientid)
	local obj = {
		param = {
			clientid = clientid,
			username = "",
			password = "",
			version = "v0.1",
			keepalive = 60,
			topics = {},
			connect_topic = nil,
			connect_payload = nil,
			will_topic = nil,
			will_payload = nil,
			extend = nil,
		},

		client = nil,

		data = "",
		state = st_new,
		active = se.time(),
		ping_start = 0,

		encode_type = 2,
		pbcache = nil,

		on_message = numb,
		on_connect = numb,
		on_disconnect = numb,
		on_encode_type = numb,
	}

	setmetatable(obj, mt)
	return obj
end

return {new = new}
