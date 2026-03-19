local isGrabDriver = false
local currentRide = nil
local blips = { ride = nil, driver = nil, taxis = {} }
local isTrackingCoords = false
local lastCoords = vector3(0, 0, 0)
local passengerTimer = nil

local BLIP_CONFIG = {
    taxi = { sprite = 280, color = 5, scale = 0.7, label = "~y~Grab~w~ - Tài xế" },
    driver = { sprite = 280, color = 3, scale = 0.8, label = "~b~Grab~w~ - Tài xế" },
    pickup = { sprite = 280, color = 2, scale = 0.9, label = "~g~Grab~w~ - Đón khách" },
    dropoff = { sprite = 280, color = 17, scale = 0.9, label = "~o~Grab~w~ - Trả khách" }
}

-------------------------------------------------------------------------------
-- Blip Management
-------------------------------------------------------------------------------

local function removeBlip(type)
    if blips[type] then RemoveBlip(blips[type]); blips[type] = nil end
end

local function removeAllTaxis()
    for _, b in ipairs(blips.taxis) do if b then RemoveBlip(b) end end
    blips.taxis = {}
end

local function createBlip(type, coords, label)
    removeBlip(type)
    local cfg = BLIP_CONFIG[type]
    if not cfg or not coords then return end
    
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z or 0.0)
    SetBlipSprite(blip, cfg.sprite)
    SetBlipScale(blip, cfg.scale)
    SetBlipColour(blip, cfg.color)
    SetBlipAsShortRange(blip, false)
    
    if type == "pickup" or type == "dropoff" then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, cfg.color)
    end
    
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(label or cfg.label)
    EndTextCommandSetBlipName(blip)
    blips[type] = blip
    return blip
end

-------------------------------------------------------------------------------
-- Real-time Tracking Threads
-------------------------------------------------------------------------------

local function startTracking()
    if isTrackingCoords then return end
    isTrackingCoords = true
    lastCoords = GetEntityCoords(PlayerPedId())
    
    CreateThread(function()
        while isTrackingCoords do
            local coords = GetEntityCoords(PlayerPedId())
            if #(lastCoords - coords) > 1.0 then
                lastCoords = coords
                SendReactMessage("grab:updateCoords", { x = math.floor(coords.x + 0.5), y = math.floor(coords.y + 0.5) })
            end
            Wait(1000)
        end
    end)
end

CreateThread(function()
    while true do
        Wait(2000)
        if isGrabDriver then
            local ped = PlayerPedId()
            TriggerServerEvent("grab:updateDriverLocation", GetEntityCoords(ped), GetVehiclePedIsIn(ped, false) ~= 0)
        end
    end
end)

-------------------------------------------------------------------------------
-- NUI Callbacks (Table-lookup)
-------------------------------------------------------------------------------

local NUI_ACTIONS = {
    getCurrentLocation = function(_, cb)
        local coords = GetEntityCoords(PlayerPedId())
        cb({ x = coords.x, y = coords.y })
    end,
    toggleUpdateCoords = function(_, cb) startTracking(); cb({}) end,
    toggleGrabDriver = function(_, cb) 
        local newStatus = not isGrabDriver
        TriggerServerEvent("grab:toggleDriver", newStatus)
        cb({ success = true, status = newStatus })
    end,
    requestGrabRide = function(data, cb)
        data.pickupCoords = data.pickupCoords or GetEntityCoords(PlayerPedId())
        cb(AwaitCallback("grab:requestRide", data))
    end,
    getGrabDriverStatus = function(_, cb) cb({ isDriver = isGrabDriver, hasRide = currentRide ~= nil }) end,
    completeGrabRide = function(_, cb) if currentRide then TriggerServerEvent("grab:completeRide", currentRide.rideId) end; cb({}) end,
    cancelGrabRide = function(_, cb) if currentRide then TriggerServerEvent("grab:cancelRide", currentRide.rideId) end; cb({}) end,
    getAllGrabDrivers = function(_, cb)
        local drivers = AwaitCallback("grab:getAllDrivers", GetEntityCoords(PlayerPedId()))
        if drivers then
            for _, d in ipairs(drivers) do
                if d.coords then d.x, d.y, d.z = d.coords.x, d.coords.y, d.coords.z; d.coords = nil end
            end
        end
        cb(drivers)
    end,
    showTaxiBlips = function(_, cb)
        removeAllTaxis()
        local drivers = AwaitCallback("grab:getAllDrivers", GetEntityCoords(PlayerPedId()))
        for _, d in ipairs(drivers or {}) do
            local b = AddBlipForCoord(d.coords.x, d.coords.y, d.coords.z)
            SetBlipSprite(b, BLIP_CONFIG.taxi.sprite)
            SetBlipColour(b, BLIP_CONFIG.taxi.color)
            SetBlipScale(b, BLIP_CONFIG.taxi.scale)
            table.insert(blips.taxis, b)
        end
        cb({})
    end,
    hideTaxiBlips = function(_, cb) removeAllTaxis(); cb({}) end,
    acceptGrabRide = function(data, cb) if data.rideId then TriggerServerEvent("grab:acceptRide", data.rideId) end; cb({}) end,
    rejectGrabRide = function(data, cb) if data.rideId then TriggerServerEvent("grab:rejectRide", data.rideId) end; cb({}) end,
}

