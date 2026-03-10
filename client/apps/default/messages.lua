local restrictedActions = {
    "sendMessage",
    "createGroup",
    "renameGroup"
}

local function buildConversationsList(recentMessages)
    local conversations = {}

    local function findConversationIndex(channelId)
        for i = 1, #conversations do
            if conversations[i].id == channelId then
                return i
            end
        end
        return false
    end

    for i = 1, #recentMessages do
        local message = recentMessages[i]
        local conversationIndex = findConversationIndex(message.channel_id)

        if not conversationIndex then
            if message.is_group then
                conversations[#conversations + 1] = {
                    id = message.channel_id,
                    lastMessage = message.last_message,
                    timestamp = message.last_message_timestamp,
                    name = message.name,
                    avatar = message.avatar,
                    isGroup = true,
                    members = {{
                        isOwner = message.is_owner,
                        number = message.phone_number
                    }}
                }
            else
                if message.phone_number ~= currentPhone then
                    conversations[#conversations + 1] = {
                        id = message.channel_id,
                        lastMessage = message.last_message,
                        timestamp = message.last_message_timestamp,
                        number = message.phone_number,
                        isGroup = false
                    }
                end
            end
        else
            if message.is_group then
                local members = conversations[conversationIndex].members
                members[#members + 1] = {
                    isOwner = message.is_owner,
                    number = message.phone_number
                }
            end
        end
    end

    for i = 1, #recentMessages do
        local message = recentMessages[i]
        local conversationIndex = findConversationIndex(message.channel_id)

        if conversationIndex and message.phone_number == currentPhone then
            conversations[conversationIndex].deleted = message.deleted
            conversations[conversationIndex].unread = message.unread > 0
        end
    end

    return conversations
end

RegisterNUICallback("Messages", function(data, callback)
    if not currentPhone then
        return
    end

    local action = data.action

    if table.contains(restrictedActions, action) and not CanInteract() then
        return callback(false)
    end

    if data.attachments and #data.attachments == 0 then
        data.attachments = nil
    elseif data.attachments then
        data.attachments = json.encode(data.attachments)
    end
    
    if action == "sendMessage" then
        TriggerServerEvent("phone:messages:messageSent", data.number, data.content, data.attachments)
        TriggerCallback("messages:sendMessage", callback, data.number, data.content, data.attachments, data.id)

    elseif action == "createGroup" then
        local memberNumbers = {}
        for i = 1, #data.members do
            memberNumbers[i] = data.members[i].number
        end
        TriggerCallback("messages:createGroup", callback, memberNumbers, data.content, data.attachments)

    elseif action == "renameGroup" then
        TriggerCallback("messages:renameGroup", callback, data.id, data.name)

    elseif action == "updateGroupAvatar" or action == "setGroupAvatar" then
        TriggerCallback("messages:updateGroupAvatar", callback, data.id, data.avatar)

    elseif action == "removeGroupAvatar" then
        TriggerCallback("messages:updateGroupAvatar", callback, data.id, nil)

    elseif action == "getRecentMessages" then
        local recentMessages = AwaitCallback("messages:getRecentMessages")
        callback(buildConversationsList(recentMessages))
        
    elseif action == "getMessages" then
        TriggerCallback("messages:getMessages", function(messages)
            for i = 1, #messages do
                messages[i].attachments = json.decode(messages[i].attachments or "[]")
            end
            callback(messages)
        end, data.id, data.page)

    elseif action == "deleteMessage" then
        if Config.DeleteMessages then
            TriggerCallback("messages:deleteMessage", function(result)
                if callback then
                    callback(result)
                end
            end, data.id, data.channel)
        else
            if callback then
                callback(false)
            end
        end
        
    elseif action == "addMember" then
        TriggerCallback("messages:addMember", function(result)
            -- Gửi event tới React để cập nhật UI ngay lập tức
            if result and result.success and result.member then
                SendReactMessage("messages:addMember", {
                    channelId = data.id,
                    number = result.member.number,
                    isOwner = result.member.isOwner or false
                })
            end
            -- Trả callback về cho UI
            if callback then
                callback(result)
            end
        end, data.id, data.number)
        
    elseif action == "removeMember" then
        TriggerCallback("messages:removeMember", function(result)
            -- Gửi event tới React để cập nhật UI ngay lập tức
            if result and result.success then
                SendReactMessage("messages:removeMember", {
                    channelId = result.channelId,
                    number = result.number
                })
            end
            -- Trả callback về cho UI
            if callback then
                callback(result)
            end
        end, data.id, data.number)

    elseif action == "leaveGroup" then
        TriggerCallback("messages:leaveGroup", callback, data.id)

    elseif action == "markRead" then
        TriggerCallback("messages:markRead", callback, data.id)

    elseif action == "deleteConversations" then
        TriggerCallback("messages:deleteConversations", callback, data.channels)
    end
end)

