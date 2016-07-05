-- require("global")
-- define("luci")
package.cpath = "/ugw/apps/uci/?.so;" .. package.cpath
local se = require("se")
local log = require("log") 
local js = require("cjson.safe")
local request = require("request")
local uci = require("muci")
local system = require("system")
local status = require("status")
local network = require("network")

local pcli
-- local is_ac
local tcp_addr = "tcp://127.0.0.1:9988"
-- local rds_addr = "tcp://127.0.0.1:6379"

local cmd_func = {
	GetStatus		= status.getstatus,
	GetEthStatus	= status.getethstatus,
	GetDhcpLease	= status.getdhcplease,
	GetRoutes		= status.getroutes,
	GetSyslog		= status.getsyslog,
	GetWanconfig	= network.getwanconfig,
	SetWanconfig	= network.setwanconfig,
	GetLanconfig	= network.getlanconfig,
	SetLanconfig	= network.setlanconfig,
	GetStaroutes	= network.getstaroutes,
	GetInterface	= network.getinterface,
	AddRoutes		= network.addroutes,
	UpdateRoutes	= network.updateroutes,
	DeleteRoutes	= network.deleteroutes,
	DiagPing		= network.diagping,
	DiagTraceroute	= network.diagtraceroute,
	DiagNslookup	= network.diagnslookup,
	GetFirewall		= network.getfirewall,
	AddFirewall		= network.addfirewall,
	SetFirewall		= network.setfirewall,
	DeleteFirewall	= network.deletefirewall,
	-- GetDhcpconfig	= network.getdhcpconfig,
	-- SetDhcpconfig	= network.setdhcpconfig,
	GetMwan			= network.getmwan,
	SetMwan			= network.setmwan,
	Login			= system.login,
	UpdateLoginTime	= system.updatelogintime,
	SetPassword		= system.setpassword,
	GetSystem		= system.getsystem,
	SetSystem		= system.setsystem,
	SyncTimes		= system.synctimes,
	DownloadBackup	= system.downloadbackup,
	UploadBackup	= system.uploadbackup,
	ConfReset		= system.confreset,
	UploadBrush		= system.uploadbrush,
	SysReboot		= system.sysreboot,
}

-- local function init_rds()
	-- mredis.connect_blpop(rds_addr):go()
	-- mredis.connect_normal(rds_addr):go() 
-- end

local function dispatcher(data)
	local result
	-- print(os.date(), "start" ,data)
	local t = js.decode(data)
	if not (t and t.key) then 
		result = {status = 1, data = "error cmd"}
		log.error("%s", js.encode(result))
		return result
	end
	
	local cmd = t.key
	local func = cmd_func[cmd]
	
	if not func then
		result = {status = 1, data = "invalid cmd " .. cmd}
		log.error("error cmd %s", js.encode(result))
		return result
	else 
		local group, data = t.group, t.data		assert(group, data)
		result = func(group, data) or {status = 1, data = "error"}
		-- result = func({rds = nrds, pcli = pcli},  group, data) or {status = 1, data = "error"}
	end	
	
	-- print(os.date(), "end" ,data)

	-- TODO
	return result
end

local function main()
	log.debug("start uci web ...")
	-- check_ac()

	-- local unique = "a/local/rds"
	-- pcli = cfgclient.new({clientid = unique, topic = unique, port = 61883}) 	assert(pcli)
	-- pcli:run()

	-- init_rds()

	local serv, err = se.listen(tcp_addr) 
	
	local _ = serv or log.fatal("listen %s fail %s", tcp_addr, err)
	while true do
		local cli = se.accept(serv)
		local _ = cli and request.new(cli, dispatcher):run() 
	end
end

-- local function check_debug()
-- 	while true do  
-- 		log.setdebug(lfs.attributes("/tmp/wac_debug") and true or false) 
-- 		se.sleep(3)
-- 	end
-- end

log.setmodule("uci")
-- se.go(check_debug)
-- se.go(collect.start)
se.run(main)