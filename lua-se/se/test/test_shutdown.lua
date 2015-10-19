local se = require("se")

local tcp_addr = 'tcp://127.0.0.1:8888'
local exit = false

local function create_server()
	local srv, err = se.listen(tcp_addr)
	assert(not err, err)
	se.go(function()
		while not exit do
			local cli, err = se.accept(srv, 0.1)
			assert(not err or err == 'TIMEOUT', err)
			if err ~= 'TIMEOUT' then
				local cliaddr = se.getpeername(cli)
				print(string.format('client online, %s:%d', cliaddr.ip, cliaddr.port))
			end
		end
		local err = se.close(srv)
		assert(not err, err)
		print('server exit')
	end)
end

local function test_shutdown_read()
	local sock, err = se.connect(tcp_addr)
	assert(not err, err)
	se.go(function()
		local err = se.shutdown(sock, 0)
		assert(not err, err)
		print('shutdown(0) done')
	end)
	local data, err = se.read(sock, 0, 6)
	assert(err == 'EOF', err)
	local err = se.close(sock)
	assert(not err, err)
end

local function test_shutdown_write()
	local sock, err = se.connect(tcp_addr)
	assert(not err, err)
	se.go(function()
		local err = se.shutdown(sock, 1)
		assert(not err, err)
		print('shutdown(1) done')
	end)
	while true do
		local err = se.write(sock, '1')
		if err then
			print('write error:', err)
			break
		end
	end
	local err = se.close(sock)
	assert(not err, err)
end

local function main()
	create_server()

	test_shutdown_read()
	test_shutdown_write()

	exit = true
end

se.run(main)