RegisterNUICallback("GrabApp", function(data, cb)
    if NUI_ACTIONS[data.action] then NUI_ACTIONS[data.action](data, cb) else cb({}) end
end)

-------------------------------------------------------------------------------
-- System Event Handlers
-------------------------------------------------------------------------------

RegisterNetEvent("grab:driverStatus", function(status)
    isGrabDriver = status
    SendReactMessage("grab:updateDriverStatus", { isDriver = status })
    if not status then 
        removeBlip("ride"); removeBlip("driver"); removeBlip("pickup"); removeBlip("dropoff"); removeAllTaxis(); 
        currentRide = nil 
    end
end)

RegisterNetEvent("grab:rideRequest", function(data)
    if not isGrabDriver then return end
    currentRide = data
    local msg = string.format("~g~[Grab]~w~ Yêu cầu đặt xe mới!\nĐón: ~y~%dm~w~\nGiá: ~g~$%d~w~\n[Y] Chấp nhận | [N] Từ chối", data.distance, data.price)
    TriggerEvent("QBCore:Notify", msg, "info", 15000)
    
    CreateThread(function()
        local timeout = GetGameTimer() + 15000
        while GetGameTimer() < timeout and currentRide and currentRide.rideId == data.rideId do
            Wait(0)
            if IsControlJustReleased(0, 246) then TriggerServerEvent("grab:acceptRide", data.rideId); break
            elseif IsControlJustReleased(0, 249) then TriggerServerEvent("grab:rejectRide", data.rideId); currentRide = nil; break end
        end
    end)
end)

RegisterNetEvent("grab:startNavigation", function(coords)
    createBlip("pickup", coords)
    CreateThread(function()
        while currentRide do
            Wait(1000)
            if #(GetEntityCoords(PlayerPedId()) - vector3(coords.x, coords.y, coords.z or 0.0)) < 20.0 then
                TriggerServerEvent("grab:arrivedAtPickup", currentRide.rideId); break
            end
        end
    end)
end)

