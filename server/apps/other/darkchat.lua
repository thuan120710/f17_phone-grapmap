



local function NotifyUsersWithUsername(username, notificationData, excludePhoneNumber)
    local query = "SELECT phone_number FROM phone_logged_in_accounts WHERE app = 'DarkChat' AND `active` = 1 AND username = ?"
    if excludePhoneNumber then
        query = query .. " AND phone_number != ?"
    end
    
    local params = {username}
    if excludePhoneNumber then
        table.insert(params, excludePhoneNumber)
    end
    
    local users = MySQL.query.await(query, params)
    
    for i = 1, #users do
        SendNotification(users[i].phone_number, notificationData)
    end
end


BaseCallback("darkchat:getUsername", function(source, phoneNumber)
    local username = GetLoggedInAccount(phoneNumber, "DarkChat")
    
    if not username then

        username = MySQL.scalar.await("SELECT username FROM phone_darkchat_accounts WHERE phone_number = ? AND `password` IS NULL", {
            phoneNumber
        })
        
        if username then
            AddLoggedInAccount(phoneNumber, "DarkChat", username)
        else
            return false
        end
    end
    

    local hasPassword = MySQL.scalar.await("SELECT TRUE FROM phone_darkchat_accounts WHERE username = ? AND `password` IS NOT NULL", {
        username
    })
    
    return {
        username = username,
        password = hasPassword and true or false
    }
end)


BaseCallback("darkchat:setPassword", function(source, phoneNumber, password)
    if #password < 3 then
        debugprint("DarkChat: password < 3 characters")
        return false
    end
    
    local username = GetLoggedInAccount(phoneNumber, "DarkChat")
    if not username then
        return false
    end
    

    local hasPassword = MySQL.scalar.await("SELECT TRUE FROM phone_darkchat_accounts WHERE username = ? AND `password` IS NOT NULL", {
        username
    })
    
    if hasPassword then
        return false
    end
    
    local passwordHash = GetPasswordHash(password)
    MySQL.update.await("UPDATE phone_darkchat_accounts SET `password` = ? WHERE username = ?", {
        passwordHash,
        username
    })
    
    return true
end)


BaseCallback("darkchat:login", function(source, phoneNumber, username, password)
    local storedPassword = MySQL.scalar.await("SELECT `password` FROM phone_darkchat_accounts WHERE username = ?", {
        username
    })
    
    if not storedPassword then
        return {
            success = false,
            reason = "invalid_username"
        }
    end
    
    if not VerifyPasswordHash(password, storedPassword) then
        return {
            success = false,
            reason = "incorrect_password"
        }
    end
    
    AddLoggedInAccount(phoneNumber, "DarkChat", username)
    
    return {
        success = true
    }
end)


BaseCallback("darkchat:register", function(source, phoneNumber, username, password)
    username = username:lower()
    
    if not IsUsernameValid(username) then
        return {
            success = false,
            reason = "USERNAME_NOT_ALLOWED"
        }
    end
    

    local exists = MySQL.scalar.await("SELECT 1 FROM phone_darkchat_accounts WHERE username = ?", {
        username
    })
    
    if exists then
        return {
            success = false,
            reason = "username_taken"
        }
    end
    
    local passwordHash = GetPasswordHash(password)
    local inserted = MySQL.update.await("INSERT INTO phone_darkchat_accounts (phone_number, username, `password`) VALUES (?, ?, ?)", {
        phoneNumber,
        username,
        passwordHash
    })
    
    if inserted <= 0 then
        return {
            success = false,
            reason = "unknown"
        }
    end
    
    AddLoggedInAccount(phoneNumber, "DarkChat", username)
    
    return {
        success = true
    }
end)


local function CreateAuthenticatedCallback(callbackName, handler, defaultReturn)
    BaseCallback("darkchat:" .. callbackName, function(source, phoneNumber, ...)
        local username = GetLoggedInAccount(phoneNumber, "DarkChat")
        if not username then
            return defaultReturn
        end
        
        return handler(source, phoneNumber, username, ...)
    end, defaultReturn)
end


