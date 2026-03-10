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
RegisterNUICallback("Maps", function(data, callback)
    local action = data.action
    debugprint("Maps:" .. (action or ""))
    
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
    end
end)
