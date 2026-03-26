local activeDrivers = {}
local activeRides = {}
local passengerTimers = {}
local QBCore = exports['qb-core']:GetCoreObject()

-------------------------------------------------------------------------------
-- Helper Functions
-------------------------------------------------------------------------------

local function getDistance(c1, c2)
    return #(vector3(c1.x, c1.y, c1.z or 0.0) - vector3(c2.x, c2.y, c2.z or 0.0))
end

local function notify(target, message, type)
    TriggerClientEvent("QBCore:Notify", target, message, type or "info", 8000)
end

local function cleanupRide(rideId)
    local ride = activeRides[rideId]
    if not ride then return end
    
    if activeDrivers[ride.driver] then
        activeDrivers[ride.driver].busy = false
    end
    passengerTimers[rideId] = nil
    activeRides[rideId] = nil
end

local function processPayment(rideId, isTimeout)
    local ride = activeRides[rideId]
    if not ride then return false end

    local Passenger = QBCore.Functions.GetPlayer(ride.passenger)
    local Driver = QBCore.Functions.GetPlayer(ride.driver)
    if not Passenger or not Driver then return false end

    local amount = ride.price
    if Passenger.Functions.GetMoney("tienkhoa") >= amount then
        Passenger.Functions.RemoveMoney("tienkhoa", amount, "grab-payment")
        Driver.Functions.AddMoney("tienkhoa", amount, "grab-payment")

        local suffix = isTimeout and " (Tự động - Hết giờ)" or ""
        notify(ride.passenger, string.format("~r~[Grab]~w~ Đã thanh toán%s!\n- ~r~$%d", suffix, amount), "error")
        notify(ride.driver, string.format("~g~[Grab]~w~ Hoàn thành chuyến xe%s!\n+ ~g~$%d", suffix, amount), "success")
        return true
    else
        local msg = "Giao dịch thất bại: Khách hàng không đủ tiền!"
        notify(ride.passenger, msg, "error")
        notify(ride.driver, msg, "error")
        return false
    end
end

local function findNearestDriver(coords)
    local nearest, minDist = nil, 999999
    for source, driver in pairs(activeDrivers) do
        if not driver.busy and driver.inVehicle then
            local dist = getDistance(coords, driver.coords)
            if dist < minDist then
                minDist, nearest = dist, source
            end
        end
    end
    return nearest, minDist
end

-------------------------------------------------------------------------------
-- Event Handlers
-------------------------------------------------------------------------------

RegisterNetEvent("grab:toggleDriver", function(toggle)
    local src = source
    if toggle then
        activeDrivers[src] = { coords = GetEntityCoords(GetPlayerPed(src)), inVehicle = false, busy = false }
        TriggerClientEvent("grab:driverStatus", src, true)
        exports['f17notify']:Notify(src, "Đã đăng ký chạy Grab thành công!", "success", 5000)
    else
        for id, ride in pairs(activeRides) do
            if ride.driver == src then
                notify(ride.passenger, "Tài xế đã hủy đăng ký!", "error")
                cleanupRide(id)
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
    
    for _, ride in pairs(activeRides) do
        if ride.driver == src and (ride.status == "accepted" or ride.status == "pickedup") then
            TriggerClientEvent("grab:updateDriverLocation", ride.passenger, coords)
            break
        end
    end
end)

BaseCallback("grab:requestRide", function(source, _, data)
    local src = source
    local pCoords = GetEntityCoords(GetPlayerPed(src))
    local dCoords = (type(data) == "table") and data.dropoffCoords or nil
    
    local driverId, dist = findNearestDriver(pCoords)
    if not driverId then return { success = false, message = "Không tìm thấy tài xế Grab gần bạn!" } end
    
    local tripDist = dCoords and getDistance(pCoords, dCoords) or 0
    local price = math.floor((dist + tripDist) * 100)
    local rideId = "GRAB_" .. os.time() .. "_" .. src
    
    activeDrivers[driverId].busy = true
    activeRides[rideId] = {
        passenger = src, driver = driverId, passengerCoords = pCoords,
        dropoffCoords = dCoords, distance = dist, tripDistance = tripDist,
        price = price, status = "waiting"
    }
    
    local Passenger = QBCore.Functions.GetPlayer(src)
    local pName = Passenger and (Passenger.PlayerData.charinfo.firstname .. " " .. Passenger.PlayerData.charinfo.lastname) or "Khách hàng"
    
    TriggerClientEvent("grab:rideRequest", driverId, {
        rideId = rideId, passengerName = pName, passengerCoords = pCoords, dropoffCoords = dCoords,
        distance = math.floor(dist), tripDistance = math.floor(tripDist), price = price
    })
    
    return { success = true, message = "Đang chờ tài xế xác nhận...", rideId = rideId, price = price }
end)

RegisterNetEvent("grab:acceptRide", function(rideId)
    local src, ride = source, activeRides[rideId]
    if not ride or ride.driver ~= src then return end
    
    ride.status = "accepted"
    local Driver = QBCore.Functions.GetPlayer(src)
    local dName = Driver and (Driver.PlayerData.charinfo.firstname .. " " .. Driver.PlayerData.charinfo.lastname) or "Tài xế"
    local dPlate = GetVehicleNumberPlateText(GetVehiclePedIsIn(GetPlayerPed(src), false)) or "N/A"
    
    local acceptData = {
        rideId = rideId,
        message = "Chuyến xe đã được chấp nhận!",
        driverName = dName,
        vehiclePlate = dPlate,
        driverCoords = activeDrivers[src].coords,
        pickupCoords = ride.passengerCoords,
        dropoffCoords = ride.dropoffCoords
    }
    
    TriggerClientEvent("grab:rideAccepted", ride.passenger, acceptData)
    TriggerClientEvent("grab:rideAccepted", src, acceptData)
    TriggerClientEvent("grab:startNavigation", src, ride.passengerCoords)
end)

