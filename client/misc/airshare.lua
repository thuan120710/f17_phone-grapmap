



local function getNearbyDevices()
    local nearbyDevices = {}
    local nearbyPlayers = GetNearbyPlayers()
    local playerCoords = GetEntityCoords(PlayerPedId())
    
    debugprint("Nearby players:", nearbyPlayers)
    
    for i = 1, #nearbyPlayers do
        local player = nearbyPlayers[i]
        local playerState = Player(player.source).state
        
        debugprint("Player data", player.source, player)
        
        local playerPedCoords = GetEntityCoords(player.ped)
        local distance = #(playerCoords - playerPedCoords)
        

        if distance <= 7.5 then

            if playerState.lbTabletOpen and playerState.lbTabletName then
                nearbyDevices[#nearbyDevices + 1] = {
                    name = playerState.lbTabletName,
                    source = player.source,
                    device = "tablet"
                }

            elseif playerState.phoneOpen and playerState.phoneName then
                nearbyDevices[#nearbyDevices + 1] = {
                    name = playerState.phoneName,
                    source = player.source,
                    device = "phone"
                }
            end
        end
    end
    
    debugprint("Nearby devices:", nearbyDevices)
    return nearbyDevices
end


RegisterNUICallback("AirShare", function(data, callback)
    if not currentPhone then
        return
    end
    
    local action = data.action
    debugprint("AirShare:" .. (action or ""))
    
    if action == "getNearby" then

        callback(getNearbyDevices())
    elseif action == "share" then

        TriggerCallback("airShare:share", callback, data.source, data.device, data.data)
    elseif action == "accept" then

        TriggerServerEvent("phone:airShare:interacted", data.source, data.device, true)
        callback("ok")
    elseif action == "deny" then

        TriggerServerEvent("phone:airShare:interacted", data.source, data.device, false)
        callback("ok")
    end
end)


RegisterNetEvent("phone:airShare:received", function(shareData)
    debugprint("phone:airShare:received", shareData)
    

    if shareData.type == "note" and shareData.note then
        debugprint("Triggering immediate note update for realtime")
        TriggerEvent("notes:sharedNoteReceived", shareData.note)
    end
    
    SendReactMessage("airShare:received", shareData)
end)


RegisterNetEvent("phone:airShare:interacted", function(source, accepted)
    SendReactMessage("airShare:interacted", {
        source = source,
        accepted = accepted
    })
end)
