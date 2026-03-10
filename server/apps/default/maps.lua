
-- Grab system variables
local activeDrivers = {} -- {source, coords, inVehicle, busy}
local activeRides = {} -- {passenger, driver, coords, distance, price, status}

-- Grab helper functions
local function getDistance(coords1, coords2)
    return #(vector3(coords1.x, coords1.y, coords1.z) - vector3(coords2.x, coords2.y, coords2.z))
end

local function findNearestDriver(passengerCoords)
    local nearestDriver = nil
    local minDistance = 999999
    
    for source, driver in pairs(activeDrivers) do
        if not driver.busy and driver.inVehicle then
            local distance = getDistance(passengerCoords, driver.coords)
            if distance < minDistance then
                minDistance = distance
                nearestDriver = source
            end
        end
    end
    
    return nearestDriver, minDistance
end

BaseCallback("maps:getSavedLocations", function(source, phoneNumber)
    local locations = MySQL.query.await(
    "SELECT id, `name`, x_pos, y_pos FROM phone_maps_locations WHERE phone_number = ? ORDER BY `name` ASC", { phoneNumber })


    for i = 1, #locations do
        local location = locations[i]
        locations[i] = {
            id = location.id,
            name = location.name,
            position = { location.y_pos, location.x_pos }
        }
    end


    return (locations)
end)


BaseCallback("maps:addLocation", function(source, phoneNumber, locationName, xPos, yPos)
    local locationId = MySQL.insert.await(
    "INSERT INTO phone_maps_locations (phone_number, `name`, x_pos, y_pos) VALUES (?, ?, ?, ?)", {
        phoneNumber,
        locationName,
        xPos,
        yPos
    })
    return (locationId)
end)


BaseCallback("maps:renameLocation", function(source, phoneNumber, locationId, newName)
    local success = MySQL.update.await("UPDATE phone_maps_locations SET `name` = ? WHERE id = ? AND phone_number = ?", {
        newName,
        locationId,
        phoneNumber
    })
    return (success > 0)
end)


BaseCallback("maps:removeLocation", function(source, phoneNumber, locationId)
    local success = MySQL.update.await("DELETE FROM phone_maps_locations WHERE id = ? AND phone_number = ?", {
        locationId,
        phoneNumber
    })
    return (success > 0)
end)
-- Grab Server Events
RegisterNetEvent("grab:toggleDriver", function(toggle)
    local src = source
    
    if toggle then
        local ped = GetPlayerPed(src)
        local coords = GetEntityCoords(ped)
        
        activeDrivers[src] = {
            coords = coords,
            inVehicle = false,
            busy = false
        }
        
        TriggerClientEvent("grab:driverStatus", src, true)
        exports['f17notify']:Notify(src, "Đã đăng ký chạy Grab thành công!", "success", 5000)
    else
        activeDrivers[src] = nil
        TriggerClientEvent("grab:driverStatus", src, false)
        exports['f17notify']:Notify(src, "Đã hủy đăng ký chạy Grab!", "info", 5000)
    end
end)

RegisterNetEvent("grab:updateDriverLocation", function(coords, inVehicle)
    local src = source
    
    if activeDrivers[src] then
        activeDrivers[src].coords = coords
        activeDrivers[src].inVehicle = inVehicle
        
        -- Tìm chuyến xe mà tài xế này đang phục vụ
        for rideId, ride in pairs(activeRides) do
            if ride.driver == src and (ride.status == "accepted" or ride.status == "pickedup") then
                -- Gửi vị trí tài xế cho khách hàng
                TriggerClientEvent("grab:updateDriverLocation", ride.passenger, coords)
                break
            end
        end
    end
end)

BaseCallback("grab:requestRide", function(source, phoneNumber, passengerCoords)
    local src = source
    
    local driverSource, distance = findNearestDriver(passengerCoords)
    
    if not driverSource then
        return { success = false, message = "Không tìm thấy tài xế Grab gần bạn!" }
    end
    
    local estimatedPrice = math.floor(distance * 100)
    activeDrivers[driverSource].busy = true
    
    local rideId = "GRAB_" .. os.time() .. "_" .. src
    
    activeRides[rideId] = {
        passenger = src,
        driver = driverSource,
        passengerCoords = passengerCoords,
        distance = distance,
        price = estimatedPrice,
        status = "waiting"
    }
    
    TriggerClientEvent("grab:rideRequest", driverSource, {
        rideId = rideId,
        passengerCoords = passengerCoords,
        distance = math.floor(distance),
        price = estimatedPrice
    })
    
    return { 
        success = true, 
        message = "Đã tìm thấy tài xế! Đang chờ xác nhận...",
        rideId = rideId,
        distance = math.floor(distance),
        price = estimatedPrice
    }
end)

