local log = require("log")
local md5 = require("md5")
local js = require("cjson.safe")
local uci = require("muci")
-- local nixio = require("nixio")

-- local function fork_exec(command)
	-- local pid = nixio.fork()
	-- if pid > 0 then
		-- return
	-- elseif pid == 0 then
		-- change to root dir
		-- nixio.chdir("/")

		-- patch stdin, out, err to /dev/null
		-- local null = nixio.open("/dev/null", "w+")
		-- if null then
			-- nixio.dup(null, nixio.stderr)
			-- nixio.dup(null, nixio.stdout)
			-- nixio.dup(null, nixio.stdin)
			-- if null:fileno() > 2 then
				-- null:close()
			-- end
		-- end

		-- replace with target command
		-- nixio.exec("/bin/sh", "-c", command)
	-- end
-- end

local function random_string(len)
	local templete = "abcdefghijklmnopqrstuvwxyz"
	local maxlen = 26
	local map = {}
	
	for i = 1, len, 1 do
		local index = math.random(1, maxlen)
		map[i] = string.sub(templete, index, index)
	end
	
	local str = table.concat(map, "")
	return str
	-- if mf_logintime:get(str) then
		-- return random_string(len)
	-- else
		-- return str
	-- end
end

local function touchpwd(cursor)
	local curs = cursor or uci.cursor()
	
	local mark = true
	if not io.open("/etc/config/password") then
		os.execute("touch /etc/config/password")
		if not curs:section("password", "password", "password", {pwd = "admin"}) then
			mark = false
		end
	end

	return mark
end

local function setlogintime(path, loginid)
	local map, smap = {}, {}
	local fp = io.open(path, "rb")
	if fp then 
		local s = fp:read("*a")
		fp:close()
		map = js.decode(s)
		if not map then
			os.remove(path)
			return
		end
	end

	for k, v in pairs(map) do
		local val = tonumber(v) or 0
		if os.time() - val < 3600 then
			smap[k] = v
		end
	end
	
	smap[loginid] = os.time()
	local s = js.encode(smap)
	local file, err = io.open(path, "wb")
	local _ = file or log.fatal("open %s fail %s", tmp, err)

	file:write(s)
	file:flush()
	file:close()
end

local function login(group, data)
	local curs = uci.cursor()
	if not (type(data) == "table") then
		return {status = 1, data = "登录错误！"}
	end
	
	if data.username ~= "admin" then
		return {status = 1, data = "帐号错误！"}
	end
	
	local touch = touchpwd(curs)
	if not touch then
		return {status = 1, data = ""}
	end
	
	local pwd = curs:get("password", "password", "pwd")
	if not pwd then
		curs:section("password", "password", "password", {pwd = "admin"})
		pwd = "admin"
	end
	if data.password ~= pwd then
		return {status = 1, data = "密码错误！"}
	end
	
	local loginid = random_string(10)
	local path = "/tmp/memfile/logintime.json"
	setlogintime(path, loginid)

	local map = {}
	map.md5 = md5.sumhexa(pwd)
	map.id = loginid

	if curs:commit("password") then
		return {status = 0, data = map}
	else
		log.debug("error login commit fail")
		return {status = 1, data = ""}
	end
end

local function updatelogintime(group, data)
	local path = "/tmp/memfile/logintime.json"
	setlogintime(path, data)
	return {status = 0, data = ""}
end

local function setpassword(group, data)
	local curs = uci.cursor()
	if not (type(data) == "table") or not data.opwd or not data.pwd or data.pwd == "" then
		log.debug("error setpassword invalid parameter")
		return {status = 1, data = "修改错误！"}	
	end
	
	local touch = touchpwd(curs)
	if not touch then
		return {status = 1, data = ""}
	end
	
	local opwd = curs:get("password", "password", "pwd") or "admin"
	if data.opwd ~= opwd then
		return {status = 1, data = "原密码错误！"}
	end

	local s = curs:set("password", "password", "pwd", data.pwd)
	if not s then
		return {status = 1, data = ""}
	end
	
	if curs:commit("password") then
		return {status = 0, data = md5.sumhexa(data.pwd)}
	else
		return {status = 1, data = ""}
	end
