local ffi = require('ffi')
local cur_path = (...):match("(.-)[^%(.|/)]+$")
local wpa_ctrl = require(cur_path..'wpa_ctrl')


local function str_split(str, sep)
    local fields = {}
    sep = sep or ":"
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end

local function str_strip(str)
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
    local re_str = self:sendCmd('INTERFACES', true)
    return str_split(re_str, '\n')
end

function WpaClient.__index:listNetworks()
    local results = {}
    local re_str = self:sendCmd('LIST_NETWORKS', true)
    local lst = str_split(re_str, '\n')
    table.remove(lst, 1)  -- remove output table header
    for _,v in ipairs(lst) do
        local splits = str_split(v, '\t')
        table.insert(results, {
            id = splits[1],
            ssid = splits[2],
            bssid = splits[3],
            flags = splits[4],
        })
    end
    return results
end

function WpaClient.__index:getCurrentNetwork()
    local networks = self:listNetworks()
    for _,nw in ipairs(networks) do
        if nw.flags and string.find(nw.flags, '%[CURRENT%]') then
            return nw
        end
    end
end

function WpaClient.__index:doScan()
    local re, err = self:sendCmd('SCAN', true)
    return str_strip(re), err
end

local network_mt = {__index = {}}

function network_mt.__index:getSignalQuality()
    -- Based on NetworkManager's nm_wifi_utils_level_to_quality
    -- c.f., https://github.com/NetworkManager/NetworkManager/blob/2fa8ef9fb9c7fe0cc2d9523eed6c5a3749b05175/src/nm-core-utils.c#L5083-L5100
    -- With a minor tweak: we assume a best-case at -20dBm (instead of -40dBm),
    -- because we've seen Kobos report slightly wonky values (as low as -15dBm)...
    -- https://github.com/koreader/lj-wpaclient/pull/6 & https://github.com/koreader/koreader/issues/7008
    -- There's no real silver bullet here, as the RSSI is in arbitrary units,
    -- which means every driver kinda does what it wants with it...

    local function clamp(val, min, max)
        return math.max(min, math.min(max, val))
    end

    local function dbm_to_qual(val)
        val = math.abs(clamp(val, -100, -20) + 20)    -- Normalize to 0
        val = 100 - math.floor((100.0 * val) / 80.0)  -- Rescale to [0, 100] range
        return val
    end

    local val = self.signal_level
    if val < 0 then
        -- Assume dBm already; rough conversion: best = -20, worst = -100
        val = dbm_to_qual(val)
    elseif val > 110 and val < 256 then
        -- Assume old-style WEXT 8-bit unsigned signal level
        val = val - 256                               -- Subtract 256 to convert to dBm
        val = dbm_to_qual(val)
    else
        -- Assume signal is already a "quality" percentage
    end

    return clamp(val, 0, 100)
end

function WpaClient.__index:getScanResults()
    local results = {}
    local re_str, err = self:sendCmd('SCAN_RESULTS', true)
    if err then return nil, err end

    local lst = str_split(re_str, '\n')
    for _,v in ipairs(lst) do
        local splits = str_split(v, '\t')

        if splits[5] then  -- ignore lines which don't split into 5 parts
            local network = {
                bssid = splits[1],
                frequency = tonumber(splits[2]),
                signal_level = tonumber(splits[3]),
                flags = splits[4],
                ssid = splits[5],
            }
            setmetatable(network, network_mt)
            table.insert(results, network)
        end
    end
    return results
end

function WpaClient.__index:scanThenGetResults()
    local was_attached = self.attached
    if not was_attached then
        self:attach()
    end
    local _, err = self:doScan()
    if err then return nil, err end

    local found_result = false
    local wait_cnt = 20
    while wait_cnt > 0 do
        for _,ev in ipairs(self:readAllEvents()) do
            if ev.msg == 'CTRL-EVENT-SCAN-RESULTS' then
                found_result = true
                break
            end
        end
        if found_result then break end

        wait_cnt = wait_cnt - 1
        -- sleep for 1 second
        ffi.C.poll(nil, 0, 1000)
    end

    if not was_attached then
        self:detach()
    end
    return self:getScanResults()
end

function WpaClient.__index:getStatus()
    local results = {}
    local re_str, err = self:sendCmd('STATUS', true)
    if err then return nil, err end

    local lst = str_split(re_str, '\n')
    for _,v in ipairs(lst) do
        local eqs, eqe = v:find('=')
        results[v:sub(1, eqs-1)] = v:sub(eqe+1)
    end
    return results
end

function WpaClient.__index:addNetwork()
    local re, err = self:sendCmd('ADD_NETWORK', true)
    return str_strip(re), err
end

function WpaClient.__index:removeNetwork(id)
    local re, err = self:sendCmd('REMOVE_NETWORK '..id, true)
    return str_strip(re), err
end

function WpaClient.__index:disableNetworkByID(id)
    local re, err = self:sendCmd('DISABLE_NETWORK '..id, true)
    return re, err
end

function WpaClient.__index:setNetwork(id, key, value)
    local re, err = self:sendCmd(
        string.format('SET_NETWORK %d %s %s', id, key, value),
        true)  -- set block to true
    return str_strip(re), err
end

function WpaClient.__index:enableNetworkByID(id)
    local re, err = self:sendCmd('ENABLE_NETWORK '..id, true)
    return re, err
end

function WpaClient.__index:getConnectedNetwork()
    local re = self:getStatus()
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
    wpa_ctrl.readResponse(self.wc_hdl)
    return wpa_ctrl.readEvent(self.wc_hdl)
end

function WpaClient.__index:readAllEvents()
    local evs = {}
    repeat
        local ev = self:readEvent()
        if ev ~= nil then
            table.insert(evs, ev)
        end
    until ev == nil
    return evs
end

function WpaClient.__index:disconnect()
    self:sendCmd('DISCONNECT')
end

function WpaClient.__index:close()
    if self.attached then self:detach() end
    wpa_ctrl.close(self.wc_hdl)
end

return WpaClient