RegisterNetEvent("grab:rejectRide", function(rideId)
    local src, ride = source, activeRides[rideId]
    if not ride or ride.driver ~= src then return end
    notify(ride.passenger, "Tài xế đã từ chối chuyến xe!", "error")
    cleanupRide(rideId)
end)

RegisterNetEvent("grab:arrivedAtPickup", function(rideId)
    local src, ride = source, activeRides[rideId]
    if not ride or ride.driver ~= src or ride.status ~= "accepted" then return end
    
    ride.status = "arrived"
    TriggerClientEvent("grab:driverArrived", ride.passenger)
    if ride.dropoffCoords then
        TriggerClientEvent("grab:startDropoffNavigation", src, ride.dropoffCoords, ride.passenger)
    end
    exports['f17notify']:Notify(src, "Đã đến điểm đón!", "info", 5000)
end)

RegisterNetEvent("grab:passengerInVehicle", function(rideId)
    local src, ride = source, activeRides[rideId]
    if not ride or ride.driver ~= src then return end
    
    ride.status = "pickedup"
    if passengerTimers[rideId] then
        passengerTimers[rideId] = nil
        TriggerClientEvent("grab:cancelTimer", ride.passenger)
        exports['f17notify']:Notify(src, "Khách đã vào lại xe!", "success", 3000)
    end
end)

RegisterNetEvent("grab:passengerExitVehicle", function(rideId)
    local src, ride = source, activeRides[rideId]
    if not ride or ride.driver ~= src or ride.status ~= "pickedup" or passengerTimers[rideId] then return end
    
    passengerTimers[rideId] = GetGameTimer() + 60000
    TriggerClientEvent("grab:startTimer", ride.passenger, 60)
    exports['f17notify']:Notify(src, "Khách xuống xe! Bắt đầu đếm ngược 60s.", "warning", 5000)
    
    CreateThread(function()
        while passengerTimers[rideId] and GetGameTimer() < passengerTimers[rideId] do Wait(1000) end
        if passengerTimers[rideId] then
            processPayment(rideId, true)
            TriggerClientEvent("grab:clearNavigation", src)
            TriggerClientEvent("grab:rideCompleted", ride.passenger, ride.price)
            TriggerClientEvent("grab:rideCompleted", src, ride.price)
            cleanupRide(rideId)
        end
    end)
end)

RegisterNetEvent("grab:completeRide", function(rideId)
    local src, ride = source, activeRides[rideId]
    if not ride or ride.driver ~= src then return end
    
    local dPed, pPed = GetPlayerPed(src), GetPlayerPed(ride.passenger)
    local veh = GetVehiclePedIsIn(dPed, false)
    
    if veh == 0 or GetVehiclePedIsIn(pPed, false) ~= veh then
        return notify(src, "Cả tài xế và khách phải ở trong xe!", "error")
    end
    
    if ride.dropoffCoords then
        local dist = #(GetEntityCoords(dPed) - vector3(ride.dropoffCoords.x, ride.dropoffCoords.y, ride.dropoffCoords.z or 0.0))
        if dist > 25.0 then return notify(src, "Chưa đến điểm trả! ("..math.floor(dist).."m)", "error") end
    end
    
    if processPayment(rideId, false) then
        TriggerClientEvent("grab:clearNavigation", src)
        TriggerClientEvent("grab:rideCompleted", ride.passenger, ride.price)
        TriggerClientEvent("grab:rideCompleted", src, ride.price)
        cleanupRide(rideId)
    end
end)

RegisterNetEvent("grab:cancelRide", function(rideId)
    local src, ride = source, activeRides[rideId]
    if not ride then return end
    
    local target = (ride.driver == src) and ride.passenger or ride.driver
    local msg = (ride.driver == src) and "Tài xế đã hủy chuyến!" or "Khách đã hủy chuyến!"
    notify(target, msg, "error")
    if ride.driver ~= src then TriggerClientEvent("grab:clearNavigation", ride.driver) end
    cleanupRide(rideId)
end)

-------------------------------------------------------------------------------
-- Callbacks & System Events
-------------------------------------------------------------------------------

BaseCallback("grab:getNearbyDrivers", function(src, _, pCoords)
    local list = {}
    for id, d in pairs(activeDrivers) do
        if id ~= src and not d.busy and d.inVehicle then
            local dist = getDistance(pCoords, d.coords)
            if dist < 1000 then table.insert(list, { coords = d.coords, distance = math.floor(dist) }) end
        end
    end
    return list
end)

BaseCallback("grab:getAllDrivers", function(src, _, pCoords)
    local list = {}
    for id, d in pairs(activeDrivers) do
        if id ~= src and d.inVehicle then
            local dist = pCoords and getDistance(pCoords, d.coords) or 0
            table.insert(list, { coords = d.coords, distance = math.floor(dist), busy = d.busy })
        end
    end
    return list
end)

AddEventHandler("playerDropped", function()
    local src = source
    activeDrivers[src] = nil
    for id, ride in pairs(activeRides) do
        if ride.driver == src or ride.passenger == src then
            local target = (ride.driver == src) and ride.passenger or ride.driver
            notify(target, (ride.driver == src) and "Tài xế ngắt kết nối!" or "Khách ngắt kết nối!", "error")
            cleanupRide(id)
        end
    end
end)