-- Grab App for LB Phone
-- Client-side logic for Grab ride-sharing service

local isGrabDriver = false
local currentRide = nil
local rideBlip = nil
local driverBlip = nil
local taxiBlips = {}
local isTrackingCoords = false
local currentPlayerPed = PlayerPedId()
local lastCoords = vector3(0, 0, 0)

-- Utility functions
local function removeRideBlip()
    if rideBlip then
        RemoveBlip(rideBlip)
        rideBlip = nil
    end
end

local function removeDriverBlip()
    if driverBlip then
        RemoveBlip(driverBlip)
        driverBlip = nil
    end
end

local function removeTaxiBlips()
    for i = 1, #taxiBlips do
        if taxiBlips[i] then
            RemoveBlip(taxiBlips[i])
        end
    end
    taxiBlips = {}
end

local function createTaxiBlips(drivers)
    removeTaxiBlips()
    
    for i = 1, #drivers do
        local driver = drivers[i]
        local blip = AddBlipForCoord(driver.coords.x, driver.coords.y, driver.coords.z)
        SetBlipSprite(blip, 280) -- Taxi icon
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, 0.7)
        SetBlipAsShortRange(blip, false)
        SetBlipColour(blip, 5) -- Yellow for available taxis
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName("~y~Grab~w~ - Tài xế")
        EndTextCommandSetBlipName(blip)
        
        taxiBlips[#taxiBlips + 1] = blip
    end
end

local function createDriverBlip(coords, label)
    removeDriverBlip()
    driverBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(driverBlip, 280) -- Taxi icon
    SetBlipDisplay(driverBlip, 4)
    SetBlipScale(driverBlip, 0.8)
    SetBlipAsShortRange(driverBlip, false)
    SetBlipColour(driverBlip, 3) -- Blue for driver
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(label or "~b~Grab~w~ - Tài xế")
    EndTextCommandSetBlipName(driverBlip)
end

local function createRideBlip(coords, label)
    removeRideBlip()
    rideBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(rideBlip, 280) -- Taxi icon
    SetBlipDisplay(rideBlip, 4)
    SetBlipScale(rideBlip, 0.9)
    SetBlipAsShortRange(rideBlip, false)
    SetBlipColour(rideBlip, 2) -- Green
    SetBlipRoute(rideBlip, true)
    SetBlipRouteColour(rideBlip, 2)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(label or "~g~Grab~w~ - Khách hàng")
    EndTextCommandSetBlipName(rideBlip)
end

-- Coordinate tracking
local function startCoordinateTracking()
    currentPlayerPed = PlayerPedId()
    lastCoords = GetEntityCoords(currentPlayerPed)    
    
    -- Send initial coordinates
    SendReactMessage("grab:updateCoords", {
        x = math.floor(lastCoords.x + 0.5),
        y = math.floor(lastCoords.y + 0.5)
    })
    
    -- Coordinate tracking loop
    CreateThread(function()
        while isTrackingCoords do
            local currentCoords = GetEntityCoords(currentPlayerPed)
            
            local distance = #(lastCoords - currentCoords)
            if distance > 0.5 then
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

-- Update driver location thread
CreateThread(function()
    while true do
        Wait(5000)
        
        if isGrabDriver then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local vehicle = GetVehiclePedIsIn(ped, false)
            local inVehicle = vehicle ~= 0
            
            TriggerServerEvent("grab:updateDriverLocation", coords, inVehicle)
        end
    end
end)

-- NUI Callback Handler
RegisterNetEvent("grab:handleNUICallback", function(data, callback)
    local action = data.action
    
    if action == "getCurrentLocation" then
        -- Get current player coordinates
        local coords = GetEntityCoords(PlayerPedId())
        callback({
            x = coords.x,
            y = coords.y
        })
        
    elseif action == "toggleUpdateCoords" then
        local newToggle = data.toggle == true
        
        if isTrackingCoords == newToggle then
            if newToggle then
                startCoordinateTracking()
            end
            callback("ok")
            return
        end
        
        isTrackingCoords = newToggle
        
        if isTrackingCoords then
            startCoordinateTracking()
        end
        
        callback("ok")
        
    elseif action == "toggleGrabDriver" then
        local newStatus = not isGrabDriver
        TriggerServerEvent("grab:toggleDriver", newStatus)
        callback({ success = true, status = newStatus })
        
    elseif action == "requestGrabRide" then
        local coords = GetEntityCoords(PlayerPedId())
        local result = AwaitCallback("grab:requestRide", coords)
        callback(result)
        
    elseif action == "getGrabDriverStatus" then
        callback({ isDriver = isGrabDriver, hasRide = currentRide ~= nil })
        
    elseif action == "completeGrabRide" then
        if currentRide then
            TriggerServerEvent("grab:completeRide", currentRide.rideId)
            currentRide = nil
            removeRideBlip()
        end
        callback("ok")
        
    elseif action == "cancelGrabRide" then
        if currentRide then
            TriggerServerEvent("grab:cancelRide", currentRide.rideId)
            currentRide = nil
            removeRideBlip()
        end
        callback("ok")
        
    elseif action == "getNearbyGrabDrivers" then
        local coords = GetEntityCoords(PlayerPedId())
        local drivers = AwaitCallback("grab:getNearbyDrivers", coords)
        callback(drivers)
        
    elseif action == "getAllGrabDrivers" then
        -- Get all active drivers to display blips
        local coords = GetEntityCoords(PlayerPedId())
        local drivers = AwaitCallback("grab:getAllDrivers", coords)
        
        -- Flatten coords object to avoid serialize issues
        if drivers then
            for i = 1, #drivers do
                if drivers[i].coords then
                    drivers[i].x = drivers[i].coords.x
                    drivers[i].y = drivers[i].coords.y
                    drivers[i].z = drivers[i].coords.z
                    drivers[i].coords = nil -- Remove nested object
                end
            end
        end
        
        callback(drivers)
        
    elseif action == "showTaxiBlips" then
        -- Show all taxi blips on map
        local coords = GetEntityCoords(PlayerPedId())
        local drivers = AwaitCallback("grab:getAllDrivers", coords)
        createTaxiBlips(drivers)
        callback("ok")
        
    elseif action == "hideTaxiBlips" then
        -- Hide all taxi blips
        removeTaxiBlips()
        callback("ok")
        
    elseif action == "acceptGrabRide" then
        if data.rideId then
            TriggerServerEvent("grab:acceptRide", data.rideId)
        end
        callback("ok")
        
    elseif action == "rejectGrabRide" then
        if data.rideId then
            TriggerServerEvent("grab:rejectRide", data.rideId)
        end
        callback("ok")
        
    elseif action == "arrivedAtPickup" then
        if data.rideId then
            TriggerServerEvent("grab:arrivedAtPickup", data.rideId)
        end
        callback("ok")
        
    else
        callback("ok")
    end
end)

-- Grab Events
RegisterNetEvent("grab:driverStatus", function(status)
    isGrabDriver = status
    SendReactMessage("grab:updateDriverStatus", { isDriver = status })
end)

RegisterNetEvent("grab:rideRequest", function(data)
    if not isGrabDriver then return end
    
    currentRide = data
    
    local message = string.format(
        "~g~[Grab]~w~ Yêu cầu đặt xe mới!\n" ..
        "Khoảng cách: ~y~%dm~w~\n" ..
        "Thu nhập: ~g~$%d~w~\n\n" ..
        "Ấn ~g~[Y]~w~ chấp nhận | ~r~[N]~w~ từ chối",
        data.distance, data.price
    )
    
    TriggerEvent("QBCore:Notify", message, "info", 15000)
    createRideBlip(data.passengerCoords, "~y~Yêu cầu Grab")
    
    local responded = false
    CreateThread(function()
        local timeout = GetGameTimer() + 15000
        
        while GetGameTimer() < timeout and not responded do
            Wait(0)
            
            if IsControlJustReleased(0, 246) then -- Y
                responded = true
                TriggerServerEvent("grab:acceptRide", data.rideId)
            end
            
            if IsControlJustReleased(0, 249) then -- N
                responded = true
                TriggerServerEvent("grab:rejectRide", data.rideId)
                removeRideBlip()
                currentRide = nil
                exports['f17notify']:Notify("Đã từ chối chuyến xe!", "info", 5000)
            end
        end
        
        if not responded then
            TriggerServerEvent("grab:rejectRide", data.rideId)
            removeRideBlip()
            currentRide = nil
        end
    end)
end)

RegisterNetEvent("grab:startNavigation", function(coords)
    createRideBlip(coords, "~g~Grab~w~ - Đón khách")
    
    CreateThread(function()
        while currentRide do
            Wait(1000)
            
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            local distance = #(playerCoords - vector3(coords.x, coords.y, coords.z))
            
            if distance < 10.0 then
                TriggerServerEvent("grab:arrivedAtPickup", currentRide.rideId)
                break
            end
        end
    end)
end)

RegisterNetEvent("grab:clearNavigation", function()
    removeRideBlip()
end)

RegisterNetEvent("grab:rideAccepted", function(data)
    exports['f17notify']:Notify(data.message, "success", 5000)
    SendReactMessage("grab:rideAccepted", data)
    
    -- Create driver blip for passenger
    if data.driverCoords then
        createDriverBlip(data.driverCoords, "~b~Grab~w~ - Tài xế đang đến")
    end
end)

RegisterNetEvent("grab:driverArrived", function()
    exports['f17notify']:Notify("Tài xế đã đến! Chúc bạn đi đường an toàn.", "success", 5000)
    SendReactMessage("grab:driverArrived", {})
    removeDriverBlip() -- Remove driver blip when arrived
end)

RegisterNetEvent("grab:rideCompleted", function(price)
    local message = string.format("~g~[Grab]~w~ Hoàn thành!\nChi phí: ~r~$%d", price)
    TriggerEvent("QBCore:Notify", message, "success", 8000)
    currentRide = nil
    removeDriverBlip() -- Remove driver blip when completed
    SendReactMessage("grab:rideCompleted", { price = price })
end)

RegisterNetEvent("grab:rideCancelled", function(reason)
    exports['f17notify']:Notify(reason or "Chuyến xe đã bị hủy!", "error", 5000)
    removeRideBlip()
    removeDriverBlip() -- Remove driver blip when cancelled
    currentRide = nil
    SendReactMessage("grab:rideCancelled", { reason = reason })
end)

-- Event to update driver location for passenger
RegisterNetEvent("grab:updateDriverLocation", function(coords)
    if driverBlip then
        -- Update driver blip position
        SetBlipCoords(driverBlip, coords.x, coords.y, coords.z)
    end
end)
