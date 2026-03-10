local validActions = {
    "createAccount",
    "saveProfile",
    "sendMessage"
}

RegisterNUICallback("Tinder", function(data, callback)
    if not currentPhone then
        return
    end

    local action = data.action
    debugprint("Spark: " .. (action or ""))

    if table.contains(validActions, action) and not CanInteract() then
        return callback(false)
    end

    if action == "createAccount" then
        TriggerCallback("tinder:createAccount", callback, data.data)
    elseif action == "deleteAccount" then
        TriggerCallback("tinder:deleteAccount", callback)
    elseif action == "saveProfile" then
        TriggerCallback("tinder:updateAccount", callback, data.data)
    elseif action == "isLoggedIn" then
        local result = AwaitCallback("tinder:isLoggedIn")
        if not result then
            return callback(false)
        end

        local profile = {
            name = result.name,
            photos = json.decode(result.photos),
            dob = result.dob,
            bio = result.bio,
            showMen = result.interested_men,
            showWomen = result.interested_women,
            isMale = result.is_male,
            active = result.active
        }
        callback(profile)
    elseif action == "getFeed" then
        local feed = AwaitCallback("tinder:getFeed", data.page)
        local formattedFeed = {}

        for i = 1, #feed do
            local user = feed[i]
            formattedFeed[i] = {
                name = user.name,
                dob = user.dob,
                bio = user.bio,
                photos = json.decode(user.photos),
                number = user.phone_number
            }
        end
        callback(formattedFeed)
    elseif action == "swipe" then
        TriggerCallback("tinder:swipe", callback, data.number, data.like)
    elseif action == "getMatches" then
        local matches = AwaitCallback("tinder:getMatches")
        local response = { newMatches = {}, messages = {} }

        for i = 1, #matches do
            local match = matches[i]
            local formattedMatch = {
                name = match.name,
                number = match.phone_number,
                photos = json.decode(match.photos),
                dob = match.dob,
                bio = match.bio,
                isMale = match.is_male
            }

            if match.latest_message then
                formattedMatch.lastMessage = match.latest_message
                response.messages[#response.messages + 1] = formattedMatch
            else
                response.newMatches[#response.newMatches + 1] = formattedMatch
            end
        end
        callback(response)
    elseif action == "sendMessage" then
        local messageData = data.data
        if messageData.attachments and #messageData.attachments == 0 then
            messageData.attachments = nil
        end

        TriggerCallback("tinder:sendMessage", callback, messageData.recipient, messageData.content, messageData.attachments and json.encode(messageData.attachments))
    elseif action == "getMessages" then
        local messages = AwaitCallback("tinder:getMessages", data.number, data.page)
        for i = 1, #messages do
            messages[i].attachments = messages[i].attachments and json.decode(messages[i].attachments) or {}
        end
        callback(messages)
    end
end)

RegisterNetEvent("phone:tinder:receiveMessage", function(message)
    message.attachments = message.attachments and json.decode(message.attachments) or {}
    SendReactMessage("tinder:newMessage", message)
end)

-- Helper function to check if a table contains a value
function table.contains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end