-- Grab App for LB Phone
-- Client-side logic for Grab ride-sharing service

local isGrabDriver = false
local currentRide = nil
local blips = { ride = nil, driver = nil, taxis = {} }
local isTrackingCoords = false
local lastCoords = vector3(0, 0, 0)

-- Blip Management
local BLIP_CONFIG = {
    taxi = { sprite = 280, color = 5, scale = 0.7, label = "~y~Grab~w~ - Tài xế" },
    driver = { sprite = 280, color = 3, scale = 0.8, label = "~b~Grab~w~ - Tài xế" },
    pickup = { sprite = 280, color = 2, scale = 0.9, label = "~g~Grab~w~ - Đón khách" },
    dropoff = { sprite = 280, color = 17, scale = 0.9, label = "~o~Grab~w~ - Trả khách" }
}

local function removeBlip(blipType)
    if blips[blipType] then
        RemoveBlip(blips[blipType])
        blips[blipType] = nil
    end
end

local function removeAllTaxiBlips()
    for i = 1, #blips.taxis do
        if blips.taxis[i] then RemoveBlip(blips.taxis[i]) end
    end
    blips.taxis = {}
end

local function createBlip(blipType, coords, customLabel)
    removeBlip(blipType)
    
    local config = BLIP_CONFIG[blipType]
    if not config then return end
    
    local z = coords.z or 0.0
    local blip = AddBlipForCoord(coords.x, coords.y, z)
    SetBlipSprite(blip, config.sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, config.scale)
    SetBlipAsShortRange(blip, false)
    SetBlipColour(blip, config.color)
    
    if blipType == "pickup" or blipType == "dropoff" then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, config.color)
    end
    
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(customLabel or config.label)
    EndTextCommandSetBlipName(blip)
    
    blips[blipType] = blip
    return blip
end

