
local ProfileCache = {}
local VideoCache = {}
local ThreadCache = {}
local FollowerSourcesCache = {}
local CACHE_TTL = 300000
local FOLLOWER_CACHE_TTL = 60000

local NotificationQueue = {}
local NotificationProcessing = false

local ActiveTikTokUsers = {}
local UsernameToSources = {}

local function clearExpiredCache()
    local now = GetGameTimer()

    if ProfileCache then
        for key, cache in pairs(ProfileCache) do
            if cache and (now - cache.timestamp) > CACHE_TTL then
                ProfileCache[key] = nil
            end
        end
    end

    if VideoCache then
        for key, cache in pairs(VideoCache) do
            if cache and (now - cache.timestamp) > CACHE_TTL then
                VideoCache[key] = nil
            end
        end
    end

    if ThreadCache then
        for key, cache in pairs(ThreadCache) do
            if cache and (now - cache.timestamp) > CACHE_TTL then
                ThreadCache[key] = nil
            end
        end
    end

    if FollowerSourcesCache then
        for key, cache in pairs(FollowerSourcesCache) do
            if cache and (now - cache.timestamp) > FOLLOWER_CACHE_TTL then
                FollowerSourcesCache[key] = nil
            end
        end
    end
end

local function invalidateProfileCache(username)
    ProfileCache[username] = nil
end

local function invalidateVideoCache(videoId)
    VideoCache[videoId] = nil
end

CreateThread(function()
    while true do
        Wait(300000)
        clearExpiredCache()
    end
end)

AddEventHandler("playerDropped", function()
    local source = source
    local username = ActiveTikTokUsers[source]

    if username then
        ActiveTikTokUsers[source] = nil
        if UsernameToSources[username] then
            for i, src in ipairs(UsernameToSources[username]) do
                if src == source then
                    table.remove(UsernameToSources[username], i)
                    break
                end
            end
        end
    end
end)

local function getActiveTikTokSources()
    local sources = {}
    for source, username in pairs(ActiveTikTokUsers) do
        if GetPlayerPing(source) > 0 then
            table.insert(sources, source)
        else

            ActiveTikTokUsers[source] = nil
            if UsernameToSources[username] then
                for i, s in ipairs(UsernameToSources[username]) do
                    if s == source then
                        table.remove(UsernameToSources[username], i)
                        break
                    end
                end
            end
        end
    end
    return sources
end


local function getSourcesForUsername(username)
    return UsernameToSources[username] or {}
end

local function getFollowerSources(username)
    local cached = FollowerSourcesCache[username]
    if cached and (GetGameTimer() - cached.timestamp) < FOLLOWER_CACHE_TTL then
        return cached.sources
    end

    local sources = {}
    local followers = MySQL.query.await("SELECT follower FROM phone_tiktok_follows WHERE followed = ?", { username })

    if not followers then
        FollowerSourcesCache[username] = {
            sources = sources,
            timestamp = GetGameTimer()
        }
        return sources
    end

    for i = 1, #followers do
        local followerUsername = followers[i].follower
        local followerSources = getSourcesForUsername(followerUsername)
        for _, src in ipairs(followerSources) do
            table.insert(sources, src)
        end
    end

    FollowerSourcesCache[username] = {
        sources = sources,
        timestamp = GetGameTimer()
    }

    return sources
end

local function broadcastToRelevant(eventName, data, targetSources)
    if not targetSources or #targetSources == 0 then
        return
    end

    for _, source in ipairs(targetSources) do
        if type(data) == "table" then
            TriggerClientEvent(eventName, source, table.unpack(data))
        else
            TriggerClientEvent(eventName, source, data)
        end
    end
end

local function getLoggedInTikTokAccount(playerId)
    local phoneNumber = GetEquippedPhoneNumber(playerId)
    if not phoneNumber then
        return false
    end
    return GetLoggedInAccount(phoneNumber, "TikTok")
end

local function createAuthenticatedCallback(callbackName, handler, defaultReturn)
    BaseCallback("tiktok:"..callbackName, function(source, phoneNumber, ...)
        local account = GetLoggedInAccount(phoneNumber, "TikTok")
        if not account then
            return defaultReturn
        end
        return handler(source, phoneNumber, account, ...)
    end, defaultReturn)
end

local function sendNotificationToAllAccounts(username, notification, excludePhoneNumber)
    local accounts = MySQL.query.await("SELECT phone_number FROM phone_logged_in_accounts WHERE username = ? AND app = 'TikTok' AND `active` = 1", { username })
    notification.app = "TikTok"

    for i = 1, #accounts do
        local phoneNumber = accounts[i].phone_number
        if phoneNumber ~= excludePhoneNumber then
            SendNotification(phoneNumber, notification)
        end
    end
end

