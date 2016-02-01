local log = require("log") 
local js = require("cjson.safe") 
local common = require("common")

local rds, pcli 
local read = common.read

local function acchknew(conn, group, data)
	local new_version = "/tmp/memfile/new_version.txt"
	local version = read(new_version) or ""
	return {status = 0, data = version}
end

local function acupgrade(conn, group, data)
	local ret = os.execute("ps | grep online_upgrade.sh | grep -v grep")
	if ret == 0 or ret == true then 
		return {status = 0, data = "upgrading now!"}
	end
	os.execute("/ugw/apps/chkfirmware/online_upgrade.sh &") 
	return {status = 0, data = "upgrading on backgroup, please wait!"}
end

return {acupgrade = acupgrade, acchknew = acchknew}

