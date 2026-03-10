


local batteryLevel = 100
local isCharging = false


local function setBattery(battery)
    if not Config.Battery.Enabled then
        return
    end
    
    assert(type(battery) == "number", "setBattery: battery must be a number")
    assert(battery >= 0 and battery <= 100, "setBattery: battery must be between 0 and 100")
    
    batteryLevel = battery
    

    if battery == 0 then
        OnDeath()
        TriggerEvent("lb-phone:phoneDied")
    end
    

    TriggerServerEvent("phone:battery:setBattery", battery)
end


RegisterNUICallback("setBattery", function(data, callback)
    setBattery(data)
    callback("ok")
end)


exports("SetBattery", function(battery)
    setBattery(battery)
    SendReactMessage("battery:setBattery", battery)
end)


exports("GetBattery", function()
    return batteryLevel
end)


function ToggleCharging(toggle)
    assert(type(toggle) == "boolean", "ToggleCharging: toggle must be a boolean")
    
    if isCharging == toggle then
        debugprint("ToggleCharging: charging is already set to", toggle)
        return
    end
    
    isCharging = toggle
    SendReactMessage("battery:toggleCharging", toggle)
end


exports("ToggleCharging", ToggleCharging)


exports("IsCharging", function()
    return isCharging
end)


function IsPhoneDead()
    if not Config.Battery.Enabled then
        return false
    end
    
    return batteryLevel == 0
end


exports("IsPhoneDead", IsPhoneDead)