local function createTaxiBlips(drivers)
    removeAllTaxiBlips()
    for i = 1, #drivers do
        local driver = drivers[i]
        local z = driver.coords.z or 0.0
        local blip = AddBlipForCoord(driver.coords.x, driver.coords.y, z)
        SetBlipSprite(blip, BLIP_CONFIG.taxi.sprite)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, BLIP_CONFIG.taxi.scale)
        SetBlipColour(blip, BLIP_CONFIG.taxi.color)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName(BLIP_CONFIG.taxi.label)
        EndTextCommandSetBlipName(blip)
        blips.taxis[#blips.taxis + 1] = blip
    end
end

-- Coordinate Tracking
local function startCoordinateTracking()
    local ped = PlayerPedId()
    lastCoords = GetEntityCoords(ped)
    
    SendReactMessage("grab:updateCoords", {
        x = math.floor(lastCoords.x + 0.5),
        y = math.floor(lastCoords.y + 0.5)
    })
    
    CreateThread(function()
        while isTrackingCoords do
            local currentCoords = GetEntityCoords(ped)
            if #(lastCoords - currentCoords) > 0.5 then
                lastCoords = currentCoords
                SendReactMessage("grab:updateCoords", {
                    x = math.floor(currentCoords.x + 0.5),
                    y = math.floor(currentCoords.y + 0.5)
                })
            end
            Wait(100)
        end
    end)
end

-- Driver Location Update Thread
CreateThread(function()
    while true do
        Wait(5000)
        if isGrabDriver then
            local ped = PlayerPedId()
            TriggerServerEvent("grab:updateDriverLocation", GetEntityCoords(ped), GetVehiclePedIsIn(ped, false) ~= 0)
        end
    end
end)

-- NUI Callback Handler
RegisterNetEvent("grab:handleNUICallback", function(data, callback)
    local action = data.action
    
    if action == "getCurrentLocation" then
        local coords = GetEntityCoords(PlayerPedId())
        callback({ x = coords.x, y = coords.y })
        
    elseif action == "toggleUpdateCoords" then
        if isTrackingCoords ~= data.toggle then
            isTrackingCoords = data.toggle == true
            if isTrackingCoords then startCoordinateTracking() end
        end
        callback("ok")
        
    elseif action == "toggleGrabDriver" then
        TriggerServerEvent("grab:toggleDriver", not isGrabDriver)
        callback({ success = true, status = not isGrabDriver })
        
    elseif action == "requestGrabRide" then
        local requestData = data
        if not requestData.pickupCoords then
            requestData.pickupCoords = GetEntityCoords(PlayerPedId())
        end
        callback(AwaitCallback("grab:requestRide", requestData))
        
    elseif action == "getGrabDriverStatus" then
        callback({ isDriver = isGrabDriver, hasRide = currentRide ~= nil })
        
    elseif action == "completeGrabRide" then
        if currentRide then
            TriggerServerEvent("grab:completeRide", currentRide.rideId)
            currentRide = nil
            removeBlip("ride")
        end
        callback("ok")
        
    elseif action == "cancelGrabRide" then
        if currentRide then
            TriggerServerEvent("grab:cancelRide", currentRide.rideId)
            currentRide = nil
            removeBlip("ride")
            removeBlip("driver")
        end
        callback("ok")
        
    elseif action == "getNearbyGrabDrivers" then
        callback(AwaitCallback("grab:getNearbyDrivers", GetEntityCoords(PlayerPedId())))
        
    elseif action == "getAllGrabDrivers" then
        local drivers = AwaitCallback("grab:getAllDrivers", GetEntityCoords(PlayerPedId()))
        if drivers then
            for i = 1, #drivers do
                if drivers[i].coords then
                    drivers[i].x = drivers[i].coords.x
                    drivers[i].y = drivers[i].coords.y
                    drivers[i].z = drivers[i].coords.z
                    drivers[i].coords = nil
                end
            end
        end
        callback(drivers)
        
    elseif action == "showTaxiBlips" then
        local drivers = AwaitCallback("grab:getAllDrivers", GetEntityCoords(PlayerPedId()))
        createTaxiBlips(drivers)
        callback("ok")
        
    elseif action == "hideTaxiBlips" then
        removeAllTaxiBlips()
        callback("ok")
        
    elseif action == "acceptGrabRide" then
        if data.rideId then TriggerServerEvent("grab:acceptRide", data.rideId) end
        callback("ok")
        
    elseif action == "rejectGrabRide" then
        if data.rideId then TriggerServerEvent("grab:rejectRide", data.rideId) end
        callback("ok")
        
    elseif action == "arrivedAtPickup" then
        if data.rideId then TriggerServerEvent("grab:arrivedAtPickup", data.rideId) end
        callback("ok")
        
    else
        callback("ok")
    end
end)

-- Grab Events
RegisterNetEvent("grab:driverStatus", function(status)
    isGrabDriver = status
    SendReactMessage("grab:updateDriverStatus", { isDriver = status })
    
    if not status then
        removeBlip("ride")
        removeBlip("driver")
        removeAllTaxiBlips()
        currentRide = nil
    end
end)

RegisterNetEvent("grab:rideRequest", function(data)
    if not isGrabDriver then return end
    
    currentRide = data
    if data.dropoffCoords then
        currentRide.dropoffCoords = data.dropoffCoords
    end
    
    local message = string.format(
        "~g~[Grab]~w~ Yêu cầu đặt xe mới!\n" ..
        "Khoảng cách đón: ~y~%dm~w~\n" ..
        "Quãng đường: ~y~%dm~w~\n" ..
        "Thu nhập: ~g~$%d~w~\n\n" ..
        "Ấn ~g~[Y]~w~ chấp nhận | ~r~[N]~w~ từ chối",
        data.distance, data.tripDistance or 0, data.price
    )
    
    TriggerEvent("QBCore:Notify", message, "info", 15000)
    
    local responded = false
    CreateThread(function()
        local timeout = GetGameTimer() + 15000
        
        while GetGameTimer() < timeout and not responded do
            Wait(0)
            
            if IsControlJustReleased(0, 246) then -- Y
                responded = true
                TriggerServerEvent("grab:acceptRide", data.rideId)
            elseif IsControlJustReleased(0, 249) then -- N
                responded = true
                TriggerServerEvent("grab:rejectRide", data.rideId)
                currentRide = nil
                exports['f17notify']:Notify("Đã từ chối chuyến xe!", "info", 5000)
            end
        end
        
        if not responded then
            TriggerServerEvent("grab:rejectRide", data.rideId)
            currentRide = nil
        end
    end)
end)

RegisterNetEvent("grab:startNavigation", function(coords)
    createBlip("pickup", coords)
    
    CreateThread(function()
        while currentRide do
            Wait(1000)
            local distance = #(GetEntityCoords(PlayerPedId()) - vector3(coords.x, coords.y, coords.z or 0.0))
            
            if distance < 20.0 then
                TriggerServerEvent("grab:arrivedAtPickup", currentRide.rideId)
                break
            end
        end
    end)
end)

RegisterNetEvent("grab:startDropoffNavigation", function(coords, passengerId)
    if currentRide then
        currentRide.dropoffCoords = coords
        currentRide.passengerId = passengerId
    end
    
    exports['f17notify']:Notify("Đợi khách vào xe để bắt đầu chuyến đi!", "info", 5000)
    
    CreateThread(function()
        while currentRide and currentRide.dropoffCoords do
            Wait(500)
            
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            
            if vehicle ~= 0 then
                local passengerPed = GetPlayerPed(GetPlayerFromServerId(currentRide.passengerId))
                
                if passengerPed and passengerPed ~= 0 then
                    local passengerVehicle = GetVehiclePedIsIn(passengerPed, false)
                    
                    if passengerVehicle == vehicle then
                        removeBlip("ride")
                        createBlip("dropoff", coords)
                        currentRide.status = "pickedup"
                        TriggerServerEvent("grab:passengerInVehicle", currentRide.rideId)
                        exports['f17notify']:Notify("Khách đã lên xe! GPS đã chỉ đường đến điểm trả.", "success", 5000)
                        
                        -- Thread kiểm tra đến điểm trả
                        CreateThread(function()
                            while currentRide and currentRide.status == "pickedup" do
                                Wait(1000)
                                local playerCoords = GetEntityCoords(PlayerPedId())
                                local distance = #(playerCoords - vector3(coords.x, coords.y, coords.z or 0.0))
                                
                                if distance < 20.0 then
                                    exports['f17notify']:Notify("Đã đến điểm trả! Nhấn ~g~[E]~w~ để hoàn thành chuyến", "info", 3000)
                                    
                                    while distance < 20.0 and currentRide do
                                        Wait(0)
                                        if IsControlJustReleased(0, 38) then
                                            TriggerServerEvent("grab:completeRide", currentRide.rideId)
                                        end
                                        distance = #(GetEntityCoords(PlayerPedId()) - vector3(coords.x, coords.y, coords.z or 0.0))
                                    end
                                end
                            end
                        end)
                        break
                    end
                end
            end
        end
    end)
end)

RegisterNetEvent("grab:clearNavigation", function()
    removeBlip("ride")
end)

RegisterNetEvent("grab:rideAccepted", function(data)
    exports['f17notify']:Notify(data.message, "success", 5000)
    SendReactMessage("grab:rideAccepted", data)
    
    if data.dropoffCoords then
        currentRide = currentRide or {}
        currentRide.dropoffCoords = data.dropoffCoords
    end
    
    if data.driverCoords then
        createBlip("driver", data.driverCoords, "~b~Grab~w~ - Tài xế đang đến")
    end
end)

RegisterNetEvent("grab:driverArrived", function()
    exports['f17notify']:Notify("Tài xế đã đến! Chúc bạn đi đường an toàn.", "success", 5000)
    SendReactMessage("grab:driverArrived", {})
    removeBlip("driver")
    
    if currentRide and currentRide.dropoffCoords then
        createBlip("dropoff", currentRide.dropoffCoords)
    end
end)

RegisterNetEvent("grab:rideCompleted", function(price)
    local message = string.format("~g~[Grab]~w~ Hoàn thành!\nChi phí: ~r~$%d", price)
    TriggerEvent("QBCore:Notify", message, "success", 8000)
    
    -- Xóa TẤT CẢ blips
    removeBlip("ride")
    removeBlip("driver")
    removeBlip("pickup")
    removeBlip("dropoff")
    currentRide = nil
    
    SendReactMessage("grab:rideCompleted", { price = price })
end)

RegisterNetEvent("grab:rideCancelled", function(reason)
    exports['f17notify']:Notify(reason or "Chuyến xe đã bị hủy!", "error", 5000)
    
    -- Xóa TẤT CẢ blips
    removeBlip("ride")
    removeBlip("driver")
    removeBlip("pickup")
    removeBlip("dropoff")
    currentRide = nil
    
    SendReactMessage("grab:rideCancelled", { reason = reason })
end)

RegisterNetEvent("grab:updateDriverLocation", function(coords)
    if blips.driver then
        SetBlipCoords(blips.driver, coords.x, coords.y, coords.z or 0.0)
    end
end)
