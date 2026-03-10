-- Mail app for LB Phone
-- Handles email account management, sending/receiving emails, and mail actions

local currentMail = nil

-- Process mail data to decode JSON fields
local function processMail(mail)
    if not mail then
        return false
    end
    
    -- Decode attachments
    if not mail.attachments then
        mail.attachments = {}
    else
        mail.attachments = json.decode(mail.attachments)
    end
    
    -- Decode actions
    if not mail.actions then
        mail.actions = {}
    else
        mail.actions = json.decode(mail.actions)
    end
    
    return mail
end

-- Register NUI callback for Mail actions
RegisterNUICallback("Mail", function(data, callback)
    local action = data.action
    debugprint("Mail:" .. (action or ""))
    
    if action == "isLoggedIn" then
        -- Check if user is logged into mail
        TriggerCallback("mail:isLoggedIn", callback)
        
    elseif action == "createMail" then
        -- Create new mail account
        TriggerCallback("mail:createAccount", callback, data.data.email, data.data.password)
        
    elseif action == "changePassword" then
        -- Change mail account password
        TriggerCallback("mail:changePassword", callback, data.oldPassword, data.newPassword)
        
    elseif action == "deleteAccount" then
        -- Delete mail account
        TriggerCallback("mail:deleteAccount", callback, data.password)
        
    elseif action == "login" then
        -- Login to mail account
        TriggerCallback("mail:login", callback, data.data.email, data.data.password)
        
    elseif action == "logout" then
        -- Logout from mail account
        TriggerCallback("mail:logout", callback)
        
    elseif action == "getMails" then
        -- Get mail list with pagination
        TriggerCallback("mail:getMails", callback, {
            lastId = data.lastId
        })
        
    elseif action == "getMail" then
        -- Get specific mail by ID
        TriggerCallback("mail:getMail", function(mail)
            currentMail = processMail(mail)
            callback(currentMail)
        end, data.id)
        
    elseif action == "search" then
        -- Search mails
        TriggerCallback("mail:getMails", callback, {
            search = data.query,
            lastId = data.lastId
        })
        
    elseif action == "sendMail" then
        -- Send new mail
        TriggerCallback("mail:sendMail", callback, data.data)
        
    elseif action == "deleteMail" then
        -- Delete mail
        TriggerCallback("mail:deleteMail", callback, data.id)
        
    elseif action == "action" then
        -- Execute mail action (buttons in emails)
        if currentMail.id ~= data.id then
            return debugprint("wrong mail id for action")
        end
        
        local actionIndex = (data.actionId or 0) + 1
        local actionData = currentMail.actions[actionIndex]
        
        if not actionData then
            return debugprint("no action found", actionIndex)
        end
        
        -- Handle QB-Core mail format
        if actionData.data and actionData.data.qbMail then
            TriggerEvent(actionData.event, actionData.data.data)
            return callback("ok")
        end
        
        -- Handle server or client events
        if actionData.isServer then
            TriggerServerEvent(actionData.event, data.id, actionData.data)
        else
            TriggerEvent(actionData.event, data.id, actionData.data)
        end
        
        callback("ok")
    end
end)

-- Handle new mail notification from server
RegisterNetEvent("phone:mail:newMail", function(mailData)
    SendReactMessage("mail:newMail", mailData)
end)

-- Handle mail deletion notification from server
RegisterNetEvent("phone:mail:mailDeleted", function(mailId)
    SendReactMessage("mail:deleteMail", mailId)
end)