CreateAuthenticatedCallback("changePassword", function(source, phoneNumber, username, oldPassword, newPassword)
    if not Config.ChangePassword.DarkChat then
        infoprint("warning", string.format("%s tried to change password on DarkChat, but it's not enabled in the config.", source))
        return false
    end
    
    if oldPassword == newPassword or #newPassword < 3 then
        debugprint("same password / too short")
        return false
    end
    
    local storedPassword = MySQL.scalar.await("SELECT `password` FROM phone_darkchat_accounts WHERE username = ?", {
        username
    })
    
    if not storedPassword or not VerifyPasswordHash(oldPassword, storedPassword) then
        return false
    end
    
    local updated = MySQL.update.await("UPDATE phone_darkchat_accounts SET `password` = ? WHERE username = ?", {
        GetPasswordHash(newPassword),
        username
    })
    
    if updated <= 0 then
        return false
    end
    

    NotifyUsersWithUsername(username, {
        title = L("BACKEND.MISC.LOGGED_OUT_PASSWORD.TITLE"),
        content = L("BACKEND.MISC.LOGGED_OUT_PASSWORD.DESCRIPTION")
    }, phoneNumber)
    

    MySQL.update.await("DELETE FROM phone_logged_in_accounts WHERE username = ? AND app = 'DarkChat' AND phone_number != ?", {
        username,
        phoneNumber
    })
    
    ClearActiveAccountsCache("DarkChat", username, phoneNumber)
    
    TriggerClientEvent("phone:logoutFromApp", -1, {
        username = username,
        app = "darkchat",
        reason = "password",
        number = phoneNumber
    })
    
    return true
end)


CreateAuthenticatedCallback("deleteAccount", function(source, phoneNumber, username, password)
    if not Config.DeleteAccount.DarkChat then
        infoprint("warning", string.format("%s tried to delete their account on DarkChat, but it's not enabled in the config.", source))
        return false
    end
    
    local storedPassword = MySQL.scalar.await("SELECT `password` FROM phone_darkchat_accounts WHERE username = ?", {
        username
    })
    
    if not storedPassword or not VerifyPasswordHash(password, storedPassword) then
        return false
    end
    

    NotifyUsersWithUsername(username, {
        title = L("BACKEND.MISC.DELETED_NOTIFICATION.TITLE"),
        content = L("BACKEND.MISC.DELETED_NOTIFICATION.DESCRIPTION")
    })
    

    MySQL.update.await("DELETE FROM phone_logged_in_accounts WHERE username = ? AND app = 'DarkChat'", {
        username
    })
    
    ClearActiveAccountsCache("DarkChat", username)
    
    TriggerClientEvent("phone:logoutFromApp", -1, {
        username = username,
        app = "darkchat",
        reason = "deleted"
    })
    
    return true
end)


CreateAuthenticatedCallback("logout", function(source, phoneNumber, username)
    RemoveLoggedInAccount(phoneNumber, "DarkChat", username)
    return true
end)


CreateAuthenticatedCallback("joinChannel", function(source, phoneNumber, username, channelName)

    local alreadyMember = MySQL.scalar.await("SELECT TRUE FROM phone_darkchat_members WHERE channel_name = ? AND username = ?", {
        channelName,
        username
    })
    
    if alreadyMember then
        debugprint("darkchat: already in channel")
        return false
    end
    

    local channelExists = MySQL.scalar.await("SELECT TRUE FROM phone_darkchat_channels WHERE `name` = ?", {
        channelName
    })
    

    if not channelExists then
        MySQL.update.await("INSERT INTO phone_darkchat_channels (`name`) VALUES (?)", {
            channelName
        })
        
        Log("DarkChat", source, "info",
            L("BACKEND.LOGS.DARKCHAT_CREATED_TITLE"),
            L("BACKEND.LOGS.DARKCHAT_CREATED_DESCRIPTION", {
                creator = username,
                channel = channelName
            })
        )
    end
    

    local inserted = MySQL.update.await("INSERT INTO phone_darkchat_members (channel_name, username) VALUES (?, ?)", {
        channelName,
        username
    })
    
    if inserted <= 0 then
        debugprint("darkchat: failed to insert into members")
        return false
    end
    

    if not channelExists then
        return {
            name = channelName,
            members = 1
        }
    end
    

    local channelInfo = MySQL.single.await([[
        SELECT `name`, (SELECT COUNT(username) FROM phone_darkchat_members WHERE channel_name = `name`) AS members
        FROM phone_darkchat_channels c
        WHERE `name` = ?
    ]], {
        channelName
    })
    

    local lastMessage = MySQL.single.await([[
        SELECT sender, content, `timestamp`
        FROM phone_darkchat_messages
        WHERE `channel` = ?
        ORDER BY `timestamp` DESC
        LIMIT 1
    ]], {
        channelName
    })
    
    if lastMessage then
        channelInfo.sender = lastMessage.sender
        channelInfo.lastMessage = lastMessage.content
        channelInfo.timestamp = lastMessage.timestamp
    end
    
    TriggerClientEvent("phone:darkChat:updateChannel", -1, channelName, username, "joined")
    
    return channelInfo
end)


