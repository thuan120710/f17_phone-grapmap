local QBCore = exports['qb-core']:GetCoreObject()

local NUI_ACTIONS = {
    getAppData = function(data, cb)
        local PlayerData = QBCore.Functions.GetPlayerData()
        if not PlayerData or not PlayerData.citizenid then
            cb({ owned = false, allStations = {} })
            return
        end
        local myCitizenId = PlayerData.citizenid
        local globalTurbines = GlobalState.turbine or {}
        local ownedTurbineId = nil       

        for id, status in pairs(globalTurbines) do
            if status.citizenid == myCitizenId then
                ownedTurbineId = tonumber(id)
                break
            end
        end

        local allStations = {}
        for i = 1, 36 do
            local status = globalTurbines[tostring(i)]
            table.insert(allStations, {
                id = i,
                isRented = status and status.isRented or false,
                isExpired = status and status.isExpired or false,
                ownerName = status and status.ownerName or "",
                timespan = status and status.timespan or "",
                expiryTime = status and status.expiryTime or 0
            })
        end

        if ownedTurbineId then
            QBCore.Functions.TriggerCallback('f17_diengio:server:getTurbineData', function(details)
                cb({
                    owned = true,
                    turbineId = ownedTurbineId,
                    details = details,
                    allStations = allStations
                })
            end, ownedTurbineId)
        else
            cb({
                owned = false,
                allStations = allStations
            })
        end
    end,

    setWaypoint = function(data, cb)
        if data.id then
            TriggerEvent('f17_diengio:client:setWaypoint', data.id)
            cb({ success = true })
        else
            cb({ success = false })
        end
    end
}

RegisterNUICallback("DiengioApp", function(data, cb)
    if NUI_ACTIONS[data.action] then
        NUI_ACTIONS[data.action](data, cb)
    else
        cb({})
    end
end)
