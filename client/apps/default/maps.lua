-- Maps app for LB Phone
-- Handles GPS navigation, waypoints, and saved locations

local isTrackingCoords = false
local currentPlayerPed = PlayerPedId()
local lastCoords = vector3(0, 0, 0)

-- Add a new saved location
local function addSavedLocation(name, coordinates)
    if not name then
        return false
    end
    
    local coords
    if coordinates then
        coords = vector2(coordinates[2], coordinates[1])
    else
        coords = GetEntityCoords(PlayerPedId())
    end
    
    local locationId = AwaitCallback("maps:addLocation", name, coords.x, coords.y)
    if not locationId then
        return false
    end
    
    local newLocation = {
        id = locationId,
        name = name,
        position = {coords.y, coords.x}
    }
    
    SavedLocations[#SavedLocations + 1] = newLocation
    return newLocation
end

-- Update coordinate tracking loop
local function startCoordinateTracking()
    currentPlayerPed = PlayerPedId()
    lastCoords = GetEntityCoords(currentPlayerPed)
    
    -- Send initial coordinates
    SendReactMessage("maps:updateCoords", {
        x = math.floor(lastCoords.x + 0.5),
        y = math.floor(lastCoords.y + 0.5)
    })
    
    -- Coordinate tracking loop
    while isTrackingCoords do
        local currentCoords = GetEntityCoords(currentPlayerPed)
        
        if phoneOpen then
            local distance = #(lastCoords - currentCoords)
            if distance > 1.0 then
                lastCoords = currentCoords
                SendReactMessage("maps:updateCoords", {
                    x = math.floor(currentCoords.x + 0.5),
                    y = math.floor(currentCoords.y + 0.5)
                })
            end
        end
        
        Wait(250)
    end
end
-- Register NUI callback for Maps actions
-- Grab variables
local isGrabDriver = false
local currentRide = nil
local rideBlip = nil
local driverBlip = nil -- Blip để theo dõi tài xế (cho khách hàng)

-- Grab functions
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

RegisterNUICallback("Maps", function(data, callback)
    local action = data.action  
    if action == "getCurrentLocation" then
        -- Get current player coordinates
        local coords = GetEntityCoords(PlayerPedId())
        callback({
            x = coords.x,
            y = coords.y
        })
        
    elseif action == "toggleUpdateCoords" then
        callback("ok")
        
        if isTrackingCoords == data.toggle then
            return
        end
        
        isTrackingCoords = data.toggle == true
        startCoordinateTracking()
        
    elseif action == "setWaypoint" then
        callback("ok")
        
        local coords = data.data
        local x = tonumber(coords.x)
        local y = tonumber(coords.y)
        
        if not x or not y then
            return
        end
        
        SetNewWaypoint(x / 1, y / 1)
        
    elseif action == "getLocations" then
        -- Get all saved locations
        callback(SavedLocations)
        
    elseif action == "addLocation" then
        -- Add new saved location
        callback(addSavedLocation(data.name, data.location))
        
    elseif action == "renameLocation" then
        -- Rename existing location
        local newName = data.name
        if not newName then
            return callback(false)
        end
        
        local success = AwaitCallback("maps:renameLocation", data.id, newName)
        if not success then
            return callback(false)
        end
        
        -- Update local saved locations
        for i = 1, #SavedLocations do
            if SavedLocations[i].id == data.id then
                SavedLocations[i].name = newName
                break
            end
        end
        
        callback(true)
        
    elseif action == "removeLocation" then
        -- Remove saved location
        local success = AwaitCallback("maps:removeLocation", data.id)
        if not success then
            return callback(false)
        end
        
        -- Remove from local saved locations
        for i = 1, #SavedLocations do
            if SavedLocations[i].id == data.id then
                table.remove(SavedLocations, i)
                break
            end
        end
        
        callback(true)
        
    -- Grab actions
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
        -- Lấy tất cả tài xế đang hoạt động để hiển thị blip
        local coords = GetEntityCoords(PlayerPedId())
        local drivers = AwaitCallback("grab:getAllDrivers", coords)
        
        -- Flatten coords object để tránh vấn đề serialize
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
        -- Hiển thị blip tất cả taxi trên bản đồ
        local coords = GetEntityCoords(PlayerPedId())
        local drivers = AwaitCallback("grab:getAllDrivers", coords)
        createTaxiBlips(drivers)
        callback("ok")
        
    elseif action == "hideTaxiBlips" then
        -- Ẩn tất cả blip taxi
        removeTaxiBlips()
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
    
    -- Tạo blip tài xế cho khách hàng
    if data.driverCoords then
        createDriverBlip(data.driverCoords, "~b~Grab~w~ - Tài xế đang đến")
    end
end)

RegisterNetEvent("grab:driverArrived", function()
    exports['f17notify']:Notify("Tài xế đã đến! Chúc bạn đi đường an toàn.", "success", 5000)
    SendReactMessage("grab:driverArrived", {})
    removeDriverBlip() -- Xóa blip tài xế khi đã đến
end)

RegisterNetEvent("grab:rideCompleted", function(price)
    local message = string.format("~g~[Grab]~w~ Hoàn thành!\nChi phí: ~r~$%d", price)
    TriggerEvent("QBCore:Notify", message, "success", 8000)
    currentRide = nil
    removeDriverBlip() -- Xóa blip tài xế khi hoàn thành
    SendReactMessage("grab:rideCompleted", { price = price })
end)

RegisterNetEvent("grab:rideCancelled", function(reason)
    exports['f17notify']:Notify(reason or "Chuyến xe đã bị hủy!", "error", 5000)
    removeRideBlip()
    removeDriverBlip() -- Xóa blip tài xế khi hủy chuyến
    currentRide = nil
    SendReactMessage("grab:rideCancelled", { reason = reason })
end)

-- Event mới để cập nhật vị trí tài xế cho khách hàng
RegisterNetEvent("grab:updateDriverLocation", function(coords)
    if driverBlip then
        -- Cập nhật vị trí blip tài xế
        SetBlipCoords(driverBlip, coords.x, coords.y, coords.z)
    end
end)