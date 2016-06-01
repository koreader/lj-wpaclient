local ffi = require('ffi')
local cur_path = (...):match("(.-)[^%(.|/)]+$")
local wpa_ctrl = require(cur_path..'wpa_ctrl')


function str_split(str, sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end

function str_strip(str)
    return str:match("(.-)\n$")
end


local WpaClient = {__index = {}}

function WpaClient.new(s)
    local instance = {
        wc_hdl = nil,
        attached = false,
    }

    local hdl, err_msg = wpa_ctrl.open(s)
    if not hdl then return nil, err_msg end

    instance.wc_hdl = hdl
    return setmetatable(instance, WpaClient)
end

function WpaClient.__index:sendCmd(cmd, block)
    local data, err_msg = wpa_ctrl.command(self.wc_hdl, cmd)
    if block and (data == nil or string.len(data) == 0) then
        -- wait until we get a response
        -- retry in a 1 second loop, max 10 seconds
        local re
        local cnt = 10
        while cnt > 0 and (data == nil or string.len(data)) do
            ffi.C.sleep(1)
            data, re = wpa_ctrl.readResponse(self.wc_hdl)
            if re > 0 then
                break
            elseif re < 0 then
                err_msg = re
                break
            end
            cnt = cnt - 1
        end
    end
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
    local re, err = self:sendCmd('SCAN')
    return str_strip(re), err
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
    for _,v in ipairs(lst) do
        local eqs, eqe = v:find('=')
        results[v:sub(1, eqs-1)] = v:sub(eqe+1)
    end
    return results
end

function WpaClient.__index:addNetwork()
    local re, err = self:sendCmd('ADD_NETWORK')
    return str_strip(re), err
end

function WpaClient.__index:removeNetwork(id)
    local re, err = self:sendCmd('REMOVE_NETWORK '..id)
    return str_strip(re), err
end

function WpaClient.__index:disableNetworkByID(id)
    local re, err = self:sendCmd('DISABLE_NETWORK '..id)
    return re, err
end

function WpaClient.__index:setNetwork(id, key, value)
    local re, err = self:sendCmd(
        string.format('SET_NETWORK %d %s "%s"', id, key, value),
        true)  -- set block to true
    return str_strip(re), err
end

function WpaClient.__index:enableNetworkByID(id)
    local re, err = self:sendCmd('ENABLE_NETWORK '..id)
    return re, err
end

function WpaClient.__index:getConnectedNetwork()
    re = self:getStatus()
    if re.wpa_state == 'COMPLETED' then
        return {
            id = re.id,
            ssid = re.ssid,
            bssid = re.bssid,
        }
    else
        return nil
    end
end

function WpaClient.__index:attach()
    wpa_ctrl.attach(self.wc_hdl)
    self.attached = true
end

function WpaClient.__index:detach()
    wpa_ctrl.detach(self.wc_hdl)
    self.attached = false
end

function WpaClient.__index:readEvent()
    local data, re = wpa_ctrl.readResponse(self.wc_hdl)
    return wpa_ctrl.readEvent(self.wc_hdl)
end

function WpaClient.__index:disconnect()
    self:sendCmd('DISCONNECT')
end

function WpaClient.__index:close()
    if self.attached then self:detach() end
    wpa_ctrl.close(self.wc_hdl)
end

return WpaClient
