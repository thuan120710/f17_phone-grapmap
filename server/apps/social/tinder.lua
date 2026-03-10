-- Create a new Tinder account
BaseCallback("tinder:createAccount", function(source, phoneNumber, data)
    local exists = MySQL.scalar.await("SELECT TRUE FROM phone_tinder_accounts WHERE phone_number = ?", { phoneNumber })
    if exists then
        return false
    end

    local affectedRows = MySQL.update.await([[
        INSERT INTO phone_tinder_accounts
            (`name`, phone_number, photos, bio, dob, is_male, interested_men, interested_women)
        VALUES
            (@name, @phoneNumber, @photos, @bio, @dob, @isMale, @showMen, @showWomen)
    ]], {
        ["@name"] = data.name,
        ["@phoneNumber"] = phoneNumber,
        ["@photos"] = json.encode(data.photos),
        ["@bio"] = data.bio,
        ["@dob"] = data.dob,
        ["@isMale"] = data.isMale,
        ["@showMen"] = data.showMen,
        ["@showWomen"] = data.showWomen
    })

    return affectedRows > 0
end, false)

-- Delete a Tinder account
BaseCallback("tinder:deleteAccount", function(source, phoneNumber)
    if not Config.DeleteAccount.Spark then
        infoprint("warning", "%s tried to delete their spark account, but it's not enabled in the config.", source)
        return false
    end

    local affectedRows = MySQL.update.await("DELETE FROM phone_tinder_accounts WHERE phone_number = ?", { phoneNumber })
    if affectedRows == 0 then
        return false
    end

    MySQL.update("DELETE FROM phone_tinder_swipes WHERE swiper = ? OR swipee = ?", { phoneNumber, phoneNumber })
    MySQL.update("DELETE FROM phone_tinder_matches WHERE phone_number_1 = ? OR phone_number_2 = ?", { phoneNumber, phoneNumber })
    MySQL.update("DELETE FROM phone_tinder_messages WHERE sender = ? OR recipient = ?", { phoneNumber, phoneNumber })

    return true
end)

-- Update a Tinder account
BaseCallback("tinder:updateAccount", function(source, phoneNumber, data)
    local affectedRows = MySQL.update.await([[
        UPDATE phone_tinder_accounts
        SET
            `name` = @name,
            photos = @photos,
            bio = @bio,
            is_male = @isMale,
            interested_men = @showMen,
            interested_women = @showWomen,
            `active` = @active
        WHERE phone_number = @phoneNumber
    ]], {
        ["@name"] = data.name,
        ["@photos"] = json.encode(data.photos),
        ["@bio"] = data.bio,
        ["@isMale"] = data.isMale,
        ["@showMen"] = data.showMen,
        ["@showWomen"] = data.showWomen,
        ["@active"] = data.active,
        ["@phoneNumber"] = phoneNumber
    })

    return affectedRows > 0
end, false)

-- Check if user is logged in
BaseCallback("tinder:isLoggedIn", function(source, phoneNumber)
    local account = MySQL.single.await(
        "SELECT `name`, photos, bio, dob, is_male, interested_men, interested_women, `active` FROM phone_tinder_accounts WHERE phone_number = ?",
        { phoneNumber }
    )

    if account then
        MySQL.update.await("UPDATE phone_tinder_accounts SET last_seen = NOW() WHERE phone_number = ?", { phoneNumber })
    end

    return account
end, false)

-- Get Tinder feed
BaseCallback("tinder:getFeed", function(source, phoneNumber, page)
    return MySQL.query.await([[
        SELECT
            a.`name`, a.phone_number, a.photos, a.bio, a.dob
        FROM
            phone_tinder_accounts a
        JOIN
            phone_tinder_accounts b
        ON
            b.phone_number = @phoneNumber
        WHERE
            a.phone_number != @phoneNumber
            AND a.`active` = 1
            AND (a.is_male = b.interested_men OR a.is_male = (NOT b.interested_women))
            AND (a.interested_men = b.is_male OR a.interested_women = (NOT b.is_male))
            AND NOT EXISTS (SELECT TRUE FROM phone_tinder_swipes WHERE swiper = @phoneNumber AND swipee = a.phone_number)
        ORDER BY a.phone_number
        LIMIT @page, @perPage
    ]], {
        ["@phoneNumber"] = phoneNumber,
        ["@page"] = page * 10,
        ["@perPage"] = 10
    })
end, {})

