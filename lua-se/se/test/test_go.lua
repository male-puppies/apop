local se = require("se")
local go = se.go
local sleep = se.sleep

local function test3()
	print('test3')
end

local function test2()
	print('test2-1')
	go(test3)
	print('test2-2')
end

local function test1()
	print('test1-1')
	go(test2)
	print('test1-2')
end

local function test0()
	print('test0-1')
	go(test1)
	print(coroutine.yield('a','b','c'))
	print('test0-2')
end

se.run(test0)