-- Grab App Server
-- Server-side logic for Grab ride-sharing service

local activeDrivers = {} -- {coords, inVehicle, busy}
local activeRides = {} -- {passenger, driver, passengerCoords, dropoffCoords, distance, tripDistance, price, status}
local QBCore = exports['qb-core']:GetCoreObject()

-- Helper Functions
local function getDistance(coords1, coords2)
    local z1 = coords1.z or 0.0
    local z2 = coords2.z or 0.0
    return #(vector3(coords1.x, coords1.y, z1) - vector3(coords2.x, coords2.y, z2))
end

local function findNearestDriver(passengerCoords)
    local nearestDriver, minDistance = nil, 999999
    
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

local function cleanupRide(rideId)
    local ride = activeRides[rideId]
    if ride and activeDrivers[ride.driver] then
        activeDrivers[ride.driver].busy = false
    end
    activeRides[rideId] = nil
end

-- Server Events
RegisterNetEvent("grab:toggleDriver", function(toggle)
    local src = source
    
    if toggle then
        activeDrivers[src] = {
            coords = GetEntityCoords(GetPlayerPed(src)),
            inVehicle = false,
            busy = false
        }
        TriggerClientEvent("grab:driverStatus", src, true)
        exports['f17notify']:Notify(src, "Đã đăng ký chạy Grab thành công!", "success", 5000)
    else
        for rideId, ride in pairs(activeRides) do
            if ride.driver == src then
                TriggerClientEvent("grab:rideCancelled", ride.passenger, "Tài xế đã hủy đăng ký!")
                cleanupRide(rideId)
            end
        end
        activeDrivers[src] = nil
        TriggerClientEvent("grab:driverStatus", src, false)
        exports['f17notify']:Notify(src, "Đã hủy đăng ký chạy Grab!", "info", 5000)
    end
end)

RegisterNetEvent("grab:updateDriverLocation", function(coords, inVehicle)
    local src = source
    if not activeDrivers[src] then return end
    
    activeDrivers[src].coords = coords
    activeDrivers[src].inVehicle = inVehicle
    
    for rideId, ride in pairs(activeRides) do
        if ride.driver == src and (ride.status == "accepted" or ride.status == "pickedup") then
            TriggerClientEvent("grab:updateDriverLocation", ride.passenger, coords)
            break
        end
    end
end)

BaseCallback("grab:requestRide", function(source, phoneNumber, requestData)
    local src = source
    local passengerCoords = GetEntityCoords(GetPlayerPed(src))
    local dropoffCoords = (type(requestData) == "table") and requestData.dropoffCoords or nil
    
    local driverSource, distance = findNearestDriver(passengerCoords)
    if not driverSource then
        return { success = false, message = "Không tìm thấy tài xế Grab gần bạn!" }
    end
    
    local tripDistance = dropoffCoords and getDistance(passengerCoords, dropoffCoords) or 0
    local estimatedPrice = math.floor((distance + tripDistance) * 100)
    
    activeDrivers[driverSource].busy = true
    
    local rideId = "GRAB_" .. os.time() .. "_" .. src
    activeRides[rideId] = {
        passenger = src,
        driver = driverSource,
        passengerCoords = passengerCoords,
        dropoffCoords = dropoffCoords,
        distance = distance,
        tripDistance = tripDistance,
        price = estimatedPrice,
        status = "waiting"
    }
    
    TriggerClientEvent("grab:rideRequest", driverSource, {
        rideId = rideId,
        passengerCoords = passengerCoords,
        dropoffCoords = dropoffCoords,
        distance = math.floor(distance),
        tripDistance = math.floor(tripDistance),
        price = estimatedPrice
    })
    
    return { 
        success = true, 
        message = "Đã tìm thấy tài xế! Đang chờ xác nhận...",
        rideId = rideId,
        distance = math.floor(distance),
        tripDistance = math.floor(tripDistance),
        price = estimatedPrice
    }
end)

