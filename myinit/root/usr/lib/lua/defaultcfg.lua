local function default_cloud()
	return {
		account = "yjs",
		ac_host = "192.168.0.213",
		ac_port = "61886",
		descr = "default", 
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
