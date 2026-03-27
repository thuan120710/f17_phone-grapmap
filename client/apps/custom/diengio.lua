local QBCore = exports['qb-core']:GetCoreObject()

local NUI_ACTIONS = {
    getAppData = function(data, cb)
        local PlayerData = QBCore.Functions.GetPlayerData()
        if not PlayerData or not PlayerData.citizenid then
            print("[DiengioApp] PlayerData is not ready yet.")
            cb({ owned = false, allStations = {} })
            return
        end
        local myCitizenId = PlayerData.citizenid
        local globalTurbines = GlobalState.turbine or {}
        local ownedTurbineId = nil
        
        print("[DiengioApp] Fetching data for citizenid: " .. myCitizenId)

        -- Tìm trạm người chơi đang sở hữu
        for id, status in pairs(globalTurbines) do
            if status.citizenid == myCitizenId then
                ownedTurbineId = tonumber(id)
                print("[DiengioApp] Found owned turbine: " .. id)
                break
            end
        end

        local allStations = {}
        -- Có 36 trạm trong config của f17_diengio
        for i = 1, 36 do
            local status = globalTurbines[tostring(i)]
            table.insert(allStations, {
                id = i,
                isRented = status and status.isRented or false,
                isExpired = status and status.isExpired or false,
                ownerName = status and status.ownerName or "",
                timespan = status and status.timespan or ""
            })
        end

        if ownedTurbineId then
            -- Nếu có trạm sở hữu, lấy thêm thông tin chi tiết
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
            -- Kích hoạt waypoint từ resource f17_diengio hoặc tự xử lý
            -- Giả sử Config.TurbineLocations có sẵn ở phía client f17_diengio
            -- Ở đây ta sẽ dùng export nếu có hoặc tự đặt waypoint nếu biết tọa độ
            -- Tốt nhất là gửi event về client f17_diengio để xử lý
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
