local encrypt = require("encrypt")
local common = require("common")
local read = common.read
local save = common.save
local s = read("wlan_info.json")

local function test0()
	print(#s)
	local s1, err = encrypt.encode(0, s)
	local l, t = encrypt.header(s1)
	print(l, t)
	local s2, err = encrypt.decode(s1)
	print(s2, err)
end

local function test_err()
	local s, err = encrypt.encode(2, s)
	print(s, err)
	local s, err = encrypt.encode(2, "")
	print(s, err)
	local s, err = encrypt.decode("")
	print(s, err)
	local s, err = encrypt.decode("12324")
	print(s, err)
end

local function test1()
	local s1, err = encrypt.encode(1, s)
	print("----", #s1)
	save("/tmp/xx.txt", s1)
	local l, t = encrypt.header(s1)
	print(l, t)
	local s2, err = encrypt.decode(s1)
	print(s2, err)
end

local function test2()
	local s1, err = encrypt.encode(3, s)
	print(#s, #s1, err)
	save("/tmp/xx.txt", s1)
	local s2, err = encrypt.decode(s1)
	print(s2, err)
end

-- test_err()
-- test0()
-- test1()
-- test2()
local wait_time = 1
local max = 8096
local se = require("se")

local function read_until_eof(cli)
	local data = ""
	while true do
		local s2, err = se.read(cli, max, 0.1)
		if s2 then
			data = data .. s2
		end
		if err ~= "TIMEOUT" and err ~= "EOF" then
			se.close(cli)
			return
		end
		if err == "EOF" then
			se.close(cli)
			return data
		end
	end
end

local function remote0(cli)
	local cli, err = se.connect("tcp://192.168.0.213:60000")  assert(not err, err)
	local s1, err = encrypt.encode(0, s)
	local l, t = encrypt.header(s1)				assert(l == #s1 and l == #s + 4)
	local err = se.write(cli, s1)				assert(not err, err)
	print("encode len", #s1)
	local ss1, err = encrypt.decode(s1)			assert(not err, err)

	local s2 = read_until_eof(cli)
	if s2 then
		local len, tp = encrypt.header(s2)
		print(len, tp, "------")
		local s3, err = encrypt.decode(s2) 		assert(not err, err)
		assert(#s == #s3 and s == s3)
	end
end

local function remote1(cli)
	local cli, err = se.connect("tcp://192.168.0.213:60000")  assert(not err, err)
	local s1, err = encrypt.encode(1, s)
	local l, t = encrypt.header(s1)				assert(l == #s1 and l == #s + 4)
	local err = se.write(cli, s1)				assert(not err, err)
	print("encode len", #s1)
	local ss1, err = encrypt.decode(s1)			assert(not err, err)

	local s2 = read_until_eof(cli)
	if s2 then
		local len, tp = encrypt.header(s2)
		local s3, err = encrypt.decode(s2) 		assert(not err, err)
		assert(#s == #s3 and s == s3)
	end
end

local function remote2(cli)
	local cli, err = se.connect("tcp://192.168.0.213:60000")  assert(not err, err)
	local s1, err = encrypt.encode(2, s)
	local l, t = encrypt.header(s1)
	local ss1, err = encrypt.decode(s1)			assert(not err, err)
	print("encode len", #s1)
	local err = se.write(cli, s1)				assert(not err, err)

	local s2 = read_until_eof(cli)
	if s2 then
		local len, tp = encrypt.header(s2)
		local s3, err = encrypt.decode(s2) 		assert(not err, err)
		assert(#s == #s3 and s == s3)
	end
end

local function main()
	print("data len", #s)

	local ori = s
	while true do
		local n = math.random(1, 200)
		s = ori:rep(n)
		local m = math.random(1, #ori)
		s = s .. ori:sub(1, m)
		if max < #s then
			max = #s + 16
			print("reset max to ", max, n, m)
		end
		print("test ", 0, #s)
		remote0(cli)
		print("test ", 1, #s)
		remote1(cli)
		print("test ", 2, #s)
		remote2(cli)
	end
end

se.run(main)
