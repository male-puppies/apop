local se = require("se")

local tcp_addr = 'tcp://127.0.0.1:8888'
local exit = false

local function test_tcp_server_handle_client(cli)
	local cliaddr = se.getpeername(cli)
	local srvaddr = se.getsockname(cli)
	print(string.format('client online, %s:%d => %s:%d',
						cliaddr.ip, cliaddr.port, srvaddr.ip, srvaddr.port))
	local datalist = {}
	se.go(function()
		while cli do
			local data = table.remove(datalist, 1)
			if not data then
				se.sleep(0.2)
			else
				local err = se.write(cli, data)
				if err then
					if cli then
						se.close(cli)
						cli = nil
					end
					break
				end
			end
		end
	end)
	local total_read = 0
	while cli do
		local data, err = se.read(cli, -1048576, 10)
		if err then
			print(string.format('client offline with err: %s, %s:%d => %s:%d',
								err, cliaddr.ip, cliaddr.port, srvaddr.ip, srvaddr.port))
			break
		end
		if data == 'quit\r\n' then
			exit = true
			break
		end
		total_read = total_read + #data
		print(string.format('total read from client@[%s:%d]: %d', cliaddr.ip, cliaddr.port, total_read))
		table.insert(datalist, data)
	end
	if cli then
		se.close(cli)
		cli = nil
	end
end

local function test_tcp_server()
	local srv, err = se.listen(tcp_addr)
	assert(not err, err)
	while not exit do
		local cli, err = se.accept(srv, 1)
		if err ~= 'TIMEOUT' then
			assert(not err, err)
			se.go(test_tcp_server_handle_client, cli)
		end
	end
	local err = se.close(srv)
	assert(not err, err)
	print('tcp server exit')
end

local function test_tcp_client(id)
	local sock, err = se.connect(tcp_addr)
	assert(not err, err)
	for i = 1, 100 do
		local err = se.write(sock, string.format('hello-%d from client[%d]', i, id))
		assert(not err, err)
		local data, err = se.read(sock)
		assert(not err, err)
		print('client read from server:', data)
		se.sleep(0.1)
	end
	local err = se.close(sock)
	assert(not err, err)
end

local function test_timeout()
	local str = 'hello'
	local dup = 1e6
	local sock, err = se.connect("tcp://8.8.8.8:80", 1)
	assert(err == 'TIMEOUT', err)
	local sock, err = se.connect(tcp_addr)
	assert(not err, err)
	local data, err = se.read(sock, 100, 1)
	assert(err == 'TIMEOUT')
	local err, nwrite = se.write(sock, string.rep(str, dup), 30)
	if err then
		print(string.format("write error: %s, nwrite: %d", err, nwrite))
	else
		local data, err = se.read(sock, #str * dup)
		assert(not err, err)
		print('total read:', #data)
		assert(data == string.rep(str, dup))
	end
	local err = se.close(sock)
	assert(not err, err)
	print('test_timeout exit')
end

local function test()
	se.go(test_tcp_server)
----[[
	se.go(function()
		for id = 1, 200 do
			se.go(test_tcp_client, id)
		end
	end)
--]]
----[[
	se.go(function()
		for i = 1, 5 do
			test_timeout()
			se.sleep(1)
		end
	end)
--]]
----[[
	se.go(function()
		while not exit do
			collectgarbage('collect')
			k = collectgarbage('count')
			print(string.format('[%f] lua used memory: %f KB', se.time(), k))
			se.sleep(1)
		end
	end)
--]]
end

se.run(test)