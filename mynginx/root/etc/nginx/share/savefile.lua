-- package.path = "/home/yjs/lua/run/conf/resty/?.lua;" .. package.path 
local upload = require("upload")
local tcp = ngx.socket.tcp
local chunk_size = 4096
local form = upload:new(chunk_size)
local fp  
local filelen=0  
form:set_timeout(0) -- 1 sec  
local filename  
function get_filename(res)  
    local filename = ngx.re.match(res,'(.+)filename="(.+)"(.*)')  
    if filename then   
        return filename[2]  
    end  
end  

local function query(host, port, data)
    local sock, err = tcp()
    if not sock then 
        return nil, err 
    end

    sock:settimeout(1000)

    local ret, err = sock:connect(host, port)
    if not ret then 
        return nil, err
    end 

    local ret, err = sock:send(data)
    if not ret then 
        sock:close()
        return nil, err 
    end

    local data, err = sock:receive("*a")
    sock:close()
    return data, err
end

local osfilepath = "/tmp/"  
local i =0  
while true do  
	local typ, res, err = form:read()  
	if not typ then  
		ngx.say("failed to read: ", err)  
		return  
    end  
    if typ == "header" then  
        if res[1] ~= "Content-Type" then   
            filename = (function(res)
            	local filename = ngx.re.match(res,'(.+)filename="(.+)"(.*)')  
            	if filename then
            		return filename[2]
            	end
            end)(res[2])

            if filename then  
                i=i+1  
                filepath = osfilepath  .. filename  
                fp = io.open(filepath,"w+")  
                if not fp then  
                    ngx.say("failed to open fp ")  
                    return  
                end  
            end  
        end  
    elseif typ == "body" then  
        if fp then  
            filelen= filelen + tonumber(string.len(res))      
            fp:write(res)  
        else  
        end  
    elseif typ == "part_end" then  
        if fp then  
            fp:close()  
            fp = nil  
            ngx.say("fp upload success")  
            local data, err = query("127.0.0.1", 12365, filename)
            ngx.say(string.format("--%s--%s--", data or "nil", err or "nil"))
        end  
    elseif typ == "eof" then  
        break  
    else  
    end  
end  
if i==0 then  
    ngx.say("please upload at least one fp!")  
    return  
end