local function getPhoneNumberToSourceMap(username)
    local map = {}
    local rows = MySQL.query.await("SELECT phone_number FROM phone_logged_in_accounts WHERE username = ? AND app = 'TikTok' AND `active` = 1", { username })
    for i = 1, (rows and #rows or 0) do
        local phoneNumber = rows[i].phone_number
        map[phoneNumber] = GetSourceFromNumber(phoneNumber)
    end
    return map
end

local function getTikTokProfile(username, loggedInUsername)
    local cacheKey = username
    if not loggedInUsername and ProfileCache[cacheKey] then
        local cached = ProfileCache[cacheKey]
        if (GetGameTimer() - cached.timestamp) < CACHE_TTL then
            return cached.data
        end
    end

    local fields = "`name`, bio, avatar, username, verified, follower_count, following_count, like_count, twitter, instagram, show_likes"
    local profile = nil

    if loggedInUsername then
        local query = [[
            SELECT %s,
                (SELECT TRUE FROM phone_tiktok_follows WHERE follower = @username AND followed = @loggedIn) AS isFollowingYou,
                (SELECT TRUE FROM phone_tiktok_follows WHERE follower = @loggedIn AND followed = @username) AS isFollowing
            FROM phone_tiktok_accounts WHERE username = @username
        ]]
        profile = MySQL.Sync.fetchAll(query:format(fields), {
            ["@username"] = username,
            ["@loggedIn"] = loggedInUsername
        })
        if profile then
            profile = profile[1]
        end
    else
        local query = "SELECT %s FROM phone_tiktok_accounts WHERE username = @username"
        profile = MySQL.Sync.fetchAll(query:format(fields), {
            ["@username"] = username
        })
        if profile then
            profile = profile[1]
        end
    end

    if profile then
        profile.isFollowing = profile.isFollowing == 1
        profile.isFollowingYou = profile.isFollowingYou == 1


        if not loggedInUsername then
            ProfileCache[cacheKey] = {
                data = profile,
                timestamp = GetGameTimer()
            }
        end
    end

    return profile
end

local notificationTypes = {
    like = "BACKEND.TIKTOK.LIKE",
    save = "BACKEND.TIKTOK.SAVE",
    comment = "BACKEND.TIKTOK.COMMENT",
    follow = "BACKEND.TIKTOK.FOLLOW",
    like_comment = "BACKEND.TIKTOK.LIKED_COMMENT",
    reply = "BACKEND.TIKTOK.REPLIED_COMMENT",
    message = "BACKEND.TIKTOK.DM",
    new_post = "BACKEND.TIKTOK.NEW_POST"
}

local function queueTikTokNotification(toUsername, fromUsername, notificationType, videoId, commentId, messageId, messageData)
    local notificationKey = notificationTypes[notificationType]
    if not notificationKey or toUsername == fromUsername then
        return
    end

    table.insert(NotificationQueue, {
        toUsername = toUsername,
        fromUsername = fromUsername,
        notificationType = notificationType,
        videoId = videoId,
        commentId = commentId,
        messageId = messageId,
        messageData = messageData,
        timestamp = os.time()
    })


    if not NotificationProcessing then
        NotificationProcessing = true
        CreateThread(processTikTokNotificationQueue)
    end
end

function processTikTokNotificationQueue()
    while #NotificationQueue > 0 do
        Wait(500)

        local batch = {}
        local batchSize = math.min(50, #NotificationQueue)

        for i = 1, batchSize do
            table.insert(batch, table.remove(NotificationQueue, 1))
        end


        for _, notif in ipairs(batch) do
            local toProfile = getTikTokProfile(notif.fromUsername)
            
            if toProfile then

                local params = { notif.toUsername, notif.fromUsername, notif.notificationType }
                local query = "SELECT 1 FROM phone_tiktok_notifications WHERE username = ? AND `from` = ? AND `type` = ?"

                if notif.videoId then
                    query = query.." AND video_id = ?"
                    table.insert(params, notif.videoId)
                end

                if notif.commentId then
                    query = query.." AND comment_id = ?"
                    table.insert(params, notif.commentId)
                end

                if notif.messageId then
                    query = query.." AND message_id = ?"
                    table.insert(params, notif.messageId)
                end

                local isUpdatingExisting = false
                if notif.notificationType == "message" then
                    local existingNotif = MySQL.scalar.await(
                        "SELECT id FROM phone_tiktok_notifications WHERE username = ? AND `from` = ? AND `type` = 'message' ORDER BY timestamp DESC LIMIT 1",
                        { notif.toUsername, notif.fromUsername }
                    )
                    
                    if existingNotif then
                        MySQL.update("UPDATE phone_tiktok_notifications SET message_id = ?, timestamp = NOW() WHERE id = ?", { notif.messageId, existingNotif })
                        isUpdatingExisting = true
                    end
                end

                local shouldSendPopup = false
                
                if not isUpdatingExisting then
                    local exists = MySQL.scalar.await(query, params) == 1
                    
                    if not exists then
                        MySQL.insert("INSERT INTO phone_tiktok_notifications (username, `from`, `type`, video_id, comment_id, message_id) VALUES (?, ?, ?, ?, ?, ?)",
                            { notif.toUsername, notif.fromUsername, notif.notificationType, notif.videoId, notif.commentId, notif.messageId }
                        )
                        shouldSendPopup = true
                    end
                else
                    shouldSendPopup = true
                end


                if shouldSendPopup then

                    local videoThumbnail = nil
                    if notif.videoId then
                        videoThumbnail = MySQL.Sync.fetchScalar("SELECT src FROM phone_tiktok_videos WHERE id = @id", {
                            ["@id"] = notif.videoId
                        })
                    end


                    local notification = {
                        app = "TikTok",
                        title = L(notificationTypes[notif.notificationType], { displayName = toProfile.name }),
                        thumbnail = videoThumbnail
                    }

                    if notif.notificationType == "message" then
                        notification.avatar = toProfile.avatar
                        notification.content = notif.messageData.content
                        notification.showAvatar = true
                    end


                    local accounts = MySQL.query.await("SELECT phone_number FROM phone_logged_in_accounts WHERE username = ? AND app = 'TikTok' AND `active` = 1", { notif.toUsername })
                    for i = 1, #accounts do
                        SendNotification(accounts[i].phone_number, notification)
                    end
                end
            end
        end
    end

    NotificationProcessing = false
end

local function sendTikTokNotification(toUsername, fromUsername, notificationType, videoId, commentId, messageId, messageData)
    queueTikTokNotification(toUsername, fromUsername, notificationType, videoId, commentId, messageId, messageData)
end

CreateThread(function()
    while true do
        if not DatabaseCheckerFinished then
            Wait(500)
        else
            break
        end
    end

    while true do
        MySQL.Async.execute("DELETE FROM phone_tiktok_notifications WHERE `timestamp` < DATE_SUB(NOW(), INTERVAL 7 DAY)",
            {})
        Wait(3600000)
    end
end)

RegisterLegacyCallback("tiktok:getNotifications", function(source, cb, page)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    local query = [[
        SELECT
            n.`type`, n.`timestamp`,
            CASE
                WHEN n.`type` = 'message' THEN n.message_id
                ELSE n.video_id
            END AS videoId,
            a.`name`, a.avatar, a.username, a.verified,
            CASE
                WHEN n.`type` = 'message' THEN NULL
                WHEN n.video_id IS NOT NULL THEN v.src
                ELSE NULL
            END AS videoSrc,
            n.comment_id,
            CASE
                WHEN n.comment_id IS NOT NULL THEN
                    c.comment
                ELSE NULL
            END AS commentText,
            CASE
                WHEN n.`type` = 'follow' THEN
                    CASE
                        WHEN f.follower IS NOT NULL THEN
                            TRUE
                        ELSE FALSE
                    END
                ELSE NULL
            END AS isFollowing,
            CASE
                WHEN n.`type` = 'reply' THEN
                c_original.comment
                ELSE NULL
            END AS originalText,
            CASE
                WHEN n.`type` = 'message' THEN m.content
                ELSE NULL
            END AS messageContent,
            CASE
                WHEN n.`type` = 'message' THEN m.channel_id
                ELSE NULL
            END AS channelId
        FROM
            phone_tiktok_notifications n
            LEFT JOIN phone_tiktok_accounts a ON n.from = a.username
            LEFT JOIN phone_tiktok_videos v ON n.video_id = v.id AND n.`type` != 'message'
            LEFT JOIN phone_tiktok_comments c ON n.comment_id = c.id
            LEFT JOIN phone_tiktok_comments c_original ON c.reply_to = c_original.id
            LEFT JOIN phone_tiktok_follows f ON n.username = f.follower AND n.from = f.followed
            LEFT JOIN phone_tiktok_messages m ON n.message_id = m.id AND n.`type` = 'message'
        WHERE
            n.username = @username
        ORDER BY
            n.`timestamp` DESC
        LIMIT @page, @perPage
    ]]

    MySQL.Async.fetchAll(query, {
        ["@username"] = account,
        ["@page"] = (page or 0) * 15,
        ["@perPage"] = 15
    }, function(results)
        cb({ success = true, data = results })
    end)
end)


RegisterLegacyCallback("tiktok:login", function(source, cb, username, password)
    local phoneNumber = GetEquippedPhoneNumber(source)
    if not phoneNumber then
        return cb({ success = false, error = "no_number" })
    end

    username = username:lower()

    MySQL.Async.fetchScalar("SELECT password FROM phone_tiktok_accounts WHERE username = @username", {
        ["@username"] = username
    }, function(hashedPassword)
        if not hashedPassword then
            return cb({ success = false, error = "invalid_username" })
        end

        if not VerifyPasswordHash(password, hashedPassword) then
            return cb({ success = false, error = "incorrect_password" })
        end

        local profile = getTikTokProfile(username)
        if not profile then
            return cb({ success = false, error = "invalid_username" })
        end

        AddLoggedInAccount(phoneNumber, "TikTok", username)
        cb({ success = true, data = profile })
    end)
end)


RegisterLegacyCallback("tiktok:signup", function(source, cb, username, password, displayName)
    local phoneNumber = GetEquippedPhoneNumber(source)
    if not phoneNumber then
        return cb({ success = false, error = "UNKNOWN" })
    end

    username = username:lower()

    if not IsUsernameValid(username) then
        return cb({ success = false, error = "USERNAME_NOT_ALLOWED" })
    end

    local exists = MySQL.Sync.fetchScalar("SELECT TRUE FROM phone_tiktok_accounts WHERE username = @username", {
        ["@username"] = username
    })
    if exists then
        return cb({ success = false, error = "USERNAME_TAKEN" })
    end

    MySQL.Sync.execute(
    "INSERT INTO phone_tiktok_accounts (`name`, username, password, phone_number) VALUES (@displayName, @username, @password, @phoneNumber)",
        {
            ["@displayName"] = displayName,
            ["@username"] = username,
            ["@password"] = GetPasswordHash(password),
            ["@phoneNumber"] = phoneNumber
        })

    AddLoggedInAccount(phoneNumber, "TikTok", username)
    cb({ success = true })


    if Config.AutoFollow.Enabled and Config.AutoFollow.Trendy.Enabled then
        for i = 1, #Config.AutoFollow.Trendy.Accounts do
            MySQL.update.await("INSERT INTO phone_tiktok_follows (followed, follower) VALUES (?, ?)", {
                Config.AutoFollow.Trendy.Accounts[i],
                username
            })
        end
    end
end, { preventSpam = true, rateLimit = 4 })


createAuthenticatedCallback("changePassword", function(source, phoneNumber, account, oldPassword, newPassword)
    if not Config.ChangePassword.Trendy then
        infoprint("warning",
            string.format("%s tried to change password on Trendy, but it's not enabled in the config.", source))
        return false
    end

    if oldPassword == newPassword or #newPassword < 3 then
        debugprint("same password / too short")
        return false
    end

    local currentPassword = MySQL.scalar.await("SELECT password FROM phone_tiktok_accounts WHERE username = ?", { account })
    if not currentPassword or not VerifyPasswordHash(oldPassword, currentPassword) then
        return false
    end

    local updated = MySQL.update.await("UPDATE phone_tiktok_accounts SET password = ? WHERE username = ?", {
        GetPasswordHash(newPassword),
        account
    }) > 0

    if not updated then
        return false
    end


    sendNotificationToAllAccounts(account, {
        title = L("BACKEND.MISC.LOGGED_OUT_PASSWORD.TITLE"),
        content = L("BACKEND.MISC.LOGGED_OUT_PASSWORD.DESCRIPTION")
    }, phoneNumber)

    MySQL.update.await(
    "DELETE FROM phone_logged_in_accounts WHERE username = ? AND app = 'TikTok' AND phone_number != ?", {
        account, phoneNumber
    })

    ClearActiveAccountsCache("TikTok", account, phoneNumber)

    Log("Trendy", source, "info",
        L("BACKEND.LOGS.CHANGED_PASSWORD.TITLE"),
        L("BACKEND.LOGS.CHANGED_PASSWORD.DESCRIPTION", {
            number = phoneNumber,
            username = account,
            app = "Trendy"
        })
    )


    for phone, src in pairs(getPhoneNumberToSourceMap(account)) do
        if src then
            TriggerClientEvent("phone:logoutFromApp", src, {
                username = account,
                app = "tiktok",
                reason = "password",
                number = phoneNumber
            })
        end
    end

    return true
end, false)


createAuthenticatedCallback("deleteAccount", function(source, phoneNumber, account, password)
    if not Config.DeleteAccount.Trendy then
        infoprint("warning",
            string.format("%s tried to delete their account on Trendy, but it's not enabled in the config.", source))
        return false
    end

    local currentPassword = MySQL.scalar.await("SELECT password FROM phone_tiktok_accounts WHERE username = ?", { account })
    if not currentPassword or not VerifyPasswordHash(password, currentPassword) then
        return false
    end

    local deleted = MySQL.update.await("DELETE FROM phone_tiktok_accounts WHERE username = ?", { account }) > 0
    if not deleted then
        return false
    end


    sendNotificationToAllAccounts(account, {
        title = L("BACKEND.MISC.DELETED_NOTIFICATION.TITLE"),
        content = L("BACKEND.MISC.DELETED_NOTIFICATION.DESCRIPTION")
    })

    MySQL.update.await("DELETE FROM phone_logged_in_accounts WHERE username = ? AND app = 'TikTok'", { account })
    ClearActiveAccountsCache("TikTok", account)

    Log("Trendy", source, "info",
        L("BACKEND.LOGS.DELETED_ACCOUNT.TITLE"),
        L("BACKEND.LOGS.DELETED_ACCOUNT.DESCRIPTION", {
            number = phoneNumber,
            username = account,
            app = "Trendy"
        })
    )


    for phone, src in pairs(getPhoneNumberToSourceMap(account)) do
        if src then
            TriggerClientEvent("phone:logoutFromApp", src, {
                username = account,
                app = "tiktok",
                reason = "deleted"
            })
        end
    end

    return true
end, false)


RegisterLegacyCallback("tiktok:logout", function(source, cb)
    cb(false)
end)

RegisterLegacyCallback("tiktok:isLoggedIn", function(source, cb)
    local phoneNumber = GetEquippedPhoneNumber(source)
    if not phoneNumber then return cb(false) end

    local account = getLoggedInTikTokAccount(source)
    

    if account then
        local accountExists = MySQL.scalar.await(
            "SELECT TRUE FROM phone_tiktok_accounts WHERE username = ?",
            { account }
        )
        if not accountExists then
            RemoveLoggedInAccount(phoneNumber, "TikTok", account)
            account = nil
        end
    end
    

    if not account then

        local existingUsername = MySQL.scalar.await(
            "SELECT username FROM phone_tiktok_accounts WHERE phone_number = ?",
            { phoneNumber }
        )
        
        if existingUsername then

            AddLoggedInAccount(phoneNumber, "TikTok", existingUsername)
            account = existingUsername
        else

            local firstname, lastname = GetCharacterName(source)
            

            if firstname and firstname ~= "" then
                firstname = firstname:sub(1, 8)
            else
                firstname = "Player" .. source
            end
            
            if lastname and lastname ~= "" then
                lastname = lastname:sub(1, 8)
            end
            

            local characterName = firstname
            if lastname and lastname ~= "" then
                characterName = firstname .. " " .. lastname
            end


            local username = characterName:gsub("%s+", ""):sub(1, 8):lower()
            

            local baseUsername = username
            local counter = 1
            while MySQL.scalar.await("SELECT TRUE FROM phone_tiktok_accounts WHERE username = ?", { username }) do
                username = baseUsername .. counter
                counter = counter + 1
                if counter > 999 then
                    username = "user" .. math.random(10000, 99999)
                    break
                end
            end


            if not IsUsernameValid(username) then
                username = "user" .. math.random(1000, 9999)
            end


            local displayName = characterName

            local password = tostring(math.random(100000, 999999)) .. tostring(os.time())

            MySQL.update.await(
                "INSERT INTO phone_tiktok_accounts (`name`, username, password, phone_number) VALUES (?, ?, ?, ?)",
                { displayName, username, GetPasswordHash(password), phoneNumber }
            )


            AddLoggedInAccount(phoneNumber, "TikTok", username)
            account = username


            if Config.AutoFollow.Enabled and Config.AutoFollow.Trendy and Config.AutoFollow.Trendy.Enabled then
                for i = 1, #Config.AutoFollow.Trendy.Accounts do
                    MySQL.update.await("INSERT INTO phone_tiktok_follows (followed, follower) VALUES (?, ?)", {
                        Config.AutoFollow.Trendy.Accounts[i],
                        username
                    })
                end
            end
        end
    end


    if source and account then
        ActiveTikTokUsers[source] = account
        if not UsernameToSources[account] then
            UsernameToSources[account] = {}
        end

        local exists = false
        for _, src in ipairs(UsernameToSources[account]) do
            if src == source then
                exists = true
                break
            end
        end
        if not exists then
            table.insert(UsernameToSources[account], source)
        end
    end

    local profile = account and getTikTokProfile(account) or false
    cb(profile)
end)


RegisterLegacyCallback("tiktok:getProfile", function(source, cb, username)
    local loggedInAccount = getLoggedInTikTokAccount(source)
    cb(getTikTokProfile(username, loggedInAccount))
end)


RegisterLegacyCallback("tiktok:updateProfile", function(source, cb, profileData)
    local phoneNumber = GetEquippedPhoneNumber(source)
    if not phoneNumber then
        return cb({ success = false, error = "no_number" })
    end

    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    local name = profileData.name
    local bio = profileData.bio
    local avatar = profileData.avatar
    local twitter = profileData.twitter
    local instagram = profileData.instagram
    local showLikes = profileData.show_likes

    if #name > 30 then
        return cb({ success = false, error = "display_name_too_long" })
    end

    if bio and #bio > 150 then
        return cb({ success = false, error = "bio_too_long" })
    end


    if twitter then
        local validTwitter = MySQL.Sync.fetchScalar(
        "SELECT TRUE FROM phone_logged_in_accounts WHERE phone_number = @phoneNumber and app = @app and username = @username",
            {
                ["@phoneNumber"] = phoneNumber,
                ["@app"] = "Twitter",
                ["@username"] = twitter
            })
        if not validTwitter then
            return cb({ success = false, error = "invalid_twitter" })
        end
    end


    if instagram then
        local validInstagram = MySQL.Sync.fetchScalar(
        "SELECT TRUE FROM phone_logged_in_accounts WHERE phone_number = @phoneNumber and app = @app and username = @username",
            {
                ["@phoneNumber"] = phoneNumber,
                ["@app"] = "Instagram",
                ["@username"] = instagram
            })
        if not validInstagram then
            return cb({ success = false, error = "invalid_instagram" })
        end
    end

    MySQL.Async.execute(
    "UPDATE phone_tiktok_accounts SET `name` = @displayName, bio = @bio, avatar = @avatar, twitter = @twitter, instagram = @instagram, `show_likes` = @showLikes WHERE username = @username",
        {
            ["@displayName"] = name,
            ["@bio"] = bio,
            ["@avatar"] = avatar,
            ["@twitter"] = twitter,
            ["@instagram"] = instagram,
            ["@showLikes"] = showLikes == true,
            ["@username"] = account
        }, function()

        invalidateProfileCache(account)
        cb({ success = true })
    end)
end)


RegisterLegacyCallback("tiktok:changeDisplayName", function(source, cb, newDisplayName)
    local phoneNumber = GetEquippedPhoneNumber(source)
    if not phoneNumber then
        return cb({ success = false, error = "NO_NUMBER" })
    end

    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "NOT_LOGGED_IN" })
    end

    if not newDisplayName or type(newDisplayName) ~= "string" or #newDisplayName < 1 then
        return cb({ success = false, error = "INVALID_DISPLAY_NAME" })
    end

    if #newDisplayName > 30 then
        return cb({ success = false, error = "DISPLAY_NAME_TOO_LONG" })
    end

    local cost = Config.TrendyChangeName.DisplayNameCost
    local success = RemoveMoney(source, cost, "Đổi tên hiển thị TikTok", "priority")
    
    if not success then
        return cb({ success = false, error = "INSUFFICIENT_FUNDS" })
    end

    MySQL.Async.execute(
        "UPDATE phone_tiktok_accounts SET `name` = ? WHERE username = ?",
        { newDisplayName, account },
        function(affectedRows)
            if affectedRows > 0 then
                invalidateProfileCache(account)
                
                local title = L("BACKEND.TIKTOK.DISPLAY_NAME_CHANGED_TITLE")
                if not title or title:find("BACKEND") then
                    title = "Tên hiển thị đã được thay đổi"
                end
                local content = L("BACKEND.TIKTOK.DISPLAY_NAME_CHANGED_DESCRIPTION", { displayName = newDisplayName })
                if not content or content:find("BACKEND") then
                    content = "Tên hiển thị của bạn đã được đổi thành " .. newDisplayName
                end
                
                -- Gửi thông báo cho tất cả devices (không exclude)
                sendNotificationToAllAccounts(account, {
                    title = title,
                    content = content
                })

                cb({ success = true, newDisplayName = newDisplayName })
            else
                AddMoney(source, cost, "tienkhoa")
                cb({ success = false, error = "UPDATE_FAILED" })
            end
        end
    )
end)

