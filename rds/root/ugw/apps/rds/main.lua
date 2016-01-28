require("global")
local se = require("se")
local sms = require("sms")
local log = require("log")
local lfs = require("lfs")
local auth = require("auth")
local user = require("user") 
local radio = require("radio")
local aplog = require("aplog")
local wxshop = require("wxshop")
local flow = require("flowctrl")
local struct = require("struct")
local mredis = require("mredis") 
local js = require("cjson.safe")
local wlan = require("wlanssid")
local const = require("constant")
local aps = require("apmlistaps") 
local upgrade = require("upgrade")
local request = require("request")
local collect = require("collect")
local account = require("account")
local glbcfg = require("globalcfg")
local load = require("loadbalance") 
local upaps = require("apmupdateaps")
local cfgclient = require("cfgclient")
local optimal = require("optimization")
local firelist = require("apmfirewarelist")

local pcli
local tcp_addr = "tcp://127.0.0.1:9998"
local rds_addr = "tcp://127.0.0.1:6379"

local cmd_func = {
	ApmListAPs			= aps.apmlistaps,
	ApmDeleteAps		= upaps.apmdeleteaps,
	ApmUpdateAps		= upaps.apmupdateaps,
	ApmFirewareList		= firelist.apmfirewarelist,
	ApmUpdateFireware	= firelist.apmupdatefireware, 
	ApmFWDownload 		= firelist.apmfwdownload,
	WLANList			= wlan.wlanlist,
	WLANAdd				= wlan.wlanadd,
	WLANDelete			= wlan.wlandelete,
	WLANModify			= wlan.wlanmodify,
	WLANListAps			= wlan.wlanlistaps,
	RadioList			= radio.radiolist,
	NWLAN				= radio.nwlan,
	WLANState			= radio.wlanstate, 
	ApmListUsers		= user.apmlistusers,
	GetHideColumns		= glbcfg.get_hide_columns,
	DtHideColumns		= glbcfg.hide_columns,
 	GetBandSupport		= glbcfg.get_band_support,
	SetCountry			= glbcfg.set_country,
	GetApLog			= aplog.getaplog,
 	DownloadApLog		= aplog.downloadaplog,
	ApmExecCommands		= glbcfg.execute_cmd,
 	OnlineAplist		= glbcfg.online_ap_list,
	GetLoadBalance		= load.load_balance,
	SaveLoadBalance		= load.save_load_balance,
	GetOptimization		= optimal.optimization,
	SaveOptimization	= optimal.save_optimization,
	DebugSwitch			= glbcfg.set_debug,
	LedctrlSwitch		= glbcfg.set_ledctrl,
 	UserImport			= auth.userimport,
	UserAdd				= auth.useradd,
	UserDel				= auth.userdel,
	UserSet				= auth.userset,
	UserGet				= auth.userget,
	PolicyAdd			= auth.policyadd,
	PolicyDel			= auth.policydel,
	PolicySet			= auth.policyset,
	PolicyAdj			= auth.policyadj,
	PolicyGet			= auth.policyget,
	OnlineDel			= auth.onlinedel,
	OnlineGet			= auth.onlineget,
	SetGlobal			= flow.setglobal,
	GetFlow				= flow.getflow,
	InsRules			= flow.insrules,
	UpdateRules			= flow.updaterules,
	DeleteRules			= flow.deleterules,
	ACUpgrade			= upgrade.acupgrade,
	ACChkNew			= upgrade.acchknew,

	AccountList 	= 	account.accountlist,
	AccountSet 		= 	account.accountset,
	WxShopList 		= 	wxshop.wxshoplist,
	WxShopSet 		=	wxshop.wxshopset,
	SmsList 		=	sms.smslist,
	SmsSet 			= 	sms.smsset,
}

local function init_rds()
	mredis.connect_blpop(rds_addr):go()
	mredis.connect_normal(rds_addr):go() 
end

local function dispatcher(data)
	local nrds = mredis.normal_rds() 
	local result
	
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
		collect.update(nrds, group)
		result = func({rds = nrds, pcli = pcli},  group, data) or {status = 1, data = "error"}
	end	

	-- TODO
	return result
end

local function main()
	log.debug("start rds web ...")

	local unique = "a/local/rds"
	pcli = cfgclient.new({clientid = unique, topic = unique, port = 61883}) 	assert(pcli)
	pcli:run()

	init_rds()

	local serv, err = se.listen(tcp_addr) 
	
	local _ = serv or log.fatal("listen %s fail %s", tcp_addr, err)
	while true do
		local cli = se.accept(serv)
		local _ = cli and request.new(cli, dispatcher):run() 
	end
end

local function check_debug()
	while true do  
		log.setdebug(lfs.attributes("/tmp/wac_debug") and true or false) 
		se.sleep(3)
	end
end

log.setmodule("cgi")
se.go(check_debug)
se.go(collect.start)
se.run(main)
