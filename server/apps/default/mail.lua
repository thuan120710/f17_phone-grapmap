



exports("GetEmailAddress", function(phoneNumber)
    return GetLoggedInAccount(phoneNumber, "Mail")
end)


local function CreateMailCallback(callbackName, handler, defaultReturn)
    BaseCallback("mail:" .. callbackName, function(source, phoneNumber, ...)
        local emailAddress = GetLoggedInAccount(phoneNumber, "Mail")
        if not emailAddress then
            return defaultReturn
        end
        return handler(source, phoneNumber, emailAddress, ...)
    end, defaultReturn)
end


local function NotifyLoggedInAccounts(emailAddress, notification, senderPhoneNumber)
    local accounts = MySQL.query.await("SELECT phone_number FROM phone_logged_in_accounts WHERE username = ? AND app = 'Mail' AND `active` = 1", {emailAddress})
    notification.app = "Mail"
    
    for _, account in ipairs(accounts) do
        if account.phone_number ~= senderPhoneNumber then
            SendNotification(account.phone_number, notification)
        end
    end
end


CreateMailCallback("isLoggedIn", function(source, phoneNumber, emailAddress)
    return emailAddress
end, false)


local function CreateMailAccount(emailAddress, password, callback)

    if not emailAddress or not password or #emailAddress < 3 or #password < 3 then
        if callback then
            callback({success = false, reason = "Invalid email / password"})
        end
        return false, "Invalid email / password"
    end
    

    password = GetPasswordHash(password)
    

    local exists = MySQL.scalar.await("SELECT 1 FROM phone_mail_accounts WHERE address=?", {emailAddress})
    if exists then
        if callback then
            callback({success = false, error = "Address already exists"})
        end
        return false, "Address already exists"
    end
    

    local result = MySQL.update.await("INSERT INTO phone_mail_accounts (address, `password`) VALUES (?, ?)", {emailAddress, password})
    local success = result == 1
    
    if not success then
        if callback then
            callback({success = false, error = "Server error"})
        end
        return false, "Server error"
    end
    
    if callback then
        callback({success = true})
    end
    return true
end


exports("CreateMailAccount", CreateMailAccount)


BaseCallback("mail:createAccount", function(source, phoneNumber, username, password)

    if #username < 3 or #password < 3 then
        return {
            success = false,
            error = "Invalid email / password"
        }
    end
    

    local emailAddress = username .. "@" .. Config.EmailDomain
    

    local success, error = CreateMailAccount(emailAddress, password)
    

    if success then
        AddLoggedInAccount(phoneNumber, "Mail", emailAddress)
    end
    
    return {
        success = success,
        error = error
    }
end)


CreateMailCallback("changePassword", function(source, phoneNumber, emailAddress, oldPassword, newPassword)

    if not Config.ChangePassword.Mail then
        infoprint("warning", string.format("%s tried to change password on Mail, but it's not enabled in the config.", source))
        return false
    end
    

    if oldPassword == newPassword or #newPassword < 3 then
        debugprint("same password / too short")
        return false
    end
    

    local currentPasswordHash = MySQL.scalar.await("SELECT password FROM phone_mail_accounts WHERE address = ?", {emailAddress})
    

    if not currentPasswordHash or not VerifyPasswordHash(oldPassword, currentPasswordHash) then
        return false
    end
    

    local updated = MySQL.update.await("UPDATE phone_mail_accounts SET password = ? WHERE address = ?", {
        GetPasswordHash(newPassword),
        emailAddress
    })
    
    if updated <= 0 then
        return false
    end
    

    NotifyLoggedInAccounts(emailAddress, {
        title = L("BACKEND.MISC.LOGGED_OUT_PASSWORD.TITLE"),
        content = L("BACKEND.MISC.LOGGED_OUT_PASSWORD.DESCRIPTION")
    }, phoneNumber)
    

    MySQL.update.await("DELETE FROM phone_logged_in_accounts WHERE username = ? AND app = 'Mail' AND phone_number != ?", {
        emailAddress, phoneNumber
    })
    

    ClearActiveAccountsCache("Mail", emailAddress, phoneNumber)
    

    Log("Mail", source, "info", 
        L("BACKEND.LOGS.CHANGED_PASSWORD.TITLE"),
        L("BACKEND.LOGS.CHANGED_PASSWORD.DESCRIPTION", {
            number = phoneNumber,
            username = emailAddress,
            app = "Mail"
        })
    )
    

    TriggerClientEvent("phone:logoutFromApp", -1, {
        username = emailAddress,
        app = "mail",
        reason = "password",
        number = phoneNumber
    })
    
    return true
end, false)


