


local MEDIA_TYPE_IMAGE = 1
local MEDIA_TYPE_VIDEO = 2
local MEDIA_TYPE_AUDIO = 3


local baseUrl = nil


local mediaTypes = {
    Audio = "audio",
    Image = "image", 
    Video = "video"
}


local validMetadata = {
    selfie = true,
    import = true,
    screenshot = true
}


RegisterCallback("camera:getBaseUrl", function()
    if not baseUrl then
        baseUrl = GetConvar("web_baseUrl", "")
    end
    return baseUrl
end)


RegisterCallback("camera:getPresignedUrl", function(source, mediaType)
    local fileType = mediaTypes[mediaType]
    if not fileType then
        return
    end
    
    local uploadMethod = Config.UploadMethod[mediaType]
    if uploadMethod ~= "Fivemanage" then
        if GetPresignedUrl then
            return GetPresignedUrl(source, mediaType)
        else
            infoprint("warning", "GetPresignedUrl has not been set up. Set it up in lb-phone/server/custom/functions/functions.lua, or change your upload method to Fivemanage.")
        end
        return
    end
    

    local promise = promise.new()
    local url = "https://fmapi.net/api/v2/presigned-url?fileType=" .. fileType
    
    PerformHttpRequest(url, function(statusCode, responseBody, headers, errorData)
        if statusCode ~= 200 then
            infoprint("error", "Failed to get presigned URL from Fivemanage for " .. fileType)
            print("Status:", statusCode)
            print("Body:", responseBody)
            print("Headers:", json.encode(headers or {}, {indent = true}))
            if errorData then
                print("Error:", errorData)
            end
            promise:resolve()
            return
        end
        
        local responseData = json.decode(responseBody)
        local presignedUrl = responseData and responseData.data and responseData.data.presignedUrl
        promise:resolve(presignedUrl)
    end, "GET", "", {
        Authorization = API_KEYS[mediaType]
    })
    
    return Citizen.Await(promise)
end)


RegisterNetEvent("phone:setListeningPeerId", function(peerId)
    if not Config.Voice.RecordNearby then
        return
    end
    
    local src = source
    local currentPeerId = Player(src).state.listeningPeerId
    
    if currentPeerId then
        TriggerClientEvent("phone:stoppedListening", -1, currentPeerId)
    end
    
    Player(src).state.listeningPeerId = peerId
    debugprint(src, "set listeningPeerId to", peerId)
    
    if peerId then
        TriggerClientEvent("phone:startedListening", -1, src, peerId)
    end
end)


AddEventHandler("playerDropped", function()
    local src = source
    local peerId = Player(src).state.listeningPeerId
    
    if peerId then
        debugprint(src, "dropped, listeningPeerId", peerId)
        TriggerClientEvent("phone:stoppedListening", -1, peerId)
    end
end)


RegisterCallback("camera:getUploadApiKey", function(source, mediaType)
    if not mediaType or not API_KEYS[mediaType] then
        return
    end
    
    local uploadMethod = Config.UploadMethod[mediaType]
    if uploadMethod == "Fivemanage" then
        DropPlayer(source, "Tried to abuse the upload system")
        return
    end
    
    return API_KEYS[mediaType]
end)


local function notifyAlbumMembers(albumId, callback, excludeOwner)
    local members = MySQL.query.await("SELECT phone_number FROM phone_photo_album_members WHERE album_id = ?", {albumId})
    if not members then
        return
    end
    
    if not excludeOwner then
        local ownerNumber = MySQL.scalar.await("SELECT phone_number FROM phone_photo_albums WHERE id = ?", {albumId})
        table.insert(members, {phone_number = ownerNumber})
    end
    
    for i = 1, #members do
        local phoneNumber = members[i].phone_number
        local playerSource = GetSourceFromNumber(phoneNumber)
        callback(phoneNumber, playerSource)
    end
end


local function getAlbumInfo(albumId)
    local albumInfo = MySQL.single.await([[
        SELECT
            pa.id,
            pa.title,
            pa.shared,
            (
                SELECT
                    pp_cover.link
                FROM
                    phone_photos pp_cover
                JOIN
                    phone_photo_album_photos cover ON ap_cover.photo_id = pp_cover.id
                WHERE
                    ap_cover.album_id = pa.id
                ORDER BY
                    ap_cover.photo_id DESC
                LIMIT 1
            ) AS cover,
            SUM(CASE WHEN pp.is_video = 1 THEN 1 ELSE 0 END) AS videoCount,
            SUM(CASE WHEN pp.is_video = 0 THEN 1 ELSE 0 END) AS photoCount
        FROM
            phone_photo_albums pa
        LEFT JOIN
            phone_photo_album_photos ap ON ap.album_id = pa.id
        LEFT JOIN
            phone_photos pp ON pp.id = ap.photo_id
        WHERE
            pa.id = ?
        GROUP BY
            pa.id, pa.title, pa.shared, pa.phone_number
    ]], {albumId})
    
    if not albumInfo then
        return
    end
    
    albumInfo.photoCount = tonumber(albumInfo.photoCount or 0)
    albumInfo.videoCount = tonumber(albumInfo.videoCount or 0)
    albumInfo.count = albumInfo.photoCount + albumInfo.videoCount
    
    return albumInfo
