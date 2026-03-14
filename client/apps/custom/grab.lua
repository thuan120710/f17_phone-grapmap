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
        local z = driver.coords.z or 0.0
        local blip = AddBlipForCoord(driver.coords.x, driver.coords.y, z)
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
    local z = coords.z or 0.0
    driverBlip = AddBlipForCoord(coords.x, coords.y, z)
    SetBlipSprite(driverBlip, 280) -- Taxi icon
    SetBlipDisplay(driverBlip, 4)
    SetBlipScale(driverBlip, 0.8)
    SetBlipAsShortRange(driverBlip, false)
    SetBlipColour(driverBlip, 3) -- Blue for driver
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(label or "~b~Grab~w~ - Tài xế")
    EndTextCommandSetBlipName(driverBlip)
end

local function createRideBlip(coords, label, color)
    removeRideBlip()
    local z = coords.z or 0.0
    rideBlip = AddBlipForCoord(coords.x, coords.y, z)
    SetBlipSprite(rideBlip, 280) -- Taxi icon
    SetBlipDisplay(rideBlip, 4)
    SetBlipScale(rideBlip, 0.9)
    SetBlipAsShortRange(rideBlip, false)
    SetBlipColour(rideBlip, color or 2) -- Default green
    SetBlipRoute(rideBlip, true)
    SetBlipRouteColour(rideBlip, color or 2)
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
        -- Nhận cả pickupCoords và dropoffCoords từ UI
        print("[GRAB DEBUG CLIENT] Received data from NUI:", json.encode(data))
        
        local requestData = data
        if not requestData.pickupCoords then
            -- Fallback: nếu không có pickupCoords, dùng vị trí hiện tại
            requestData.pickupCoords = GetEntityCoords(PlayerPedId())
        end
        
        print("[GRAB DEBUG CLIENT] Sending to server:", json.encode(requestData))
        
        local result = AwaitCallback("grab:requestRide", requestData)
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
            removeDriverBlip() -- Xóa blip tài xế khi khách hủy
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
    
    -- Xóa blip khi tài xế hủy đăng ký
    if not status then
        removeRideBlip()
        removeDriverBlip()
        removeTaxiBlips()
        currentRide = nil
    end
end)

RegisterNetEvent("grab:rideRequest", function(data)
    if not isGrabDriver then return end
    
    currentRide = data
    
    -- Lưu thông tin điểm trả ngay khi nhận yêu cầu
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
    -- Không tạo blip ngay lập tức, chỉ hiển thị thông báo
    
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
    -- Tạo blip chỉ khi tài xế đã chấp nhận chuyến
    createRideBlip(coords, "~g~Grab~w~ - Đón khách", 2) -- Màu xanh lá
    
    print("[GRAB DEBUG] Bắt đầu navigation đến điểm đón:", json.encode(coords))
    
    CreateThread(function()
        while currentRide do
            Wait(1000)
            
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            local z = coords.z or 0.0
            local distance = #(playerCoords - vector3(coords.x, coords.y, z))
            
            print("[GRAB DEBUG] Khoảng cách đến điểm đón:", distance)
            
            if distance < 20.0 then -- 20m
                print("[GRAB DEBUG] Đã đến điểm đón! Gửi arrivedAtPickup")
                TriggerServerEvent("grab:arrivedAtPickup", currentRide.rideId)
                break
            end
        end
    end)
end)