CreateMailCallback("deleteAccount", function(source, phoneNumber, emailAddress, password)

    if not Config.DeleteAccount.Mail then
        infoprint("warning", string.format("%s tried to delete their account on Mail, but it's not enabled in the config.", source))
        return false
    end
    

    local currentPasswordHash = MySQL.scalar.await("SELECT password FROM phone_mail_accounts WHERE address = ?", {emailAddress})
    

    if not currentPasswordHash or not VerifyPasswordHash(password, currentPasswordHash) then
        return false
    end
    

    local deleted = MySQL.update.await("DELETE FROM phone_mail_accounts WHERE address = ?", {emailAddress})
    
    if deleted <= 0 then
        return false
    end
    

    NotifyLoggedInAccounts(emailAddress, {
        title = L("BACKEND.MISC.DELETED_NOTIFICATION.TITLE"),
        content = L("BACKEND.MISC.DELETED_NOTIFICATION.DESCRIPTION")
    })
    

    MySQL.update.await("DELETE FROM phone_logged_in_accounts WHERE username = ? AND app = 'Mail'", {emailAddress})
    

    ClearActiveAccountsCache("Mail", emailAddress)
    

    Log("Mail", source, "info",
        L("BACKEND.LOGS.DELETED_ACCOUNT.TITLE"),
        L("BACKEND.LOGS.DELETED_ACCOUNT.DESCRIPTION", {
            number = phoneNumber,
            username = emailAddress,
            app = "Mail"
        })
    )
    

    TriggerClientEvent("phone:logoutFromApp", -1, {
        username = emailAddress,
        app = "mail",
        reason = "deleted"
    })
    
    return true
end, false)


BaseCallback("mail:login", function(source, phoneNumber, emailAddress, password)

    local passwordHash = MySQL.scalar.await("SELECT `password` FROM phone_mail_accounts WHERE address=?", {emailAddress})
    
    if not passwordHash then
        return {
            success = false,
            error = "Invalid address"
        }
    end
    

    if not VerifyPasswordHash(password, passwordHash) then
        return {
            success = false,
            error = "Invalid password"
        }
    end
    

    AddLoggedInAccount(phoneNumber, "Mail", emailAddress)
    
    return {
        success = true
    }
end, {
    success = false,
    error = "No phone equipped"
})


CreateMailCallback("logout", function(source, phoneNumber, emailAddress)
    RemoveLoggedInAccount(phoneNumber, "Mail", emailAddress)
    return {
        success = true
    }
end, {
    success = false,
    error = "Not logged in"
})


local function NotifyNewMail(mailData)
    if mailData.to == "all" then
        TriggerClientEvent("phone:mail:newMail", -1, mailData)
        return
    end
    
    local accounts = MySQL.query.await("SELECT phone_number FROM phone_logged_in_accounts WHERE app = 'Mail' AND username = ? AND active = 1", {mailData.to})
    
    for _, account in pairs(accounts) do
        local playerSource = GetSourceFromNumber(account.phone_number)
        if playerSource then
            TriggerClientEvent("phone:mail:newMail", playerSource, mailData)
        end
        
        SendNotification(account.phone_number, {
            app = "Mail",
            title = mailData.sender,
            content = mailData.subject,
            thumbnail = mailData.attachments[1]
        })
    end
end