end


local function doesPhoneNumberHaveAccessToAlbum(phoneNumber, albumId)
    local albumData = MySQL.single.await("SELECT phone_number, shared FROM phone_photo_albums WHERE id = ?", {albumId})
    if not albumData then
        debugprint("DoesPhoneNumberHaveAccessToAlbum: Album not found", phoneNumber, albumId)
        return false
    end
    

    if albumData.phone_number == phoneNumber then
        return albumData
    end
    

    if not albumData.shared then
        debugprint("DoesPhoneNumberHaveAccessToAlbum: Private album, not the owner", phoneNumber, albumId)
        return false
    end
    

    local isMember = MySQL.scalar.await("SELECT 1 FROM phone_photo_album_members WHERE album_id = ? AND phone_number = ?", {albumId, phoneNumber})
    if not isMember then
        debugprint("DoesPhoneNumberHaveAccessToAlbum: Album is shared, but not a member", phoneNumber, albumId)
        return false
    end
    
    return albumData
end


local function updateAlbumAndNotify(albumId)
    local albumInfo = getAlbumInfo(albumId)
    if not albumInfo then
        return
    end
    
    notifyAlbumMembers(albumId, function(phoneNumber, playerSource)
        if playerSource then
            TriggerClientEvent("phone:photos:updateAlbum", playerSource, albumInfo)
        end
    end)
end


BaseCallback("camera:saveToGallery", function(source, phoneNumber, link, size, isVideo, metadata, shouldLog)
    if not IsMediaLinkAllowed(link) then
        infoprint("error", ("%s %s tried to save an image with a link that is not allowed:"):format(source, phoneNumber), link)
        return false
    end
    
    if metadata and not validMetadata[metadata] then
        debugprint("Invalid metadata", metadata)
        metadata = nil
    end
    
    local photoId = MySQL.insert.await("INSERT INTO phone_photos (phone_number, link, is_video, size, metadata) VALUES (?, ?, ?, ?, ?)", {
        phoneNumber,
        link,
        isVideo == true,
        size or 0,
        metadata
    })
    
    if shouldLog then
        local mediaType = isVideo and L("BACKEND.LOGS.VIDEO") or L("BACKEND.LOGS.PHOTO")
        Log("Uploads", source, "info", L("BACKEND.LOGS.UPLOADED_MEDIA"), L("BACKEND.LOGS.UPLOADED_MEDIA_DESCRIPTION", {
            type = mediaType,
            id = photoId,
            link = link
        }), link)
        
        TrackSimpleEvent(isVideo and "take_video" or "take_photo")
    end
    
    return photoId
end)


BaseCallback("camera:deleteFromGallery", function(source, phoneNumber, photoIds)
    MySQL.update.await("DELETE FROM phone_photos WHERE phone_number = ? AND id IN (?)", {phoneNumber, photoIds})
    return true
end)


BaseCallback("camera:toggleFavourites", function(source, phoneNumber, isFavourite, photoIds)
    MySQL.update.await("UPDATE phone_photos SET is_favourite = ? WHERE phone_number = ? AND id IN (?)", {
        isFavourite == true,
        phoneNumber,
        photoIds
    })
    return true
end)


