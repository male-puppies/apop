-- author: gl

local js		= require("cjson.safe")
local log		= require("log")
local snlib		= require("sn")
local common	= require("common")

local read = common.read

-- 从云端获取响应
-- @url:连接地址
local function get_html(url)
	local str, err = read(url, io.popen)
	log.debug("curl get %s", str and #str ~= 0 and str or err or "nil")

	local map = str and js.decode(str)
	if not map then
		return nil, "curl map was nil"
	end

	if type(map) ~= "table" or map.status ~= 0 then
		log.debug("curl post error")
		return nil, str
	end

	return map
end

-- 生成检测时间
-- @hour_span:跨度时间
local function gen_tm_offset(hour_span, h, m, s)
	if type(hour_span) ~= "number" or hour_span >= 24 then
		return nil, "invalid parameter"
	end
	local h_intval = math.ceil(256 / hour_span)
	local m_intval = math.ceil(256 / 60)
	local s_intval = m_intval

	return math.floor(h / h_intval), math.floor(m / m_intval), math.floor(s / s_intval)
end

-- 检测表中是否有所需参数
-- @cmd:检测参数对应的命令
-- @map:检测的表
local function valid_get_pars(cmd, map)
	if not (cmd and map) then
		return nil, "cmd or map was nil"
	end

	if cmd == "register_check" then
		if not (map.data and map.data.body and map.data.body.code) then
			return nil, "map member was nil"
		end

		return map.data.body.code, map.data.body
	end

	if cmd == "update" then
		if not (map.detail and map.detail.sn) then
			return nil, "map member was nil"
		end

		return true
	end

	if cmd == "lock" then
		if not (map.detail and map.detail.locktype and map.detail.url) then
			return nil, "map member was nil"
		end

		return true
	end

	if cmd == "unlock" then
		if not (map.detail and map.detail.url) then
			return nil, "map member was nil"
		end

		return true
	end

	if cmd == "reply_ack" then
		if not (map.detail and map.detail.id) then
			return nil, "map member was nil"
		end

		return true
	end

	if cmd == "extend" then
		if not (map.detail and map.detail.url) then
			return nil, "map member was nil"
		end

		return true
	end
end

-- 获取sn,不存在就获取一个默认的
local function get_sn()
	local sn, devid = snlib.get_sn(), snlib.get_devid()
	if not sn then
		sn = snlib.get_default_sn()
	end

	return sn
end

-- 根据命令与参数生成url
-- @req_url:url前缀
-- @cmd:需要生成url的命令
-- @map:传递的参数
local function gen_url(req_url, req_host, cmd, map, timeout, cacert)
	if not (req_url and req_host and cmd and map) then
		return nil, "gen_url pars was nil"
	end

	local req_bin = "curl"
	if (timeout and type(timeout) == "number") then
		req_bin = req_bin .. " -m " .. timeout
	end

	if (cacert and type(cacert) == "string") then
		req_bin = req_bin .. " --cacert " .. cacert
	end

	local url = string.format("%s '%s/%s/%s' -d", req_bin, req_host, req_url, cmd)

	local pars = ""
	for k, v in pairs(map) do
		if type(v) == "table" then
			v = js.encode(v)
		end
		pars = string.format("%s&%s=%s",pars, k, v)
	end
	url = string.format("%s '%s'", url, pars)
	log.debug("post url: %s\n", url)

	return url
end

-- 校验状态文件合法性
-- @map:从状态文件中读取的表
local function check_valid_reg(map)
	if not map then
		return false, "map was nil"
	end
	if not (map.status and map.data and map.data.action) then
		return false
	end

	local action = map.data.action
	if map.status == "authd" then
		if action ~= "normal" then
			return false, "action was invalid"
		end

		return action
	end

	if map.status == "unauthd" then
		if action ~= "conservative" and action ~= "radical" then
			return false, "action was invalid"
		end

		return action
	end
end

return	{
	get_html	= get_html,
	get_sn		= get_sn,
	gen_url		= gen_url,
	gen_tm_offset	= gen_tm_offset,
	valid_get_pars	= valid_get_pars,
	check_valid_reg	= check_valid_reg,
}