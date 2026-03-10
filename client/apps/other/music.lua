



local function getFormattedPlaylists()
    local rawPlaylists = AwaitCallback("music:getPlaylists")
    local playlists = {}
    local seenIds = {}
    
    for i = 1, #rawPlaylists do
        local playlist = rawPlaylists[i]
        local playlistId = playlist.id
        

        if not seenIds[playlistId] then
            seenIds[playlistId] = true
            local newPlaylist = {
                Id = playlist.id,
                Title = playlist.name,
                Cover = playlist.cover,
                IsOwner = playlist.phone_number == currentPhone,
                Songs = {}
            }
            table.insert(playlists, newPlaylist)
        end
        

        if playlist.song_id then
            local currentPlaylist = playlists[#playlists]
            table.insert(currentPlaylist.Songs, playlist.song_id)
        end
    end
    
    return playlists
end


RegisterNUICallback("Music", function(data, callback)
    local action = data.action
    
    debugprint("Music:" .. (action or ""))
    
    if action == "getConfig" then
        callback(Music)
        
    elseif action == "createPlaylist" then
        TriggerCallback("music:createPlaylist", callback, data.name)
        
    elseif action == "editPlaylist" then
        TriggerCallback("music:editPlaylist", callback, data.id, data.title, data.cover)
        
    elseif action == "deletePlaylist" then
        TriggerCallback("music:deletePlaylist", callback, data.id)
        
    elseif action == "addSong" then
        TriggerCallback("music:addSong", callback, data.playlistId, data.songId)
        
    elseif action == "removeSong" then
        TriggerCallback("music:removeSong", callback, data.playlistId, data.songId)
        
    elseif action == "getPlaylists" then
        local playlists = getFormattedPlaylists()
        callback(playlists)
    end
end)