BaseCallback("camera:getImages", function(source, phoneNumber, filters, page)
    if not filters.showVideos and not filters.showPhotos then
        return {}
    end
    
    local params = {phoneNumber}
    local whereConditions = {"phone_number = ?"}
    local query = "SELECT id, link, is_video, size, metadata, is_favourite, `timestamp` FROM phone_photos {WHERE}"
    

    if filters.showPhotos ~= filters.showVideos then
        table.insert(whereConditions, "(is_video = ? OR is_video != ?)")
        table.insert(params, filters.showVideos == true)
        table.insert(params, filters.showPhotos == true)
    end
    

    if filters.favourites == true then
        table.insert(whereConditions, "is_favourite = 1")
    end
    

    if filters.type then
        table.insert(whereConditions, "metadata = ?")
        table.insert(params, filters.type)
    end
    

    if filters.album then
        local albumAccess = doesPhoneNumberHaveAccessToAlbum(phoneNumber, filters.album)
        if not albumAccess then
            debugprint("getImages: No access to album", phoneNumber, filters.album)
            return {}
        end
        

        table.remove(whereConditions, 1)
        table.remove(params, 1)
        table.insert(whereConditions, "id IN (SELECT ap.photo_id FROM phone_photo_album_photos ap WHERE ap.album_id = ?)")
        table.insert(params, filters.album)
    end
    

    if filters.duplicates then
        table.insert(whereConditions, [[
            link IN (
                SELECT link
                FROM phone_photos
                WHERE phone_number = ?
                GROUP BY link
                HAVING COUNT(1) > 1
            )
        ]])
        table.insert(params, phoneNumber)
    end
    

    local perPage = math.clamp(filters.perPage or 32, 1, 32)
    query = query .. " ORDER BY `timestamp` DESC LIMIT ?, ?"
    

    local whereClause = #whereConditions > 0 and ("WHERE " .. table.concat(whereConditions, " AND ")) or ""
    query = query:gsub("{WHERE}", whereClause)
    

    table.insert(params, (page or 0) * perPage)
    table.insert(params, perPage)
    
    return MySQL.query.await(query, params)
end)


BaseCallback("camera:getLastImage", function(source, phoneNumber)
    return MySQL.scalar.await("SELECT link FROM phone_photos WHERE phone_number = ? ORDER BY id DESC LIMIT 1", {phoneNumber})
end)


BaseCallback("camera:createAlbum", function(source, phoneNumber, title)
    return MySQL.insert.await("INSERT INTO phone_photo_albums (phone_number, title) VALUES (?, ?)", {phoneNumber, title})
end)


BaseCallback("camera:renameAlbum", function(source, phoneNumber, albumId, newTitle)
    local affectedRows = MySQL.update.await("UPDATE phone_photo_albums SET title = ? WHERE phone_number = ? AND id = ?", {
        newTitle, phoneNumber, albumId
    })
    
    local success = affectedRows > 0
    if success then
        local isShared = MySQL.scalar.await("SELECT shared FROM phone_photo_albums WHERE id = ?", {albumId})
        if isShared then
            notifyAlbumMembers(albumId, function(phoneNumber, playerSource)
                if playerSource then
                    TriggerClientEvent("phone:photos:renameAlbum", playerSource, albumId, newTitle)
                end
            end, true)
        end
    end
    
    return success
end)


BaseCallback("camera:addToAlbum", function(source, phoneNumber, albumId, photoIds)
    local albumAccess = doesPhoneNumberHaveAccessToAlbum(phoneNumber, albumId)
    if not albumAccess then
        debugprint("No access to album", phoneNumber, albumId)
        return false
    end
    
    MySQL.update.await("INSERT IGNORE INTO phone_photo_album_photos (album_id, photo_id) SELECT ?, id FROM phone_photos WHERE phone_number = ? AND id IN (?)", {
        albumId, phoneNumber, photoIds
    })
    
    debugprint("Added photos to album", phoneNumber, albumId, photoIds)
    
    if albumAccess.shared then
        updateAlbumAndNotify(albumId)
    end
    
    return true
end)


BaseCallback("camera:removeFromAlbum", function(source, phoneNumber, albumId, photoIds)
    local albumAccess = doesPhoneNumberHaveAccessToAlbum(phoneNumber, albumId)
    if not albumAccess then
        debugprint("No access to album", phoneNumber, albumId)
        return false
    end
    
    MySQL.update.await("DELETE FROM phone_photo_album_photos WHERE album_id = ? AND photo_id IN (?)", {albumId, photoIds})
    updateAlbumAndNotify(albumId)
    
    return true
end)


BaseCallback("camera:deleteAlbum", function(source, phoneNumber, albumId)
    local albumData = MySQL.single.await("SELECT shared FROM phone_photo_albums WHERE phone_number = ? AND id = ?", {phoneNumber, albumId})
    if not albumData then
        debugprint("deleteAlbum: Album not found", phoneNumber, albumId)
        return false
    end
    
    if albumData.shared then
        notifyAlbumMembers(albumId, function(phoneNumber, playerSource)
            if playerSource then
                TriggerClientEvent("phone:photos:removeMemberFromAlbum", playerSource, albumId, phoneNumber)
            end
        end, true)
    end
    
    MySQL.update("DELETE FROM phone_photo_albums WHERE phone_number = ? AND id = ?", {phoneNumber, albumId})
    return true
end)