RegisterNetEvent("grab:acceptRide", function(rideId)
    local src = source
    
    if not activeRides[rideId] then return end
    
    local ride = activeRides[rideId]
    
    if ride.driver ~= src then return end
    
    ride.status = "accepted"
    
    -- Lấy vị trí hiện tại của tài xế
    local driverCoords = activeDrivers[src] and activeDrivers[src].coords or nil
    
    TriggerClientEvent("grab:rideAccepted", ride.passenger, {
        rideId = rideId,
        message = "Tài xế đã chấp nhận! Đang trên đường đến...",
        driverCoords = driverCoords -- Gửi vị trí tài xế cho khách hàng
    })
    
    TriggerClientEvent("grab:startNavigation", src, ride.passengerCoords)
    exports['f17notify']:Notify(src, "Đã chấp nhận chuyến xe! Hãy đến đón khách.", "success", 5000)
end)

RegisterNetEvent("grab:rejectRide", function(rideId)
    local src = source
    
    if not activeRides[rideId] then return end
    
    local ride = activeRides[rideId]
    
    if ride.driver == src then
        if activeDrivers[src] then
            activeDrivers[src].busy = false
        end
        
        TriggerClientEvent("grab:rideCancelled", ride.passenger, "Tài xế đã từ chối chuyến xe!")
        activeRides[rideId] = nil
    end
end)

RegisterNetEvent("grab:arrivedAtPickup", function(rideId)
    local src = source
    
    if not activeRides[rideId] then return end
    
    local ride = activeRides[rideId]
    
    if ride.driver == src and ride.status == "accepted" then
        ride.status = "pickedup"
        
        TriggerClientEvent("grab:driverArrived", ride.passenger)
        TriggerClientEvent("grab:clearNavigation", src)
        
        exports['f17notify']:Notify(src, "Đã đến điểm đón khách! Chuyến xe bắt đầu.", "success", 5000)
    end
end)

RegisterNetEvent("grab:completeRide", function(rideId)
    local src = source
    
    if not activeRides[rideId] then return end
    
    local ride = activeRides[rideId]
    
    if ride.driver == src then
        ride.status = "completed"
        
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            Player.Functions.AddMoney("cash", ride.price, "grab-ride-payment")
            
            local notifyText = "~g~[Grab]~w~ Hoàn thành chuyến xe!\n+ ~g~$"..ride.price.." Tiền mặt"
            TriggerClientEvent("QBCore:Notify", src, notifyText, "success", 8000)
        end
        
        TriggerClientEvent("grab:rideCompleted", ride.passenger, ride.price)
        
        if activeDrivers[src] then
            activeDrivers[src].busy = false
        end
        
        activeRides[rideId] = nil
    end
end)

RegisterNetEvent("grab:cancelRide", function(rideId)
    local src = source
    
    if not activeRides[rideId] then return end
    
    local ride = activeRides[rideId]
    
    if ride.driver == src or ride.passenger == src then
        if ride.driver == src then
            TriggerClientEvent("grab:rideCancelled", ride.passenger, "Tài xế đã hủy chuyến!")
        else
            TriggerClientEvent("grab:rideCancelled", ride.driver, "Khách hàng đã hủy chuyến!")
        end
        
        if activeDrivers[ride.driver] then
            activeDrivers[ride.driver].busy = false
        end
        
        activeRides[rideId] = nil
    end
end)

BaseCallback("grab:getNearbyDrivers", function(source, phoneNumber, passengerCoords)
    local nearbyList = {}
    
    for driverSource, driver in pairs(activeDrivers) do
        if not driver.busy and driver.inVehicle then
            local distance = getDistance(passengerCoords, driver.coords)
            if distance < 1000 then -- Trong bán kính 1km
                table.insert(nearbyList, {
                    coords = driver.coords,
                    distance = math.floor(distance)
                })
            end
        end
    end
    
    return nearbyList
end)

BaseCallback("grab:getAllDrivers", function(source, phoneNumber, passengerCoords)
    local driversList = {}
    
    -- Debug: đếm số drivers
    local count = 0
    for k, v in pairs(activeDrivers) do
        count = count + 1
    end 
    for driverSource, driver in pairs(activeDrivers) do
        if driver.inVehicle then -- Hiển thị tất cả tài xế đang trong xe
            local distance = passengerCoords and getDistance(passengerCoords, driver.coords) or 0
            table.insert(driversList, {
                coords = driver.coords,
                distance = math.floor(distance),
                busy = driver.busy
            })
        end
    end
    return driversList
end)

-- Handle player disconnect
AddEventHandler("playerDropped", function()
    local src = source
    
    if activeDrivers[src] then
        activeDrivers[src] = nil
    end
    
    for rideId, ride in pairs(activeRides) do
        if ride.driver == src then
            TriggerClientEvent("grab:rideCancelled", ride.passenger, "Tài xế đã ngắt kết nối!")
            activeRides[rideId] = nil
        elseif ride.passenger == src then
            if activeDrivers[ride.driver] then
                activeDrivers[ride.driver].busy = false
            end
            TriggerClientEvent("grab:rideCancelled", ride.driver, "Khách hàng đã hủy chuyến!")
            activeRides[rideId] = nil
        end
    end
end)