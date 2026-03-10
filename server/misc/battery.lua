



local batteryLevels = {}


RegisterNetEvent("phone:battery:setBattery", function(batteryLevel)
    local source = source
    

    if not Config.Battery.Enabled then
        debugprint("setBattery: battery system disabled")
        return
    end
    

    if type(batteryLevel) ~= "number" or batteryLevel < 0 or batteryLevel > 100 then
        debugprint("setBattery: invalid battery")
        return
    end
    
    local phoneNumber = GetEquippedPhoneNumber(source)
    if not phoneNumber then
        return
    end
    

    batteryLevels[phoneNumber] = batteryLevel
end)


function IsPhoneDead(phoneNumber)
    if not Config.Battery.Enabled then
        return false
    end
    
    return batteryLevels[phoneNumber] == 0
end


exports("IsPhoneDead", IsPhoneDead)


function SaveBattery(source)
    local phoneNumber = GetEquippedPhoneNumber(source)
    if not phoneNumber or not batteryLevels[phoneNumber] then
        return
    end
    
    debugprint(string.format("saving battery level (%s) for %s", batteryLevels[phoneNumber], phoneNumber))
    

    MySQL.update("UPDATE phone_phones SET battery = ? WHERE phone_number = ?", {
        batteryLevels[phoneNumber],
        phoneNumber
    }, function()

        batteryLevels[phoneNumber] = nil
    end)
end


exports("SaveBattery", SaveBattery)


local function SaveAllBatteries()
    debugprint("saving all battery levels")
    
    local players = GetPlayers()
    for i = 1, #players do
        SaveBattery(players[i])
    end
end


exports("SaveAllBatteries", SaveAllBatteries)


AddEventHandler("playerDropped", function()
    SaveBattery(source)
end)


AddEventHandler("txAdmin:events:scheduledRestart", function(eventData)
    if eventData.secondsRemaining == 60 then
        SaveAllBatteries()
    end
end)


AddEventHandler("txAdmin:events:serverShuttingDown", SaveAllBatteries)


AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        SaveAllBatteries()
    end
end)
