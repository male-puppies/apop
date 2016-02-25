local function default_cloud()
	return {
		account = "",
		ac_host = "",
		ac_port = "61886",
		descr = "", 
		switch = "0",
	}
end 

local function default_wxshop()
	return {
		appid = "",
		shop_name = "",
		shop_id = "",
		ssid = "",
		secretkey = "",
	}
end 

return {
	default_cloud = default_cloud,
	default_wxshop = default_wxshop,
}
