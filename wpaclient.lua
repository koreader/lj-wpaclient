local cur_path = (...):match("(.-)[^%(.|/)]+$")
local wpa_ctrl = require(cur_path .. "wpa_ctrl")


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
    if not hdl then
        return nil, err_msg
    end

    instance.wc_hdl = hdl
    return setmetatable(instance, WpaClient)
end

function WpaClient.__index:sendCmd(cmd, block)
    return wpa_ctrl.command(self.wc_hdl, cmd, block)
end

function WpaClient.__index:sendCtrlCmd(cmd)
    return wpa_ctrl.control_command(self.wc_hdl, cmd)
end

function WpaClient.__index:getInterfaces()
    local reply, err = self:sendCmd("INTERFACES", true)
    if reply == nil then
        return nil, err
    end

    return str_split(reply, "\n")
end

function WpaClient.__index:listNetworks()
    local reply, err = self:sendCmd("LIST_NETWORKS", true)
    if reply == nil then
        return nil, err
    end

    local results = {}
    local lst = str_split(reply, "\n")
    table.remove(lst, 1)  -- remove output table header
    for _, v in ipairs(lst) do
        local splits = str_split(v, "\t")
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
    local networks, err = self:listNetworks()
    if networks == nil then
        return nil, err
    end

    for _, nw in ipairs(networks) do
        if nw.flags and string.find(nw.flags, "%[CURRENT%]") then
            return nw
        end
    end
end

function WpaClient.__index:doScan()
    local reply, err = self:sendCtrlCmd("SCAN")
    if reply == nil then
        return nil, err
    end

    return str_strip(reply), err
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
    --[[
    else
        -- Assume signal is already a "quality" percentage
    --]]
    end

    return clamp(val, 0, 100)
end

function WpaClient.__index:getScanResults()
    local reply, err = self:sendCmd("SCAN_RESULTS", true)
    if reply == nil then
        return nil, err
    end

    local results = {}
    local lst = str_split(reply, "\n")
    for _, v in ipairs(lst) do
        local splits = str_split(v, "\t")

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
    local success, reply, err
    if not self.attached then
        success, err = self:attach()
        if not success then
            return nil, "Failed to ATTACH: " .. err
        end
    end
    -- May harmlessly fail with FAIL-BUSY
    reply, err = self:doScan()
    if reply == nil then
        return nil, err
    end

    local found_result
    local started_scans = 0
    local finished_scans = 0
    local expected_scans = 1
    local iter = 0
    while not found_result and iter < 20 do
        iter = iter + 1
        -- Wait for new data from wpa_supplicant in steps of at most 1 second.
        -- NOTE: I'm wary of simply doing a 20s poll, because we *may* receive events unrelated to the scan,
        --       unlike in sendCmd...
        -- NOTE: We do multiple passes, because wpa_supplicant may start a second scan on its own,
        --       and we'd like to catch it in a single of our own iteration...
        --       (i.e., we don't want to break on CTRL-EVENT-SCAN-RESULTS and then potentially miss
        --       a CTRL-EVENT-SCAN-STARTED on the *next* iteration...)
        --       c.f., the extra logic below that tries to handle this in case that wasn't enough.
        local evs = {}
        wpa_ctrl.waitForResponse(self.wc_hdl, 1 * 1000)
        self:readAllEvents(evs)
        wpa_ctrl.waitForResponse(self.wc_hdl, 1 * 1000)
        self:readAllEvents(evs)
        wpa_ctrl.waitForResponse(self.wc_hdl, 1 * 1000)
        self:readAllEvents(evs)

        for _, ev in ipairs(evs) do
            -- NOTE: If we hit a network preferred by the system, we may get connected directly,
            --       but we'll handle that later in WpaSupplicant:getNetworkList...

            if ev.msg == "CTRL-EVENT-SCAN-RESULTS" then
                finished_scans = finished_scans + 1
                -- We're only done once all the scans we've started have finished *and*
                -- when this number matches the actual number of scans we expected,
                -- in case there were rescans triggered by CTRL-EVENT-NETWORK-NOT-FOUND
                found_result = finished_scans == started_scans and finished_scans == expected_scans
            end

            -- If we get CTRL-EVENT-NETWORK-NOT-FOUND, it means a preferred network wasn't found during the scan.
            -- It also means *another* scan will be fired, so this invalidates CTRL-EVENT-SCAN-RESULTS,
            -- as the actual CTRL-EVENT-SCAN-STARTED may be delayed until our next iteration...
            -- It may take *multiple* scans, and events may be split across multiple reads...
            -- Which is why NetworkManager does another pass of waiting in case our heuristics fail...
            -- (A "perfect" solution for this case would be to wait *only* for CTRL-EVENT-CONNECTED *here*,
            -- but that only works when we actually have preferred networks to begin with, and one in range to boot ;o)).
            if ev.msg == "CTRL-EVENT-NETWORK-NOT-FOUND" then
                found_result = false
                expected_scans = expected_scans + 1
            end

            -- Wait for it to finish
            if ev.msg == "CTRL-EVENT-SCAN-STARTED" then
                found_result = false
                started_scans = started_scans + 1
            end

            -- Also break on successful connection (which usually implies we saw SCAN-RESULTS earlier ;p)
            if string.sub(ev.msg, 1, 20) == "CTRL-EVENT-CONNECTED" then
                found_result = true
            end

            -- For debugging purposes
            --print(iter, expected_scans, started_scans, finished_scans, ev.msg)
        end
    end

    if self.attached then
        success, err = self:detach()
        if not success then
           return nil, "Failed to DETACH: " .. err
        end
    end
    return self:getScanResults()
