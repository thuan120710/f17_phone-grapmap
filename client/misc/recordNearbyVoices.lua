


local GetEntityCoords = GetEntityCoords
local nearbyVoices = {}


local function updateNearbyVoices()
    local newVoices = {}
    local nearbyPlayers = GetNearbyPlayers()
    local playerCoords = GetEntityCoords(PlayerPedId())
    
    for i = 1, #nearbyPlayers do
        local player = nearbyPlayers[i]
        local playerState = Player(player.source).state
        local listeningPeerId = playerState and playerState.listeningPeerId
        
        if listeningPeerId then
            local playerPedCoords = GetEntityCoords(player.ped)
            local distance = #(playerCoords - playerPedCoords)
            

            if distance <= 25.0 then
                local voiceData = {
                    source = player.source,
                    ped = player.ped,
                    channel = playerState.listeningPeerId
                }
                

                for j = 1, #nearbyVoices do
                    local existingVoice = nearbyVoices[j]
                    if existingVoice.source == player.source then
                        voiceData.volume = existingVoice.volume
                        break
                    end
                end
                

                if not voiceData.volume then
                    voiceData.volume = GetVoiceVolume(distance)
                    SendReactMessage("voice:joinChannel", {
                        channel = playerState.listeningPeerId,
                        volume = GetVoiceVolume(distance)
                    })
                end
                
                newVoices[#newVoices + 1] = voiceData
            end
        end
    end
    
    nearbyVoices = newVoices
end


local function updateVoiceVolumes()
    local playerCoords = GetEntityCoords(PlayerPedId())
    
    for i = 1, #nearbyVoices do
        local voice = nearbyVoices[i]
        local voicePedCoords = GetEntityCoords(voice.ped)
        local distance = #(playerCoords - voicePedCoords)
        local newVolume = GetVoiceVolume(distance)
        

        if newVolume ~= voice.volume then
            voice.volume = newVolume
            SendReactMessage("voice:setVolume", {
                channel = voice.channel,
                volume = newVolume
            })
        end
    end
end


if not Config.Voice.RecordNearby then
    return
end


CreateThread(function()
    while true do
        Wait(1000)
        updateNearbyVoices()
    end
end)


CreateThread(function()
    while true do
        if #nearbyVoices > 0 then
            updateVoiceVolumes()
            Wait(50)
        else
            Wait(500)
        end
    end
end)


RegisterNetEvent("phone:startedListening", function(source, channel)
    local playerId = GetPlayerFromServerId(source)
    

    if not playerId or playerId == PlayerId() or playerId == -1 then
        return
    end
    
    local playerPed = PlayerPedId()
    local otherPlayerPed = GetPlayerPed(playerId)
    local playerCoords = GetEntityCoords(playerPed)
    local otherPlayerCoords = GetEntityCoords(otherPlayerPed)
    local distance = #(playerCoords - otherPlayerCoords)
    

    if not DoesEntityExist(otherPlayerPed) or otherPlayerPed == playerPed or distance > 25.0 then
        return
    end
    

    for i = 1, #nearbyVoices do
        local voice = nearbyVoices[i]
        if voice.source == source then
            return
        end
    end
    

    nearbyVoices[#nearbyVoices + 1] = {
        source = source,
        ped = otherPlayerPed,
        channel = channel,
        volume = GetVoiceVolume(distance)
    }
    

    SendReactMessage("voice:joinChannel", {
        channel = channel,
        volume = GetVoiceVolume(distance)
    })
end)


RegisterNetEvent("phone:stoppedListening", function(channel)
    SendReactMessage("voice:leaveChannel", channel)
end)


RegisterNUICallback("setListeningPeerId", function(data, callback)
    TriggerServerEvent("phone:setListeningPeerId", data)
    callback("ok")
end)


RegisterNUICallback("voice:getConfig", function(data, callback)
    callback({
        recordNearbyVoices = Config.Voice.RecordNearby,
        rtc = Config.RTCConfig
    })
end)