RegisterNetEvent("grab:startDropoffNavigation", function(coords, passengerId)
    -- KHÔNG xóa blip điểm đón ngay, giữ lại để tài xế biết vị trí
    
    -- Lưu thông tin điểm trả và ID khách
    if currentRide then
        currentRide.dropoffCoords = coords
        currentRide.passengerId = passengerId
        print("[GRAB DEBUG] Lưu dropoffCoords và passengerId:", json.encode(coords), passengerId)
    end
    
    -- Thông báo cho tài xế đợi khách vào xe
    exports['f17notify']:Notify("Đợi khách vào xe để bắt đầu chuyến đi!", "info", 5000)
    
    -- Thread kiểm tra khách vào xe
    CreateThread(function()
        print("[GRAB DEBUG] Bắt đầu thread kiểm tra khách vào xe")
        
        while currentRide and currentRide.dropoffCoords do
            Wait(500)
            
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            
            -- Kiểm tra tài xế có trong xe không
            if vehicle ~= 0 then
                -- Kiểm tra khách có trong xe không (theo ID)
                local passengerPed = GetPlayerPed(GetPlayerFromServerId(currentRide.passengerId))
                
                if passengerPed and passengerPed ~= 0 then
                    local passengerVehicle = GetVehiclePedIsIn(passengerPed, false)
                    
                    -- Khách đã vào cùng xe với tài xế
                    if passengerVehicle == vehicle then
                        print("[GRAB DEBUG] Khách đã vào xe! Tạo GPS điểm trả")
                        
                        -- Xóa blip điểm đón cũ
                        removeRideBlip()
                        
                        -- Tạo blip điểm trả
                        createRideBlip(coords, "~o~Grab~w~ - Trả khách", 17) -- Màu cam
                        
                        -- Cập nhật trạng thái
                        currentRide.status = "pickedup"
                        
                        -- Thông báo server
                        TriggerServerEvent("grab:passengerInVehicle", currentRide.rideId)
                        
                        exports['f17notify']:Notify("Khách đã lên xe! GPS đã chỉ đường đến điểm trả.", "success", 5000)
                        
                        -- Bắt đầu thread kiểm tra đến điểm trả
                        CreateThread(function()
                            print("[GRAB DEBUG] Bắt đầu thread kiểm tra điểm trả")
                            
                            while currentRide and currentRide.status == "pickedup" do
                                Wait(1000)
                                
                                local checkPed = PlayerPedId()
                                local playerCoords = GetEntityCoords(checkPed)
                                local z = coords.z or 0.0
                                local distance = #(playerCoords - vector3(coords.x, coords.y, z))
                                
                                print("[GRAB DEBUG] Khoảng cách đến điểm trả:", distance)
                                
                                -- Hiển thị thông báo khi đến gần điểm trả
                                if distance < 20.0 then
                                    print("[GRAB DEBUG] Đã đến điểm trả! Nhấn E để hoàn thành")
                                    exports['f17notify']:Notify("Đã đến điểm trả! Nhấn ~g~[E]~w~ để hoàn thành chuyến", "info", 3000)
                                    
                                    -- Chờ tài xế nhấn E để hoàn thành
                                    while distance < 20.0 and currentRide do
                                        Wait(0)
                                        
                                        if IsControlJustReleased(0, 38) then -- E key
                                            print("[GRAB DEBUG] Tài xế nhấn E, gửi completeRide")
                                            TriggerServerEvent("grab:completeRide", currentRide.rideId)
                                            -- KHÔNG xóa blip ở đây, chờ server xác nhận
                                            -- Blip sẽ được xóa trong event grab:rideCompleted
                                        end
                                        
                                        -- Cập nhật khoảng cách
                                        local recheckPed = PlayerPedId()
                                        local recheckCoords = GetEntityCoords(recheckPed)
                                        distance = #(recheckCoords - vector3(coords.x, coords.y, z))
                                        
                                        if distance >= 20.0 then
                                            print("[GRAB DEBUG] Đã rời xa điểm trả")
                                            break
                                        end
                                    end
                                    
                                    if not currentRide then
                                        break
                                    end
                                end
                            end
                            print("[GRAB DEBUG] Thread kiểm tra điểm trả kết thúc")
                        end)
                        
                        break -- Thoát thread kiểm tra khách vào xe
                    end
                end
            end
        end
        
        print("[GRAB DEBUG] Thread kiểm tra khách vào xe kết thúc")
    end)
end)

RegisterNetEvent("grab:clearNavigation", function()
    removeRideBlip()
end)

RegisterNetEvent("grab:rideAccepted", function(data)
    exports['f17notify']:Notify(data.message, "success", 5000)
    SendReactMessage("grab:rideAccepted", data)
    
    -- Lưu thông tin điểm trả
    if data.dropoffCoords then
        currentRide = currentRide or {}
        currentRide.dropoffCoords = data.dropoffCoords
    end
    
    -- Create driver blip for passenger
    if data.driverCoords then
        createDriverBlip(data.driverCoords, "~b~Grab~w~ - Tài xế đang đến")
    end
end)

RegisterNetEvent("grab:driverArrived", function()
    exports['f17notify']:Notify("Tài xế đã đến! Chúc bạn đi đường an toàn.", "success", 5000)
    SendReactMessage("grab:driverArrived", {})
    removeDriverBlip() -- Remove driver blip when arrived
    
    -- Hiển thị điểm trả cho khách
    if currentRide and currentRide.dropoffCoords then
        createRideBlip(currentRide.dropoffCoords, "~o~Grab~w~ - Điểm trả")
    end
end)

RegisterNetEvent("grab:rideCompleted", function(price)
    local message = string.format("~g~[Grab]~w~ Hoàn thành!\nChi phí: ~r~$%d", price)
    TriggerEvent("QBCore:Notify", message, "success", 8000)
    
    -- Clear tất cả blips và reset trạng thái (CHỈ KHI HOÀN THÀNH THÀNH CÔNG)
    removeRideBlip()
    removeDriverBlip()
    currentRide = nil
    
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
        local z = coords.z or 0.0
        SetBlipCoords(driverBlip, coords.x, coords.y, z)
    end
end)