RegisterNetEvent("grab:startDropoffNavigation", function(coords, pId)
    if currentRide then currentRide.dropoffCoords, currentRide.passengerId = coords, pId end
    exports['f17notify']:Notify("Đợi khách vào xe!", "info", 5000)
    
    CreateThread(function()
        while currentRide and currentRide.dropoffCoords do
            Wait(1000)
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 then
                local passPed = GetPlayerPed(GetPlayerFromServerId(currentRide.passengerId))
                if passPed ~= 0 and GetVehiclePedIsIn(passPed, false) == veh then
                    removeBlip("ride"); createBlip("dropoff", coords)
                    currentRide.status = "pickedup"
                    TriggerServerEvent("grab:passengerInVehicle", currentRide.rideId)
                    
                    CreateThread(function()
                        local wasIn = true
                        local hasShownArrivedNotify = false
                        local nextStatusCheck = 0
                        
                        while currentRide and currentRide.status == "pickedup" do
                            local pPed = PlayerPedId()
                            local pCoords = GetEntityCoords(pPed)
                            local dist = #(pCoords - vector3(coords.x, coords.y, coords.z or 0.0))
                            local sleep = 1000
                            
                            if dist < 25.0 then
                                sleep = 0
                                if not hasShownArrivedNotify then
                                    exports['f17notify']:Notify("Đã đến điểm trả! [E] hoàn thành", "info", 5000)
                                    hasShownArrivedNotify = true
                                end
                                if IsControlJustReleased(0, 38) then -- E
                                    TriggerServerEvent("grab:completeRide", currentRide.rideId)
                                    Wait(1000) 
                                end
                            else
                                hasShownArrivedNotify = false
                            end

                            if GetGameTimer() > nextStatusCheck then
                                nextStatusCheck = GetGameTimer() + 1000
                                local targetPed = GetPlayerPed(GetPlayerFromServerId(currentRide.passengerId))
                                local isIn = (GetVehiclePedIsIn(targetPed, false) == veh)
                                if wasIn and not isIn then TriggerServerEvent("grab:passengerExitVehicle", currentRide.rideId)
                                elseif not wasIn and isIn then TriggerServerEvent("grab:passengerInVehicle", currentRide.rideId) end
                                wasIn = isIn
                            end
                            
                            Wait(sleep)
                        end
                    end)
                    break
                end
            end
        end
    end)
end)

RegisterNetEvent("grab:rideAccepted", function(data)
    exports['f17notify']:Notify(data.message, "success", 5000)
    SendReactMessage("grab:rideAccepted", data)
    if data.driverCoords then createBlip("driver", data.driverCoords) end
    if data.dropoffCoords then createBlip("dropoff", data.dropoffCoords) end
end)

RegisterNetEvent("grab:driverArrived", function()
    exports['f17notify']:Notify("Tài xế đã đến!", "success", 5000)
    SendReactMessage("grab:driverArrived", {})
    removeBlip("driver")
end)

RegisterNetEvent("grab:rideCompleted", function(p)
    TriggerEvent("QBCore:Notify", string.format("~g~[Grab]~w~ Hoàn thành!\nGiá: ~r~$%d", p), "success", 8000)
    removeBlip("driver"); removeBlip("pickup"); removeBlip("dropoff"); removeAllTaxis()
    currentRide = nil; passengerTimer = nil
    SendReactMessage("grab:rideCompleted", { price = p })
end)

RegisterNetEvent("grab:rideCancelled", function(r)
    exports['f17notify']:Notify(r or "Hủy chuyến!", "error", 5000)
    removeBlip("driver"); removeBlip("pickup"); removeBlip("dropoff"); removeAllTaxis()
    currentRide = nil; passengerTimer = nil
    SendReactMessage("grab:rideCancelled", { reason = r })
end)

RegisterNetEvent("grab:startTimer", function(s)
    if passengerTimer then return end
    passengerTimer = s
    exports['f17notify']:Notify("~r~[Cảnh báo]~w~ Bạn có "..s.."s vào lại xe!", "error", 5000)
    CreateThread(function()
        while passengerTimer and passengerTimer > 0 do
            Wait(1000); passengerTimer = passengerTimer - 1
            if passengerTimer > 0 and passengerTimer % 10 == 0 then exports['f17notify']:Notify("Còn "..passengerTimer.."s!", "error", 3000) end
        end
        passengerTimer = nil
    end)
end)

RegisterNetEvent("grab:cancelTimer", function() passengerTimer = nil; exports['f17notify']:Notify("Đã hủy đếm ngược!", "success", 3000) end)
RegisterNetEvent("grab:updateDriverLocation", function(c) if blips.driver then SetBlipCoords(blips.driver, c.x, c.y, c.z or 0.0) end end)
RegisterNetEvent("grab:clearNavigation", function() removeBlip("pickup"); removeBlip("dropoff") end)

CreateThread(function() Wait(2000); startTracking() end)
