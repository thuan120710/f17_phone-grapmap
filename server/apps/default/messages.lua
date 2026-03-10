-- ========================================
-- PERFORMANCE OPTIMIZATION SYSTEM
-- ========================================
-- OPTIMIZED FOR 200-400 CONCURRENT USERS
--
-- Key optimizations:
-- 1. CACHING: Channel members cached for 5 minutes
-- 2. NOTIFICATION QUEUE: Batch processing 50 notifications per 500ms
-- 3. TARGETED BROADCASTING: Only send events to channel members (not -1 broadcast)
-- 4. ACTIVE USERS TRACKING: Track who has Messages app open
-- 5. ASYNC OPERATIONS: Non-blocking database updates
-- 6. BATCH QUERIES: Combined SQL operations where possible
--
-- Similar to Twitter optimization strategy
-- ========================================

-- Caching System
local ChannelCache = {}
local CACHE_TTL = 300000 -- 5 minutes (ms)

-- Notification Queue for batch processing
local NotificationQueue = {}
local NotificationProcessing = false

-- Active Messages Users Cache (for targeted broadcasting)
local ActiveMessagesUsers = {} -- [source] = phoneNumber
local PhoneToSources = {} -- [phoneNumber] = {source1, source2, ...}

-- ========================================
-- CACHE HELPERS
-- ========================================

local function clearExpiredCache()
    local now = GetGameTimer()
    for key, cache in pairs(ChannelCache) do
        if (now - cache.timestamp) > CACHE_TTL then
            ChannelCache[key] = nil
        end
    end
end

local function invalidateChannelCache(channelId)
    ChannelCache[channelId] = nil
    ChannelCache["members_" .. channelId] = nil
end

-- Run cache cleanup every 5 minutes
CreateThread(function()
    while true do
        Wait(300000)
        clearExpiredCache()
    end
end)

-- Cleanup on player disconnect
AddEventHandler("playerDropped", function()
    local source = source
    local phoneNumber = ActiveMessagesUsers[source]

    if phoneNumber then
        ActiveMessagesUsers[source] = nil
        if PhoneToSources[phoneNumber] then
            for i, src in ipairs(PhoneToSources[phoneNumber]) do
                if src == source then
                    table.remove(PhoneToSources[phoneNumber], i)
                    break
                end
            end
        end
    end
end)

-- ========================================
-- TARGETED BROADCASTING HELPERS
-- ========================================

-- Get sources for specific phone number
local function getSourcesForPhone(phoneNumber)
    return PhoneToSources[phoneNumber] or {}
end

-- Get sources for channel members - OPTIMIZED with cache
local function getChannelMemberSources(channelId)
    local sources = {}

    -- Check cache first
    local cacheKey = "members_" .. channelId
    local cachedMembers = ChannelCache[cacheKey]

    local members
    if cachedMembers and (GetGameTimer() - cachedMembers.timestamp) < CACHE_TTL then
        members = cachedMembers.data
    else
        members = MySQL.query.await("SELECT phone_number FROM phone_message_members WHERE channel_id = ?", {channelId})

        -- Cache members list
        if members then
            ChannelCache[cacheKey] = {
                data = members,
                timestamp = GetGameTimer()
            }
        end
    end

    if not members then return sources end

    for i = 1, #members do
        local memberPhone = members[i].phone_number
        local memberSources = getSourcesForPhone(memberPhone)
        for _, src in ipairs(memberSources) do
            table.insert(sources, src)
        end
    end

    return sources
end

-- Broadcast event to relevant users only (FIXED: variadic args support)
local function broadcastToRelevant(eventName, targetSources, ...)
    if not targetSources or #targetSources == 0 then
        return
    end

    for _, source in ipairs(targetSources) do
        TriggerClientEvent(eventName, source, ...)
    end
end

-- ========================================
-- NOTIFICATION QUEUE SYSTEM
-- ========================================