RegisterNetEvent("grab:acceptRide", function(rideId)
    local src = source
    local ride = activeRides[rideId]
    if not ride or ride.driver ~= src then return end
    
    ride.status = "accepted"
    local driverCoords = activeDrivers[src] and activeDrivers[src].coords or nil
    
    TriggerClientEvent("grab:rideAccepted", ride.passenger, {
        rideId = rideId,
        message = "Tài xế đã chấp nhận! Đang trên đường đến...",
        driverCoords = driverCoords,
        dropoffCoords = ride.dropoffCoords
    })
    
    TriggerClientEvent("grab:startNavigation", src, ride.passengerCoords)
    exports['f17notify']:Notify(src, "Đã chấp nhận chuyến xe! Hãy đến đón khách.", "success", 5000)
end)

RegisterNetEvent("grab:rejectRide", function(rideId)
    local src = source
    local ride = activeRides[rideId]
    if not ride or ride.driver ~= src then return end
    
    TriggerClientEvent("grab:rideCancelled", ride.passenger, "Tài xế đã từ chối chuyến xe!")
    cleanupRide(rideId)
end)

RegisterNetEvent("grab:arrivedAtPickup", function(rideId)
    local src = source
    local ride = activeRides[rideId]
    if not ride or ride.driver ~= src or ride.status ~= "accepted" then return end
    
    ride.status = "arrived"
    TriggerClientEvent("grab:driverArrived", ride.passenger)
    
    if ride.dropoffCoords then
        TriggerClientEvent("grab:startDropoffNavigation", src, ride.dropoffCoords, ride.passenger)
        exports['f17notify']:Notify(src, "Đã đến điểm đón! Đợi khách vào xe.", "info", 5000)
    else
        exports['f17notify']:Notify(src, "Đã đến điểm đón khách!", "info", 5000)
    end
end)

RegisterNetEvent("grab:passengerInVehicle", function(rideId)
    local src = source
    local ride = activeRides[rideId]
    if not ride or ride.driver ~= src or ride.status ~= "arrived" then return end
    
    ride.status = "pickedup"
end)

RegisterNetEvent("grab:completeRide", function(rideId)
    local src = source
    local ride = activeRides[rideId]
    
    if not ride then
        TriggerClientEvent("QBCore:Notify", src, "Không tìm thấy chuyến xe!", "error", 5000)
        return
    end
    
    if ride.driver ~= src then
        TriggerClientEvent("QBCore:Notify", src, "Bạn không phải tài xế của chuyến này!", "error", 5000)
        return
    end
    
    if ride.status ~= "pickedup" and ride.status ~= "arrived" then
        TriggerClientEvent("QBCore:Notify", src, "Bạn chưa đến điểm đón khách!", "error", 5000)
        return
    end
    
    local driverPed = GetPlayerPed(src)
    local driverVehicle = GetVehiclePedIsIn(driverPed, false)
    
    if driverVehicle == 0 then
        TriggerClientEvent("QBCore:Notify", src, "Bạn phải ở trong xe!", "error", 5000)
        return
    end
    
    local passengerPed = GetPlayerPed(ride.passenger)
    local passengerVehicle = GetVehiclePedIsIn(passengerPed, false)
    
    if passengerVehicle ~= driverVehicle then
        TriggerClientEvent("QBCore:Notify", src, "Khách hàng không ở trên xe của bạn!", "error", 5000)
        return
    end
    
    if ride.dropoffCoords then
        local driverCoords = GetEntityCoords(driverPed)
        local distance = #(driverCoords - vector3(ride.dropoffCoords.x, ride.dropoffCoords.y, ride.dropoffCoords.z or 0.0))
        
        if distance > 20.0 then
            TriggerClientEvent("QBCore:Notify", src, "Bạn chưa đến điểm trả khách! (Còn "..math.floor(distance).."m)", "error", 5000)
            return
        end
    end
    
    ride.status = "completed"
    
    local Passenger = QBCore.Functions.GetPlayer(ride.passenger)
    if Passenger then
        local passengerMoney = Passenger.Functions.GetMoney("tienkhoa")
        if passengerMoney >= ride.price then
            Passenger.Functions.RemoveMoney("tienkhoa", ride.price, "grab-ride-payment")
            
            local passengerNotify = "~r~[Grab]~w~ Đã thanh toán chuyến xe!\n- ~r~$"..ride.price.." Tiền mặt"
            TriggerClientEvent("QBCore:Notify", ride.passenger, passengerNotify, "error", 8000)
            
            local Driver = QBCore.Functions.GetPlayer(src)
            if Driver then
                Driver.Functions.AddMoney("tienkhoa", ride.price, "grab-ride-payment")
                
                local driverNotify = "~g~[Grab]~w~ Hoàn thành chuyến xe!\n+ ~g~$"..ride.price.." Tiền mặt"
                TriggerClientEvent("QBCore:Notify", src, driverNotify, "success", 8000)
            end
        else
            TriggerClientEvent("QBCore:Notify", ride.passenger, "Bạn không đủ tiền để thanh toán chuyến xe!", "error", 8000)
            TriggerClientEvent("QBCore:Notify", src, "Khách hàng không đủ tiền thanh toán!", "error", 8000)
        end
    end
    
    TriggerClientEvent("grab:clearNavigation", src)
    TriggerClientEvent("grab:rideCompleted", ride.passenger, ride.price)
    TriggerClientEvent("grab:rideCompleted", src, ride.price)
    
    cleanupRide(rideId)
end)

