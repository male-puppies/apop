local se = require("se")

local function main( ... )
	local serv = se.listen("tcp://0.0.0.0:12365")
	while true do 
		local cli = se.accept(serv)
		if cli then 
			local data, err = se.read(cli, 16, 0.1)
			
			print(data, err)
			se.write(cli, os.date())
			se.close(cli)
		end
	end
end
se.run(main)