
local disabledNotifications = Config.DisabledNotifications or {}


function SendNotification(phoneNumberOrSource, notificationData, callback)

    if table.contains(disabledNotifications, notificationData.app) then
        if callback then
            callback(false)
        end
        debugprint("Notification are disabled for app", notificationData.app)
        return
    end
    

    notificationData = table.clone(notificationData)
    

    if type(notificationData) ~= "table" or not notificationData.app then
        if type(phoneNumberOrSource) ~= "string" then
            if callback then
                callback(false)
            end
            debugprint("Invalid data or no app")
            return
        end
    end
    

    if notificationData.content and #notificationData.content > 500 then
        if callback then
            callback(false)
        end
        debugprint("Content too long")
        return
    end
    

    if type(phoneNumberOrSource) == "number" then
        notificationData.source = phoneNumberOrSource
    end
    

    if notificationData.app and not notificationData.source then
        if type(phoneNumberOrSource) == "string" then
            local source = GetSourceFromNumber(phoneNumberOrSource)
            if source then
                notificationData.source = source
            end
        end
    end
    

    if not notificationData.app or type(phoneNumberOrSource) ~= "string" then
        if callback then
            callback(true)
        end
        
        if notificationData.source then
            TriggerClientEvent("phone:sendNotification", notificationData.source, notificationData)
            debugprint("Sending notification to source: " .. notificationData.source)
        else
            debugprint("Couldn't find source, no notification printing")
        end
        
        debugprint("No app or no phone number provided (not a string)")
        return
    end
    

    if Config.MaxNotifications then
        local oldestId = MySQL.scalar.await("SELECT id FROM phone_notifications WHERE phone_number = ? ORDER BY id DESC LIMIT ?, 1", {
            phoneNumberOrSource, Config.MaxNotifications - 1
        })
        
        if oldestId then
            debugprint("Max notifications reached, deleting all older notifications", phoneNumberOrSource, oldestId)
            MySQL.update.await("DELETE FROM phone_notifications WHERE phone_number = ? AND id <= ?", {
                phoneNumberOrSource, oldestId
            })
        end
    end
    

    local customDataJson = nil
    if notificationData.customData then
        customDataJson = json.encode(notificationData.customData)
    end
    
    local notificationId = MySQL.insert.await("INSERT IGNORE INTO phone_notifications (phone_number, app, title, content, thumbnail, avatar, show_avatar, custom_data) VALUES (@phoneNumber, @app, @title, @content, @thumbnail, @avatar, @showAvatar, @data)", {
        ["@phoneNumber"] = phoneNumberOrSource,
        ["@app"] = notificationData.app,
        ["@title"] = notificationData.title,
        ["@content"] = notificationData.content,
        ["@thumbnail"] = notificationData.thumbnail,
        ["@avatar"] = notificationData.avatar,
        ["@showAvatar"] = notificationData.showAvatar,
        ["@data"] = customDataJson
    })
    
    notificationData.id = notificationId
    

    if notificationData.source then
        TriggerClientEvent("phone:sendNotification", notificationData.source, notificationData)
        debugprint("Sending notification to source: " .. notificationData.source)
    else
        debugprint("Couldn't find source, no notification printing")
    end
    
    if callback then
        callback(notificationId)
    end
end


exports("SendNotification", SendNotification)


function NotifyEveryone(notifyType, notificationData)
    assert(notifyType == "all" or notifyType == "online", "Invalid notify")
    assert(type(notificationData and notificationData.app) == "string", "Invalid app")
    assert(type(notificationData and notificationData.title) == "string", "Invalid title")
    

    if table.contains(disabledNotifications, notificationData.app) then
        debugprint("NotifyEveryone: Notification are disabled for app", notificationData.app)
        return
    end
    

    if notifyType == "all" then
        MySQL.insert([[
            INSERT INTO phone_notifications
                (phone_number, app, title, content, thumbnail, avatar, show_avatar)
            SELECT
                phone_number, @app, @title, @content, @thumbnail, @avatar, @showAvatar
            FROM
                phone_phones
            WHERE
                last_seen > DATE_SUB(NOW(), INTERVAL 7 DAY)
        ]], {
            ["@app"] = notificationData.app,
            ["@title"] = notificationData.title,
            ["@content"] = notificationData.content,
            ["@thumbnail"] = notificationData.thumbnail,
            ["@avatar"] = notificationData.avatar,
            ["@showAvatar"] = notificationData.showAvatar
        })
    end
    

    TriggerClientEvent("phone:sendNotification", -1, notificationData)
end


exports("NotifyEveryone", NotifyEveryone)


function NotifyPhones(sqlTable, notificationData, columnPrefix, parameters)

    if table.contains(disabledNotifications, notificationData.app) then
        debugprint("NotifyPhones: Notification are disabled for app", notificationData.app)
        return
    end
    

    if not parameters then
        parameters = {}
    end
    if not columnPrefix then
        columnPrefix = ""
    end
    

    parameters["@app"] = notificationData.app
    parameters["@title"] = notificationData.title
    parameters["@content"] = notificationData.content
    parameters["@thumbnail"] = notificationData.thumbnail
    parameters["@avatar"] = notificationData.avatar
    parameters["@showAvatar"] = notificationData.showAvatar
    

    local query = string.format([[
        INSERT INTO phone_notifications
            (phone_number, app, title, content, thumbnail, avatar, show_avatar)
        SELECT
            %sphone_number, @app, @title, @content, @thumbnail, @avatar, @showAvatar
        FROM
            %s
        RETURNING
            id, phone_number
    ]], columnPrefix, sqlTable)
    

    MySQL.query(query, parameters, function(results)
        for i = 1, #results do
            local phoneNumber = results[i].phone_number
            local source = GetSourceFromNumber(phoneNumber)
            
            if source then
                notificationData.id = results[i].id
                TriggerClientEvent("phone:sendNotification", source, notificationData)
            end
        end
    end)
end


function EmergencyNotification(source, alertData)
    assert(type(source) == "number", "Invalid source")
    assert(type(alertData) == "table", "Invalid data")
    
    SendNotification(source, {
        title = alertData.title or "Emergency Alert",
        content = alertData.content or "This is a test emergency alert.",
        icon = "./assets/img/icons/" .. (alertData.icon or "warning") .. ".png"
    })
end


exports("SendAmberAlert", EmergencyNotification)
exports("EmergencyNotification", EmergencyNotification)


BaseCallback("getNotifications", function(source, phoneNumber, ...)
    return MySQL.query.await("SELECT id, app, title, content, thumbnail, avatar, show_avatar AS showAvatar, custom_data, `timestamp` FROM phone_notifications WHERE phone_number=?", {
        phoneNumber
    })
end, {})


BaseCallback("deleteNotification", function(source, phoneNumber, notificationId)
    local deleted = MySQL.update.await("DELETE FROM phone_notifications WHERE id=? AND phone_number=?", {
        notificationId, phoneNumber
    })
    return deleted > 0
end)


BaseCallback("clearNotifications", function(source, phoneNumber, appName)
    MySQL.update.await("DELETE FROM phone_notifications WHERE phone_number=? AND app=?", {
        phoneNumber, appName
    })
    return true
end)
