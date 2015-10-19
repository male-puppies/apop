local se = require('se')
local redis = require('redis')
local cjson = require('cjson')

local redis_server_address = "tcp://192.168.0.212:6379"

local redis_client_options = {
	connect_timeout = 300,
	read_timeout = 30,
	write_timeout = 6,
}

local total_clients = 25000
local online_clients = 0

function test_lpush()
	local r = redis.new(redis_server_address, redis_client_options)

	local err = r:connect()
	assert(not err, err)

	math.randomseed(se.time())

	while true do
		local id = math.random(total_clients)
		local res, err = r:call('rpush', 'list-'..id, se.time())
		if err == 'TIMEOUT' then
			print('lpush timeout')
		else
			assert(not err, err)
			assert(type(res) == 'number')
		end
		se.sleep(0.01)
	end
end

function test_blpop(id)
	local r = redis.new(redis_server_address, redis_client_options)

	local err = r:connect()
	assert(not err, err)

	online_clients = online_clients + 1

	local key = 'list-'..id

	while true do
		local res, err = r:call('blpop', key, 1)
		if err == 'TIMEOUT' then
			print('redis call timeout')
			break
		end
		assert(not err, err)
		if res then
			assert(res[1] == key)
			if res[2] == 'quit' then break end
			local delay = se.time() - res[2]
			print(id, delay, cjson.encode(res))
		end
	end

	r:close()

	online_clients = online_clients - 1
end

local function show_stats()
	while true do
		print(string.format('[%f] total clients: %d', se.time(), online_clients))
		se.sleep(1)
	end
end

local function main()
	se.go(function()
		for i = 1, total_clients do
			se.go(test_blpop, i)
		end
	end)

	se.go(test_lpush)

	se.go(show_stats)
end

se.run(main)