RegisterLegacyCallback("tiktok:changeUsername", function(source, cb, newUsername)
    local phoneNumber = GetEquippedPhoneNumber(source)
    if not phoneNumber then
        return cb({ success = false, error = "NO_NUMBER" })
    end

    local currentUsername = getLoggedInTikTokAccount(source)
    if not currentUsername then
        return cb({ success = false, error = "NOT_LOGGED_IN" })
    end

    if not newUsername or type(newUsername) ~= "string" or #newUsername < 1 then
        return cb({ success = false, error = "INVALID_USERNAME" })
    end

    -- Chuyển username về lowercase
    newUsername = newUsername:lower()

    -- Kiểm tra độ dài username
    if #newUsername < 3 then
        return cb({ success = false, error = "USERNAME_TOO_SHORT" })
    end

    if #newUsername > 8 then
        return cb({ success = false, error = "USERNAME_TOO_LONG" })
    end

    -- Kiểm tra username hợp lệ (chỉ chữ cái, số, gạch dưới)
    if not newUsername:match("^[a-z0-9_.]+$") then
        return cb({ success = false, error = "USERNAME_NOT_ALLOWED" })
    end

    -- Kiểm tra username đã tồn tại chưa
    local exists = MySQL.scalar.await(
        "SELECT TRUE FROM phone_tiktok_accounts WHERE username = ? AND username != ?",
        { newUsername, currentUsername }
    )
    
    if exists then
        SendNotification(phoneNumber, {
            app = "TikTok",
            title = "Username đã được sử dụng",
            content = "Username @" .. newUsername .. " đã có người sử dụng"
        })
        return cb({ success = false, error = "USERNAME_TAKEN" })
    end

    -- Lấy giá từ config
    local cost = Config.TrendyChangeName.UsernameCost
    local success = RemoveMoney(source, cost, "Đổi username TikTok", "priority")
    
    if not success then
        SendNotification(phoneNumber, {
            app = "TikTok",
            title = "Không đủ tiền",
            content = "Bạn cần $" .. cost .. " IC để đổi username"
        })
        return cb({ success = false, error = "INSUFFICIENT_FUNDS" })
    end

    -- Cập nhật username trong database
    -- Sử dụng phone_number để đảm bảo cập nhật đúng account
    MySQL.Async.execute(
        "UPDATE phone_tiktok_accounts SET username = ? WHERE username = ? AND phone_number = ?",
        { newUsername, currentUsername, phoneNumber },
        function(affectedRows)
            if affectedRows > 0 then
                -- Cập nhật các bảng liên quan
                MySQL.Async.execute("UPDATE phone_tiktok_videos SET username = ? WHERE username = ?", { newUsername, currentUsername })
                MySQL.Async.execute("UPDATE phone_tiktok_follows SET follower = ? WHERE follower = ?", { newUsername, currentUsername })
                MySQL.Async.execute("UPDATE phone_tiktok_follows SET followed = ? WHERE followed = ?", { newUsername, currentUsername })
                MySQL.Async.execute("UPDATE phone_tiktok_likes SET username = ? WHERE username = ?", { newUsername, currentUsername })
                MySQL.Async.execute("UPDATE phone_tiktok_comments SET username = ? WHERE username = ?", { newUsername, currentUsername })
                MySQL.Async.execute("UPDATE phone_tiktok_notifications SET username = ? WHERE username = ?", { newUsername, currentUsername })
                MySQL.Async.execute("UPDATE phone_tiktok_notifications SET `from` = ? WHERE `from` = ?", { newUsername, currentUsername })
                MySQL.Async.execute("UPDATE phone_logged_in_accounts SET username = ? WHERE username = ? AND app = 'TikTok'", { newUsername, currentUsername })
                
                -- Xóa cache cũ
                invalidateProfileCache(currentUsername)
                invalidateProfileCache(newUsername)
                
                -- Cập nhật ActiveTikTokUsers
                for src, uname in pairs(ActiveTikTokUsers) do
                    if uname == currentUsername then
                        ActiveTikTokUsers[src] = newUsername
                    end
                end
                
                -- Cập nhật UsernameToSources
                if UsernameToSources[currentUsername] then
                    UsernameToSources[newUsername] = UsernameToSources[currentUsername]
                    UsernameToSources[currentUsername] = nil
                end
                
                -- Cập nhật logged in account
                RemoveLoggedInAccount(phoneNumber, "TikTok", currentUsername)
                AddLoggedInAccount(phoneNumber, "TikTok", newUsername)
                
                local title = L("BACKEND.TIKTOK.USERNAME_CHANGED_TITLE")
                if not title or title:find("BACKEND") then
                    title = "Username đã được thay đổi"
                end
                local content = L("BACKEND.TIKTOK.USERNAME_CHANGED_DESCRIPTION", { username = newUsername })
                if not content or content:find("BACKEND") then
                    content = "Username của bạn đã được đổi thành @" .. newUsername
                end
                
                -- Gửi thông báo cho tất cả devices đang đăng nhập (không exclude)
                sendNotificationToAllAccounts(newUsername, {
                    title = title,
                    content = content
                })

                -- Lấy profile mới để trả về cho client
                local newProfile = getTikTokProfile(newUsername, phoneNumber)
                cb({ success = true, newUsername = newUsername, profile = newProfile, needReload = true })
            else
                AddMoney(source, cost, "Hoàn tiền đổi username")
                cb({ success = false, error = "UPDATE_FAILED" })
            end
        end
    )
end)