CreateAuthenticatedCallback("leaveChannel", function(source, phoneNumber, username, channelName)
    local removed = MySQL.update.await("DELETE FROM phone_darkchat_members WHERE channel_name = ? AND username = ?", {
        channelName,
        username
    })
    
    if not removed then
        return false
    end
    
    TriggerClientEvent("phone:darkChat:updateChannel", -1, channelName, username, "left")
    
    return true
end)


CreateAuthenticatedCallback("getChannels", function(source, phoneNumber, username)
    return MySQL.query.await([[
        SELECT
            `name`,
            (SELECT COUNT(username) FROM phone_darkchat_members WHERE channel_name = `name`) AS members,
            m.sender AS sender,
            m.content AS lastMessage,
            m.`timestamp` AS `timestamp`
        FROM phone_darkchat_channels c
        LEFT JOIN phone_darkchat_messages m ON m.`channel` = c.name
        WHERE EXISTS (SELECT TRUE FROM phone_darkchat_members WHERE channel_name = c.name AND username = ?)
        AND COALESCE(m.`timestamp`, '1970-01-01 00:00:00') = (
            SELECT COALESCE(MAX(`timestamp`), '1970-01-01 00:00:00') FROM phone_darkchat_messages WHERE `channel` = c.`name`
        )
    ]], {
        username
    })
end, {})


CreateAuthenticatedCallback("getMessages", function(source, phoneNumber, username, channelName, page)
    return MySQL.query.await([[
        SELECT sender, content, `timestamp`
        FROM phone_darkchat_messages
        WHERE `channel` = ?
        ORDER BY `timestamp` DESC
        LIMIT ?, ?
    ]], {
        channelName,
        page * 15,
        15
    })
end)


local function SendMessageToDatabase(sender, channel, content)
    local messageId = MySQL.insert.await("INSERT INTO phone_darkchat_messages (sender, `channel`, content) VALUES (?, ?, ?)", {
        sender,
        channel,
        content
    })
    
    if not messageId then
        return false
    end
    

    NotifyPhones([[
        phone_darkchat_members m
        JOIN phone_logged_in_accounts l
            ON l.app = 'DarkChat'
            AND l.`active` = 1
            AND l.username = m.username
        WHERE
            m.channel_name = @channel
            AND m.username != @username
    ]], {
        app = "DarkChat",
        title = channel,
        content = sender .. ": " .. content
    }, "l.", {
        ["@channel"] = channel,
        ["@username"] = sender
    })
    
    TriggerClientEvent("phone:darkChat:newMessage", -1, channel, sender, content)
    
    return true
end


CreateAuthenticatedCallback("sendMessage", function(source, phoneNumber, username, channelName, message)
    if ContainsBlacklistedWord(source, "DarkChat", message) then
        return false
    end
    
    if not SendMessageToDatabase(username, channelName, message) then
        return false
    end
    
    Log("DarkChat", source, "info",
        L("BACKEND.LOGS.DARKCHAT_MESSAGE_TITLE"),
        L("BACKEND.LOGS.DARKCHAT_MESSAGE_DESCRIPTION", {
            sender = username,
            channel = channelName,
            message = message
        })
    )
    
    return true
end)


exports("SendDarkChatMessage", function(username, channel, message, callback)
    assert(type(username) == "string", "username must be a string")
    assert(type(channel) == "string", "channel must be a string")
    assert(type(message) == "string", "message must be a string")
    
    local success = SendMessageToDatabase(username, channel, message)
    
    if callback then
        callback(success)
    end
    
    return success
end)


exports("SendDarkChatLocation", function(username, channel, location, callback)
    assert(type(username) == "string", "Expected string for argument 1, got " .. type(username))
    assert(type(channel) == "string", "Expected string for argument 2, got " .. type(channel))
    assert(type(location) == "vector2", "Expected vector2 for argument 3, got " .. type(location))
    
    local locationMessage = string.format("<!SENT-LOCATION-X=%sY=%s!>", location.x, location.y)
    local success = SendMessageToDatabase(username, channel, locationMessage)
    
    if callback then
        callback(success)
    end
    
    return success
end)