local function queueNotification(phoneNumber, notificationData)
    table.insert(NotificationQueue, {
        phoneNumber = phoneNumber,
        data = notificationData,
        timestamp = os.time()
    })

    -- Start processor if not running
    if not NotificationProcessing then
        NotificationProcessing = true
        CreateThread(processNotificationQueue)
    end
end

-- Helper function to send notification immediately
local function sendMessageNotification(phoneNumber, senderNumber, content, attachments)
    if content == "<!CALL-NO-ANSWER!>" then
        debugprint("Skipping notification for call message")
        return -- Skip call messages
    end

    debugprint("Processing notification for:", phoneNumber, "from:", senderNumber, "content:", content)

    local contact = GetContact(senderNumber, phoneNumber)
    local senderName = (contact and contact.name) or senderNumber
    local thumbnail = nil

    if attachments then
        local attachmentData = json.decode(attachments)
        if attachmentData and attachmentData[1] then
            thumbnail = attachmentData[1]
        end
    end

    local notificationData = {
        app = "Messages",
        title = senderName,
        content = content,
        thumbnail = thumbnail,
        avatar = contact and contact.avatar,
        showAvatar = true
    }

    debugprint("Notification data prepared:", json.encode(notificationData))
    debugprint("Calling SendNotification for:", phoneNumber)
    
    local success = SendNotification(phoneNumber, notificationData)
    debugprint("SendNotification result:", success)
end