RegisterLegacyCallback("tiktok:searchAccounts", function(source, cb, query, page)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb(false)
    end

    local searchQuery = [[
        SELECT `name`, username, avatar, verified, follower_count, video_count,
            (SELECT TRUE FROM phone_tiktok_follows WHERE follower = @username AND followed = a.username) AS isFollowing

        FROM phone_tiktok_accounts a
        WHERE username LIKE @query OR `name` LIKE @query
        ORDER BY username
        LIMIT @page, @perPage
    ]]

    MySQL.Async.fetchAll(searchQuery, {
        ["@query"] = "%"..query.."%",
        ["@username"] = account,
        ["@page"] = (page or 0) * 10,
        ["@perPage"] = 10
    }, cb)
end)


RegisterLegacyCallback("tiktok:toggleFollow", function(source, cb, targetUsername, isFollowing)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    if targetUsername == account then
        return cb({ success = false, error = "cannot_follow_self" })
    end

    local targetProfile = getTikTokProfile(targetUsername)
    if not targetProfile then
        return cb({ success = false, error = "invalid_username" })
    end

    cb({ success = true })

    local query = isFollowing == true and
        "INSERT IGNORE INTO phone_tiktok_follows (follower, followed) VALUES (@follower, @followed)" or
        "DELETE FROM phone_tiktok_follows WHERE follower = @follower AND followed = @followed"

    MySQL.Async.execute(query, {
        ["@follower"] = account,
        ["@followed"] = targetUsername
    }, function(affectedRows)
        if affectedRows == 0 then
            return
        end

        local action = isFollowing == true and "add" or "remove"


        local relevantSources = {}


        local targetSources = getSourcesForUsername(targetUsername)
        for _, src in ipairs(targetSources) do
            table.insert(relevantSources, src)
        end


        local accountSources = getSourcesForUsername(account)
        for _, src in ipairs(accountSources) do
            table.insert(relevantSources, src)
        end

        broadcastToRelevant("phone:tiktok:updateFollowers", {targetUsername, action}, relevantSources)
        broadcastToRelevant("phone:tiktok:updateFollowing", {account, action}, relevantSources)


        invalidateProfileCache(targetUsername)
        invalidateProfileCache(account)


        FollowerSourcesCache[targetUsername] = nil

        if isFollowing == true then
            queueTikTokNotification(targetUsername, account, "follow", nil, nil, nil)
        else

            MySQL.update.await("DELETE FROM phone_tiktok_notifications WHERE username = ? AND `from` = ? AND `type` = 'follow'", { targetUsername, account })
        end
    end)
end, { preventSpam = true })