RegisterNetEvent("phone:messages:newMessage", function(channelId, messageId, sender, content, attachments)
    SendReactMessage("messages:newMessage", {
        channelId = channelId,
        messageId = messageId,
        sender = sender,
        content = content,
        attachments = attachments and json.decode(attachments) or {}
    })
end)

RegisterNetEvent("phone:messages:messageDeleted", function(channelId, messageId, isLastMessage)
    SendReactMessage("messages:messageDeleted", {
        channelId = channelId,
        messageId = messageId,
        isLastMessage = isLastMessage
    })
end)

RegisterNetEvent("phone:messages:renameGroup", function(channelId, name)
    SendReactMessage("messages:renameGroup", {
        channelId = channelId,
        name = name
    })
end)

RegisterNetEvent("phone:messages:updateGroupAvatar", function(channelId, avatarUrl)
    SendReactMessage("messages:updateGroupAvatar", {
        channelId = channelId,
        avatar = avatarUrl
    })

    local recentMessages = AwaitCallback("messages:getRecentMessages")
    local conversations = buildConversationsList(recentMessages)

    SendNUIMessage({
        action = "forceUpdateConversations",
        data = conversations
    })
end)

RegisterNetEvent("phone:messages:memberAdded", function(channelId, memberInfo)
    SendReactMessage("messages:addMember", {
        channelId = channelId,
        number = memberInfo.number,
        isOwner = memberInfo.isOwner or false
    })
end)

RegisterNetEvent("phone:messages:memberRemoved", function(channelId, number)
    -- Kiểm tra xem người bị xóa có phải là chính mình không
    if number == currentPhone then
        -- Nếu là chính mình bị xóa, reload toàn bộ conversations để xóa group khỏi danh sách
        local recentMessages = AwaitCallback("messages:getRecentMessages")
        local conversations = buildConversationsList(recentMessages)
        
        SendNUIMessage({
            action = "forceUpdateConversations",
            data = conversations
        })
    else
        -- Nếu là người khác bị xóa, chỉ cập nhật danh sách members
        SendReactMessage("messages:removeMember", {
            channelId = channelId,
            number = number
        })
    end
end)

RegisterNetEvent("phone:messages:ownerChanged", function(channelId, number)
    SendReactMessage("messages:changeOwner", {
        channelId = channelId,
        number = number
    })
end)

RegisterNetEvent("phone:messages:newChannel", function(channelData)
    SendReactMessage("messages:newChannel", channelData)
end)

-- ========================================
-- PERFORMANCE OPTIMIZATION
-- Track when user opens/closes Messages app
-- ========================================

local messagesAppOpen = false

-- Track when Messages app is opened
RegisterNUICallback("messagesAppOpened", function(data, callback)
    if not messagesAppOpen then
        messagesAppOpen = true
        TriggerServerEvent("phone:messages:appOpened")
    end
    callback(true)
end)

-- Track when Messages app is closed
RegisterNUICallback("messagesAppClosed", function(data, callback)
    if messagesAppOpen then
        messagesAppOpen = false
        TriggerServerEvent("phone:messages:appClosed")
    end
    callback(true)
end)

-- Alternative: Track app changes via getRecentMessages callback
local originalGetRecentMessages = function(data, callback)
    if not messagesAppOpen then
        messagesAppOpen = true
        TriggerServerEvent("phone:messages:appOpened")
    end
    TriggerCallback("messages:getRecentMessages", callback)
end