-- Handle swipe action
BaseCallback("tinder:swipe", function(source, phoneNumber, swipeeNumber, liked)
    local affectedRows = MySQL.query.await(
        "INSERT INTO phone_tinder_swipes (swiper, swipee, liked) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE liked = ?",
        { phoneNumber, swipeeNumber, liked, liked }
    )

    if affectedRows == 0 or not liked then
        return false
    end

    local mutualLike = MySQL.scalar.await(
        "SELECT liked FROM phone_tinder_swipes WHERE swiper = ? AND swipee = ?",
        { swipeeNumber, phoneNumber }
    ) == true

    if not mutualLike then
        return false
    end

    MySQL.update.await(
        "INSERT INTO phone_tinder_matches (phone_number_1, phone_number_2) VALUES (?, ?)",
        { phoneNumber, swipeeNumber }
    )

    local swiperAccount = MySQL.single.await(
        "SELECT `name`, photos FROM phone_tinder_accounts WHERE phone_number = ?",
        { phoneNumber }
    )

    if not swiperAccount then
        return
    end

    SendNotification(swipeeNumber, {
        app = "Tinder",
        title = L("BACKEND.TINDER.NEW_MATCH"),
        content = L("BACKEND.TINDER.MATCHED_WITH", { name = swiperAccount.name }),
        thumbnail = json.decode(swiperAccount.photos)[1]
    })

    return true
end)

-- Get matches
BaseCallback("tinder:getMatches", function(source, phoneNumber)
    return MySQL.query.await([[
        SELECT
            a.`name`, a.phone_number, a.photos, a.dob, a.bio, a.is_male, b.latest_message
        FROM
            phone_tinder_accounts a
        JOIN
            phone_tinder_matches b
        ON
            (b.phone_number_1 = @phoneNumber AND b.phone_number_2 = a.phone_number)
            OR
            (b.phone_number_2 = @phoneNumber AND b.phone_number_1 = a.phone_number)
        ORDER BY b.latest_message_timestamp DESC
    ]], {
        ["@phoneNumber"] = phoneNumber
    })
end)

-- Send a message
BaseCallback("tinder:sendMessage", function(source, sender, recipient, content, attachments)
    if ContainsBlacklistedWord(source, "Spark", content) then
        return false
    end

    local senderAccount = MySQL.single.await(
        "SELECT `name`, photos FROM phone_tinder_accounts WHERE phone_number = ?",
        { sender }
    )

    if not senderAccount then
        return true
    end

    local messageId = MySQL.insert.await(
        "INSERT INTO phone_tinder_messages (sender, recipient, content, attachments) VALUES (?, ?, ?, ?)",
        { sender, recipient, content, attachments }
    )

    if not messageId then
        return false
    end

    MySQL.update.await(
        "UPDATE phone_tinder_matches SET latest_message = ? WHERE (phone_number_1 = ? AND phone_number_2 = ?) OR (phone_number_2 = ? AND phone_number_1 = ?)",
        { content, sender, recipient, sender, recipient }
    )

    local recipientSource = GetSourceFromNumber(recipient)
    if recipientSource then
        TriggerClientEvent("phone:tinder:receiveMessage", recipientSource, {
            sender = sender,
            recipient = recipient,
            content = content,
            attachments = attachments,
            timestamp = os.time() * 1000
        })
    end

    SendNotification(recipient, {
        app = "Tinder",
        title = senderAccount.name,
        content = content,
        thumbnail = attachments and json.decode(attachments)[1] or nil,
        avatar = json.decode(senderAccount.photos)[1],
        showAvatar = true
    })

    return true
end)

-- Get messages
BaseCallback("tinder:getMessages", function(source, phoneNumber, number, page)
    return MySQL.query.await([[
        SELECT
            sender, recipient, content, attachments, timestamp
        FROM
            phone_tinder_messages
        WHERE
            (sender = @phoneNumber AND recipient = @number)
            OR
            (recipient = @phoneNumber AND sender = @number)
        ORDER BY timestamp DESC
        LIMIT @page, @perPage
    ]], {
        ["@phoneNumber"] = phoneNumber,
        ["@number"] = number,
        ["@page"] = page * 25,
        ["@perPage"] = 25
    })
end)

-- Auto-disable inactive accounts
CreateThread(function()
    if not Config.AutoDisableSparkAccounts then
        return
    end

    local interval = 3600000 -- 1 hour
    local daysInactive = type(Config.AutoDisableSparkAccounts) == "number" and math.max(Config.AutoDisableSparkAccounts, 1) or 7

    while not DatabaseCheckerFinished do
        Wait(500)
    end

    while true do
        MySQL.update("UPDATE phone_tinder_accounts SET active = 0 WHERE active = 1 AND last_seen < NOW() - INTERVAL ? DAY", { daysInactive }, function(affectedRows)
            debugprint("Disabled", affectedRows, "inactive Spark accounts.")
        end)
        Wait(interval)
    end
end)