local function SendMail(mailData)

    if mailData.to then
        if mailData.to ~= "all" then
            local accountExists = MySQL.scalar.await("SELECT 1 FROM phone_mail_accounts WHERE address = ?", {mailData.to})
            if not accountExists then
                return false, "Invalid address"
            end
        end
    else
        return false, "Invalid address"
    end
    

    if Config.ConvertMailToMarkdown and ConvertHTMLToMarkdown then
        mailData.message = ConvertHTMLToMarkdown(mailData.message)
    end
    

    mailData.attachments = mailData.attachments or {}
    mailData.actions = mailData.actions or {}
    

    local mailId = MySQL.insert.await("INSERT INTO phone_mail_messages (recipient, sender, subject, content, attachments, actions) VALUES (@recipient, @sender, @subject, @content, @attachments, @actions)", {
        ["@recipient"] = mailData.to,
        ["@sender"] = mailData.sender or "system",
        ["@subject"] = mailData.subject or "System mail",
        ["@content"] = mailData.message or "",
        ["@attachments"] = #mailData.attachments > 0 and json.encode(mailData.attachments) or nil,
        ["@actions"] = #mailData.actions > 0 and json.encode(mailData.actions) or nil
    })
    

    local mail = {
        id = mailId,
        to = mailData.to,
        sender = mailData.sender or "System",
        subject = mailData.subject or "System mail",
        message = mailData.message or "",
        attachments = mailData.attachments,
        actions = mailData.actions,
        read = false,
        timestamp = os.time() * 1000
    }
    

    TriggerEvent("lb-phone:mail:mailSent", mail)
    

    NotifyNewMail(mail)
    
    return true, mailId
end


exports("SendMail", SendMail)


local function GenerateEmailAccount(source, phoneNumber)
    if not Config.AutoCreateEmail or not phoneNumber then
        return
    end
    
    local firstname, lastname = GetCharacterName(source)
    

    firstname = firstname:gsub("[^%w]", "")
    lastname = lastname:gsub("[^%w]", "")
    

    if #firstname == 0 then
        firstname = GenerateString(5)
    end
    if #lastname == 0 then
        lastname = GenerateString(5)
    end
    

    local baseAddress = firstname .. "." .. lastname
    

    local existingCount = MySQL.scalar.await("SELECT COUNT(1) FROM phone_mail_accounts WHERE address LIKE ?", {baseAddress .. "%"}) or 0
    
    if existingCount > 0 then
        baseAddress = baseAddress .. (existingCount + 1)
    end
    

    local emailAddress = baseAddress .. "@" .. Config.EmailDomain
    

    local addressExists = MySQL.scalar.await("SELECT 1 FROM phone_mail_accounts WHERE address=?", {emailAddress})
    local attempts = 0
    
    while addressExists and attempts < 50 do
        emailAddress = firstname .. "." .. lastname .. math.random(1000, 9999) .. "@" .. Config.EmailDomain
        addressExists = MySQL.scalar.await("SELECT 1 FROM phone_mail_accounts WHERE address=?", {emailAddress})
        attempts = attempts + 1
        Wait(0)
    end
    
    if addressExists then
        debugprint("Failed to generate address for", source)
        return
    end
    

    emailAddress = emailAddress:lower()
    

    local password = GenerateString(5)
    

    if not CreateMailAccount(emailAddress, password) then
        return
    end
    

    AddLoggedInAccount(phoneNumber, "Mail", emailAddress)
    

    SendMail({
        to = emailAddress,
        sender = L("BACKEND.MAIL.AUTOMATIC_PASSWORD.SENDER"),
        subject = L("BACKEND.MAIL.AUTOMATIC_PASSWORD.SUBJECT"),
        message = L("BACKEND.MAIL.AUTOMATIC_PASSWORD.MESSAGE", {
            address = emailAddress,
            password = password
        })
    })
end

GenerateEmailAccount = GenerateEmailAccount


exports("DeleteMail", function(mailId)
    local deleted = MySQL.Sync.execute("DELETE FROM phone_mail_messages WHERE id=@id", {
        ["@id"] = mailId
    })
    
    if deleted > 0 then
        TriggerClientEvent("phone:mail:mailDeleted", -1, mailId)
    end
    
    return deleted > 0
end)


