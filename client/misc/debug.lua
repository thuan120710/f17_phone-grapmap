-- Debug commands and utilities for LB Phone
-- Provides various debugging commands when debug mode is enabled

-- Toggle debug mode on/off
RegisterCommand("phonedebug", function()
    Config.Debug = not Config.Debug
    SendReactMessage("toggleDebug", Config.Debug)
    print("DEBUG:", Config.Debug)
end, false)

-- Helper function to register debug-only commands
local function RegisterDebugCommand(command, fn)
    RegisterCommand("phone" .. command, function(...)
        if not Config.Debug then
            return
        end
        fn(...)
    end, false)
end

-- Debug command to print cache information
RegisterDebugCommand("getcache", function()
    SendReactMessage("printCache")
end)

-- Debug command to print stack information
RegisterDebugCommand("getstacks", function()
    SendReactMessage("printStacks")
end)

-- Exit early if debug mode is disabled
if not Config.Debug then
    return
end

-- Debug command to send test notification
RegisterDebugCommand("notification", function()
    ---@type Notification
    local notification = {
        app = "Settings",
        title = "Test notification",
        content = "This is a test notification",
    }
    
    exports["lb-phone"]:SendNotification(notification)
end)

-- Debug command to toggle charging state
RegisterDebugCommand("togglecharging", function()
    exports["lb-phone"]:ToggleCharging(not exports["lb-phone"]:IsCharging())
end)

-- Debug command to set battery level
RegisterDebugCommand("setbattery", function(_, args)
    local battery = tonumber(args[1])
    
    if not battery or battery < 0 or battery > 100 then
        print("Invalid battery value. Must be between 0 and 100.")
        return
    end
    
    exports["lb-phone"]:SetBattery(battery)
end)