local mediaTypeCategories = {
    "videos", "photos", "favouritesVideos", "favouritesPhotos",
    "selfiesVideos", "selfiesPhotos", "screenshotsVideos", "screenshotsPhotos",
    "importsVideos", "importsPhotos", "duplicatesPhotos", "duplicatesVideos"
}


BaseCallback("camera:getHomePageData", function(source, phoneNumber)

    local mediaStats = MySQL.single.await([[
        SELECT
            SUM(is_video = 1) AS videos,
            SUM(is_video = 0) AS photos,
            SUM(is_video = 1 AND is_favourite = 1) AS favouritesVideos,
            SUM(is_video = 0 AND is_favourite = 1) AS favouritesPhotos,
            SUM(metadata = 'selfie' AND is_video = 1) AS selfiesVideos,
            SUM(metadata = 'selfie' AND is_video = 0) AS selfiesPhotos,
            SUM(metadata = 'screenshot' AND is_video = 1) AS screenshotsVideos,
            SUM(metadata = 'screenshot' AND is_video = 0) AS screenshotsPhotos,
            SUM(metadata = 'import' AND is_video = 1) AS importsVideos,
            SUM(metadata = 'import' AND is_video = 0) AS importsPhotos

        FROM phone_photos
        WHERE phone_number = ?
    ]], {phoneNumber})
    

    local totalPhotos = tonumber(mediaStats.photos or 0)
    local uniquePhotos = MySQL.scalar.await([[
        SELECT COUNT(DISTINCT link)
        FROM phone_photos
        WHERE phone_number = ? AND is_video = 0
    ]], {phoneNumber})
    mediaStats.duplicatesPhotos = totalPhotos - uniquePhotos
    

    local totalVideos = tonumber(mediaStats.videos or 0)
    local uniqueVideos = MySQL.scalar.await([[
        SELECT COUNT(DISTINCT link)
        FROM phone_photos
        WHERE phone_number = ? AND is_video = 1
    ]], {phoneNumber})
    mediaStats.duplicatesVideos = totalVideos - uniqueVideos
    

    for i = 1, #mediaTypeCategories do
        local category = mediaTypeCategories[i]
        mediaStats[category] = tonumber(mediaStats[category] or 0)
    end
    

    if mediaStats.duplicatesPhotos > 0 then
        mediaStats.duplicatesPhotos = mediaStats.duplicatesPhotos + 1
    end
    if mediaStats.duplicatesVideos > 0 then
        mediaStats.duplicatesVideos = mediaStats.duplicatesVideos + 1
    end
    

    local albums = {}
    

    local recentsAlbum = {
        id = "recents",
        title = L("APPS.PHOTOS.RECENTS"),
        videoCount = mediaStats.videos,
        photoCount = mediaStats.photos,
        cover = MySQL.scalar.await("SELECT link FROM phone_photos WHERE phone_number = ? ORDER BY id DESC LIMIT 1", {phoneNumber}),
        removable = false
    }
    

    local favouritesAlbum = {
        id = "favourites",
        title = L("APPS.PHOTOS.FAVOURITES"),
        videoCount = mediaStats.favouritesVideos,
        photoCount = mediaStats.favouritesPhotos,
        cover = MySQL.scalar.await("SELECT link FROM phone_photos WHERE phone_number = ? AND is_favourite = 1 ORDER BY id DESC LIMIT 1", {phoneNumber}),
        removable = false
    }
    
    table.insert(albums, recentsAlbum)
    table.insert(albums, favouritesAlbum)
    

    local userAlbums = MySQL.query.await([[
        SELECT
            pa.id,
            pa.title,
            pa.shared,
            pa.phone_number,
            (
                SELECT
                    pp_cover.link
                FROM
                    phone_photos pp_cover
                JOIN
                    phone_photo_album_photos ap_cover ON ap_cover.photo_id = pp_cover.id
                WHERE
                    ap_cover.album_id = pa.id
                ORDER BY
                    ap_cover.photo_id DESC
                LIMIT 1
            ) AS cover,
            SUM(CASE WHEN pp.is_video = 1 THEN 1 ELSE 0 END) AS videoCount,
            SUM(CASE WHEN pp.is_video = 0 THEN 1 ELSE 0 END) AS photoCount
        FROM
            phone_photo_albums pa
        LEFT JOIN
            phone_photo_album_photos ap ON ap.album_id = pa.id
        LEFT JOIN
            phone_photos pp ON pp.id = ap.photo_id
        WHERE
            pa.phone_number = ?
            OR EXISTS (
                SELECT 1
                FROM phone_photo_album_members member
                WHERE member.album_id = pa.id AND member.phone_number = ?
            )
        GROUP BY
            pa.id, pa.title, pa.shared, pa.phone_number
        ORDER BY
            pa.id ASC
    ]], {phoneNumber, phoneNumber})
    

    for i = 1, #userAlbums do
        local album = userAlbums[i]
        album.removable = true
        album.isOwner = album.phone_number == phoneNumber
        album.phone_number = nil
        table.insert(albums, album)
    end
    

    for i = 1, #albums do
        local album = albums[i]
        album.photoCount = tonumber(album.photoCount or 0)
        album.videoCount = tonumber(album.videoCount or 0)
        album.count = album.photoCount + album.videoCount
    end
    
    return {
        albums = albums,
        mediaTypes = mediaStats
    }
end, {
    albums = {},
    mediaTypes = {}
})


