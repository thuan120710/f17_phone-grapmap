


local notificationActions = {}


local function getNotifications()
    local notifications = AwaitCallback("getNotifications")
    

    for i = 1, #notifications do
        local notification = notifications[i]
        

        if notification.content == nil then
            notification.content = notification.title
            notification.title = nil
        end
        

        if notification.custom_data then
            local customData = json.decode(notification.custom_data)
            if customData.buttons then
                notification.actions = customData.buttons
                notificationActions[notification.id] = notification
            end
            notification.custom_data = nil
        end
    end
    
    return notifications
end


local function deleteNotification(notificationId)
    if not notificationId then
        return true
    end
    

    if type(notificationId) == "string" and notificationId:find("client%-notification%-") then
        notificationActions[notificationId] = nil
        return true
    end
    

    local success = AwaitCallback("deleteNotification", notificationId)
    if not success then
        return false
    end
    

    if notificationActions[notificationId] then
        notificationActions[notificationId] = nil
    end
    
    return success
end


local function clearNotifications(appName)
    local success = AwaitCallback("clearNotifications", appName)
    if not success then
        return false
    end
    

    for id, notification in pairs(notificationActions) do
        if notification.app == appName then
            notificationActions[id] = nil
        end
    end
    
    return success
end


local function handleNotificationButton(notificationId, buttonIndex)
    local notification = notificationActions[notificationId]
    if not notification or not notification.actions then
        debugprint("No buttons found for notification", notificationId)
        return false
    end
    
    local button = notification.actions[buttonIndex]
    if not button then
        debugprint("Button not found for notification", notificationId, buttonIndex)
        return false
    end
    

    if button.event then
        if button.server then
            TriggerServerEvent(button.event, button.data)
        else
            TriggerEvent(button.event, button.data)
        end
    end
    
    return true
end


RegisterNUICallback("Notifications", function(data, callback)
    local action = data.action
    debugprint("Notifications:" .. (action or ""))
    
    if action == "getNotifications" then
        return callback(getNotifications())
    elseif action == "deleteNotification" then
        if data.id ~= nil then
            return callback(deleteNotification(data.id))
        end
    elseif action == "clearNotifications" then
        return callback(clearNotifications(data.app))
    elseif action == "button" then
        callback(handleNotificationButton(data.id, (data.buttonId or 0) + 1))
    end
end)


RegisterNetEvent("phone:sendNotification", function(notification)

    if not HasPhoneItem(currentPhone) or phoneDisabled then
        debugprint("no phone, not showing notification")
        return
    end
    

    if notification.content == nil then
        notification.content = notification.title
        notification.title = nil
    end
    

    if notification.customData then
        if notification.customData.buttons and notification.id then
            notification.actions = notification.customData.buttons
            notificationActions[notification.id] = notification
        end
        notification.customData = nil
    end
    

    SendReactMessage("newNotification", notification)
end)


exports("SendNotification", function(notification)

    notification.id = "client-notification-" .. math.random()
    TriggerEvent("phone:sendNotification", notification)
end)