RegisterNetEvent("grab:cancelRide", function(rideId)
    local src = source
    local ride = activeRides[rideId]
    if not ride then return end
    
    if ride.driver == src then
        TriggerClientEvent("grab:rideCancelled", ride.passenger, "Tài xế đã hủy chuyến!")
    elseif ride.passenger == src then
        TriggerClientEvent("grab:rideCancelled", ride.driver, "Khách hàng đã hủy chuyến!")
        TriggerClientEvent("grab:clearNavigation", ride.driver)
    end
    
    cleanupRide(rideId)
end)

BaseCallback("grab:getNearbyDrivers", function(source, phoneNumber, passengerCoords)
    local src = source
    local nearbyList = {}
    
    for driverSource, driver in pairs(activeDrivers) do
        -- Bỏ qua chính người dùng yêu cầu để tránh marker trùng lặp
        if driverSource ~= src and not driver.busy and driver.inVehicle then
            local distance = getDistance(passengerCoords, driver.coords)
            if distance < 1000 then
                nearbyList[#nearbyList + 1] = {
                    coords = driver.coords,
                    distance = math.floor(distance)
                }
            end
        end
    end
    return nearbyList
end)

BaseCallback("grab:getAllDrivers", function(source, phoneNumber, passengerCoords)
    local src = source
    local driversList = {}
    
    for driverSource, driver in pairs(activeDrivers) do
        -- Bỏ qua chính người dùng yêu cầu để tránh marker trùng lặp
        if driverSource ~= src and driver.inVehicle then
            local distance = passengerCoords and getDistance(passengerCoords, driver.coords) or 0
            driversList[#driversList + 1] = {
                coords = driver.coords,
                distance = math.floor(distance),
                busy = driver.busy
            }
        end
    end
    return driversList
end)

AddEventHandler("playerDropped", function()
    local src = source
    
    if activeDrivers[src] then
        activeDrivers[src] = nil
    end
    
    for rideId, ride in pairs(activeRides) do
        if ride.driver == src then
            TriggerClientEvent("grab:rideCancelled", ride.passenger, "Tài xế đã ngắt kết nối!")
            cleanupRide(rideId)
        elseif ride.passenger == src then
            TriggerClientEvent("grab:rideCancelled", ride.driver, "Khách hàng đã hủy chuyến!")
            cleanupRide(rideId)
        end
    end
end)