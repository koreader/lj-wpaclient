local cur_path = (...):match("(.-)[^%(.|/)]+$")
local wpa_ctrl = require(cur_path..'wpa_ctrl')

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

function WpaClient.__index:close()
    wpa_ctrl.close(self.wc_hdl)
end

return WpaClient
