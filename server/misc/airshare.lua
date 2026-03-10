
local pendingAlbumShares = {}
local pendingNoteShares = {}
local pendingContactShares = {}

BaseCallback("airShare:share", function(source, phoneNumber, targetSource, targetDevice, shareData)
    local senderName = Player(source).state.phoneName
    if not senderName then
        debugprint("No sender name")
        return false
    end

    local senderInfo = {
        name = senderName,
        source = source,
        device = "phone"
    }
    shareData.sender = senderInfo

    if targetDevice == "tablet" then
        if GetResourceState("lb-tablet") == "started" then
            if Player(targetSource).state.lbTabletOpen then
                TriggerClientEvent("tablet:airShare:received", targetSource, shareData)
            else
                return false
            end
        else
            return false
        end
    elseif targetDevice == "phone" then
        if not Player(targetSource).state.phoneOpen then
            debugprint("sendToSource's phone is not open")
            return false
        end
        TriggerClientEvent("phone:airShare:received", targetSource, shareData)
    end

    if shareData.type == "album" then
        if not pendingAlbumShares[targetSource] then
            pendingAlbumShares[targetSource] = {}
        end
        pendingAlbumShares[targetSource][source] = shareData.album.id
    end

    if shareData.type == "note" then
        if not pendingNoteShares[targetSource] then
            pendingNoteShares[targetSource] = {}
        end
        pendingNoteShares[targetSource][source] = shareData.note
    end

    return true
end, false)

RegisterNetEvent("phone:airShare:interacted", function(senderSource, senderDevice, accepted)
    local targetSource = source

    if type(senderSource) ~= "number" or type(senderDevice) ~= "string" then
        debugprint("AirShare:interacted: Invalid senderSource or senderDevice", senderSource, senderDevice)
        return
    end

    if senderDevice == "tablet" then
        TriggerClientEvent("tablet:airShare:interacted", senderSource, targetSource, accepted)
    elseif senderDevice == "phone" then
        TriggerClientEvent("phone:airShare:interacted", senderSource, targetSource, accepted)
    end

    if pendingAlbumShares[targetSource] and pendingAlbumShares[targetSource][senderSource] then
        local albumId = pendingAlbumShares[targetSource][senderSource]
        pendingAlbumShares[targetSource][senderSource] = nil
        if not next(pendingAlbumShares[targetSource]) then
            pendingAlbumShares[targetSource] = nil
        end
        
        if not accepted then
            debugprint("AirShare: denied album share", albumId)
            return
        end
        
        debugprint("AirShare: accepted album share", albumId)
        HandleAcceptAirShareAlbum(targetSource, senderSource, albumId)
    end

    if pendingNoteShares[targetSource] and pendingNoteShares[targetSource][senderSource] then
        local noteData = pendingNoteShares[targetSource][senderSource]
        pendingNoteShares[targetSource][senderSource] = nil
        if not next(pendingNoteShares[targetSource]) then
            pendingNoteShares[targetSource] = nil
        end

        if not accepted then
            debugprint("AirShare: denied note share")
            return
        end

        debugprint("AirShare: accepted note share", noteData.title)

        local targetPhoneNumber = GetEquippedPhoneNumber(targetSource)
        if not targetPhoneNumber then
            debugprint("AirShare: target has no phone equipped")
            return
        end

        local noteId = MySQL.insert.await("INSERT INTO phone_notes (phone_number, title, content) VALUES (?, ?, ?)", {
            targetPhoneNumber,
            noteData.title,
            noteData.content
        })
        
        if noteId then
            debugprint("AirShare: note created successfully with id", noteId)

            TriggerClientEvent("phone:notes:noteAdded", targetSource, {
                id = noteId,
                title = noteData.title,
                content = noteData.content,
                timestamp = os.time() * 1000
            })

            SendNotification(targetPhoneNumber, {
                app = "NOTES",
                title = "Note Received",
                content = noteData.title
            })
        else
            debugprint("AirShare: failed to create note")
        end
    end

    if pendingContactShares[targetSource] and pendingContactShares[targetSource][senderSource] then
        local contactData = pendingContactShares[targetSource][senderSource]
        pendingContactShares[targetSource][senderSource] = nil
        if not next(pendingContactShares[targetSource]) then
            pendingContactShares[targetSource] = nil
        end
        
        if not accepted then
            debugprint("AirShare: denied contact share")
            return
        end
    
        debugprint("AirShare: accepted contact share", json.encode(contactData))

        if not contactData or not contactData.number then
            debugprint("AirShare: invalid contact data - missing number")
            return
        end
    
        if not contactData.firstname or contactData.firstname == "" then
            contactData.firstname = contactData.number
        end

        local cleanContactData = {
            number = contactData.number,
            firstname = contactData.firstname,
            lastname = contactData.lastname or "",
            avatar = contactData.avatar,
            email = contactData.email,
            address = contactData.address
        }

        local targetPhoneNumber = GetEquippedPhoneNumber(targetSource)
        if not targetPhoneNumber then
            debugprint("AirShare: target has no phone equipped")
            return
        end

        local success = CreateContact(targetPhoneNumber, cleanContactData)
        
        if success then
            debugprint("AirShare: contact created successfully")
            TriggerClientEvent("phone:phone:contactAdded", targetSource, cleanContactData)
            local contactName = cleanContactData.firstname
            if cleanContactData.lastname and cleanContactData.lastname ~= "" then
                contactName = contactName .. " " .. cleanContactData.lastname
            end
            
            SendNotification(targetPhoneNumber, {
                app = "Phone",
                title = "Contact Received",
                content = contactName,
                avatar = cleanContactData.avatar,
                showAvatar = true
            })
        else
            debugprint("AirShare: failed to create contact")
        end
    end
end)

