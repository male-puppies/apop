local se = require("se")
local js = require("cjson.safe")

local step, maxtries = 0.01, 100
local client_method = {}
local client_mt = {__index = client_method}

function client_method:reply_close(map)
	local s = js.encode(map)
	local data = #s .. "\r\n" .. s
	se.write(self.cli, data)
	se.close(self.cli)
end

function client_method:readlen()
	local buff, maxlen = "", 9
	local left = maxlen
	for i = 1, maxtries do
		local s, err = se.read(self.cli, left, step)
		if err and err ~= "TIMEOUT" then
			return nil, err
		end
		local _ = err and print("read len timeout")
		if s then
			buff, left = buff .. s, left - #s 	assert(left >= 0)
			local s, e = buff:find("\r\n")
			if s then
				return buff:sub(1, s), buff:sub(e + 1)
			end
		end
	end

	return nil, "TIMEOUT"
end

function client_method:readdata(expect, buff)
	local left = expect - #buff
	for i = 1, maxtries do
		local s, err = se.read(self.cli, left, step)
		if err and err ~= "TIMEOUT" then
			return nil, err
		end
		local _ = err and print("read data timeout")
		if s then
			buff, left = buff .. s, left - #s 	assert(left >= 0)
			if left == 0 then
				return buff
			end
		end
	end
end

function client_method:handle()
	local len, data = self:readlen() 	print(len, data)
	if not len then
		return self:reply_close({status = 1, data = data})
	end

	local data, err = self:readdata(len, data) 	print(data, err)
	if not data then
		return self:reply_close({status = 1, data = err})
	end

	self:reply_close(self.cb(data))
end

function client_method:run()
	se.go(self.handle, self)
end

local function new_client(cli, cb)
	local obj = {cli = cli, cb = cb}
	setmetatable(obj, client_mt)
	return obj
end

return {new =  new_client}