end

local function getsystem(group, data)
	local curs = uci.cursor()
	
	local times = os.date("%Y-%m-%d %H:%M:%S")
	
	local arr = {}
	curs:foreach("system", "system", 
		function(x)
			local map = {}
			map.debug_switch = x.debug_switch or "disable"
			map.g_ledctrl = x.g_ledctrl or "enable"
			map.zonename = x.zonename or "UTC"
			map.times = times
			table.insert(arr, map)
		end
	)
	
	return {status = 0, data = arr[1]}
end

local function setsystem(group, data)
	local curs = uci.cursor()
	if not (type(data) == "table") then
		return {status = 1, data = "参数错误！"}	
	end
	
	local mark = true
	curs:foreach("system", "system", 
		function(x)
			local name = x[".name"]
			if not curs:tset("system", name, data) then
				mark = false
			end
		end
	)
	
	if mark and curs:commit("system") then
		local s = data.timezone or "GMT0"
		local fp = io.open("/tmp/TZ", "w")
		if fp then
			fp:write(s)
			fp:close()
		end
		return {status = 0, data = ""}
	else
		log.debug("error setsystem commit")
		return {status = 1, data = ""}
	end
end

local function synctimes(group, data)
	local curs = uci.cursor()
	if not (type(data) == "table") and not data.loginid and not data.times then
		return {status = 1, data = "参数错误！"}	
	end

	local cmd = string.format("date -s %q >/dev/null 2>/dev/null", data.times)
	os.execute(cmd)
	local path = "/tmp/memfile/logintime.json"
	setlogintime(path, data.loginid)
	
	local times = os.date("%Y-%m-%d %H:%M:%S")
	return {status = 0, data = times}
end

local function downloadbackup(group, data)
	local file = string.format("backup-%s.tgz", os.date("%Y-%m-%d"))
	local icmd = string.format("/tmp/%s", file)
	local cmd = string.format("sysupgrade --create-backup /tmp/%s", file)
	
	os.execute(cmd)
	local fp = io.open(icmd)
	if fp then
		return {status = 0, data = file}
	else
		return {status = 1, data = ""}
	end
end

local function uploadbackup(group, data)
	os.execute("tar -zxf /tmp/UploadBackup.img -C /")
	os.execute("reboot >/dev/null 2>&1")
end

local function confreset(group, data)
	os.execute("/ugw/script/reset_data.sh; sleep 1; mtd -r erase rootfs_data")
end

local function image_supported(image_tmp)
	local cmd = string.format("sysupgrade -T %q >/dev/null", image_tmp)
	return (os.execute(cmd) == 0)
end

local function uploadbrush(group, data)
	local image_tmp = "/tmp/UploadBrush.img"
	if not image_supported(image_tmp) then
		return {status = 1, data = "badupload"}
	end
	
	local keep = ""
	if data and data.keep and data.keep == "0" then
		keep = "-n"
	end
	
	local cmd = string.format("/ugw/script/stop_all.sh; sleep 1; /sbin/sysupgrade %s %q", keep, image_tmp)
	os.execute(cmd)
end

local function sysreboot(group, data)
	os.execute("reboot >/dev/null 2>&1")
end

return {
	login = login,
	updatelogintime = updatelogintime,
	setpassword = setpassword,
	getsystem = getsystem,
	setsystem = setsystem,
	synctimes = synctimes,
	-- systembackup = systembackup,
	downloadbackup = downloadbackup,
	uploadbackup = uploadbackup,
	confreset = confreset,
	uploadbrush = uploadbrush,
	sysreboot = sysreboot,
}