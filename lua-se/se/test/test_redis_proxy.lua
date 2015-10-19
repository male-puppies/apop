local se = require('se')
local redis = require('redis')
local cjson = require('cjson')
local bufio = require('bufio')

local redis_server_address = 'tcp://127.0.0.1:6379'
local command_server_address = 'tcp://0.0.0.0:12345'
local request_queue = {}

-- message format:
--    len\r\n
--    xxxxxxxxxxxxxxxxxx\r\n
local function recv_message(r)
	-- read cmd length
	local line, err = r:read_until('\r\n')
	if err then return nil, err end
	local len = tonumber(string.sub(line, 1, -3))
	if not len then return nil, err end

	-- read fix length data as cmd
	local cmd, err = r:read(len + 2)
	if err then return nil, err end
	if string.sub(cmd, -2) ~= '\r\n' then
		return nil, 'invalid message'
	end

	local jsonmsg = string.sub(cmd, 1, -3) -- trim '\r\n'
	return cjson.decode(jsonmsg)
end

local function send_message(r, msg)
	local jsonmsg = cjson.encode(msg)
	local data = string.format('%d\r\n%s\r\n', #jsonmsg, jsonmsg)
	return se.write(r.fd, data)
end

local function command_client(cli)
	local r = bufio.new_reader(cli)

	local notify = {}

	while not notify.err do
		local cmd, err = recv_message(r)
		if err then
			notify.err = err
			break
		end

		print('recv command:', cjson.encode(cmd))

		-- TODO: check array of string
		if type(cmd) ~= 'table' then
			notify.err = 'invalid message'
			break
		end

		local req = {
			notify = notify,
			cmd = cmd,
			cb = function(result)
				print('send result:', cjson.encode(result))
				-- send result
				local err = send_message(r, result)
				if err then
					notify.err = err
					err = se.shutdown(cli, 2) -- recv_message(r) will return err
					assert(not err, err)
				end
			end,
		}

		-- TODO: check if too many pending requests
		table.insert(request_queue, req)
	end

	-- TODO: log notify.err

	local err = se.close(cli)
	assert(not err, err)
end

local function command_server()
	local srv, err = se.listen(command_server_address)
	assert(not err, err)

	while true do
		local cli, err = se.accept(srv)
		if not err then
			se.go(command_client, cli)
		end
	end
end

local function redis_command_client()
	local r = redis.new(redis_server_address)

	local err = r:connect()
	assert(not err, err)

	while true do
		local req = table.remove(request_queue, 1)
		if not req then
			se.sleep(0.01) -- TODO
		elseif not req.notify.err then
			--print('redis call:', cjson.encode(req.cmd))
			local res, err = r:call(table.unpack(req.cmd))
			if err then
				-- TODO: reconnect redis
				assert(false)
			end
			if not req.notify.err then
				req.cb(res)
			end
		end
	end
end

local function command_execute(r, ...)
	local cmd = {...}

	local err = send_message(r, cmd)
	if err then return nil, err end

	return recv_message(r)
end

local function command_execute_test()
	local fd, err = se.connect(command_server_address)
	assert(not err, err)

	local r = bufio.new_reader(fd)

	while true do
		local res, err = command_execute(r, 'keys', '*')
		assert(not err, err)

		print('execute result:', cjson.encode(res))

		se.sleep(1)
	end

	local err = se.close(fd)
	assert(not err, err)
end

local function main()
	se.go(redis_command_client)
	se.go(command_server)
	se.go(command_execute_test)
end

se.run(main)