end

function WpaClient.__index:getStatus()
    local reply, err = self:sendCmd("STATUS", true)
    if reply == nil then
        return nil, err
    end

    local results = {}
    local lst = str_split(reply, "\n")
    for _, v in ipairs(lst) do
        local eqs, eqe = v:find("=")
        if eqs and eqe then
            results[v:sub(1, eqs-1)] = v:sub(eqe+1)
        end
    end
    return results
end

function WpaClient.__index:addNetwork()
    local reply, err = self:sendCtrlCmd("ADD_NETWORK")
    if reply == nil then
        return nil, err
    end

    return str_strip(reply), err
end

function WpaClient.__index:removeNetwork(id)
    local reply, err = self:sendCtrlCmd("REMOVE_NETWORK " .. id)
    if reply == nil then
        return nil, err
    end

    return str_strip(reply), err
end

function WpaClient.__index:disableNetworkByID(id)
    local reply, err = self:sendCtrlCmd("DISABLE_NETWORK " .. id)
    if reply == nil then
        return nil, err
    end

    return reply, err
end

function WpaClient.__index:setNetwork(id, key, value)
    local reply, err = self:sendCtrlCmd(string.format("SET_NETWORK %d %s %s", id, key, value))
    if reply == nil then
        return nil, err
    end

    return str_strip(reply), err
end

function WpaClient.__index:enableNetworkByID(id)
    local reply, err = self:sendCtrlCmd("ENABLE_NETWORK " .. id)
    if reply == nil then
        return nil, err
    end

    return reply, err
end

function WpaClient.__index:getConnectedNetwork()
    local reply, err = self:getStatus()
    if reply == nil then
        return nil, err
    end

    if reply.wpa_state == "COMPLETED" then
        return {
            id = reply.id,
            ssid = reply.ssid,
            bssid = reply.bssid,
        }
    else
        return nil, reply.wpa_state
    end
end

function WpaClient.__index:attach()
    local reply, err = wpa_ctrl.attach(self.wc_hdl)
    if reply ~= nil and reply == "OK\n" then
        self.attached = true
        return true
    end

    if reply == nil then
        return false, err
    end

    return false, str_strip(reply) or "N/A"
end

function WpaClient.__index:reattach()
    local reply, err = wpa_ctrl.reattach(self.wc_hdl)
    if reply ~= nil and reply == "OK\n" then
        self.attached = true
        return true
    end

    if reply == nil then
        return false, err
    end

    return false, str_strip(reply) or "N/A"
end

function WpaClient.__index:detach()
    local reply, err = wpa_ctrl.detach(self.wc_hdl)
    if reply ~= nil and reply == "OK\n" then
        self.attached = false
        return true
    end

    if reply == nil then
        return false, err
    end

    return false, str_strip(reply) or "N/A"
end

function WpaClient.__index:waitForEvent(timeout)
    return wpa_ctrl.waitForResponse(self.wc_hdl, timeout)
end

-- Return the *last* event
function WpaClient.__index:readEvent()
    -- NOTE: This may read nothing...
    wpa_ctrl.readResponse(self.wc_hdl)
    ---      ... what we care about is actually simply draining the event queue ;).
    return wpa_ctrl.readEvent(self.wc_hdl)
end

-- Return *all* events *in the order they came in* (into the array evs)
function WpaClient.__index:readAllEvents(evs)
    -- This will call Socket:recvAll, filling the event queue (or not)
    wpa_ctrl.readResponse(self.wc_hdl)

    -- Drain the replies pushed in the event queue by Socket:recvAll, keeping everything in order.
    evs = evs or {}
    wpa_ctrl.readAllEvents(self.wc_hdl, evs)
    return evs
end

function WpaClient.__index:disconnect()
    -- NOTE: Probably expects an actual response, and as such, should use sendCtrlCmd?
    --       We're currently not using it, though.
    return self:sendCmd("DISCONNECT")
end

function WpaClient.__index:close()
    if self.attached then
        self:detach()
    end
    wpa_ctrl.close(self.wc_hdl)
end

return WpaClient
