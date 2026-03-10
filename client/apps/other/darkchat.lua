



RegisterNUICallback("DarkChat", function(data, callback)

    if not currentPhone then
        return
    end
    
    local action = data.action
    debugprint("DarkChat:" .. (action or ""))
    
    if action == "getUsername" then
        TriggerCallback("darkchat:getUsername", callback)
        
    elseif action == "setPassword" then
        TriggerCallback("darkchat:setPassword", callback, data.password)
        
    elseif action == "login" then
        TriggerCallback("darkchat:login", callback, data.username, data.password)
        
    elseif action == "logout" then
        TriggerCallback("darkchat:logout", callback)
        
    elseif action == "changePassword" then
        TriggerCallback("darkchat:changePassword", callback, data.oldPassword, data.newPassword)
        
    elseif action == "deleteAccount" then
        TriggerCallback("darkchat:deleteAccount", callback, data.password)
        
    elseif action == "register" then
        TriggerCallback("darkchat:register", callback, data.username, data.password)
        
    elseif action == "getChannels" then
        TriggerCallback("darkchat:getChannels", callback)
        
    elseif action == "joinChannel" then
        TriggerCallback("darkchat:joinChannel", callback, data.channel)
        
    elseif action == "getMessages" then
        TriggerCallback("darkchat:getMessages", callback, data.channel, data.page)
        
    elseif action == "sendMessage" then
        TriggerCallback("darkchat:sendMessage", callback, data.channel, data.content)
        
    elseif action == "leaveChannel" then
        TriggerCallback("darkchat:leaveChannel", callback, data.channel)
    end
end)


RegisterNetEvent("phone:darkchat:newMessage", function(channel, sender, content)
    SendReactMessage("darkchat:newMessage", {channel = channel, sender = sender, content = content})
end)


RegisterNetEvent("phone:darkChat:updateChannel", function(channel, username, action)
    SendReactMessage("darkChat:updateChannel", {channel = channel, username = username, action = action})
end)