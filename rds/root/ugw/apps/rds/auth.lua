local log = require("log") 
local lfs = require("lfs")
local js = require("cjson.safe")

local rds, pcli

local ip_pattern = "^[0-9]+%.[0-9]+%.[0-9]+%.[0-9]+$"
local mac_part = "[0-9a-z][0-9a-z]"
local mac_pattern = string.format("^%s:%s:%s:%s:%s:%s$", mac_part, mac_part, mac_part, mac_part, mac_part, mac_part)	

local function errmsg(msg)
	return {status = 1, data = msg}
end

local function get_status(s, d)
	return {status = s, data = d or ""}
end

local function check_user(map) 
	local name, pwd, desc, enable, multi, bind, maclist = map.name, map.pwd, map.desc, map.enable, map.multi, map.bind, map.maclist
	local expire, remain = map.expire, map.remain 

	if not (name and #name >= 1 and #name <= 32) then 
		return nil, "名字格式错误！"
	end 

	if not (pwd and #pwd >= 4 and #pwd <= 32) then 
		return nil, "密码格式错误！"
	end

	if not (desc and #desc < 32) then 
		return nil, "描述格式错误！"
	end 

	if not (enable and (enable == 0 or enable == 1)) then 
		return nil, "参数错误，请尝试刷新！"
	end

	if not (multi and (multi == 0 or multi == 1)) then 
		return nil, "参数错误，请尝试刷新！"
	end

	if not (bind and (bind == "mac" or bind == "none")) then 
		return nil, "参数错误，请尝试刷新！"
	end

	if not (maclist and type(maclist) == "table") then 
		return nil, "MAC格式错误！"
	end 

	for _, mac in ipairs(maclist) do  
		if not (mac and mac:find(mac_pattern)) then 
			return nil, "MAC格式错误！"
		end
	end

	if not (expire and (expire[1] == 0 or expire[1] == 1)) then 
		return nil, "参数错误，请尝试刷新！"
	end

	if not (expire and expire[2]:find("%d%d%d%d%d%d%d%d %d%d%d%d%d%d")) then 
		return nil, "过期时间格式错误！"
	end 

	if not (remain and (remain[1] == 0 or remain[1] == 1)) then 
		return nil, "参数错误，请尝试刷新！"
	end

	if not (remain and remain[2] >= 0) then 
		return nil, "剩余时间格式错误！"
	end

	return true
end

local function useradd(conn, group, map)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	local ret, err = check_user(map)
	if not ret then 
		return get_status(1, err) 
	end

	return pcli:query_auth({cmd = "user_add", data = {group = group, data = {map}}}) or get_status(1, "error")  
end 

local function userdel(conn, group, arr)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	for _, name in ipairs(arr) do 
		if not (#name >= 1 and #name <= 32) then 
			return get_status(1, "无效的账号！")  
		end 
	end 
	return pcli:query_auth({cmd = "user_del", data = {group = group, data = arr}}) or get_status(1, "error") 
end 

local function userset(conn, group, map)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)

	local ret, err = check_user(map)
	if not ret then 
		return get_status(1, err) 
	end

	return pcli:query_auth({cmd = "user_set", data = {group = group, data = {[map.name] = map}}}) or get_status(1, "error")  
end 

local function userget(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	return pcli:query_auth({cmd = "user_get", data = {group = group, data = data}}) or get_status(0, {}) 
end

local function userimport(conn, group, path)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	if not lfs.attributes(path) then 
		return get_status(1, "not find " .. path)  
	end
	local importuesr = require("importuesr")
	local arr, err = importuesr.check(path)
	if not arr then 
		return get_status(1, err) 
	end 

	return pcli:query_auth({cmd = "user_add", data = {group = group, data = arr}}) or get_status(1, "error") 
end

local function check_policy(map)
	local name, ip1, ip2, tp = map.name, map.ip1, map.ip2, map.type 
	if not (name and #name >= 1 and #name <= 32) then  
		return nil, errmsg("认证名格式错误！")
	end 

	if not (ip1 and ip1:find(ip_pattern) and ip2 and ip2:find(ip_pattern)) then 
		print(ip1, ip1:find(ip_pattern), ip2, ip2:find(ip_pattern))
		return nil, errmsg("IP范围格式错误！")
	end 

	if not (tp and (tp == "auto" or tp == "web")) then 
		return nil, errmsg("参数错误，请尝试刷新！")
	end 

	return true 
end

local function policyadd(conn, group, map)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)

	local ret, err = check_policy(map) 
	if not ret then 
		return get_status(1, err)
	end 

	return pcli:query_auth({cmd = "policy_add", data = {group = group, data = map}}) or get_status(1, "error") 
end 

local function policydel(conn, group, arr)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	for _, name in pairs(arr) do 
		if not (#name >= 1 and #name < 32) then 
			return get_status(1, "无效的认证名！")
		end 
	end
	return pcli:query_auth({cmd = "policy_del", data = {group = group, data = arr}}) or get_status(1, "error") 
end 


local function policyset(conn, group, map)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	local ret, err = check_policy(map) 
	if not ret then 
		return get_status(1, err)
	end 

	return pcli:query_auth({cmd = "policy_set", data = {group = group, data = {[map.name] = map}}}) or get_status(1, "error")
end

local function policyadj(conn, group, arr)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)

	for _, name in pairs(arr) do  
		if not (#name >= 1 and #name < 32) then 
			return get_status(1, "无效的认证名！")
		end 
	end

	return pcli:query_auth({cmd = "policy_adj", data = {group = group, data = arr}}) or get_status(1, "error") 
end 

local function policyget(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli) 
	return pcli:query_auth({cmd = "policy_get", data = {group = group}}) or get_status(1, "error")
end 

local function onlinedel(conn, group, arr)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	for _, mac in ipairs(arr) do 
		if not (#mac == 17 and mac:find(mac_pattern)) then 
			return get_status(1, "invalid mac")
		end
	end
	local ret = pcli:query_auth({cmd = "online_del", data = {group = group, data = arr}})
	if not ret then 
		return get_status(1, "query_auth fail") 
	end 
	return get_status(0)
end 

local function onlineget(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	return pcli:query_auth({cmd = "online_get", data = {group = group, data = data}}) or get_status(1, "error")
end 


local function check_whitelist(map)
	return true, "ok"
end


local function whitelistset(conn, group, arr)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli)
	local ret, err = check_whitelist(arr) 
	if not ret then 
		return get_status(1, err)
	end 

	return pcli:query_auth({cmd = "whitelist_set", data = {group = group, data = arr}}) or get_status(1, "error")
end

local function whitelistget(conn, group, data)
	rds, pcli = conn.rds, conn.pcli 	assert(group and rds and pcli) 
	return pcli:query_auth({cmd = "whitelist_get", data = {group = group, data = data}}) or get_status(1, "error")
end 


return {
	useradd = useradd,
	userdel = userdel,
	userset = userset,
	userget = userget,
	userimport = userimport,
	policyadd = policyadd,
	policydel = policydel,
	policyset = policyset,
	policyadj = policyadj,
	policyget = policyget,
	onlinedel = onlinedel,
	onlineget = onlineget,
	whitelistset = whitelistset,
	whitelistget = whitelistget,
}