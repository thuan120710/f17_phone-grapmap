-- Grab App Server
-- Server-side logic for Grab ride-sharing service

-- Grab system variables
local activeDrivers = {} -- {source, coords, inVehicle, busy}
local activeRides = {} -- {passenger, driver, coords, distance, price, status}

-- Grab helper functions
local function getDistance(coords1, coords2)
    local z1 = coords1.z or 0.0
    local z2 = coords2.z or 0.0
    return #(vector3(coords1.x, coords1.y, z1) - vector3(coords2.x, coords2.y, z2))
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
        -- Hủy tất cả chuyến xe đang thực hiện khi tài xế hủy đăng ký
        for rideId, ride in pairs(activeRides) do
            if ride.driver == src then
                TriggerClientEvent("grab:rideCancelled", ride.passenger, "Tài xế đã hủy đăng ký!")
                activeRides[rideId] = nil
            end
        end
        
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
        
        -- Find the ride this driver is serving
        for rideId, ride in pairs(activeRides) do
            if ride.driver == src and (ride.status == "accepted" or ride.status == "pickedup") then
                -- Send driver location to passenger
                TriggerClientEvent("grab:updateDriverLocation", ride.passenger, coords)
                break
            end
        end
    end
end)

BaseCallback("grab:requestRide", function(source, phoneNumber, requestData)
    local src = source
    
    print("[GRAB DEBUG] Raw requestData type:", type(requestData))
    print("[GRAB DEBUG] Raw requestData:", json.encode(requestData))
    
    -- Lấy tọa độ thực của khách (3D) thay vì từ UI (2D)
    local passengerCoords = GetEntityCoords(GetPlayerPed(src))
    local dropoffCoords = nil
    
    -- Xử lý dropoffCoords từ UI
    if type(requestData) == "table" and requestData.dropoffCoords then
        dropoffCoords = requestData.dropoffCoords
    end
    
    print("[GRAB DEBUG] Pickup coords (3D thực):", json.encode(passengerCoords))
    print("[GRAB DEBUG] Dropoff coords (2D từ UI):", json.encode(dropoffCoords))
    
    local driverSource, distance = findNearestDriver(passengerCoords)
    
    if not driverSource then
        return { success = false, message = "Không tìm thấy tài xế Grab gần bạn!" }
    end
    
    -- Tính khoảng cách từ điểm đón đến điểm trả
    local tripDistance = 0
    if dropoffCoords then
        tripDistance = getDistance(passengerCoords, dropoffCoords)
        print("[GRAB DEBUG] Trip distance:", tripDistance)
    end
    
    local estimatedPrice = math.floor((distance + tripDistance) * 100)
    activeDrivers[driverSource].busy = true
    
    local rideId = "GRAB_" .. os.time() .. "_" .. src
    
    activeRides[rideId] = {
        passenger = src,
        driver = driverSource,
        passengerCoords = passengerCoords, -- Tọa độ 3D thực
        dropoffCoords = dropoffCoords, -- Lưu điểm trả
        distance = distance,
        tripDistance = tripDistance,
        price = estimatedPrice,
        status = "waiting"
    }
    
    print("[GRAB DEBUG] Saved ride with dropoffCoords:", json.encode(activeRides[rideId].dropoffCoords))
    
    TriggerClientEvent("grab:rideRequest", driverSource, {
        rideId = rideId,
        passengerCoords = passengerCoords, -- Gửi tọa độ 3D thực
        dropoffCoords = dropoffCoords, -- Gửi điểm trả cho tài xế
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
    
    if not activeRides[rideId] then return end
    
    local ride = activeRides[rideId]
    
    if ride.driver ~= src then return end
    
    ride.status = "accepted"
    
    -- Get current driver location
    local driverCoords = activeDrivers[src] and activeDrivers[src].coords or nil
    
    TriggerClientEvent("grab:rideAccepted", ride.passenger, {
        rideId = rideId,
        message = "Tài xế đã chấp nhận! Đang trên đường đến...",
        driverCoords = driverCoords, -- Send driver location to passenger
        dropoffCoords = ride.dropoffCoords -- Gửi điểm trả cho khách
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
    
    print("[GRAB DEBUG SERVER] arrivedAtPickup called by", src, "for ride", rideId)
    
    if not activeRides[rideId] then 
        print("[GRAB DEBUG SERVER] Ride not found:", rideId)
        return 
    end
    
    local ride = activeRides[rideId]
    
    if ride.driver == src and ride.status == "accepted" then
        -- KHÔNG chuyển status sang pickedup ngay, giữ status = "arrived"
        ride.status = "arrived"
        
        print("[GRAB DEBUG SERVER] Status updated to arrived (waiting for passenger)")
        
        -- Thông báo cho khách
        TriggerClientEvent("grab:driverArrived", ride.passenger)
        
        -- KHÔNG xóa blip điểm đón, gửi thông tin để client xử lý
        if ride.dropoffCoords then
            print("[GRAB DEBUG SERVER] Gửi dropoffCoords cho tài xế (chờ khách vào xe):", json.encode(ride.dropoffCoords))
            -- Gửi cả passengerId để client check
            TriggerClientEvent("grab:startDropoffNavigation", src, ride.dropoffCoords, ride.passenger)
            exports['f17notify']:Notify(src, "Đã đến điểm đón! Đợi khách vào xe.", "info", 5000)
        else
            print("[GRAB DEBUG SERVER] Không có dropoffCoords!")
            exports['f17notify']:Notify(src, "Đã đến điểm đón khách!", "info", 5000)
        end
    else
        print("[GRAB DEBUG SERVER] Invalid status or driver. Status:", ride.status, "Driver:", ride.driver, "Source:", src)
    end
end)

-- Event mới: Khi khách đã vào xe
RegisterNetEvent("grab:passengerInVehicle", function(rideId)
    local src = source
    
    print("[GRAB DEBUG SERVER] passengerInVehicle called by", src, "for ride", rideId)
    
    if not activeRides[rideId] then 
        print("[GRAB DEBUG SERVER] Ride not found:", rideId)
        return 
    end
    
    local ride = activeRides[rideId]
    
    if ride.driver == src and ride.status == "arrived" then
        -- Bây giờ mới chuyển status sang pickedup
        ride.status = "pickedup"
        print("[GRAB DEBUG SERVER] Status updated to pickedup (passenger in vehicle)")
    end
end)

RegisterNetEvent("grab:completeRide", function(rideId)
    local src = source
    
    print("[GRAB DEBUG SERVER] completeRide called by", src, "for ride", rideId)
    
    if not activeRides[rideId] then 
        print("[GRAB DEBUG SERVER] Ride not found:", rideId)
        TriggerClientEvent("QBCore:Notify", src, "Không tìm thấy chuyến xe!", "error", 5000)
        return 
    end
    
    local ride = activeRides[rideId]
    
    -- Kiểm tra đúng tài xế
    if ride.driver ~= src then
        print("[GRAB DEBUG SERVER] Driver mismatch. Expected:", ride.driver, "Got:", src)
        TriggerClientEvent("QBCore:Notify", src, "Bạn không phải tài xế của chuyến này!", "error", 5000)
        return
    end
    
    -- Kiểm tra status phải là pickedup (đã đón khách) hoặc arrived (đã đến điểm đón)
    if ride.status ~= "pickedup" and ride.status ~= "arrived" then
        print("[GRAB DEBUG SERVER] Invalid status:", ride.status)
        TriggerClientEvent("QBCore:Notify", src, "Bạn chưa đến điểm đón khách!", "error", 5000)
        return
    end
    
    -- Lấy QBCore
    local QBCore = exports['qb-core']:GetCoreObject()
    
    -- Kiểm tra khách có trên xe không
    local driverPed = GetPlayerPed(src)
    local driverVehicle = GetVehiclePedIsIn(driverPed, false)
    
    if driverVehicle == 0 then
        print("[GRAB DEBUG SERVER] Driver not in vehicle")
        TriggerClientEvent("QBCore:Notify", src, "Bạn phải ở trong xe!", "error", 5000)
        return
    end
    
    -- Kiểm tra khách có trong cùng xe không
    local passengerPed = GetPlayerPed(ride.passenger)
    local passengerVehicle = GetVehiclePedIsIn(passengerPed, false)
    
    if passengerVehicle ~= driverVehicle then
        print("[GRAB DEBUG SERVER] Passenger not in same vehicle. Driver vehicle:", driverVehicle, "Passenger vehicle:", passengerVehicle)
        TriggerClientEvent("QBCore:Notify", src, "Khách hàng không ở trên xe của bạn!", "error", 5000)
        return
    end
    
    -- Kiểm tra có đến đúng điểm trả không
    if ride.dropoffCoords then
        local driverCoords = GetEntityCoords(driverPed)
        local dropoffCoords = ride.dropoffCoords
        local z = dropoffCoords.z or 0.0
        local distance = #(driverCoords - vector3(dropoffCoords.x, dropoffCoords.y, z))
        
        print("[GRAB DEBUG SERVER] Distance to dropoff:", distance)
        
        if distance > 20.0 then
            print("[GRAB DEBUG SERVER] Too far from dropoff point")
            TriggerClientEvent("QBCore:Notify", src, "Bạn chưa đến điểm trả khách! (Còn "..math.floor(distance).."m)", "error", 5000)
            return
        end
    end
    
    -- Tất cả điều kiện đã thỏa mãn, tiến hành thanh toán
    ride.status = "completed"
    
    print("[GRAB DEBUG SERVER] All checks passed, processing payment", ride.price)
    
    -- Trừ tiền khách trước
    local Passenger = QBCore.Functions.GetPlayer(ride.passenger)
    if Passenger then
        local passengerMoney = Passenger.Functions.GetMoney("tienkhoa")
        if passengerMoney >= ride.price then
            Passenger.Functions.RemoveMoney("tienkhoa", ride.price, "grab-ride-payment")
            
            local passengerNotify = "~r~[Grab]~w~ Đã thanh toán chuyến xe!\n- ~r~$"..ride.price.." Tiền mặt"
            TriggerClientEvent("QBCore:Notify", ride.passenger, passengerNotify, "error", 8000)
            
            -- Sau đó cộng tiền cho tài xế
            local Driver = QBCore.Functions.GetPlayer(src)
            if Driver then
                Driver.Functions.AddMoney("tienkhoa", ride.price, "grab-ride-payment")
                
                local driverNotify = "~g~[Grab]~w~ Hoàn thành chuyến xe!\n+ ~g~$"..ride.price.." Tiền mặt"
                TriggerClientEvent("QBCore:Notify", src, driverNotify, "success", 8000)
            end
        else
            -- Khách không đủ tiền
            TriggerClientEvent("QBCore:Notify", ride.passenger, "Bạn không đủ tiền để thanh toán chuyến xe!", "error", 8000)
            TriggerClientEvent("QBCore:Notify", src, "Khách hàng không đủ tiền thanh toán!", "error", 8000)
        end
    end
    
    -- Clear navigation cho tài xế
    TriggerClientEvent("grab:clearNavigation", src)
    
    -- Thông báo cho cả tài xế và khách
    TriggerClientEvent("grab:rideCompleted", ride.passenger, ride.price)
    TriggerClientEvent("grab:rideCompleted", src, ride.price) -- Gửi cho tài xế để xóa blip
    
    if activeDrivers[src] then
        activeDrivers[src].busy = false
    end
    
    activeRides[rideId] = nil
    print("[GRAB DEBUG SERVER] Ride completed successfully")
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
            -- Xóa blip cho tài xế khi khách hủy
            TriggerClientEvent("grab:clearNavigation", ride.driver)
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
            if distance < 1000 then -- Within 1km radius
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
    
    for driverSource, driver in pairs(activeDrivers) do
        if driver.inVehicle then -- Show all drivers in vehicles
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