RegisterLegacyCallback("tiktok:getFollowing", function(source, cb, username, page)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({})
    end

    local query = [[
        SELECT
            a.username, a.`name`, a.avatar, a.verified,
                (SELECT TRUE FROM phone_tiktok_follows WHERE follower = a.username AND followed = @loggedIn) AS isFollowingYou,
                (SELECT TRUE FROM phone_tiktok_follows WHERE follower = @loggedIn AND followed = a.username) AS isFollowing
        FROM phone_tiktok_follows f
        INNER JOIN phone_tiktok_accounts a ON a.username = f.followed
        WHERE f.follower = @username
        ORDER BY a.username
        LIMIT @page, @perPage
    ]]

    MySQL.Async.fetchAll(query, {
        ["@username"] = username,
        ["@loggedIn"] = account,
        ["@page"] = (page or 0) * 15,
        ["@perPage"] = 15
    }, cb)
end)


RegisterLegacyCallback("tiktok:getFollowers", function(source, cb, username, page)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({})
    end

    local query = [[
        SELECT
            a.username, a.`name`, a.avatar, a.verified,
                (SELECT TRUE FROM phone_tiktok_follows WHERE follower = @username AND followed = @loggedIn) AS isFollowingYou,
                (SELECT TRUE FROM phone_tiktok_follows WHERE follower = @loggedIn AND followed = @username) AS isFollowing
        FROM phone_tiktok_follows f
        INNER JOIN phone_tiktok_accounts a ON a.username = f.follower
        WHERE f.followed = @username
        ORDER BY a.username
        LIMIT @page, @perPage
    ]]

    MySQL.Async.fetchAll(query, {
        ["@username"] = username,
        ["@loggedIn"] = account,
        ["@page"] = (page or 0) * 15,
        ["@perPage"] = 15
    }, cb)
end)


RegisterLegacyCallback("tiktok:uploadVideo", function(source, cb, videoData)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    if ContainsBlacklistedWord(source, "Trendy", videoData.caption) then
        return cb(false)
    end

    if not videoData.src or type(videoData.src) ~= "string" or #videoData.src == 0 then
        return cb({ success = false, error = "invalid_src" })
    end

    if not videoData.caption or type(videoData.caption) ~= "string" or #videoData.caption == 0 then
        return cb({ success = false, error = "invalid_caption" })
    end

    local videoId = GenerateId("phone_tiktok_videos", "id")

    MySQL.Async.execute("INSERT INTO phone_tiktok_videos (id, username, src, caption, metadata, music) VALUES (@id, @username, @src, @caption, @metadata, @music)",
        {
            ["@id"] = videoId,
            ["@username"] = account,
            ["@src"] = videoData.src,
            ["@caption"] = videoData.caption,
            ["@metadata"] = videoData.metadata,
            ["@music"] = videoData.music
        }, function()
        cb({ success = true, id = videoId })

        local videoInfo = {
            username = account,
            caption = videoData.caption,
            videoUrl = videoData.src,
            id = videoId
        }


        local relevantSources = {}
        local sourceSet = {}


        local followerSources = getFollowerSources(account)
        for _, src in ipairs(followerSources) do
            if not sourceSet[src] then
                sourceSet[src] = true
                table.insert(relevantSources, src)
            end
        end


        local activeSources = getActiveTikTokSources()
        for _, src in ipairs(activeSources) do
            if not sourceSet[src] then
                sourceSet[src] = true
                table.insert(relevantSources, src)
            end
        end

        broadcastToRelevant("phone:tiktok:newVideo", videoInfo, relevantSources)
        TriggerEvent("lb-phone:trendy:newPost", videoInfo)
        TrackSocialMediaPost("trendy", { videoData.src })

        Log("Trendy", source, "success", L("BACKEND.LOGS.TRENDY_UPLOAD_TITLE"), L("BACKEND.LOGS.TRENDY_UPLOAD_DESCRIPTION", {
            username = account,
            caption = videoData.caption,
            id = videoId
        }))

        if TIKTOK_WEBHOOK then
            local avatar = MySQL.scalar.await("SELECT avatar FROM phone_tiktok_accounts WHERE username = ?", { account })
            local mediaUrl = videoData.src
            local isVideo = mediaUrl and string.find(mediaUrl:lower(), "%.mp4")
            local isImage = mediaUrl and (string.find(mediaUrl:lower(), "%.webp") or string.find(mediaUrl:lower(), "%.png") or string.find(mediaUrl:lower(), "%.jpg"))
    
            local payload = {
                username = "TikTok",
                avatar_url = "https://cdn.discordapp.com/attachments/1449969256082051092/1453316580346957945/tiktoklogo.png?ex=694d020a&is=694bb08a&hm=adf5fa7c5ef1706e13b6f8202ec53bf914b5bb3a5e3d7a59edb5f6452f8a7a07&",
                embeds = {{
                    title = 'Bài đăng mới',
                    description = videoData.caption,
                    color = 9059001,
                    timestamp = GetTimestampISO(),
                    author = { name = "@" .. account, icon_url = avatar or "https://cdn.discordapp.com/embed/avatars/5.png" },
                    footer = { text = "F17 Phone", icon_url = "https://media.discordapp.net/attachments/1008372897695404042/1369276368591917126/F17launcher_icon.png" }
                }}
            }
    
            if isVideo then
                payload.content = mediaUrl
            else
                payload.embeds[1].image = { url = mediaUrl }
            end
    
            PerformHttpRequest(TIKTOK_WEBHOOK, function() end, "POST", json.encode(payload), { ["Content-Type"] = "application/json" })
        end

        MySQL.Async.fetchAll("SELECT follower FROM phone_tiktok_follows WHERE followed = @username", { ["@username"] = account }, function(followers)
            if followers and #followers > 0 then
                for i = 1, #followers do
                    sendTikTokNotification(followers[i].follower, account, "new_post", videoId)
                end
            end
        end)
    end)
end, { preventSpam = true, rateLimit = 6 })

RegisterLegacyCallback("tiktok:deleteVideo", function(source, cb, videoId)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    local query = "DELETE FROM phone_tiktok_videos WHERE id = @id"
    if not IsAdmin(source) then
        query = query.." AND username = @username"
    end

    MySQL.Async.execute(query, {
        ["@id"] = videoId,
        ["@username"] = account
    }, function(affectedRows)
        cb({ success = affectedRows > 0 })

        if affectedRows > 0 then
            Log("Trendy", source, "error",
                L("BACKEND.LOGS.TRENDY_DELETE_TITLE"),
                L("BACKEND.LOGS.TRENDY_DELETE_DESCRIPTION", {
                    username = account,
                    id = videoId
                })
            )
        end
    end)
end)

RegisterLegacyCallback("tiktok:togglePinnedVideo", function(source, cb, videoId, isPinned)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    if isPinned then
        local pinnedCount = MySQL.Sync.fetchScalar(
        "SELECT COUNT(*) FROM phone_tiktok_pinned_videos WHERE username = @username", {
            ["@username"] = account
        })
        if pinnedCount >= 3 and isPinned then
            return cb({ success = false, error = "max_pinned" })
        end
    end

    local query = isPinned and
        "INSERT INTO phone_tiktok_pinned_videos (username, video_id) VALUES (@username, @videoId)" or
        "DELETE FROM phone_tiktok_pinned_videos WHERE username = @username AND video_id = @videoId"

    MySQL.Async.execute(query, {
        ["@videoId"] = videoId,
        ["@username"] = account
    }, function(affectedRows)
        cb({ success = affectedRows > 0 })
    end)
end)


local baseVideoQuery = [[
    SELECT
        v.id, v.src, v.caption, v.`timestamp`,
        p.video_id IS NOT NULL AS pinned,

        v.likes, v.comments, v.views, v.saves,
        (SELECT TRUE FROM phone_tiktok_likes WHERE username = @loggedIn AND video_id = v.id) AS liked,
        (SELECT TRUE FROM phone_tiktok_saves WHERE username = @loggedIn AND video_id = v.id) AS saved,
        w.video_id IS NOT NULL AS viewed,

        v.metadata, v.music,

        a.username, a.`name`, a.avatar, a.verified,
        (SELECT TRUE FROM phone_tiktok_follows WHERE follower = @username AND followed = a.username) AS following

    FROM phone_tiktok_videos v
    INNER JOIN phone_tiktok_accounts a ON a.username = v.username
    LEFT JOIN phone_tiktok_views w ON v.id = w.video_id AND w.username = @loggedIn
    LEFT JOIN phone_tiktok_pinned_videos p ON p.video_id = v.id AND p.username = @loggedIn
]]


RegisterLegacyCallback("tiktok:getVideo", function(source, cb, videoId)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    local query = baseVideoQuery..[[
        WHERE v.id = @id
    ]]

    MySQL.Async.fetchAll(query, {
        ["@id"] = videoId,
        ["@loggedIn"] = account,
        ["@username"] = account
    }, function(results)
        if #results == 0 then
            return cb({ success = false, error = "invalid_id" })
        end
        cb({ success = true, video = results[1] })
    end)
end)


