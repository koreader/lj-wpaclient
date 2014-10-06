local cur_path = (...):match("(.-)[^%(.|/)]+$")
local wpa_ctrl = require(cur_path..'wpa_ctrl')



function str_split(str, sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end


local WpaClient = { __index = {} }

function WpaClient.new(s)
    local instance = {
        wc_hdl = nil,
    }

    local hdl, err_msg = wpa_ctrl.open(s)
    if not hdl then return nil, err_msg end

    instance.wc_hdl = hdl
    return setmetatable(instance, WpaClient)
end

function WpaClient.__index:sendCmd(cmd)
    local data, err_msg = wpa_ctrl.command(self.wc_hdl, cmd)
    return data, err_msg
end

function WpaClient.__index:getInterfaces()
    local re_str = self:sendCmd('INTERFACES')
    return str_split(re_str, '\n')
end

function WpaClient.__index:listNetworks()
    local results = {}
    local re_str = self:sendCmd('LIST_NETWORKS')
    local lst = str_split(re_str, '\n')
    table.remove(lst, 1)
    for k,v in ipairs(lst) do
        splits = str_split(v, '\t')
        results[k] = {
            id = splits[1],
            ssid = splits[2],
            bssid = splits[3],
            flags = splits[4],
        }
    end
    return results
end

function WpaClient.__index:doScan()
    return self:sendCmd('SCAN')
end

function WpaClient.__index:getScanResults()
    local results = {}
    local re_str, err = self:sendCmd('SCAN_RESULTS')
    local lst = str_split(re_str, '\n')
    table.remove(lst, 1)
    for k,v in ipairs(lst) do
        splits = str_split(v, '\t')
        results[k] = {
            bssid = splits[1],
            frequency = splits[2],
            signal_level = splits[3],
            flags = splits[4],
            ssid = splits[5],
        }
    end
    return results
end

function WpaClient.__index:getStatus()
    local results = {}
    local re_str, err = self:sendCmd('STATUS')
    local lst = str_split(re_str, '\n')
    for k,v in ipairs(lst) do
        eqs, eqe = v:find('=')
        results[v:sub(1, eqs-1)] = v:sub(eqe+1)
    end
    return results
end

function WpaClient.__index:disableNetworkByID(id)
    local re, err = self:sendCmd('DISABLE_NETWORK '..id)
    return re, err
end

function WpaClient.__index:enableNetworkByID(id)
    local re, err = self:sendCmd('ENABLE_NETWORK '..id)
    return re, err
end

function WpaClient.__index:close()
    wpa_ctrl.close(self.wc_hdl)
end

return WpaClient
