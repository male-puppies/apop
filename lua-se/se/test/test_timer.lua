local se = require("se")
local go = se.go
local sleep = se.sleep

local function test()
	for n = 1,3 do
		go(function()
			for i = 1,2 do
				print(string.format('timer[%d]: %d', n, i))
				sleep(1)
			end
		end)
	end
end

se.run(test)