BaseCallback("camera:getAlbumMembers", function(source, phoneNumber, albumId)
    local albumAccess = doesPhoneNumberHaveAccessToAlbum(phoneNumber, albumId)
    if not albumAccess then
        debugprint("getAlbumMembers: No access to album", phoneNumber, albumId)
        return false
    end
    
    local members = {}
    local ownerNumber = MySQL.scalar.await("SELECT phone_number FROM phone_photo_albums WHERE id = ?", {albumId})
    local memberNumbers = MySQL.query.await("SELECT phone_number FROM phone_photo_album_members WHERE album_id = ?", {albumId})
    

    for i = 1, #memberNumbers do
        members[i] = memberNumbers[i].phone_number
    end
    

    table.insert(members, ownerNumber)
    
    return members
end)


local function removeMemberFromAlbum(phoneNumber, albumId)
    local affectedRows = MySQL.update.await("DELETE FROM phone_photo_album_members WHERE album_id = ? AND phone_number = ?", {albumId, phoneNumber})
    
    if affectedRows <= 0 then
        debugprint("removeMemberFromAlbum: failed to remove member from album", phoneNumber, albumId)
        return false
    end
    
    local remainingMembers = MySQL.scalar.await("SELECT COUNT(1) FROM phone_photo_album_members WHERE album_id = ?", {albumId})
    
    notifyAlbumMembers(albumId, function(memberPhone, playerSource)
        if playerSource then
            TriggerClientEvent("phone:photos:removeMemberFromAlbum", playerSource, albumId, phoneNumber)
        end
    end)
    
    return true
end


BaseCallback("camera:addMemberToAlbum", function(source, phoneNumber, albumId, targetPhoneNumber)
    local albumData = MySQL.single.await("SELECT phone_number FROM phone_photo_albums WHERE id = ?", {albumId})
    if not albumData or albumData.phone_number ~= phoneNumber then
        debugprint("addMemberToAlbum: Not album owner", phoneNumber, albumId)
        return false
    end
    
    MySQL.update.await("INSERT IGNORE INTO phone_photo_album_members (album_id, phone_number) VALUES (?, ?)", {albumId, targetPhoneNumber})
    
    local albumInfo = getAlbumInfo(albumId)
    if albumInfo then
        local targetSource = GetSourceFromNumber(targetPhoneNumber)
        if targetSource then
            TriggerClientEvent("phone:photos:addMemberToAlbum", targetSource, albumInfo)
        end
    end
    
    return true
end)


BaseCallback("camera:removeMemberFromAlbum", function(source, phoneNumber, albumId, targetPhoneNumber)
    local albumData = MySQL.single.await("SELECT phone_number FROM phone_photo_albums WHERE id = ?", {albumId})
    if not albumData or albumData.phone_number ~= phoneNumber then
        debugprint("removeMemberFromAlbum: Not album owner", phoneNumber, albumId)
        return false
    end
    
    return removeMemberFromAlbum(targetPhoneNumber, albumId)
end)


BaseCallback("camera:leaveSharedAlbum", function(source, phoneNumber, albumId)
    return removeMemberFromAlbum(phoneNumber, albumId)
end)


BaseCallback("camera:toggleAlbumSharing", function(source, phoneNumber, albumId, shared)
    local affectedRows = MySQL.update.await("UPDATE phone_photo_albums SET shared = ? WHERE phone_number = ? AND id = ?", {
        shared == true, phoneNumber, albumId
    })
    
    local success = affectedRows > 0
    if success and not shared then

        MySQL.update.await("DELETE FROM phone_photo_album_members WHERE album_id = ?", {albumId})
        
        notifyAlbumMembers(albumId, function(memberPhone, playerSource)
            if playerSource then
                TriggerClientEvent("phone:photos:removeMemberFromAlbum", playerSource, albumId, memberPhone)
            end
        end, true)
    end
    
    return success
end)