-- Process notification queue in batches (runs async)
function processNotificationQueue()
    while #NotificationQueue > 0 do
        Wait(100) -- Process batch every 100ms (faster)

        local batch = {}
        local batchSize = math.min(10, #NotificationQueue) -- Smaller batches

        for i = 1, batchSize do
            table.insert(batch, table.remove(NotificationQueue, 1))
        end

        -- Process batch
        for _, notif in ipairs(batch) do
            CreateThread(function()
                debugprint("Processing queued notification for:", notif.phoneNumber)
                SendNotification(notif.phoneNumber, notif.data)
            end)
        end
    end

    NotificationProcessing = false
    debugprint("Notification queue processing completed")
end

-- Track user opening Messages app
RegisterNetEvent("phone:messages:appOpened", function()
    local source = source
    local phoneNumber = GetEquippedPhoneNumber(source)

    if phoneNumber then
        ActiveMessagesUsers[source] = phoneNumber
        if not PhoneToSources[phoneNumber] then
            PhoneToSources[phoneNumber] = {}
        end

        local exists = false
        for _, src in ipairs(PhoneToSources[phoneNumber]) do
            if src == source then
                exists = true
                break
            end
        end
        if not exists then
            table.insert(PhoneToSources[phoneNumber], source)
        end
    end
end)

-- Track user closing Messages app
RegisterNetEvent("phone:messages:appClosed", function()
    local source = source
    local phoneNumber = ActiveMessagesUsers[source]

    if phoneNumber then
        ActiveMessagesUsers[source] = nil
        if PhoneToSources[phoneNumber] then
            for i, src in ipairs(PhoneToSources[phoneNumber]) do
                if src == source then
                    table.remove(PhoneToSources[phoneNumber], i)
                    break
                end
            end
        end
    end
end)

-- ========================================
-- ORIGINAL FUNCTIONS (OPTIMIZED)
-- ========================================

local function FindDirectMessageChannel(senderNumber, recipientNumber)
    return MySQL.scalar.await([[
        SELECT c.id FROM phone_message_channels c
        WHERE c.is_group = 0
            AND EXISTS (SELECT TRUE FROM phone_message_members m WHERE m.channel_id = c.id AND m.phone_number = ?)
            AND EXISTS (SELECT TRUE FROM phone_message_members m WHERE m.channel_id = c.id AND m.phone_number = ?)
    ]], {senderNumber, recipientNumber})
end

function SendMessage(senderNumber, recipientNumber, content, attachments, callback, channelId)
    if not (channelId or recipientNumber) or not senderNumber then
        return
    end

    if not content then
        if not attachments or #attachments == 0 then
            return
        end
    end

    if content and #content == 0 then
        content = nil
    end

    if not content and (not attachments or #attachments == 0) then
        return
    end
    
    -- Giới hạn độ dài content
    if content and #content > 2000 then
        debugprint("Message content too long:", #content)
        return false
    end
    
    -- Giới hạn số lượng attachments
    if attachments and type(attachments) == "table" and #attachments > 5 then
        debugprint("Too many attachments:", #attachments)
        return false
    end

    if not channelId then
        channelId = FindDirectMessageChannel(senderNumber, recipientNumber)
    end

    -- KIỂM TRA MEMBERSHIP: Nếu channelId đã tồn tại, kiểm tra sender có phải member không
    if channelId then
        local isMember = MySQL.scalar.await("SELECT TRUE FROM phone_message_members WHERE channel_id = ? AND phone_number = ?", {
            channelId, senderNumber
        })
        
        if not isMember then
            debugprint("Sender", senderNumber, "is not a member of channel", channelId)
            if callback then
                callback(false)
            end
            return false
        end
    end

    local senderSource = GetSourceFromNumber(senderNumber)
    
    -- Create new direct message channel if none exists
    if not channelId then
        channelId = MySQL.insert.await("INSERT INTO phone_message_channels (is_group) VALUES (0)")
        
        -- Add both members to the channel
        MySQL.update.await("INSERT INTO phone_message_members (channel_id, phone_number) VALUES (?, ?), (?, ?)", {
            channelId, senderNumber, channelId, recipientNumber
        })
        
        local recipientSource = GetSourceFromNumber(recipientNumber)
        local timestamp = os.time() * 1000
        
        -- Notify sender about new channel
        if senderSource then
            TriggerClientEvent("phone:messages:newChannel", senderSource, {
                id = channelId,
                lastMessage = content,
                timestamp = timestamp,
                number = recipientNumber,
                isGroup = false,
                unread = false
            })
        end
        
        -- Notify recipient about new channel
        if recipientSource then
            TriggerClientEvent("phone:messages:newChannel", recipientSource, {
                id = channelId,
                lastMessage = content,
                timestamp = timestamp,
                number = senderNumber,
                isGroup = false,
                unread = true
            })
        end
    end
    
    -- Log the message if sender is online
    if senderSource then
        Log("Messages", senderSource, "info", L("BACKEND.LOGS.MESSAGE_TITLE"), L("BACKEND.LOGS.NEW_MESSAGE", {
            sender = FormatNumber(senderNumber),
            recipient = FormatNumber(recipientNumber),
            message = content or "Attachment"
        }))
    end
    
    -- Encode attachments if they're a table
    if type(attachments) == "table" then
        attachments = json.encode(attachments)
    end
    
    -- Insert message into database
    local messageId = MySQL.insert.await("INSERT INTO phone_message_messages (channel_id, sender, content, attachments) VALUES (@channelId, @sender, @content, @attachments)", {
        ["@channelId"] = channelId,
        ["@sender"] = senderNumber,
        ["@content"] = content,
        ["@attachments"] = attachments
    })
    
    if not messageId then
        if callback then
            callback(false)
        end
        return
    end
    
    -- OPTIMIZED: Async database updates (non-blocking)
    local lastMessagePreview = string.sub(content or "Attachment", 1, 50)

    -- Run updates in parallel (non-blocking)
    CreateThread(function()
        MySQL.update("UPDATE phone_message_channels SET last_message = ? WHERE id = ?", {lastMessagePreview, channelId})
    end)

    CreateThread(function()
        -- Combined update: unread + deleted in one query
        MySQL.update("UPDATE phone_message_members SET unread = unread + 1, deleted = 0 WHERE channel_id = ? AND phone_number != ?", {channelId, senderNumber})
    end)

    CreateThread(function()
        -- Ensure sender's channel is not marked as deleted
        MySQL.update("UPDATE phone_message_members SET deleted = 0 WHERE channel_id = ? AND phone_number = ?", {channelId, senderNumber})
    end)

    -- REALTIME FIX: Get all channel members and broadcast consistently
    -- Broadcast to ALL members including sender for multi-device support
    local members = MySQL.query.await("SELECT phone_number FROM phone_message_members WHERE channel_id = ?", {channelId})

    -- Batch process members
    if members and #members > 0 then
        debugprint("Processing", #members, "members for notifications")
        for i = 1, #members do
            local memberNumber = members[i].phone_number
            local memberSource = GetSourceFromNumber(memberNumber)

            debugprint("Processing member:", memberNumber, "source:", memberSource)

            -- Broadcast to ALL members (including sender for multi-device sync)
            if memberSource then
                TriggerClientEvent("phone:messages:newMessage", memberSource, channelId, messageId, senderNumber, content, attachments)
                debugprint("Sent newMessage event to source:", memberSource)
            end

            -- Send notification to recipients only (NOT sender)
            if content ~= "<!CALL-NO-ANSWER!>" and memberNumber ~= senderNumber then
                CreateThread(function()
                    debugprint("Starting notification thread for:", memberNumber)
                    
                    local contact = GetContact(senderNumber, memberNumber)
                    local senderName = (contact and contact.name) or senderNumber
                    local thumbnail = nil

                    if attachments then
                        local attachmentData = json.decode(attachments)
                        if attachmentData and attachmentData[1] then
                            thumbnail = attachmentData[1]
                        end
                    end

                    local notificationData = {
                        app = "Messages",
                        title = senderName,
                        content = content,
                        thumbnail = thumbnail,
                        avatar = contact and contact.avatar,
                        showAvatar = true
                    }

                    debugprint("Sending notification to:", memberNumber, "data:", json.encode(notificationData))
                    SendNotification(memberNumber, notificationData)
                end)
            end
        end
    else
        debugprint("No members found for channel:", channelId)
    end
    
    -- Execute callback if provided
    if callback then
        callback(channelId)
    end
    
    -- Trigger message sent event
    TriggerEvent("lb-phone:messages:messageSent", {
        channelId = channelId,
        messageId = messageId,
        sender = senderNumber,
        recipient = recipientNumber,
        message = content,
        attachments = attachments
    })
    
    return {
        channelId = channelId,
        messageId = messageId
    }
end

-- Export functions for external use
exports("SentMoney", function(senderNumber, recipientNumber, amount)
    assert(type(senderNumber) == "string", "Expected string for argument 1, got " .. type(senderNumber))
    assert(type(recipientNumber) == "string", "Expected string for argument 2, got " .. type(recipientNumber))
    assert(type(amount) == "number", "Expected number for argument 3, got " .. type(amount))
    
    local message = "<!SENT-PAYMENT-" .. math.floor(amount + 0.5) .. "!>"
    SendMessage(senderNumber, recipientNumber, message)
end)

exports("SendCoords", function(senderNumber, recipientNumber, coords)
    assert(type(senderNumber) == "string", "Expected string for argument 1, got " .. type(senderNumber))
    assert(type(recipientNumber) == "string", "Expected string for argument 2, got " .. type(recipientNumber))
    assert(type(coords) == "vector2", "Expected vector2 for argument 3, got " .. type(coords))
    
    local message = "<!SENT-LOCATION-X=" .. coords.x .. "Y=" .. coords.y .. "!>"
    SendMessage(senderNumber, recipientNumber, message)
end)

exports("SendMessage", function(senderNumber, recipientNumber, content, attachments, callback, channelId)
    assert(type(senderNumber) == "string", "Expected string for argument 1, got " .. type(senderNumber))
    assert(type(recipientNumber) == "string" or recipientNumber == nil, "Expected string or nil for argument 2, got " .. type(recipientNumber))
    assert(type(content) == "string" or content == nil, "Expected string or nil for argument 3, got " .. type(content))
    assert(type(attachments) == "table" or type(attachments) == "string" or attachments == nil, "Expected table, string or nil for argument 4, got " .. type(attachments))
    assert(type(callback) == "function" or callback == nil, "Expected function or nil for argument 5, got " .. type(callback))
    
    return SendMessage(senderNumber, recipientNumber, content, attachments, callback, channelId)
end)

-- Send message callback
BaseCallback("messages:sendMessage", function(source, phoneNumber, recipientNumber, content, attachments, channelId)
    if ContainsBlacklistedWord(source, "Messages", content) then
        return false
    end
    
    return SendMessage(phoneNumber, recipientNumber, content, attachments, nil, channelId)
end, nil, {
    preventSpam = true,
    rateLimit = 30
})

-- Create group message
BaseCallback("messages:createGroup", function(source, phoneNumber, members, initialMessage, attachments)
    -- Giới hạn số lượng members trong group
    if type(members) == "table" and #members > 50 then
        debugprint("Too many members in group:", #members)
        return false
    end
    
    local groupId = MySQL.insert.await("INSERT INTO phone_message_channels (is_group) VALUES (1)")
    if not groupId then
        return false
    end
    
    -- Add creator as owner
    local groupMembers = {{number = phoneNumber, isOwner = true}}
    MySQL.update.await("INSERT INTO phone_message_members (channel_id, phone_number, is_owner) VALUES (?, ?, 1)", {groupId, phoneNumber})
    
    -- Add other members
    for i = 1, #members do
        local memberNumber = members[i]
        MySQL.update.await("INSERT INTO phone_message_members (channel_id, phone_number, is_owner) VALUES (?, ?, 0)", {groupId, memberNumber})
        table.insert(groupMembers, {number = memberNumber, isOwner = false})
    end
    
    -- Create channel data
    local channelData = {
        id = groupId,
        lastMessage = initialMessage,
        timestamp = os.time() * 1000,
        name = nil,
        isGroup = true,
        members = groupMembers,
        unread = false
    }
    
    -- Notify all members about new group
    for i = 1, #members do
        local memberSource = GetSourceFromNumber(members[i])
        if memberSource then
            TriggerClientEvent("phone:messages:newChannel", memberSource, channelData)
        end
    end
    
    -- Notify creator
    TriggerClientEvent("phone:messages:newChannel", source, channelData)
    
    -- Send initial message if provided
    return SendMessage(phoneNumber, nil, initialMessage, attachments, nil, groupId)
end)

-- Rename group - HYBRID OPTIMIZATION
BaseCallback("messages:renameGroup", function(source, phoneNumber, groupId, newName)
    local affectedRows = MySQL.update.await("UPDATE phone_message_channels SET `name` = ? WHERE id = ? AND is_group = 1", {newName, groupId})
    local success = affectedRows > 0

    if success then
        -- HYBRID: Keep -1 broadcast for UI updates (conversations list needs this)
        -- This is acceptable since renaming happens rarely
        TriggerClientEvent("phone:messages:renameGroup", -1, groupId, newName)

        -- Invalidate cache
        invalidateChannelCache(groupId)
    end

    return success
end)

-- Update group avatar - HYBRID OPTIMIZATION
BaseCallback("messages:updateGroupAvatar", function(source, phoneNumber, groupId, avatarUrl)
    local isMember = MySQL.scalar.await("SELECT TRUE FROM phone_message_members WHERE channel_id = ? AND phone_number = ?", {
        groupId, phoneNumber
    })

    if not isMember then
        return false
    end

    local affectedRows = MySQL.update.await("UPDATE phone_message_channels SET `avatar` = ? WHERE id = ? AND is_group = 1", {
        avatarUrl, groupId
    })

    local success = affectedRows > 0

    if success then
        -- HYBRID: Keep -1 broadcast for UI updates (conversations list needs forceUpdateConversations)
        -- Client needs to refresh conversations list to show new avatar
        -- This is acceptable since avatar updates happen rarely
        TriggerClientEvent("phone:messages:updateGroupAvatar", -1, {
            channelId = groupId,
            avatar = avatarUrl
        })

        -- Invalidate cache
        invalidateChannelCache(groupId)
    end

    return {
        success = success,
        groupId = groupId,
        avatar = avatarUrl
    }
end)

-- Set group avatar (wrapper for client compatibility)
BaseCallback("messages:setGroupAvatar", function(source, phoneNumber, data)
    local groupId = data.id
    local avatarUrl = data.avatar
    
    local isMember = MySQL.scalar.await("SELECT TRUE FROM phone_message_members WHERE channel_id = ? AND phone_number = ?", {
        groupId, phoneNumber
    })

    if not isMember then
        return false
    end

    local affectedRows = MySQL.update.await("UPDATE phone_message_channels SET `avatar` = ? WHERE id = ? AND is_group = 1", {
        avatarUrl, groupId
    })

    local success = affectedRows > 0

    if success then
        TriggerClientEvent("phone:messages:updateGroupAvatar", -1, {
            channelId = groupId,
            avatar = avatarUrl
        })
        invalidateChannelCache(groupId)
    end

    return success
end)

-- Remove group avatar (set to null)
BaseCallback("messages:removeGroupAvatar", function(source, phoneNumber, data)
    local groupId = data.id
    
    local isMember = MySQL.scalar.await("SELECT TRUE FROM phone_message_members WHERE channel_id = ? AND phone_number = ?", {
        groupId, phoneNumber
    })

    if not isMember then
        return false
    end

    -- Set avatar to NULL in database
    local affectedRows = MySQL.update.await("UPDATE phone_message_channels SET `avatar` = NULL WHERE id = ? AND is_group = 1", {
        groupId
    })

    local success = affectedRows > 0

    if success then
        -- Broadcast với avatar = nil (Lua nil sẽ thành JSON null)
        TriggerClientEvent("phone:messages:updateGroupAvatar", -1, {
            channelId = groupId,
            avatar = nil
        })
        invalidateChannelCache(groupId)
    end

    return success
end)

-- Get recent message channels
BaseCallback("messages:getRecentMessages", function(source, phoneNumber)
    return MySQL.query.await([[
        SELECT
            channel.id AS channel_id,
            channel.is_group,
            channel.`name`,
            channel.avatar,
            channel.last_message,
            channel.last_message_timestamp,
            channel_member.phone_number,
            channel_member.is_owner,
            channel_member.unread,
            channel_member.deleted
        FROM
            phone_message_members target_member

        INNER JOIN phone_message_channels channel
            ON channel.id = target_member.channel_id

        INNER JOIN phone_message_members channel_member
            ON channel_member.channel_id = channel.id

        WHERE
            target_member.phone_number = ?

        ORDER BY
            channel.last_message_timestamp DESC
    ]], {phoneNumber})
end)

-- Get messages from a channel
BaseCallback("messages:getMessages", function(source, phoneNumber, channelId, page)
    return MySQL.query.await([[
        SELECT id, sender, content, attachments, `timestamp`
        FROM phone_message_messages

        WHERE channel_id = ? AND EXISTS (SELECT TRUE FROM phone_message_members m WHERE m.channel_id = ? AND m.phone_number = ?)

        ORDER BY `timestamp` DESC
        LIMIT ?, ?
    ]], {channelId, channelId, phoneNumber, page * 25, 25})
end)

-- Delete message - OPTIMIZED
BaseCallback("messages:deleteMessage", function(source, phoneNumber, messageId, channelId)
    if not Config.DeleteMessages then
        return false
    end

    -- Check if this is the latest message
    local latestMessageId = MySQL.scalar.await("SELECT MAX(id) FROM phone_message_messages WHERE channel_id = ?", {channelId})
    local isLatestMessage = latestMessageId == messageId

    -- Delete the message
    local affectedRows = MySQL.update.await("DELETE FROM phone_message_messages WHERE id = ? AND sender = ? AND channel_id = ?", {
        messageId, phoneNumber, channelId
    })
    local success = affectedRows > 0

    -- Update channel's last message if this was the latest message
    if success and isLatestMessage then
        MySQL.update.await("UPDATE phone_message_channels SET last_message = ? WHERE id = ?", {
            L("APPS.MESSAGES.MESSAGE_DELETED"), channelId
        })
    end

    -- REALTIME FIX: Broadcast to ALL channel members immediately
    -- This ensures deletion is visible even for messages just sent
    if success then
        local members = MySQL.query.await("SELECT phone_number FROM phone_message_members WHERE channel_id = ?", {channelId})

        if members then
            for i = 1, #members do
                local memberNumber = members[i].phone_number
                local memberSource = GetSourceFromNumber(memberNumber)
                
                -- Broadcast to this member if they're online
                if memberSource then
                    TriggerClientEvent("phone:messages:messageDeleted", memberSource, channelId, messageId, isLatestMessage)
                end
            end
        end

        -- Invalidate cache
        invalidateChannelCache(channelId)
    end

    -- Return full info for immediate UI update
    return {
        success = success,
        messageId = messageId,
        channelId = channelId,
        isLastMessage = isLatestMessage
    }
end)

-- Add member to group
BaseCallback("messages:addMember", function(source, phoneNumber, groupId, newMemberNumber)
    local affectedRows = MySQL.update.await("INSERT IGNORE INTO phone_message_members (channel_id, phone_number) VALUES (?, ?)", {
        groupId, newMemberNumber
    })
    local success = affectedRows > 0
    local newMemberSource = GetSourceFromNumber(newMemberNumber)

    if not success then
        return false
    end

    -- Get member info (với isOwner = false vì member mới không phải owner)
    local memberInfo = {
        number = newMemberNumber,
        isOwner = false
    }

    local allMembers = MySQL.query.await("SELECT phone_number FROM phone_message_members WHERE channel_id = ?", {groupId})

    -- Gửi event memberAdded cho TẤT CẢ members NGOẠI TRỪ người thêm (người thêm reload qua callback)
    for i = 1, #allMembers do
        local memberNumber = allMembers[i].phone_number

        if memberNumber ~= phoneNumber then
            local memberSource = GetSourceFromNumber(memberNumber)
            if memberSource then
                TriggerClientEvent("phone:messages:memberAdded", memberSource, groupId, memberInfo)
            end
        end
    end

    -- Send group info to new member
    if newMemberSource then
        local members = MySQL.query.await("SELECT phone_number AS `number`, is_owner AS isOwner FROM phone_message_members WHERE channel_id = ?", {groupId})
        local groupInfo = MySQL.single.await("SELECT `name`, avatar, last_message, last_message_timestamp FROM phone_message_channels WHERE id = ?", {groupId})

        if #members > 0 and groupInfo then
            TriggerClientEvent("phone:messages:newChannel", newMemberSource, {
                id = groupId,
                lastMessage = groupInfo.last_message,
                timestamp = groupInfo.last_message_timestamp,
                name = groupInfo.name,
                avatar = groupInfo.avatar,
                isGroup = true,
                members = members,
                unread = false
            })
        end
    end

    return {
        success = true,
        member = memberInfo
    }
end)

-- Remove member from group - OPTIMIZED
BaseCallback("messages:removeMember", function(source, phoneNumber, groupId, targetMemberNumber)
    -- Check if requester is owner
    local isOwner = MySQL.scalar.await("SELECT is_owner FROM phone_message_members WHERE channel_id = ? AND phone_number = ?", {
        groupId, phoneNumber
    })

    if not isOwner then
        return false
    end

    -- LẤY DANH SÁCH MEMBERS TRƯỚC KHI XÓA (bao gồm cả member sẽ bị xóa)
    local memberSources = getChannelMemberSources(groupId)

    -- Remove the member
    local affectedRows = MySQL.update.await("DELETE FROM phone_message_members WHERE channel_id = ? AND phone_number = ?", {
        groupId, targetMemberNumber
    })
    local success = affectedRows > 0

    if success then
        -- Broadcast tới TẤT CẢ members (bao gồm cả người bị xóa)
        broadcastToRelevant("phone:messages:memberRemoved", memberSources, groupId, targetMemberNumber)

        -- Invalidate cache
        invalidateChannelCache(groupId)
    end

    -- Return đầy đủ thông tin để UI cập nhật ngay
    return {
        success = success,
        number = targetMemberNumber,
        channelId = groupId
    }
end)

-- Leave group - OPTIMIZED
BaseCallback("messages:leaveGroup", function(source, phoneNumber, groupId)
    -- Check if leaving member is owner
    local isOwner = MySQL.scalar.await("SELECT is_owner FROM phone_message_members WHERE channel_id = ? AND phone_number = ?", {
        groupId, phoneNumber
    })

    -- If owner is leaving, transfer ownership to another member
    if isOwner then
        MySQL.update.await([[
            UPDATE phone_message_members m
            SET is_owner = TRUE
            WHERE m.channel_id = ?
            AND m.phone_number != ?
            LIMIT 1
        ]], {groupId, phoneNumber})

        -- Get new owner
        local newOwner = MySQL.scalar.await("SELECT phone_number FROM phone_message_members WHERE channel_id = ? AND is_owner = TRUE", {groupId})

        -- OPTIMIZED: Broadcast only to channel members
        local memberSources = getChannelMemberSources(groupId)
        broadcastToRelevant("phone:messages:ownerChanged", memberSources, groupId, newOwner)
    end

    -- LẤY DANH SÁCH MEMBERS TRƯỚC KHI XÓA (bao gồm cả người rời nhóm)
    local memberSources = getChannelMemberSources(groupId)

    -- Remove member from group
    local affectedRows = MySQL.update.await("DELETE FROM phone_message_members WHERE channel_id = ? AND phone_number = ?", {
        groupId, phoneNumber
    })
    local success = affectedRows > 0

    -- Check if group is now empty
    local remainingMembers = MySQL.scalar.await("SELECT COUNT(1) FROM phone_message_members WHERE channel_id = ?", {groupId})
    local isEmpty = remainingMembers == 0

    if success then
        -- Broadcast tới TẤT CẢ members (bao gồm cả người rời nhóm)
        broadcastToRelevant("phone:messages:memberRemoved", memberSources, groupId, phoneNumber)

        -- Invalidate cache
        invalidateChannelCache(groupId)
    end

    -- Delete empty group
    if isEmpty then
        MySQL.update.await("DELETE FROM phone_message_channels WHERE id = ?", {groupId})
    end

    return success
end)

-- Mark messages as read
BaseCallback("messages:markRead", function(source, phoneNumber, channelId)
    MySQL.update.await("UPDATE phone_message_members SET unread = 0 WHERE channel_id = ? AND phone_number = ?", {
        channelId, phoneNumber
    })
    return true
end)

-- Delete conversations
BaseCallback("messages:deleteConversations", function(source, phoneNumber, channelIds)
    if type(channelIds) ~= "table" then
        return false
    end

    MySQL.update.await("UPDATE phone_message_members SET deleted = 1 WHERE channel_id IN (?) AND phone_number = ?", {
        channelIds, phoneNumber
    })
    return true
end)