CreateMailCallback("sendMail", function(source, phoneNumber, emailAddress, mailData)

    if mailData.to == "all" then
        return false
    end
    
    local recipient = mailData.to
    local subject = mailData.subject
    local message = mailData.message
    local attachments = mailData.attachments
    

    if not recipient or not subject or not message or type(attachments) ~= "table" then
        return false
    end
    

    if ContainsBlacklistedWord(source, "Mail", subject) or ContainsBlacklistedWord(source, "Mail", message) then
        return false
    end
    

    local success, mailId = SendMail({
        to = recipient,
        sender = emailAddress,
        subject = subject,
        message = message,
        attachments = attachments
    })
    
    if not success then
        return false
    end
    

    Log("Mail", source, "info",
        L("BACKEND.LOGS.MAIL_TITLE"),
        L("BACKEND.LOGS.NEW_MAIL", {
            sender = emailAddress,
            recipient = recipient
        })
    )
    
    return mailId
end)


CreateMailCallback("getMails", function(source, phoneNumber, emailAddress, options)
    local lastId = options and options.lastId
    local searchTerm = options and options.search and #options.search > 0 and "%" .. options.search .. "%" or nil
    
    local params = {emailAddress, emailAddress}
    
    local query = [[
        SELECT
            m.id,
            m.recipient AS `to`,
            m.sender,
            m.`subject`,
            LEFT(m.content, 70) AS message,
            m.`read`,
            m.`timestamp`

        FROM
            phone_mail_messages m

        WHERE (
            recipient=?
            OR recipient="all"
            OR sender=?
        ) {EXCLUDE_DELETED} {SEARCH} {PAGINATION}

        ORDER BY `id` DESC

        LIMIT 10
    ]]
    

    if Config.DeleteMail then
        query = query:gsub("{EXCLUDE_DELETED}", [[
            AND NOT EXISTS (
                SELECT 1
                FROM phone_mail_deleted d
                WHERE d.message_id = m.id
                AND d.address = ?
            )
        ]])
        table.insert(params, emailAddress)
    else
        query = query:gsub("{EXCLUDE_DELETED}", "")
    end
    

    if searchTerm then
        query = query:gsub("{SEARCH}", [[
            AND (
                m.recipient LIKE ?
                OR m.sender LIKE ?
                OR m.subject LIKE ?
                OR m.content LIKE ?
            )
        ]])
        table.insert(params, searchTerm)
        table.insert(params, searchTerm)
        table.insert(params, searchTerm)
        table.insert(params, searchTerm)
    else
        query = query:gsub("{SEARCH}", "")
    end
    

    if lastId then
        query = query:gsub("{PAGINATION}", "AND m.id < ?")
        table.insert(params, lastId)
    else
        query = query:gsub("{PAGINATION}", "")
    end
    
    return MySQL.query.await(query, params)
end, {})


CreateMailCallback("getMail", function(source, phoneNumber, emailAddress, mailId)
    local mail = MySQL.single.await([[
        SELECT
            id, recipient AS `to`, sender, subject, content as message, attachments, `read`, `timestamp`, actions

        FROM phone_mail_messages

        WHERE (
            recipient=@address
            OR recipient="all"
            OR sender=@address
        ) AND id=@id
    ]], {
        ["@address"] = emailAddress,
        ["@id"] = mailId
    })
    
    if not mail then
        return false
    end
    

    if not mail.read then
        MySQL.update("UPDATE phone_mail_messages SET `read`=1 WHERE id=? AND sender != ?", {mailId, emailAddress})
    end
    
    return mail
end)


CreateMailCallback("deleteMail", function(source, phoneNumber, emailAddress, mailId)
    if not Config.DeleteMail then
        return
    end
    
    MySQL.update.await("INSERT IGNORE INTO phone_mail_deleted (message_id, address) VALUES (?, ?)", {mailId, emailAddress})
    
    return true
end)
