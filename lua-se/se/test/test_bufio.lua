local se = require("se")
local bufio = require("bufio")

function main()
	local fd, err = se.connect('tcp://127.0.0.1:9999')
	assert(not err, err)

	local r = bufio.new_reader(fd)

	local data, err = r:read_until('aa')
	assert(not err, err)
	print(data)

	local data, err = r:read_until('bb')
	assert(not err, err)
	print(data)

	local data, err = r:read_until('cc')
	assert(not err, err)
	print(data)

	local err = se.close(fd)
	assert(not err, err)
end

se.run(main)