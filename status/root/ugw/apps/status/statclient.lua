local se = require("se") 
local sandc = require("sandc")
local js = require("cjson.safe")

local method = {}
local mt = {__index = method}

local function wait_response(response_map, seq, timeout)
	local st = se.time()
	while true do
		se.sleep(0.005)
		local res = response_map[seq]
		if res ~= nil then
			response_map[seq] = nil
			return res
		end

		if se.time() - st > timeout then
			return nil, "timeout"
		end
	end
end

function method:request_common(topic, payload)
	local nseq
	nseq, self.seq = self.seq, self.seq + 1

	local map = {seq = nseq, mod = self.subtopic, pld = payload}
	self.seq_map[nseq] = 1, self.mqtt:publish(topic, js.encode(map)) 
	return wait_response(self.response_map, nseq, 3) 
end

function method:query(group, karr)
	return self:request_common("a/ac/cfgmgr/query", {group = group, karr = karr})
end

function method:publish(topic, payload)
	self.mqtt:publish(topic, payload)
end

function method:next()
	if #self.notify_arr == 0 then 
		return
	end 
	return table.remove(self.notify_arr, 1)
end

local function error_exit(fmt, ...)
	local _ = io.stderr:write(string.format(fmt, ...), "\n"), os.exit(-1)
end

local function start()
	local unique = "a/ac/report"
	local mqtt = sandc.new(unique)
	mqtt:set_auth("ewrdcv34!@@@zvdasfFD*s34!@@@fadefsasfvadsfewa123$", "1fff89167~!223423@$$%^^&&&*&*}{}|/.,/.,.,<>?")
	mqtt:pre_subscribe(unique)

	local seq_map, response_map, notify_arr = {}, {}, {}
	mqtt:set_callback("on_message", function(topic, payload)
		local map = js.decode(payload)
		if not (map and map.pld) then 
			return 
		end

		if map.seq then 
			if seq_map[map.seq] then
				response_map[map.seq], seq_map[map.seq] = map.pld, nil
			end
			return
		end 

		table.insert(notify_arr, map.pld)
	end)

	mqtt:set_callback("on_disconnect", function(st, err) error_exit("disconnect %s %s", st, err) end)

	local host, port = "127.0.0.1", 61886
	local ret, err = mqtt:connect(host, port)
	local _ = ret or error_exit("connect fail %s", err)

	print("connect ok", host, port)

	mqtt:run()

	local obj = {mqtt = mqtt, seq = 0, subtopic = unique, seq_map = seq_map, response_map = response_map, notify_arr = notify_arr}
	setmetatable(obj, mt)

	return obj
end

return {start = start}