RegisterLegacyCallback("tiktok:getVideos", function(source, cb, options, page)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({})
    end

    local query = nil
    local perPage = nil

    if options.full then
        if options.type == "recent" then
            if options.id then
                if options.username then
                    query = baseVideoQuery..[[
                        WHERE v.username = @username AND v.`timestamp` %s (SELECT `timestamp` FROM phone_tiktok_videos WHERE id = @id)
                        ORDER BY (w.username IS NOT NULL), v.timestamp DESC
                        LIMIT @page, @perPage
                    ]]
                    query = query:format(options.backwards and ">" or "<")
                else
                    query = baseVideoQuery..[[
                        WHERE v.username != @loggedIn AND v.`timestamp` %s (SELECT `timestamp` FROM phone_tiktok_videos WHERE id = @id)
                        ORDER BY (w.username IS NOT NULL), v.timestamp DESC
                        LIMIT @page, @perPage
                    ]]
                    query = query:format(options.backwards and ">" or "<")
                end
            else
                query = baseVideoQuery..[[
                    WHERE v.username != @loggedIn
                    ORDER BY (w.username IS NOT NULL), v.timestamp DESC
                    LIMIT @page, @perPage
                ]]
            end
        elseif options.type == "following" then
            query = baseVideoQuery..[[
                INNER JOIN phone_tiktok_follows f ON f.followed = v.username
                WHERE f.follower = @loggedIn
                ORDER BY (w.username IS NOT NULL), v.timestamp DESC
                LIMIT @page, @perPage
            ]]
        end
        perPage = 5
    else
        if options.type == "recent" then
            if options.username then
                if page == 0 then
                    query = [[
                        SELECT
                            v.id, v.src, v.views,
                            p.video_id IS NOT NULL AS pinned
                        FROM phone_tiktok_videos v
                        LEFT JOIN phone_tiktok_pinned_videos p ON p.video_id = v.id AND p.username = @username
                        WHERE v.username = @username
                        ORDER BY (p.video_id IS NOT NULL) DESC, v.`timestamp` DESC
                        LIMIT @page, @perPage
                    ]]
                else
                    query = [[
                        SELECT id, src, views
                        FROM phone_tiktok_videos
                        WHERE username = @username
                        ORDER BY `timestamp` DESC
                        LIMIT @page, @perPage
                    ]]
                end
            end
        elseif options.type == "liked" then
            query = [[
                SELECT v.id, v.src, v.views
                FROM phone_tiktok_videos v
                INNER JOIN phone_tiktok_likes l ON l.video_id = v.id
                WHERE l.username = @username
                ORDER BY v.`timestamp` DESC
                LIMIT @page, @perPage
            ]]
        elseif options.type == "saved" then
            if account ~= options.username then
                debugprint("wrong account", account, #account, options.username, #options.username)
                return cb({})
            end
            query = [[
                SELECT v.id, v.src, v.views
                FROM phone_tiktok_videos v
                INNER JOIN phone_tiktok_saves s ON s.video_id = v.id
                WHERE s.username = @username
                ORDER BY v.`timestamp` DESC
                LIMIT @page, @perPage
            ]]
        end
        perPage = 15
    end

    if not query then
        return cb({})
    end


    
    MySQL.Async.fetchAll(query, {
        ["@username"] = options.username,
        ["@loggedIn"] = account,
        ["@id"] = options.id,
        ["@page"] = (page or 0) * perPage,
        ["@perPage"] = perPage
    }, cb)
end)


RegisterNetEvent("phone:tiktok:setViewed", function(videoId)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return
    end

    MySQL.Async.execute("INSERT IGNORE INTO phone_tiktok_views (username, video_id) VALUES (@username, @videoId)", {
        ["@username"] = account,
        ["@videoId"] = videoId
    })
end)


RegisterLegacyCallback("tiktok:toggleVideoAction", function(source, cb, action, videoId, isActive)
    if action ~= "like" and action ~= "save" then
        return cb({ success = false, error = "invalid_action" })
    end

    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    local videoOwner = MySQL.Sync.fetchScalar("SELECT username FROM phone_tiktok_videos WHERE id = @id", {
        ["@id"] = videoId
    })
    if not videoOwner then
        return cb({ success = false, error = "invalid_id" })
    end

    local tableName = action == "like" and "likes" or "saves"
    local query = isActive == true and
        ("INSERT IGNORE INTO phone_tiktok_%s (username, video_id) VALUES (@username, @videoId)"):format(tableName) or
        ("DELETE FROM phone_tiktok_%s WHERE username = @username AND video_id = @videoId"):format(tableName)

    MySQL.Async.execute(query, {
        ["@username"] = account,
        ["@videoId"] = videoId
    }, function(affectedRows)
        if affectedRows == 0 then

            return cb({ success = true, isActive = isActive })
        end

        local actionType = isActive == true and "add" or "remove"


        local countQuery = ("SELECT COUNT(*) FROM phone_tiktok_%s WHERE video_id = @videoId"):format(tableName)
        local newCount = MySQL.Sync.fetchScalar(countQuery, {
            ["@videoId"] = videoId
        })


        cb({
            success = true,
            isActive = isActive,
            count = newCount or 0
        })


        local relevantSources = getActiveTikTokSources()
        broadcastToRelevant("phone:tiktok:updateVideoStats", {action, videoId, actionType}, relevantSources)


        invalidateVideoCache(videoId)

        if isActive then
            queueTikTokNotification(videoOwner, account, action, videoId, nil, nil)
        end
    end)
end, { preventSpam = true, rateLimit = 30 })


RegisterLegacyCallback("tiktok:postComment", function(source, cb, videoId, replyToId, comment)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    if not comment or #comment == 0 or #comment > 500 then
        return cb({ success = false, error = "invalid_comment" })
    end

    if ContainsBlacklistedWord(source, "Trendy", comment) then
        return cb(false)
    end

    local videoOwner = MySQL.Sync.fetchScalar("SELECT username FROM phone_tiktok_videos WHERE id = @id", {
        ["@id"] = videoId
    })
    if not videoOwner then
        return cb({ success = false, error = "invalid_id" })
    end

    local replyToOwner = replyToId and
    MySQL.Sync.fetchScalar("SELECT username FROM phone_tiktok_comments WHERE id = @id", {
        ["@id"] = replyToId
    }) or nil
    if replyToId and not replyToOwner then
        return cb({ success = false, error = "invalid_reply_to" })
    end

    local commentId = GenerateId("phone_tiktok_comments", "id")

    MySQL.Async.execute("INSERT INTO phone_tiktok_comments (id, reply_to, video_id, username, comment) VALUES (@id, @replyTo, @videoId, @loggedIn, @comment)",
        {
            ["@id"] = commentId,
            ["@replyTo"] = replyToId,
            ["@videoId"] = videoId,
            ["@loggedIn"] = account,
            ["@comment"] = comment
        }, function(affectedRows)
        if affectedRows == 0 then
            return cb({ success = false, error = "failed_insert" })
        end


        local profile = getTikTokProfile(account)
        if not profile then
            profile = {
                name = account,
                avatar = nil,
                verified = false
            }
        end


        local commentPayload = {
            id = commentId,
            comment = comment,
            timestamp = os.time() * 1000,
            likes = 0,
            replies = 0,
            reply_to = replyToId,
            liked = false,
            username = account,
            name = profile.name,
            avatar = profile.avatar,
            verified = profile.verified,
            pinned = false
        }


        local relevantSources = getActiveTikTokSources()


        broadcastToRelevant("phone:tiktok:updateVideoStats", {"comment", videoId, "add", 1}, relevantSources)


        for _, targetSource in ipairs(relevantSources) do
            TriggerClientEvent("phone:tiktok:newComment", targetSource, commentPayload, videoId)
        end


        invalidateVideoCache(videoId)

        if replyToId then
            MySQL.Async.execute("UPDATE phone_tiktok_comments SET replies = replies + 1 WHERE id = @id", {
                ["@id"] = replyToId
            })
            broadcastToRelevant("phone:tiktok:updateCommentStats", {"reply", replyToId, "add"}, relevantSources)
            queueTikTokNotification(replyToOwner, account, "reply", videoId, commentId, nil)
        end



        local response = { success = true }
        for k, v in pairs(commentPayload) do
            response[k] = v
        end

        cb(response)
        queueTikTokNotification(videoOwner, account, "comment", videoId, commentId, nil)
    end)
end, { 
    preventSpam = true, 
    rateLimit = 10,
    rateLimitNotification = true,
    rateLimitMessage = "Bạn đã đạt giới hạn bình luận. Vui lòng quay lại sau 1 phút",
    rateLimitApp = "TikTok"
})


RegisterLegacyCallback("tiktok:deleteComment", function(source, cb, commentId, videoId)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    local adminCheck = ""
    if not IsAdmin(source) then
        adminCheck = " AND username = @username"
    end

    local replyCount = 0
    local replyToId = MySQL.Sync.fetchScalar("SELECT reply_to FROM phone_tiktok_comments WHERE id = @id"..adminCheck, {
        ["@id"] = commentId,
        ["@username"] = account
    })

    if replyToId then
        MySQL.Async.execute("UPDATE phone_tiktok_comments SET replies = replies - 1 WHERE id = @id", {
            ["@id"] = replyToId
        })


        local relevantSources = getActiveTikTokSources()
        broadcastToRelevant("phone:tiktok:updateCommentStats", {"reply", replyToId, "remove"}, relevantSources)
    else
        replyCount = MySQL.Sync.fetchScalar("SELECT COUNT(*) FROM phone_tiktok_comments WHERE reply_to = @id", {
            ["@id"] = commentId
        })
    end

    MySQL.Async.execute("DELETE FROM phone_tiktok_comments WHERE id = @id"..adminCheck, {
        ["@id"] = commentId,
        ["@username"] = account
    }, function(affectedRows)
        if affectedRows > 0 then
            cb({ success = true })



            local totalDeleted = replyCount + 1


            local relevantSources = getActiveTikTokSources()
            broadcastToRelevant("phone:tiktok:updateVideoStats", {"comment", videoId, "remove", totalDeleted}, relevantSources)


            invalidateVideoCache(videoId)
        else
            cb({ success = false, error = "failed_delete" })
        end
    end)
end)


RegisterLegacyCallback("tiktok:getCommentVideoId", function(source, cb, commentId)
    local videoId = MySQL.Sync.fetchScalar("SELECT video_id FROM phone_tiktok_comments WHERE id = @id", {
        ["@id"] = commentId
    })
    cb(videoId)
end)


RegisterLegacyCallback("tiktok:setPinnedComment", function(source, cb, commentId, videoId)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    local ownsVideo = MySQL.Sync.fetchScalar(
    "SELECT TRUE FROM phone_tiktok_videos WHERE id = @id AND username = @username", {
        ["@id"] = videoId,
        ["@username"] = account
    })
    if not ownsVideo then
        return cb({ success = false, error = "invalid_id" })
    end

    if commentId ~= nil then
        local ownsComment = MySQL.Sync.fetchScalar(
        "SELECT TRUE FROM phone_tiktok_comments WHERE id = @id AND username = @username", {
            ["@id"] = commentId,
            ["@username"] = account
        })
        if not ownsComment then
            return cb({ success = false, error = "invalid_comment" })
        end
    end

    MySQL.Async.execute("UPDATE phone_tiktok_videos SET pinned_comment = @commentId WHERE id = @id", {
        ["@commentId"] = commentId,
        ["@id"] = videoId
    }, function(affectedRows)
        if affectedRows > 0 then
            cb({ success = true })
        else
            cb({ success = false, error = "failed_update" })
        end
    end)
end)


RegisterLegacyCallback("tiktok:getComments", function(source, cb, videoId, commentId, page, sortBy, getReplies)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end


    local query = [[
        SELECT
            c.id, c.comment, UNIX_TIMESTAMP(c.`timestamp`) AS `timestamp`, c.likes, c.replies, c.reply_to,
            (SELECT TRUE FROM phone_tiktok_comments_likes WHERE username = @loggedIn AND comment_id = c.id) AS liked,
            a.username, a.`name`, a.avatar, a.verified,
            v.pinned_comment = c.id AS pinned
        FROM phone_tiktok_comments c
        INNER JOIN phone_tiktok_accounts a ON a.username = c.username
        INNER JOIN phone_tiktok_videos v ON v.id = c.video_id
        WHERE c.video_id = @videoId
    ]]

    local params = {
        ["@videoId"] = videoId,
        ["@loggedIn"] = account,
        ["@page"] = (tonumber(page) or 0) * 15,
        ["@perPage"] = 15
    }


    if getReplies and commentId and commentId ~= "" then
        query = query.." AND c.reply_to = @commentId"
        params["@commentId"] = commentId
    else
        query = query.." AND c.reply_to IS NULL"
    end


    if sortBy == "newest" then
        query = query.." ORDER BY c.`timestamp` DESC"
    elseif sortBy == "popular" then
        query = query.." ORDER BY c.likes DESC, c.`timestamp` DESC"
    else
        query = query.." ORDER BY c.`timestamp` DESC"
    end

    query = query.." LIMIT @page, @perPage"

    MySQL.Async.fetchAll(query, params, function(results)

        if results and type(results) == "table" then
            for i = 1, #results do

                results[i].liked = (results[i].liked == 1)
                results[i].verified = (results[i].verified == 1)
                results[i].pinned = (results[i].pinned == 1)


                results[i].likes = tonumber(results[i].likes) or 0
                results[i].replies = tonumber(results[i].replies) or 0


                if results[i].timestamp then
                    results[i].timestamp = tonumber(results[i].timestamp) * 1000
                end
            end
        end

        cb({ success = true, comments = results or {} })
    end)
end)


RegisterLegacyCallback("tiktok:getReplies", function(source, cb, commentId, page)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    if not commentId or commentId == "" then
        return cb({ success = false, error = "invalid_comment_id" })
    end

    local query = [[
        SELECT
            c.id, c.comment, UNIX_TIMESTAMP(c.`timestamp`) AS `timestamp`, c.likes, c.replies, c.reply_to,
            (SELECT TRUE FROM phone_tiktok_comments_likes WHERE username = @loggedIn AND comment_id = c.id) AS liked,
            a.username, a.`name`, a.avatar, a.verified
        FROM phone_tiktok_comments c
        INNER JOIN phone_tiktok_accounts a ON a.username = c.username
        WHERE c.reply_to = @commentId
        ORDER BY c.`timestamp` ASC
        LIMIT @page, @perPage
    ]]

    MySQL.Async.fetchAll(query, {
        ["@commentId"] = commentId,
        ["@loggedIn"] = account,
        ["@page"] = (tonumber(page) or 0) * 15,
        ["@perPage"] = 15
    }, function(results)
        if results and type(results) == "table" then
            for i = 1, #results do
                results[i].liked = (results[i].liked == 1)
                results[i].verified = (results[i].verified == 1)
                results[i].likes = tonumber(results[i].likes) or 0
                results[i].replies = tonumber(results[i].replies) or 0
                if results[i].timestamp then
                    results[i].timestamp = tonumber(results[i].timestamp) * 1000
                end
            end
        end

        cb({ success = true, replies = results or {} })
    end)
end)


RegisterLegacyCallback("tiktok:toggleLikeComment", function(source, cb, commentId, isLiked)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    local commentOwner = MySQL.Sync.fetchScalar("SELECT username FROM phone_tiktok_comments WHERE id = @id", {
        ["@id"] = commentId
    })
    if not commentOwner then
        return cb({ success = false, error = "invalid_id" })
    end

    cb({ success = true })

    local query = isLiked == true and
        "INSERT IGNORE INTO phone_tiktok_comments_likes (username, comment_id) VALUES (@username, @commentId)" or
        "DELETE FROM phone_tiktok_comments_likes WHERE username = @username AND comment_id = @commentId"

    MySQL.Async.execute(query, {
        ["@username"] = account,
        ["@commentId"] = commentId
    }, function(affectedRows)
        if affectedRows == 0 then
            return
        end

        local action = isLiked == true and "add" or "remove"


        local relevantSources = getActiveTikTokSources()
        broadcastToRelevant("phone:tiktok:updateCommentStats", {"like", commentId, action}, relevantSources)

        if isLiked then
            queueTikTokNotification(commentOwner, account, "like_comment", nil, commentId, nil)
        end
    end)
end, { preventSpam = true })


RegisterLegacyCallback("tiktok:getChannelId", function(source, cb, username)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end


    if not username or username == "" then
        debugprint("getChannelId: missing username parameter")
        return cb({ success = false, error = "missing_username" })
    end

    debugprint("getChannelId: account=" .. account .. ", target=" .. username)


    local targetExists = MySQL.Sync.fetchScalar("SELECT TRUE FROM phone_tiktok_accounts WHERE username = ?", { username })
    if not targetExists then
        debugprint("getChannelId: user_not_found - " .. username)
        return cb({ success = false, error = "user_not_found" })
    end


    local channelId = MySQL.Sync.fetchScalar(
        "SELECT id FROM phone_tiktok_channels WHERE (member_1 = @loggedIn AND member_2 = @username) OR (member_1 = @username AND member_2 = @loggedIn)",
        {
            ["@loggedIn"] = account,
            ["@username"] = username
        }
    )


    if not channelId then
        channelId = GenerateId("phone_tiktok_channels", "id")
        MySQL.Async.execute(
            "INSERT INTO phone_tiktok_channels (id, member_1, member_2, last_message) VALUES (?, ?, ?, ?)",
            { channelId, account, username, "" }
        )
    end

    cb({ success = true, id = channelId })
end)


RegisterLegacyCallback("tiktok:getRecentMessages", function(source, cb)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    local query = [[
        SELECT
            c.id,
            c.last_message,
            c.timestamp,
            CASE
                WHEN c.member_1 = ? THEN c.member_2
                ELSE c.member_1
            END as username,
            a.name,
            a.avatar,
            a.verified,
            COALESCE(u.amount, 0) as unread
        FROM phone_tiktok_channels c
        INNER JOIN phone_tiktok_accounts a ON a.username = (
            CASE
                WHEN c.member_1 = ? THEN c.member_2
                ELSE c.member_1
            END
        )
        LEFT JOIN phone_tiktok_unread_messages u ON u.channel_id = c.id AND u.username = ?
        WHERE c.member_1 = ? OR c.member_2 = ?
        ORDER BY c.timestamp DESC
        LIMIT 50
    ]]

    MySQL.Async.fetchAll(query, { account, account, account, account, account }, function(results)
        cb({ success = true, channels = results or {} })
    end)
end)


RegisterLegacyCallback("tiktok:sendMessage", function(source, cb, data)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end


    local channelId = data.channelId or data.id
    local content = data.content or data.message
    local replyTo = data.replyTo
    local attachments = data.attachments
    local sharedVideoId = data.sharedVideoId

    if not channelId then
        return cb({ success = false, error = "missing_channel_id" })
    end


    if (not content or #content == 0) and not attachments and not sharedVideoId then
        return cb({ success = false, error = "invalid_content" })
    end
    
    if content and #content > 500 then
        return cb({ success = false, error = "content_too_long" })
    end

    if ContainsBlacklistedWord(source, "Trendy", content) then
        return cb({ success = false, error = "blacklisted_word" })
    end


    local channel = MySQL.Sync.fetchAll(
        "SELECT member_1, member_2 FROM phone_tiktok_channels WHERE id = ?",
        { channelId }
    )

    if not channel or #channel == 0 then
        return cb({ success = false, error = "channel_not_found" })
    end

    channel = channel[1]
    if channel.member_1 ~= account and channel.member_2 ~= account then
        return cb({ success = false, error = "not_member" })
    end


    local recipient = channel.member_1 == account and channel.member_2 or channel.member_1


    local attachmentsJson = nil
    if attachments then
        if type(attachments) == "table" then
            attachmentsJson = json.encode(attachments)
        else
            attachmentsJson = attachments
        end
    end
    

    local messageId = GenerateId("phone_tiktok_messages", "id")
    local query = "INSERT INTO phone_tiktok_messages (id, channel_id, sender, content"
    local values = "VALUES (?, ?, ?, ?"
    local params = { messageId, channelId, account, content or "" }
    
    if replyTo then
        query = query .. ", reply_to"
        values = values .. ", ?"
        table.insert(params, replyTo)
    end
    
    if attachmentsJson then
        query = query .. ", attachments"
        values = values .. ", ?"
        table.insert(params, attachmentsJson)
    end
    
    if sharedVideoId then
        query = query .. ", shared_video_id"
        values = values .. ", ?"
        table.insert(params, sharedVideoId)
    end
    
    query = query .. ") " .. values .. ")"
    
    MySQL.Async.execute(query, params, function(affectedRows)
            if affectedRows == 0 then
                return cb({ success = false, error = "insert_failed" })
            end



            MySQL.Async.execute(
                "INSERT INTO phone_tiktok_unread_messages (username, channel_id, amount) VALUES (?, ?, 1) ON DUPLICATE KEY UPDATE amount = amount + 1",
                { recipient, channelId }
            )

            cb({ success = true, id = messageId, timestamp = os.time() * 1000 })


            queueTikTokNotification(recipient, account, "message", nil, nil, messageId, { content = content })


            local replyContent, replySender = nil, nil
            if replyTo then
                local replyMsg = MySQL.Sync.fetchAll("SELECT content, sender FROM phone_tiktok_messages WHERE id = ?", { replyTo })
                if replyMsg and #replyMsg > 0 then
                    replyContent = replyMsg[1].content
                    replySender = replyMsg[1].sender
                end
            end


            local recipientSources = getSourcesForUsername(recipient)
            for _, src in ipairs(recipientSources) do
                TriggerClientEvent("phone:tiktok:receivedMessage", src, {
                    id = messageId,
                    channelId = channelId,
                    sender = account,
                    content = content,
                    attachments = attachmentsJson,
                    shared_video_id = sharedVideoId,
                    reply_to = replyTo,
                    reply_content = replyContent,
                    reply_sender = replySender,
                    timestamp = os.time() * 1000
                })

                TriggerClientEvent("phone:tiktok:updateInbox", src, { channelId = channelId })
            end
            

            local senderSources = getSourcesForUsername(account)
            for _, src in ipairs(senderSources) do
                TriggerClientEvent("phone:tiktok:updateInbox", src, { channelId = channelId })
            end
        end
    )
end, { preventSpam = true, rateLimit = 10 })


RegisterLegacyCallback("tiktok:getMessages", function(source, cb, channelId, page)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end


    local isMember = MySQL.Sync.fetchScalar(
        "SELECT TRUE FROM phone_tiktok_channels WHERE id = ? AND (member_1 = ? OR member_2 = ?)",
        { channelId, account, account }
    )

    if not isMember then
        return cb({ success = false, error = "not_member" })
    end

    local query = [[
        SELECT
            m.id,
            m.sender,
            m.content,
            m.attachments,
            m.shared_video_id,
            m.timestamp,
            m.reply_to,
            rm.content as reply_content,
            rm.sender as reply_sender,
            a.name as sender_name,
            a.avatar as sender_avatar
        FROM phone_tiktok_messages m
        INNER JOIN phone_tiktok_accounts a ON a.username = m.sender
        LEFT JOIN phone_tiktok_messages rm ON m.reply_to = rm.id
        WHERE m.channel_id = ?
        ORDER BY m.timestamp DESC
        LIMIT ?, 50
    ]]

    MySQL.Async.fetchAll(query, { channelId, (page or 0) * 50 }, function(results)
        cb({ success = true, messages = results or {} })
    end)
end)


RegisterNetEvent("phone:tiktok:clearUnreadMessages", function(channelId)
    local source = source
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return
    end

    MySQL.Async.execute(
        "DELETE FROM phone_tiktok_unread_messages WHERE username = ? AND channel_id = ?",
        { account, channelId }
    )
end)


RegisterLegacyCallback("tiktok:getUnreadMessages", function(source, cb)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end

    local count = MySQL.Sync.fetchScalar(
        "SELECT COALESCE(SUM(amount), 0) FROM phone_tiktok_unread_messages WHERE username = ?",
        { account }
    )

    cb({ success = true, count = count or 0 })
end)


RegisterLegacyCallback("tiktok:deleteMessage", function(source, cb, messageId)
    local account = getLoggedInTikTokAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end


    local messageExists = MySQL.Sync.fetchScalar(
        "SELECT TRUE FROM phone_tiktok_messages WHERE id = ? AND sender = ?",
        { messageId, account }
    )

    if not messageExists then
        return cb({ success = false, error = "not_found" })
    end


    local channelId = MySQL.Sync.fetchScalar(
        "SELECT channel_id FROM phone_tiktok_messages WHERE id = ?",
        { messageId }
    )


    local channel = MySQL.Sync.fetchAll(
        "SELECT member_1, member_2 FROM phone_tiktok_channels WHERE id = ?",
        { channelId }
    )
    

    MySQL.Async.execute(
        "DELETE FROM phone_tiktok_messages WHERE id = ?",
        { messageId },
        function(affectedRows)
            if affectedRows > 0 then

                if channelId then
                    MySQL.Async.execute([[
                        UPDATE phone_tiktok_channels c
                        SET c.last_message = (
                            SELECT m.content
                            FROM phone_tiktok_messages m
                            WHERE m.channel_id = c.id
                            ORDER BY m.timestamp DESC
                            LIMIT 1
                        ),
                        c.timestamp = (
                            SELECT m.timestamp
                            FROM phone_tiktok_messages m
                            WHERE m.channel_id = c.id
                            ORDER BY m.timestamp DESC
                            LIMIT 1
                        )
                        WHERE c.id = ?
                    ]], { channelId }, function()

                        if channel and #channel > 0 then
                            local member1Sources = getSourcesForUsername(channel[1].member_1)
                            local member2Sources = getSourcesForUsername(channel[1].member_2)


                            for _, src in ipairs(member1Sources) do
                                TriggerClientEvent("phone:tiktok:messageDeleted", src, { messageId = messageId, channelId = channelId })
                                TriggerClientEvent("phone:tiktok:updateInbox", src, { channelId = channelId })
                            end


                            for _, src in ipairs(member2Sources) do
                                TriggerClientEvent("phone:tiktok:messageDeleted", src, { messageId = messageId, channelId = channelId })
                                TriggerClientEvent("phone:tiktok:updateInbox", src, { channelId = channelId })
                            end
                        end
                    end)
                end
                cb({ success = true })
            else
                cb({ success = false, error = "failed" })
            end
        end
    )
end)