local supportedShareTypes = {
    image = true,
    contact = true,
    location = true,
    note = true,
    voicememo = true
}


exports("AirShare", function(senderSource, targetSource, shareType, shareData)
    assert(type(senderSource) == "number", "Invalid sender")
    assert(type(targetSource) == "number", "Invalid target")
    assert(supportedShareTypes[shareType], "Invalid shareType")
    assert(type(shareData) == "table", "Invalid data")

    local phoneNumber = GetEquippedPhoneNumber(senderSource)
    if not phoneNumber then
        return false
    end

    local sharePacket = {
        type = shareType
    }

    local senderName = Player(senderSource).state.phoneName
    if not senderName then
        senderName = phoneNumber
    end
    
    sharePacket.sender = {
        name = senderName,
        source = senderSource,
        device = "phone"
    }

    if shareType == "image" then
        sharePacket.attachment = shareData
        assert(shareData.src, "Invalid image data (missing src)")

        if not sharePacket.attachment.timestamp then
            sharePacket.attachment.timestamp = os.time() * 1000
        end
        
    elseif shareType == "contact" then
        sharePacket.contact = shareData
        assert(type(sharePacket.contact.number) == "string", "Invalid/missing contact data (contact.number)")
        assert(type(sharePacket.contact.firstname) == "string", "Invalid/missing contact data (contact.firstname)")
        
    elseif shareType == "location" then
        assert(shareData.location, "Invalid location data (missing location)")
        assert(type(shareData.name) == "string", "Invalid/missing location data (location.name)")
        
        sharePacket.location = shareData.location
        sharePacket.name = shareData.name
        
    elseif shareType == "note" then
        sharePacket.note = shareData
        assert(type(sharePacket.note.title) == "string", "Invalid/missing note data (note.title)")
        assert(type(sharePacket.note.content) == "string", "Invalid/missing note data (note.content)")
        
    elseif shareType == "voicememo" then
        sharePacket.voicememo = shareData
        assert(type(sharePacket.voicememo.title) == "string", "Invalid/missing voicememo data (voicememo.title)")
        assert(type(sharePacket.voicememo.src) == "string", "Invalid/missing voicememo data (voicememo.src)")
        assert(type(sharePacket.voicememo.duration) == "number", "Invalid/missing voicememo data (voicememo.duration)")
    end

    TriggerClientEvent("phone:airShare:received", targetSource, sharePacket)
end)

AddEventHandler("playerDropped", function()
    local playerSource = source
    pendingAlbumShares[playerSource] = nil
    pendingNoteShares[playerSource] = nil
end)
