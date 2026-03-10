local ProfileCache = {}
local TweetCache = {}
local ThreadCache = {}
local PostCache = {}
local CACHE_TTL = 300000
local POST_CACHE_TTL = 180000
local MAX_POST_CACHE_ENTRIES = 300

local NotificationQueue = {}
local NotificationProcessing = false

local ActiveTwitterUsers = {}
local UsernameToSources = {}

local function clearExpiredCache()
    local now = GetGameTimer()
    for key, cache in pairs(ProfileCache) do
        if (now - cache.timestamp) > CACHE_TTL then
            ProfileCache[key] = nil
        end
    end
    for key, cache in pairs(TweetCache) do
        if (now - cache.timestamp) > CACHE_TTL then
            TweetCache[key] = nil
        end
    end
    for key, cache in pairs(PostCache) do
        if (now - cache.timestamp) > POST_CACHE_TTL then
            PostCache[key] = nil
        end
    end
end

local function invalidateProfileCache(username)
    ProfileCache[username] = nil
end

local function invalidateTweetCache(tweetId)
    TweetCache[tweetId] = nil
end

local function invalidatePostCache(pattern)
    if not pattern then
        PostCache = {}
        return
    end
    for key in pairs(PostCache) do
        if key:match(pattern) then
            PostCache[key] = nil
        end
    end
end

local function getCachedPosts(cacheKey)
    if PostCache[cacheKey] then
        local cached = PostCache[cacheKey]
        if (GetGameTimer() - cached.timestamp) < POST_CACHE_TTL then
            return cached.data
        end
        PostCache[cacheKey] = nil
    end
    return nil
end

local function cachePostData(cacheKey, data)
    local count = 0
    for _ in pairs(PostCache) do
        count = count + 1
    end

    if count >= MAX_POST_CACHE_ENTRIES then
        local oldestKey = nil
        local oldestTime = math.huge
        for key, cache in pairs(PostCache) do
            if cache.timestamp < oldestTime then
                oldestTime = cache.timestamp
                oldestKey = key
            end
        end
        if oldestKey then
            PostCache[oldestKey] = nil
        end
    end

    PostCache[cacheKey] = {
        data = data,
        timestamp = GetGameTimer()
    }
end

CreateThread(function()
    while true do
        Wait(300000)
        clearExpiredCache()
    end
end)

AddEventHandler("playerDropped", function()
    local source = source
    local username = ActiveTwitterUsers[source]

    if username then
        ActiveTwitterUsers[source] = nil
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

local function getActiveTwitterSources()
    local sources = {}
    for source, username in pairs(ActiveTwitterUsers) do
        if GetPlayerPing(source) > 0 then
            table.insert(sources, source)
        else
            ActiveTwitterUsers[source] = nil
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
    local sources = {}
    local followers = MySQL.query.await("SELECT follower FROM phone_twitter_follows WHERE followed = ?", { username })

    if not followers then return sources end

    for i = 1, #followers do
        local followerUsername = followers[i].follower
        local followerSources = getSourcesForUsername(followerUsername)
        for _, src in ipairs(followerSources) do
            table.insert(sources, src)
        end
    end

    return sources
end

local function broadcastToRelevant(eventName, data, targetSources)
    if not targetSources or #targetSources == 0 then
        return
    end

    for _, source in ipairs(targetSources) do
        TriggerClientEvent(eventName, source, data)
    end
end

local function getLoggedInTwitterAccount(source)
    local phone = GetEquippedPhoneNumber(source)
    if not phone then return false end
    return GetLoggedInAccount(phone, "Twitter")
end

local function createAuthenticatedCallback(name, handler, defaultReturn, options)
    BaseCallback("birdy:"..name, function(source, phoneNumber, ...)
        local account = GetLoggedInAccount(phoneNumber, "Twitter")
        if not account then
            return defaultReturn
        end
        return handler(source, phoneNumber, account, ...)
    end, defaultReturn, options)
end

local function notifyLoggedInDevices(username, notification, excludePhoneNumber)
    local rows = MySQL.query.await("SELECT phone_number FROM phone_logged_in_accounts WHERE username = ? AND app = 'Twitter' AND `active` = 1", { username })
    notification.app = "Twitter"
    for i = 1, (rows and #rows or 0) do
        local number = rows[i].phone_number
        if number ~= excludePhoneNumber then
            SendNotification(number, notification)
        end
    end
end

local function getPhoneNumberToSourceMap(username)
    local map = {}
    local rows = MySQL.query.await("SELECT phone_number FROM phone_logged_in_accounts WHERE username = ? AND app = 'Twitter' AND `active` = 1", { username })
    for i = 1, (rows and #rows or 0) do
        local phoneNumber = rows[i].phone_number
        map[phoneNumber] = GetSourceFromNumber(phoneNumber)
    end
    return map
end

local function getTwitterProfile(username, loggedInPhoneNumber)
    username = username:lower()

    local cacheKey = username
    if not loggedInPhoneNumber and ProfileCache[cacheKey] then
        local cached = ProfileCache[cacheKey]
        if (GetGameTimer() - cached.timestamp) < CACHE_TTL then
            return cached.data
        end
    end

    local acc = MySQL.single.await([[SELECT `display_name`, `bio`, `profile_image`, `profile_header`, `verified`, `follower_count`, `following_count`, `date_joined`, private FROM `phone_twitter_accounts` WHERE `username`=?]], { username })
    if not acc then return false end

    local isFollowing, isFollowingYou, notificationsEnabled, requested = false, false, false, false
    local pinnedTweet = nil

    local loggedInAs = nil
    if loggedInPhoneNumber then
        loggedInAs = GetLoggedInAccount(loggedInPhoneNumber, "Twitter")
    end

    if loggedInAs then
        local relationships = MySQL.single.await([[
            SELECT
                EXISTS(SELECT 1 FROM phone_twitter_follows WHERE follower = ? AND followed = ?) as isFollowing,
                EXISTS(SELECT 1 FROM phone_twitter_follows WHERE follower = ? AND followed = ?) as isFollowingYou,
                (SELECT notifications FROM phone_twitter_follows WHERE follower = ? AND followed = ? LIMIT 1) as notificationsEnabled,
                EXISTS(SELECT 1 FROM phone_twitter_follow_requests WHERE requester = ? AND requestee = ?) as requested,
                (SELECT pinned_tweet FROM phone_twitter_accounts WHERE username = ? LIMIT 1) as pinnedTweet
        ]], { loggedInAs, username, username, loggedInAs, loggedInAs, username, loggedInAs, username, username })

        if relationships then
            isFollowing = relationships.isFollowing == 1
            isFollowingYou = relationships.isFollowingYou == 1
            notificationsEnabled = relationships.notificationsEnabled == 1
            requested = relationships.requested == 1

            if relationships.pinnedTweet then
                pinnedTweet = GetTweet(relationships.pinnedTweet, loggedInAs)
            end
        end
    end

    local profile = {
        name = acc.display_name,
        username = username,
        followers = acc.follower_count,
        following = acc.following_count,
        date_joined = acc.date_joined,
        bio = acc.bio,
        verified = acc.verified,
        private = acc.private,
        profile_picture = acc.profile_image,
        header = acc.profile_header,
        isFollowing = isFollowing,
        isFollowingYou = isFollowingYou,
        notificationsEnabled = notificationsEnabled,
        pinnedTweet = pinnedTweet,
        requested = requested
    }

    if not loggedInPhoneNumber then
        ProfileCache[cacheKey] = {
            data = profile,
            timestamp = GetGameTimer()
        }
    end

    return profile
end

local notifKeys = {
    like = "BACKEND.TWITTER.LIKE",
    retweet = "BACKEND.TWITTER.RETWEET",
    reply = "BACKEND.TWITTER.REPLY",
    follow = "BACKEND.TWITTER.FOLLOW",
    tweet = "BACKEND.TWITTER.TWEET",
}

local function queueTwitterNotification(toUser, fromUser, notifType, tweetId)
    if toUser == fromUser then return end
    local key = notifKeys[notifType]
    if not key then return end

    table.insert(NotificationQueue, {
        toUser = toUser,
        fromUser = fromUser,
        notifType = notifType,
        tweetId = tweetId,
        timestamp = os.time()
    })

    if not NotificationProcessing then
        NotificationProcessing = true
        CreateThread(processNotificationQueue)
    end
end

function processNotificationQueue()
    while #NotificationQueue > 0 do
        Wait(500)

        local batch = {}
        local batchSize = math.min(50, #NotificationQueue)

        for i = 1, batchSize do
            table.insert(batch, table.remove(NotificationQueue, 1))
        end

        for _, notif in ipairs(batch) do
            local exists = MySQL.scalar.await(
                notif.notifType == "follow" and
                "SELECT TRUE FROM phone_twitter_notifications WHERE username=? AND `from`=? AND `type`=?" or
                "SELECT TRUE FROM phone_twitter_notifications WHERE username=? AND `from`=? AND `type`=? AND tweet_id=?",
                notif.notifType == "follow" and
                { notif.toUser, notif.fromUser, notif.notifType } or
                { notif.toUser, notif.fromUser, notif.notifType, notif.tweetId }
            )
            
            if not exists then
                local sender = MySQL.single.await("SELECT display_name, private FROM phone_twitter_accounts WHERE username=?", { notif.fromUser })
                
                if sender and not (sender.private and notif.notifType == "reply") then
                    local notifId = GenerateId("phone_twitter_notifications", "id")
                    local affected = MySQL.update.await(
                        "INSERT INTO phone_twitter_notifications (id, username, `from`, `type`, tweet_id) VALUES (?, ?, ?, ?, ?)",
                        { notifId, notif.toUser, notif.fromUser, notif.notifType, notif.tweetId }
                    )

                    if affected > 0 then
                        local title = L(notifKeys[notif.notifType], { displayName = sender.display_name, username = notif.fromUser })
                        local content, attachments = nil, nil

                        if notif.notifType ~= "follow" and notif.tweetId then
                            local tweet = MySQL.single.await("SELECT content, attachments FROM phone_twitter_tweets WHERE id=?", { notif.tweetId })
                            if tweet then
                                content = tweet.content
                                attachments = tweet.attachments
                                if attachments then
                                    attachments = json.decode(attachments)
                                end
                            end
                        end

                        notifyLoggedInDevices(notif.toUser, { title = title, content = content, attachments = attachments })
                    end
                end
            end
        end
    end

    NotificationProcessing = false
end

local function sendTwitterNotification(toUser, fromUser, notifType, tweetId)
    queueTwitterNotification(toUser, fromUser, notifType, tweetId)
end

local function GetTweetInternal(id, loggedInAs)
    if not id then return end
    local tweet = MySQL.single.await([[SELECT DISTINCT t.id, t.username, t.content, t.attachments,
        t.like_count, t.reply_count, t.retweet_count, t.reply_to, t.`timestamp`,
        (CASE WHEN t.reply_to IS NULL THEN NULL ELSE (SELECT username FROM phone_twitter_tweets WHERE id=t.reply_to LIMIT 1) END) AS replyToAuthor,
        a.display_name, a.username, a.profile_image, a.verified
        FROM phone_twitter_tweets t INNER JOIN phone_twitter_accounts a ON a.username=t.username
        WHERE t.id=@tweetId AND (a.private=0 OR a.username=@loggedInAs OR (
            SELECT TRUE FROM phone_twitter_follows f WHERE f.follower=@loggedInAs AND f.followed=a.username))]],
        { ["@tweetId"] = id, ["@loggedInAs"] = loggedInAs }
    )

    if not tweet then return nil end

    return tweet
end

GetTweet = function(id, loggedInAs)
    return GetTweetInternal(id, loggedInAs)
end

exports("GetTweet", function(id, cb)
    infoprint("warning", "GetTweet is deprecated, use GetBirdyPost instead")
    MySQL.Async.fetchAll([[SELECT DISTINCT t.id, t.username, t.content, t.attachments,
        t.like_count, t.reply_count, t.retweet_count, t.reply_to, t.`timestamp`,
        a.display_name, a.username, a.profile_image, a.verified
        FROM (phone_twitter_tweets t, phone_twitter_accounts a)
        WHERE t.id=@tweetId AND t.username=a.username]], { ["@tweetId"] = id }, cb)
end)

exports("GetBirdyPost", function(id)
    local row = MySQL.single.await([[SELECT t.id,
        t.username,
        t.content,
        t.attachments,
        t.like_count AS likes,
        t.reply_count AS replies,
        t.retweet_count AS reposts,
        t.reply_to AS replyTo,
        t.`timestamp`,
        a.display_name AS displayName,
        a.profile_image AS avatar,
        a.verified
        FROM phone_twitter_tweets t LEFT JOIN phone_twitter_accounts a ON a.username = t.username
        WHERE t.id = ?]], { id })
    if not row then return nil end

    if row.attachments then row.attachments = json.decode(row.attachments) end

    return row
end)

RegisterLegacyCallback("birdy:getNotifications", function(source, cb, page)
    local username = getLoggedInTwitterAccount(source)
    if not username then
        return cb({ notifications = {}, requests = 0 })
    end

    local notifications = MySQL.query.await([[SELECT
            n.id, n.`from`, n.`type`, n.tweet_id, n.`timestamp` AS notification_timestamp,
            t.username AS tweet_author, t.content, t.attachments, t.reply_to, t.like_count,
            t.reply_count, t.retweet_count, t.`timestamp`,
            (
                SELECT TRUE FROM phone_twitter_likes l
                WHERE l.tweet_id=t.id AND l.username=@username
            ) AS liked,
            (
                SELECT TRUE FROM phone_twitter_retweets r
                WHERE r.tweet_id=t.id AND r.username=@username
            ) AS retweeted,
            n.`from` AS username, a.display_name AS `name`, a.profile_image AS profile_picture, a.verified,
            (
                CASE WHEN t.reply_to IS NULL THEN NULL ELSE (SELECT username FROM phone_twitter_tweets WHERE id=t.reply_to LIMIT 1) END
            ) AS replyToAuthor
        FROM phone_twitter_notifications n
        LEFT JOIN phone_twitter_tweets t ON n.tweet_id = t.id
        JOIN phone_twitter_accounts a ON a.username = n.from
        WHERE n.username=@username
            AND (n.type = 'follow' OR t.id IS NOT NULL)
        ORDER BY n.`timestamp` DESC
        LIMIT @page, @perPage
    ]], {
        ["@username"] = username,
        ["@page"] = (page or 0) * 15,
        ["@perPage"] = 15
    }) or {}

    if (page or 0) > 0 then
        return cb({ notifications = notifications })
    end

    local requests = MySQL.scalar.await(
        "SELECT COUNT(1) FROM phone_twitter_follow_requests WHERE requestee=@username",
        { ["@username"] = username }
    ) or 0

    cb({ notifications = notifications, requests = requests })
end)

RegisterLegacyCallback("birdy:createAccount", function(source, cb, displayName, username, password)
    local phoneNumber = GetEquippedPhoneNumber(source)
    if not phoneNumber then return cb(false) end

    username = username:lower()
    if not IsUsernameValid(username) then
        return cb({ success = false, error = "USERNAME_NOT_ALLOWED" })
    end

    local exists = MySQL.scalar.await(
        "SELECT TRUE FROM phone_twitter_accounts WHERE username=@username",
        { ["@username"] = username }
    )
    if exists then
        return cb({ success = false, error = "USERNAME_TAKEN" })
    end

    MySQL.update.await("INSERT INTO phone_twitter_accounts (display_name, username, `password`, phone_number) VALUES (@displayName, @username, @password, @phonenumber)",
        {
            ["@displayName"] = displayName,
            ["@username"] = username,
            ["@password"] = GetPasswordHash(password),
            ["@phonenumber"] = phoneNumber
        }
    )

    AddLoggedInAccount(phoneNumber, "Twitter", username)
    cb({ success = true })

    if Config.AutoFollow.Enabled and Config.AutoFollow.Birdy.Enabled then
        for i = 1, #Config.AutoFollow.Birdy.Accounts do
            MySQL.update.await("INSERT INTO phone_twitter_follows (followed, follower) VALUES (?, ?)", {
                Config.AutoFollow.Birdy.Accounts[i],
                username
            })
        end
    end
end, { preventSpam = true, rateLimit = 4 })

BaseCallback("birdy:login", function(source, phoneNumber, username, password)
    username = username:lower()
    local hashed = MySQL.scalar.await("SELECT `password` FROM phone_twitter_accounts WHERE username = ?", { username })
    if not hashed then
        return { success = false, error = "INVALID_ACCOUNT" }
    end
    if not VerifyPasswordHash(password, hashed) then
        return { success = false, error = "INVALID_PASSWORD" }
    end

    AddLoggedInAccount(phoneNumber, "Twitter", username)
    local data = getTwitterProfile(username)
    if not data then
        return { success = false, error = "INVALID_ACCOUNT" }
    end
    return { success = true, data = data }
end)

BaseCallback("birdy:isLoggedIn", function(source, phoneNumber)
    local account = GetLoggedInAccount(phoneNumber, "Twitter")
    
    if account then
        local accountExists = MySQL.scalar.await(
            "SELECT TRUE FROM phone_twitter_accounts WHERE username = ?",
            { account }
        )
        if not accountExists then
            RemoveLoggedInAccount(phoneNumber, "Twitter", account)
            account = nil
        end
    end
    
    if not account then
        local existingUsername = MySQL.scalar.await(
            "SELECT username FROM phone_twitter_accounts WHERE phone_number = ?",
            { phoneNumber }
        )
        
        if existingUsername then
            AddLoggedInAccount(phoneNumber, "Twitter", existingUsername)
            account = existingUsername
        else
            local firstname, lastname = GetCharacterName(source)
            
            if firstname and firstname ~= "" then
                firstname = firstname:sub(1, 8)
            else
                firstname = "Player"..source
            end
            
            if lastname and lastname ~= "" then
                lastname = lastname:sub(1, 8)
            end
            
            local characterName = firstname
            if lastname and lastname ~= "" then
                characterName = firstname.." "..lastname
            end

            local username = characterName:gsub("%s+", ""):sub(1, 8):lower()
            
            local baseUsername = username
            local counter = 1
            while MySQL.scalar.await("SELECT TRUE FROM phone_twitter_accounts WHERE username = ?", { username }) do
                username = baseUsername..counter
                counter = counter + 1
                if counter > 999 then
                    username = "user"..math.random(10000, 99999)
                    break
                end
            end

            if not IsUsernameValid(username) then
                username = "user"..math.random(1000, 9999)
            end

            local displayName = characterName
            local password = tostring(math.random(100000, 999999))..tostring(os.time())

            MySQL.update.await("INSERT INTO phone_twitter_accounts (display_name, username, `password`, phone_number) VALUES (?, ?, ?, ?)",
                { displayName, username, GetPasswordHash(password), phoneNumber }
            )

            AddLoggedInAccount(phoneNumber, "Twitter", username)
            account = username

            if Config.AutoFollow.Enabled and Config.AutoFollow.Birdy.Enabled then
                for i = 1, #Config.AutoFollow.Birdy.Accounts do
                    MySQL.update.await("INSERT INTO phone_twitter_follows (followed, follower) VALUES (?, ?)", {
                        Config.AutoFollow.Birdy.Accounts[i],
                        username
                    })
                end
            end
        end
    end

    if source and account then
        ActiveTwitterUsers[source] = account
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

    return getTwitterProfile(account)
end, false)

createAuthenticatedCallback("getProfile", function(_, phoneNumber, __, target)
    return getTwitterProfile(target, phoneNumber)
end, false)

RegisterLegacyCallback("birdy:pinPost", function(source, cb, tweetId)
    local username = getLoggedInTwitterAccount(source)
    if not username then return cb(false) end

    if tweetId then
        local owns = MySQL.scalar.await(
            "SELECT TRUE FROM phone_twitter_tweets WHERE id = ? AND username = ?",
            { tweetId, username }
        )
        if not owns then
            infoprint("warning", ("%s (%s) tried to pin a post they didn't make."):format(username, source))
            return cb(false)
        end
    end

    MySQL.Async.execute("UPDATE phone_twitter_accounts SET pinned_tweet=@tweetId WHERE username=@username", {
        ["@tweetId"] = tweetId or nil,
        ["@username"] = username
    }, function()
        cb(true)
    end)
end)

RegisterLegacyCallback("birdy:signOut", function(source, cb)
    cb(false)
end)

RegisterLegacyCallback("birdy:updateProfile", function(source, cb, data)
    local username = getLoggedInTwitterAccount(source)
    if not username then return cb(false) end

    MySQL.Async.execute("UPDATE phone_twitter_accounts SET display_name=@displayName, bio=@bio, profile_image=@profilePicture, profile_header=@header, private=@private WHERE username=@username",
        {
            ["@username"] = username,
            ["@displayName"] = data.name,
            ["@bio"] = data.bio,
            ["@profilePicture"] = data.profile_picture,
            ["@header"] = data.header,
            ["@private"] = data.private,
        }, function()
        invalidateProfileCache(username)
        cb(true)
    end)
end)

RegisterLegacyCallback("birdy:changeDisplayName", function(source, cb, newDisplayName)
    local username = getLoggedInTwitterAccount(source)
    if not username then 
        return cb({ success = false, error = "NOT_LOGGED_IN" })
    end

    if not newDisplayName or type(newDisplayName) ~= "string" or #newDisplayName < 1 then
        return cb({ success = false, error = "INVALID_DISPLAY_NAME" })
    end

    if #newDisplayName > 20 then
        return cb({ success = false, error = "DISPLAY_NAME_TOO_LONG" })
    end

    local cost = Config.BirdyChangeName.DisplayNameCost
    local success = RemoveMoney(source, cost, "Đổi tên hiển thị Twitter", "priority")
    
    if not success then
        local phoneNumber = GetEquippedPhoneNumber(source)
        if phoneNumber then
            SendNotification(phoneNumber, {
                app = "Twitter",
                title = "Không đủ tiền",
                content = "Bạn cần $1 IC để đổi tên hiển thị"
            })
        end
        return cb({ success = false, error = "INSUFFICIENT_FUNDS" })
    end

    MySQL.Async.execute("UPDATE phone_twitter_accounts SET display_name = ? WHERE username = ?", { newDisplayName, username }, function(affectedRows)
        if affectedRows > 0 then
            invalidateProfileCache(username)
            
            local phoneNumber = GetEquippedPhoneNumber(source)
            if phoneNumber then
                local title = L("BACKEND.TWITTER.DISPLAY_NAME_CHANGED_TITLE")
                if not title or title:find("BACKEND") then
                    title = "Tên hiển thị đã được thay đổi"
                end
                local content = L("BACKEND.TWITTER.DISPLAY_NAME_CHANGED_DESCRIPTION", { displayName = newDisplayName })
                if not content or content:find("BACKEND") then
                    content = "Tên hiển thị của bạn đã được đổi thành "..newDisplayName
                end
                SendNotification(phoneNumber, {
                    app = "Twitter",
                    title = title,
                    content = content
                })
            end

            cb({ success = true, newDisplayName = newDisplayName })
        else
            cb({ success = false, error = "UPDATE_FAILED" })
        end
    end)
end)

RegisterLegacyCallback("birdy:changeUsername", function(source, cb, newUsername)
    local currentUsername = getLoggedInTwitterAccount(source)
    if not currentUsername then 
        return cb({ success = false, error = "NOT_LOGGED_IN" })
    end

    if not newUsername or type(newUsername) ~= "string" or #newUsername < 1 then
        return cb({ success = false, error = "INVALID_USERNAME" })
    end

    newUsername = newUsername:lower()

    if #newUsername < 3 then
        return cb({ success = false, error = "USERNAME_TOO_SHORT" })
    end

    if #newUsername > 8 then
        return cb({ success = false, error = "USERNAME_TOO_LONG" })
    end

    if not IsUsernameValid(newUsername) then
        return cb({ success = false, error = "USERNAME_NOT_ALLOWED" })
    end

    local exists = MySQL.scalar.await("SELECT TRUE FROM phone_twitter_accounts WHERE username = ? AND username != ?", { newUsername, currentUsername })
    
    if exists then
        local phoneNumber = GetEquippedPhoneNumber(source)
        if phoneNumber then
            SendNotification(phoneNumber, {
                app = "Twitter",
                title = "Username đã được sử dụng",
                content = "Username @"..newUsername.." đã có người sử dụng"
            })
        end
        return cb({ success = false, error = "USERNAME_TAKEN" })
    end

    local cost = Config.BirdyChangeName.UsernameCost
    local success = RemoveMoney(source, cost, "Đổi username Twitter", "priority")
    
    if not success then
        local phoneNumber = GetEquippedPhoneNumber(source)
        if phoneNumber then
            SendNotification(phoneNumber, {
                app = "Twitter",
                title = "Không đủ tiền",
                content = "Bạn cần $1 IC để đổi username"
            })
        end
        return cb({ success = false, error = "INSUFFICIENT_FUNDS" })
    end

    local phoneNumber = GetEquippedPhoneNumber(source)
    
    MySQL.Async.execute("UPDATE phone_twitter_accounts SET username = ? WHERE username = ? AND phone_number = ?", { newUsername, currentUsername, phoneNumber }, function(affectedRows)
        if affectedRows > 0 then
            MySQL.Async.execute("UPDATE phone_twitter_tweets SET username = ? WHERE username = ?", { newUsername, currentUsername })
            MySQL.Async.execute("UPDATE phone_twitter_follows SET follower = ? WHERE follower = ?", { newUsername, currentUsername })
            MySQL.Async.execute("UPDATE phone_twitter_follows SET followed = ? WHERE followed = ?", { newUsername, currentUsername })
            MySQL.Async.execute("UPDATE phone_twitter_likes SET username = ? WHERE username = ?", { newUsername, currentUsername })
            MySQL.Async.execute("UPDATE phone_twitter_retweets SET username = ? WHERE username = ?", { newUsername, currentUsername })
            MySQL.Async.execute("UPDATE phone_twitter_notifications SET username = ? WHERE username = ?", { newUsername, currentUsername })
            MySQL.Async.execute("UPDATE phone_twitter_notifications SET `from` = ? WHERE `from` = ?", { newUsername, currentUsername })
            MySQL.Async.execute("UPDATE phone_twitter_follow_requests SET requester = ? WHERE requester = ?", { newUsername, currentUsername })
            MySQL.Async.execute("UPDATE phone_twitter_follow_requests SET requestee = ? WHERE requestee = ?", { newUsername, currentUsername })
            MySQL.Async.execute("UPDATE phone_logged_in_accounts SET username = ? WHERE username = ? AND app = 'Twitter'", { newUsername, currentUsername })
            
            invalidateProfileCache(currentUsername)
            invalidateProfileCache(newUsername)
            
            for src, uname in pairs(ActiveTwitterUsers) do
                if uname == currentUsername then
                    ActiveTwitterUsers[src] = newUsername
                end
            end
            
            if UsernameToSources[currentUsername] then
                UsernameToSources[newUsername] = UsernameToSources[currentUsername]
                UsernameToSources[currentUsername] = nil
            end
            
            local phoneNumber = GetEquippedPhoneNumber(source)
            if phoneNumber then
                RemoveLoggedInAccount(phoneNumber, "Twitter", currentUsername)
                AddLoggedInAccount(phoneNumber, "Twitter", newUsername)
                
                local title = L("BACKEND.TWITTER.USERNAME_CHANGED_TITLE")
                if not title or title:find("BACKEND") then
                    title = "Username đã được thay đổi"
                end
                local content = L("BACKEND.TWITTER.USERNAME_CHANGED_DESCRIPTION", { username = newUsername })
                if not content or content:find("BACKEND") then
                    content = "Username của bạn đã được đổi thành @"..newUsername
                end
                SendNotification(phoneNumber, {
                    app = "Twitter",
                    title = title,
                    content = content
                })
            end

            local newProfile = getTwitterProfile(newUsername, phoneNumber)
            cb({ success = true, newUsername = newUsername, profile = newProfile, needReload = true })
        else
            cb({ success = false, error = "UPDATE_FAILED" })
        end
    end)
end)

createAuthenticatedCallback("changePassword", function(source, phoneNumber, account, oldPassword, newPassword)
    if not Config.ChangePassword or not Config.ChangePassword.Birdy then
        infoprint("warning", ("%s tried to change Birdy password but it's disabled in config"):format(source))
        return false
    end
    if oldPassword == newPassword or #tostring(newPassword) < 3 then
        return false
    end

    local current = MySQL.scalar.await("SELECT password FROM phone_twitter_accounts WHERE username = ?", { account })
    if not current or not VerifyPasswordHash(oldPassword, current) then
        return false
    end

    local ok = MySQL.update.await("UPDATE phone_twitter_accounts SET password = ? WHERE username = ?", {GetPasswordHash(newPassword), account}) > 0
    if not ok then return false end

    notifyLoggedInDevices(account, {
        title = L("BACKEND.MISC.LOGGED_OUT_PASSWORD.TITLE"),
        content = L("BACKEND.MISC.LOGGED_OUT_PASSWORD.DESCRIPTION")
    }, phoneNumber)

    MySQL.update.await("DELETE FROM phone_logged_in_accounts WHERE username = ? AND app = 'Twitter' AND phone_number != ?", { account, phoneNumber })
    ClearActiveAccountsCache("Twitter", account, phoneNumber)

    Log("Birdy", source, "info",
        L("BACKEND.LOGS.CHANGED_PASSWORD.TITLE"),
        L("BACKEND.LOGS.CHANGED_PASSWORD.DESCRIPTION", { number = phoneNumber, username = account, app = "Birdy" })
    )

    for phone, src in pairs(getPhoneNumberToSourceMap(account)) do
        if src then
            TriggerClientEvent("phone:logoutFromApp", src, { username = account, app = "birdy", reason = "password", number = phoneNumber })
        end
    end
    return true
end, false)

createAuthenticatedCallback("deleteAccount", function(source, phoneNumber, account, password)
    if not Config.DeleteAccount or not Config.DeleteAccount.Birdy then
        infoprint("warning", ("%s tried to delete Birdy account but it's disabled in config"):format(source))
        return false
    end
    local current = MySQL.scalar.await("SELECT password FROM phone_twitter_accounts WHERE username = ?", { account })
    if not current or not VerifyPasswordHash(password, current) then
        return false
    end

    local deleted = MySQL.update.await("DELETE FROM phone_twitter_accounts WHERE username = ?", { account }) > 0
    if not deleted then return false end

    notifyLoggedInDevices(account, {
        title = L("BACKEND.MISC.DELETED_NOTIFICATION.TITLE"),
        content = L("BACKEND.MISC.DELETED_NOTIFICATION.DESCRIPTION")
    })

    MySQL.update.await("DELETE FROM phone_logged_in_accounts WHERE username = ? AND app = 'Twitter'", { account })
    ClearActiveAccountsCache("Twitter", account)

    Log("Birdy", source, "info",
        L("BACKEND.LOGS.DELETED_ACCOUNT.TITLE"),
        L("BACKEND.LOGS.DELETED_ACCOUNT.DESCRIPTION", { number = phoneNumber, username = account, app = "Birdy" })
    )

    for phone, src in pairs(getPhoneNumberToSourceMap(account)) do
        if src then
            TriggerClientEvent("phone:logoutFromApp", src, { username = account, app = "twitter", reason = "deleted" })
        end
    end
    return true
end, false)

local function sendPostWebhook(username, content, attachments, isReply)
    if not (Config.Post and Config.Post.Birdy) or isReply then return end
    if not BIRDY_WEBHOOK or not BIRDY_WEBHOOK:find("/api/webhooks/") then return end

    local avatar = MySQL.scalar.await("SELECT profile_image FROM phone_twitter_accounts WHERE username = ?", { username })
    PerformHttpRequest(BIRDY_WEBHOOK, function() end, "POST", json.encode({
        username = Config.Post.Accounts.Birdy.Username or "Twitter",
        avatar_url = Config.Post.Accounts.Birdy.Avatar or "https://loaf-scripts.com/fivem/lb-phone/icons/Birdy.png",
        embeds = { {
            title = 'Bài đăng mới',
            description = (content and #content > 0) and content or nil,
            color = 1942002,
            timestamp = GetTimestampISO(),
            author = { name = "@"..username, icon_url = avatar or "https://cdn.discordapp.com/embed/avatars/5.png" },
            image = (attachments and #attachments > 0) and { url = attachments[1] } or nil,
            footer = { text = "F17 Phone", icon_url = "https://media.discordapp.net/attachments/1008372897695404042/1369276368591917126/F17launcher_icon.png?ex=694c78be&is=694b273e&hm=ae0a4d047ef79822d08ed6a8d570d37edb0fb430e672c2c4bbb5b72ce33f7e71&=&format=webp&quality=lossless&width=461&height=461" }
        } }
    }), { ["Content-Type"] = "application/json" })
end

local function PostBirdy(username, content, attachments, replyTo, hashtags, source)
    content = content or ""
    assert(type(username) == "string", "PostBirdy: Expected string for argument 1 (username), got "..type(username))
    assert(type(content) == "string", "PostBirdy: Expected string/nil for argument 2 (content), got "..type(content))

    if replyTo then
        local parentReply = MySQL.scalar.await("SELECT reply_to FROM phone_twitter_tweets WHERE id = ?", { replyTo })
        if parentReply then
            error("PostBirdy: Cannot reply to a reply. Only replies to original tweets are allowed.")
        end
    end

    local id = GenerateId("phone_twitter_tweets", "id")
    local params = { id, username, content }
    local query = "INSERT INTO phone_twitter_tweets (id, username, content"

    if attachments then
        if type(attachments) == "table" and table.type(attachments) == "array" and #attachments > 0 then
            query = query..", attachments"
            params[#params + 1] = json.encode(attachments)
        elseif type(attachments) ~= "table" then
            error("PostBirdy: Expected table/nil for argument 3 (attachments), got "..type(attachments))
        end
    end

    if hashtags then
        if type(hashtags) == "table" and table.type(hashtags) == "array" and #hashtags > 0 then
            query = query..", hashtags"
            params[#params + 1] = json.encode(hashtags)
        elseif type(hashtags) ~= "table" then
            error("PostBirdy: Expected table/nil for argument 5 (hashtags), got "..type(hashtags))
        end
    end

    if replyTo then
        assert(type(replyTo) == "string", "PostBirdy: Expected string/nil for argument 4 (replyTo), got "..type(replyTo))
        query = query..", reply_to"
        params[#params + 1] = replyTo
    end

    local values = "("..string.rep("?,", #params):sub(1, -2)..")"
    query = query..") VALUES "..values

    local affected = MySQL.update.await(query, params)
    if affected == 0 then return false end

    if replyTo then
        MySQL.update("UPDATE phone_twitter_tweets SET reply_count = reply_count + 1 WHERE id = ?", { replyTo })

        local relevantSources = {}

        local authorFollowerSources = getFollowerSources(username)
        for _, src in ipairs(authorFollowerSources) do
            table.insert(relevantSources, src)
        end

        local activeSources = getActiveTwitterSources()
        for _, src in ipairs(activeSources) do
            table.insert(relevantSources, src)
        end

        broadcastToRelevant("phone:twitter:updateTweetData", {replyTo, "replies", true}, relevantSources)

        local tweetData = MySQL.single.await([[
            WITH RECURSIVE thread_hierarchy AS (
                SELECT id, username, reply_to, 0 as depth
                FROM phone_twitter_tweets
                WHERE id = ?

                UNION ALL

                SELECT t.id, t.username, t.reply_to, th.depth + 1
                FROM phone_twitter_tweets t
                INNER JOIN thread_hierarchy th ON t.id = th.reply_to
                WHERE th.depth < 10
            )
            SELECT id, username FROM thread_hierarchy ORDER BY depth DESC LIMIT 1
        ]], { replyTo })

        local originalTweetId = tweetData and tweetData.id or replyTo
        local replyToAuthor = tweetData and tweetData.username or nil

        local threadParticipants = ThreadCache[originalTweetId]

        if not threadParticipants or (GetGameTimer() - threadParticipants.timestamp) > 60000 then
            local participants = MySQL.query.await([[
                SELECT DISTINCT username FROM (
                    SELECT username FROM phone_twitter_tweets WHERE reply_to = ?
                    UNION
                    SELECT username FROM phone_twitter_tweets
                    WHERE reply_to IN (SELECT id FROM phone_twitter_tweets WHERE reply_to = ?)
                ) as all_participants
            ]], { originalTweetId, originalTweetId }) or {}

            threadParticipants = {}
            for i = 1, #participants do
                threadParticipants[participants[i].username] = true
            end

            ThreadCache[originalTweetId] = {
                participants = threadParticipants,
                timestamp = GetGameTimer()
            }
        else
            threadParticipants = threadParticipants.participants
        end

        local notifiedUsers = {}

        if replyToAuthor and replyToAuthor ~= username then
            queueTwitterNotification(replyToAuthor, username, "reply", id)
            notifiedUsers[replyToAuthor] = true
        end

        for participant, _ in pairs(threadParticipants) do
            if participant ~= username and not notifiedUsers[participant] then
                queueTwitterNotification(participant, username, "reply", id)
                notifiedUsers[participant] = true
            end
        end

        if content then
            local mentions = {}
            for mentionedUser in string.gmatch(content, "@(%w+)") do
                mentionedUser = mentionedUser:lower()
                if mentionedUser ~= username and not notifiedUsers[mentionedUser] then
                    table.insert(mentions, mentionedUser)
                end
            end

            if #mentions > 0 then
                local placeholders = string.rep("?,", #mentions):sub(1, -2)
                local existingUsers = MySQL.query.await(
                    "SELECT username FROM phone_twitter_accounts WHERE username IN ("..placeholders..")",
                    mentions
                ) or {}

                for _, user in ipairs(existingUsers) do
                    if not notifiedUsers[user.username] then
                        queueTwitterNotification(user.username, username, "reply", id)
                        notifiedUsers[user.username] = true
                    end
                end
            end
        end
    end

    if not replyTo then
        MySQL.query("SELECT follower FROM phone_twitter_follows WHERE followed = ?", { username },
            function(rows)
                for i = 1, (rows and #rows or 0) do
                    sendTwitterNotification(rows[i].follower, username, "tweet", id)
                end
            end)
    end

    TrackSocialMediaPost("birdy", attachments)

    sendPostWebhook(username, content, attachments, replyTo ~= nil)

    local profile = MySQL.single.await(
    "SELECT display_name, profile_image, verified, private FROM phone_twitter_accounts WHERE username = ?", { username }) or
    { display_name = username }
    local payload = {
        id = id,
        username = username,
        content = content,
        attachments = attachments,
        like_count = 0,
        reply_count = 0,
        retweet_count = 0,
        reply_to = replyTo,
        timestamp = os.time() * 1000,
        liked = false,
        retweeted = false,
        display_name = profile.display_name,
        profile_image = profile.profile_image,
        verified = profile.verified
    }
    if replyTo then
        payload.replyToAuthor = MySQL.scalar.await("SELECT username FROM phone_twitter_tweets WHERE id = ?", { replyTo })
    end

    if not replyTo then
        local relevantSources = {}

        local followerSources = getFollowerSources(username)
        for _, src in ipairs(followerSources) do
            table.insert(relevantSources, src)
        end

        local activeSources = getActiveTwitterSources()
        for _, src in ipairs(activeSources) do
            local isDuplicate = false
            for _, existingSrc in ipairs(relevantSources) do
                if existingSrc == src then
                    isDuplicate = true
                    break
                end
            end
            if not isDuplicate then
                table.insert(relevantSources, src)
            end
        end

        broadcastToRelevant("phone:twitter:newtweet", payload, relevantSources)
    end

    TriggerEvent("lb-phone:birdy:newPost", payload)


    if Config.BirdyTrending and Config.BirdyTrending.Enabled and hashtags and type(hashtags) == "table" and table.type(hashtags) == "array" and #hashtags > 0 then
        local q = "INSERT INTO phone_twitter_hashtags (hashtag, amount) VALUES " ..
        string.rep("(?, 1), ", #hashtags):sub(1, -3).." ON DUPLICATE KEY UPDATE amount = amount + 1"
        MySQL.update(q, hashtags)
    end

    invalidatePostCache("posts_.*_"..username)
    invalidatePostCache("posts_.*_all")

    return true, id
end

exports("PostBirdy", PostBirdy)

createAuthenticatedCallback("sendPost", function(source, phoneNumber, account, content, attachments, replyTo, hashtags)
    if ContainsBlacklistedWord(source, "Birdy", content) then
        return false
    end

    if replyTo then
        local parentTweet = MySQL.scalar.await("SELECT reply_to FROM phone_twitter_tweets WHERE id = ?", { replyTo })
        if parentTweet then
            return false
        end
    end

    local result = PostBirdy(account, content, attachments, replyTo, hashtags, source)
    return result
end, { success = false, error = "COMMENT_RATE_LIMIT" }, { 
    preventSpam = true, 
    rateLimit = 15, 
    rateLimitNotification = true,
    rateLimitMessage = "Bạn đã đạt giới hạn đăng bài. Vui lòng quay lại sau 1 phút"
})


RegisterCallback("birdy:getRecentHashtags", function()
    if Config.BirdyTrending and Config.BirdyTrending.Enabled then
        return MySQL.query.await(
        "SELECT hashtag, amount AS uses FROM phone_twitter_hashtags ORDER BY amount DESC LIMIT 5")
    end
    return {}
end)

RegisterLegacyCallback("birdy:deletePost", function(source, cb, tweetId)
    local username = getLoggedInTwitterAccount(source)
    if not username then return cb(false) end

    local replyTo = MySQL.scalar.await("SELECT reply_to FROM phone_twitter_tweets WHERE id=@id",
        { ["@id"] = tweetId })

    local canDelete = IsAdmin and IsAdmin(source) or false
    if not canDelete then
        canDelete = MySQL.scalar.await("SELECT TRUE FROM phone_twitter_tweets WHERE id=@id AND username=@username",
            { ["@id"] = tweetId, ["@username"] = username })
    end
    if not canDelete then return cb(false) end

    local params = { ["@id"] = tweetId }
    MySQL.update.await("DELETE FROM phone_twitter_likes WHERE tweet_id=@id", params)
    MySQL.update.await("DELETE FROM phone_twitter_retweets WHERE tweet_id=@id", params)
    MySQL.update.await("DELETE FROM phone_twitter_notifications WHERE tweet_id=@id", params)
    local deleted = MySQL.update.await("DELETE FROM phone_twitter_tweets WHERE id=@id", params) > 0
    cb(deleted)
    if not deleted then return end

    local relevantSources = getActiveTwitterSources()
    broadcastToRelevant("phone:twitter:deleteTweet", tweetId, relevantSources)

    if replyTo then
        local count = MySQL.scalar.await("SELECT COUNT(id) FROM phone_twitter_tweets WHERE reply_to=@replyTo",
            { ["@replyTo"] = replyTo })
        MySQL.update.await("UPDATE phone_twitter_tweets SET reply_count=@count WHERE id=@replyTo",
            { ["@replyTo"] = replyTo, ["@count"] = count })

        broadcastToRelevant("phone:twitter:updateTweetData", {
            tweetId = replyTo,
            field = "replies",
            count = count
        }, relevantSources)

        invalidateTweetCache(tweetId)
        invalidateTweetCache(replyTo)
    end

    invalidatePostCache("posts_.*_"..username)
    invalidatePostCache("posts_.*_all")

    Log("Birdy", source, "info", "Post deleted", "**ID**: "..tostring(tweetId))
end)

RegisterLegacyCallback("birdy:getRandomPromoted", function(source, cb)
    local username = getLoggedInTwitterAccount(source)
    if not username then return cb(false) end

    local tweetId = MySQL.scalar.await(
    "SELECT tweet_id FROM phone_twitter_promoted WHERE promotions > 0 ORDER BY RAND() LIMIT 1")
    if not tweetId then return cb(false) end

    MySQL.update.await(
    "UPDATE phone_twitter_promoted SET promotions = promotions - 1, views = views + 1 WHERE tweet_id = @tweetId",
        { ["@tweetId"] = tweetId })
    cb(GetTweet(tweetId))
end)

RegisterLegacyCallback("birdy:promotePost", function(source, cb, tweetId)
    if not (Config.PromoteBirdy and Config.PromoteBirdy.Enabled) then
        return cb(false)
    end
    
    local success = RemoveMoney(source, Config.PromoteBirdy.Cost, "Quảng bá bài đăng Twitter", "priority")
    
    if not success then
        return cb(false)
    end
    
    MySQL.Async.execute(
    [[INSERT INTO phone_twitter_promoted (tweet_id, promotions, views) VALUES (@tweetId, @promotions, 0)
        ON DUPLICATE KEY UPDATE promotions = promotions + @promotions]], {
        ["@tweetId"] = tweetId,
        ["@promotions"] = Config.PromoteBirdy.Views
    }, function()
        cb(true)
    end)
end)

RegisterLegacyCallback("birdy:searchAccounts", function(_, cb, search)
    MySQL.Async.fetchAll([[SELECT display_name, username, profile_image, verified, private
        FROM phone_twitter_accounts
        WHERE username LIKE CONCAT(@search, "%") OR display_name LIKE CONCAT("%", @search, "%")]], {
        ["@search"] = search
    }, cb)
end)

RegisterLegacyCallback("birdy:searchTweets", function(source, cb, search, page)
    local loggedInAs = getLoggedInTwitterAccount(source)
    if not loggedInAs then return cb(false) end

    MySQL.Async.fetchAll([[SELECT DISTINCT t.id, t.username, t.content, t.attachments,
            t.like_count, t.reply_count, t.retweet_count, t.reply_to, t.`timestamp`,
            (CASE WHEN t.reply_to IS NULL THEN NULL ELSE (SELECT username FROM phone_twitter_tweets WHERE id=t.reply_to LIMIT 1) END) AS replyToAuthor,
            a.display_name, a.username, a.profile_image, a.verified,
            (SELECT TRUE FROM phone_twitter_likes l WHERE l.tweet_id=t.id AND l.username=@loggedInAs) AS liked,
            (SELECT TRUE FROM phone_twitter_retweets r WHERE r.tweet_id=t.id AND r.username=@loggedInAs) AS retweeted
        FROM phone_twitter_tweets t LEFT JOIN phone_twitter_accounts a ON a.username=t.username
        WHERE t.content LIKE CONCAT("%", @search, "%")
        ORDER BY t.`timestamp` DESC
        LIMIT @page, @perPage]], {
        ["@loggedInAs"] = loggedInAs,
        ["@search"] = search,
        ["@page"] = (page or 0) * 10,
        ["@perPage"] = 10
    }, cb)
end)

RegisterLegacyCallback("birdy:getData", function(source, cb, kind, whereValue, page)
    local loggedInAs = getLoggedInTwitterAccount(source)
    if not loggedInAs then return cb(false) end

    local tbl, colWhere, colUser = "phone_twitter_likes", "tweet_id", "username"
    if kind == "following" or kind == "followers" then
        tbl = "phone_twitter_follows"
        if kind == "following" then
            colWhere = "follower"; colUser = "followed"
        else
            colWhere = "followed"; colUser = "follower"
        end
    elseif kind == "retweeters" then
        tbl = "phone_twitter_retweets"; colWhere = "tweet_id"; colUser = "username"
    end

    local sql = ([[SELECT a.display_name AS `name`, a.username, a.profile_image AS profile_picture, a.bio, a.verified,
        (SELECT CASE WHEN f.followed IS NULL THEN FALSE ELSE TRUE END FROM phone_twitter_follows f WHERE f.follower=@loggedInAs AND a.username=f.followed) AS isFollowing,
        (SELECT CASE WHEN f.follower IS NULL THEN FALSE ELSE TRUE END FROM phone_twitter_follows f WHERE f.follower=a.username AND f.followed=@loggedInAs) AS isFollowingYou
        FROM %s w JOIN phone_twitter_accounts a ON a.username=w.%s WHERE w.%s=@whereValue
        ORDER BY a.username DESC LIMIT @page, @perPage]]):format(tbl, colUser, colWhere)

    MySQL.Async.fetchAll(sql, {
        ["@loggedInAs"] = loggedInAs,
        ["@whereValue"] = whereValue,
        ["@page"] = (page or 0) * 20,
        ["@perPage"] = 20
    }, cb)
end)

RegisterLegacyCallback("birdy:getPost", function(source, cb, tweetId)
    local loggedInAs = getLoggedInTwitterAccount(source)
    if not loggedInAs then return cb(false) end
    cb(GetTweet(tweetId, loggedInAs))
end)

RegisterLegacyCallback("birdy:getAuthor", function(source, cb, tweetId)
    local phoneNumber = GetEquippedPhoneNumber(source)
    if not phoneNumber then return cb(false) end
    local loggedIn = GetLoggedInAccount(phoneNumber, "Twitter")
    if not loggedIn then return cb(false) end

    local author = MySQL.scalar.await("SELECT username FROM phone_twitter_tweets WHERE id = ?", { tweetId })
    if not author then return cb(false) end

    cb(getTwitterProfile(author, phoneNumber))
end)

RegisterLegacyCallback("birdy:getReplies", function(source, cb, tweetId, page)
    local loggedInAs = getLoggedInTwitterAccount(source)
    if not loggedInAs then
        return cb({})
    end

    MySQL.Async.fetchAll([[SELECT t.id, t.username, t.content, t.attachments,
            t.like_count, t.reply_count, t.retweet_count, t.reply_to, t.`timestamp`,
            reply_author.username AS replyToAuthor,
            a.display_name, a.profile_image, a.verified, a.private,
            (l.tweet_id IS NOT NULL) AS liked,
            (r.tweet_id IS NOT NULL) AS retweeted
        FROM phone_twitter_tweets t
        INNER JOIN phone_twitter_accounts a ON a.username=t.username
        LEFT JOIN phone_twitter_tweets reply_author ON t.reply_to=reply_author.id
        LEFT JOIN phone_twitter_likes l ON l.tweet_id=t.id AND l.username=@loggedInAs
        LEFT JOIN phone_twitter_retweets r ON r.tweet_id=t.id AND r.username=@loggedInAs
        WHERE t.reply_to=@tweetId 
            AND (a.private=0 OR a.username=@loggedInAs OR EXISTS(
                SELECT 1 FROM phone_twitter_follows WHERE follower=@loggedInAs AND followed=a.username LIMIT 1
            ))
        ORDER BY t.`timestamp` DESC
        LIMIT @page, @perPage]], {
        ["@tweetId"] = tweetId,
        ["@loggedInAs"] = loggedInAs,
        ["@page"] = (page or 0) * 20,
        ["@perPage"] = 20
    }, function(replies)
        if replies then
            for i, reply in ipairs(replies) do
                if reply.attachments then
                    reply.attachments = json.decode(reply.attachments)
                end
            end
        end
        
        cb(replies or {})
    end)
end)

RegisterLegacyCallback("birdy:getPosts", function(source, cb, filter, page)
    local loggedInAs = getLoggedInTwitterAccount(source)
    if not loggedInAs then return cb({}) end

    filter = filter or {}
    page = page or 0

    local cacheKey = string.format("posts_%s_%s_%s_%s_%d",
        loggedInAs,
        filter.type or "default",
        filter.username or "all",
        filter.tweet_id or "none",
        page
    )

    if filter.type ~= "replyTo" and page == 0 then
        local cached = getCachedPosts(cacheKey)
        if cached then
            return cb(cached)
        end
    end

    local whereUser = ""
    local joinLiked = ""
    local joinFollowing = ""
    local wherePrivacy = "(a.private=0 OR a.username=@loggedInAs OR EXISTS(SELECT 1 FROM phone_twitter_follows WHERE follower=@loggedInAs AND followed=a.username))"
    local extraWhere = ""
    local excludeReplies = " t.reply_to IS NULL AND "
    local includeRetweets = false

    local isViewingOwnProfile = filter.username and filter.username == loggedInAs
    local isViewingProfile = filter.username ~= nil

    if filter.type == "replyTo" and filter.tweet_id then
        extraWhere = " AND t.reply_to=@tweetId"
        excludeReplies = ""
        includeRetweets = false
    elseif filter.type == "liked" then
        joinLiked = "JOIN phone_twitter_likes l ON l.tweet_id=t.id"
        extraWhere = " AND l.username=@username"
        includeRetweets = false
    elseif filter.type == "media" then
        if isViewingProfile then
            whereUser = " AND a.username=@username"
        end
        extraWhere = " AND t.attachments IS NOT NULL AND t.attachments != '[]'"
        includeRetweets = false
    elseif filter.type == "replies" then
        if isViewingProfile then
            whereUser = " AND a.username=@username"
            includeRetweets = true
        end
        excludeReplies = ""
    elseif filter.type == "following" then
        joinFollowing = "INNER JOIN phone_twitter_follows fol ON fol.follower=@loggedInAs AND fol.followed=a.username"
        wherePrivacy = "1=1"
        whereUser = " AND a.username != @loggedInAs"
        includeRetweets = false
    else
        if isViewingProfile then
            whereUser = " AND a.username=@username"
            includeRetweets = true
        else
            includeRetweets = false
        end
    end

    local indexHint = ""
    if filter.type == "following" then
        indexHint = ""
    elseif filter.type == "liked" then
        indexHint = ""
    else
        indexHint = "USE INDEX (idx_tweets_reply_timestamp)"
    end
    
    local base1 = ([[SELECT
            reply_author.username AS replyToAuthor,
            t.id, t.username, t.content, t.attachments, t.like_count, t.reply_count, t.retweet_count, t.reply_to, t.`timestamp`,
            a.display_name, a.profile_image, a.verified, a.private,
            (liked_check.username IS NOT NULL) AS liked,
            (retweet_check.username IS NOT NULL) AS retweeted,
            NULL AS tweet_timestamp, NULL AS retweeted_by_display_name, NULL AS retweeted_by_username
        FROM phone_twitter_tweets t %s
        INNER JOIN phone_twitter_accounts a ON a.username=t.username
        LEFT JOIN phone_twitter_tweets reply_author ON t.reply_to=reply_author.id
        LEFT JOIN phone_twitter_likes liked_check ON liked_check.tweet_id=t.id AND liked_check.username=@loggedInAs
        LEFT JOIN phone_twitter_retweets retweet_check ON retweet_check.tweet_id=t.id AND retweet_check.username=@loggedInAs
        %s
        %s WHERE %s %s %s%s
    ]]):format(indexHint, joinLiked, joinFollowing, excludeReplies, wherePrivacy, whereUser, extraWhere)

    local base2 = ""
    if includeRetweets then
        local whereUserForRetweets = ""
        if isViewingProfile then
            if filter.type == "replies" then
                whereUserForRetweets = " AND (r.username=@username OR t.username=@username)"
            else
                whereUserForRetweets = " AND r.username=@username"
            end
        else
            whereUserForRetweets = whereUser
        end

        base2 = ([[SELECT
                reply_author.username AS replyToAuthor,
                t.id, t.username, t.content, t.attachments, t.like_count, t.reply_count, t.retweet_count, t.reply_to, r.timestamp,
                a.display_name, a.profile_image, a.verified, a.private,
                (liked_check.username IS NOT NULL) AS liked,
                (retweet_check.username IS NOT NULL) AS retweeted,
                t.`timestamp` AS tweet_timestamp,
                retweeter.display_name AS retweeted_by_display_name,
                r.username AS retweeted_by_username
            FROM phone_twitter_tweets t
            INNER JOIN phone_twitter_accounts a ON a.username=t.username
            JOIN phone_twitter_retweets r ON r.tweet_id=t.id
            LEFT JOIN phone_twitter_accounts retweeter ON retweeter.username=r.username
            LEFT JOIN phone_twitter_tweets reply_author ON t.reply_to=reply_author.id
            LEFT JOIN phone_twitter_likes liked_check ON liked_check.tweet_id=t.id AND liked_check.username=@loggedInAs
            LEFT JOIN phone_twitter_retweets retweet_check ON retweet_check.tweet_id=t.id AND retweet_check.username=@loggedInAs
            %s
            WHERE %s %s %s%s
        ]]):format(joinFollowing, excludeReplies, wherePrivacy, whereUserForRetweets, extraWhere)
    end

    local unionSql
    local perPage = (filter.type == "replyTo") and 20 or 15
    local offset = page * perPage
    local limit = perPage
    local orderDirection = "DESC"
    
    if includeRetweets and base2 ~= "" then
        unionSql = ([[(
            %s
        ) UNION ALL (
            %s
        )
        ORDER BY `timestamp` %s
        LIMIT %d OFFSET %d]]):format(base1, base2, orderDirection, limit, offset)
    else
        unionSql = ([[%s
            ORDER BY t.`timestamp` %s
            LIMIT %d OFFSET %d]]):format(base1, orderDirection, limit, offset)
    end

    local params = { ["@loggedInAs"] = loggedInAs }
    if filter.username then params["@username"] = filter.username end
    if filter.tweet_id then params["@tweetId"] = filter.tweet_id end

    MySQL.Async.fetchAll(unionSql, params, function(tweets)
        if not tweets then
            cb({})
            return
        end

        for i, tweet in ipairs(tweets) do
            if tweet.attachments then
                tweet.attachments = json.decode(tweet.attachments)
            end
        end

        if filter.type ~= "replyTo" and page == 0 then
            cachePostData(cacheKey, tweets)
        end

        cb(tweets)
    end)
end)

RegisterLegacyCallback("birdy:toggleInteraction", function(source, cb, kind, tweetId, isActive)
    if kind ~= "like" and kind ~= "retweet" then
        return cb({ success = false, error = "invalid_action" })
    end

    local username = getLoggedInTwitterAccount(source)
    if not username then
        return cb({ success = false, error = "not_logged_in" })
    end

    if kind == "retweet" and isActive then
        local isReply = MySQL.scalar.await("SELECT reply_to FROM phone_twitter_tweets WHERE id = ?", { tweetId })
        if isReply then
            return cb({ success = false, error = "cannot_retweet_reply" })
        end
    end

    local map = {
        like = { table = "phone_twitter_likes", column1 = "username", column2 = "tweet_id" },
        retweet = { table = "phone_twitter_retweets", column1 = "username", column2 = "tweet_id" }
    }
    local info = map[kind]
    local dataField = kind == "like" and "likes" or "retweets"
    local countColumn = kind == "like" and "like_count" or "retweet_count"

    local query = isActive and
        ("INSERT IGNORE INTO %s (%s, %s) VALUES (?, ?)"):format(info.table, info.column1, info.column2) or
        ("DELETE FROM %s WHERE %s = ? AND %s = ?"):format(info.table, info.column1, info.column2)

    local affected = MySQL.update.await(query, { username, tweetId })

    if affected == 0 then
        return cb({ success = true, isActive = isActive })
    end

    local newCount = MySQL.scalar.await(
        ("SELECT COUNT(*) FROM %s WHERE %s = ?"):format(info.table, info.column2),
        { tweetId }
    ) or 0

    MySQL.update.await(
        ("UPDATE phone_twitter_tweets SET %s = ? WHERE id = ?"):format(countColumn),
        { newCount, tweetId }
    )

    cb({
        success = true,
        isActive = isActive,
        count = newCount
    })

    local relevantSources = getActiveTwitterSources()
    broadcastToRelevant("phone:twitter:updateTweetData", {
        tweetId = tweetId,
        field = dataField,
        count = newCount,
        username = username,
        isActive = isActive
    }, relevantSources)

    invalidateTweetCache(tweetId)
    
    if kind == "like" then
        invalidatePostCache("posts_"..username.."_liked")
        invalidatePostCache("posts_.*_all")
    elseif kind == "retweet" then
        invalidatePostCache("posts_.*_"..username)
        invalidatePostCache("posts_.*_all")
    end

    if isActive then
        local owner = MySQL.scalar.await("SELECT username FROM phone_twitter_tweets WHERE id = ?", { tweetId })
        if owner and owner ~= username then
            queueTwitterNotification(owner, username, kind, tweetId)
        end
    end
end, { preventSpam = true, rateLimit = 30 })

RegisterLegacyCallback("birdy:toggleNotifications", function(source, cb, target, enabled)
    local username = getLoggedInTwitterAccount(source)
    if not username then return cb(not enabled) end

    MySQL.Async.execute(
    "UPDATE phone_twitter_follows SET notifications=@enabled WHERE follower=@loggedInAs AND followed=@username ", {
        ["@enabled"] = enabled,
        ["@loggedInAs"] = username,
        ["@username"] = target
    }, function(affected)
        if affected > 0 then cb(enabled) else cb(not enabled) end
    end)
end)

RegisterLegacyCallback("birdy:toggleFollow", function(source, cb, target, enabled)
    local username = getLoggedInTwitterAccount(source)
    if not username or target == username then return cb(not enabled) end

    local context = { ["@loggedInAs"] = username, ["@username"] = target }
    local isPrivate = MySQL.scalar.await("SELECT private FROM phone_twitter_accounts WHERE username=@username",
        context)

    if isPrivate then
        if enabled then
            MySQL.Async.execute(
            "INSERT IGNORE INTO phone_twitter_follow_requests (requester, requestee) VALUES (@loggedInAs, @username)",
                context, function(rows)
                cb(enabled)
                if rows == 0 then return end
                for phone, src in pairs(getPhoneNumberToSourceMap(target)) do
                    SendNotification(phone,
                        { app = "Twitter", content = L("BACKEND.TWITTER.NEW_FOLLOW_REQUEST", { username = username }) })
                end
            end)
            return
        else
            MySQL.Async.execute(
            "DELETE FROM phone_twitter_follow_requests WHERE requester=@loggedInAs AND requestee=@username", context)
        end
    end

    local sql = enabled and
        "INSERT IGNORE INTO phone_twitter_follows (followed, follower) VALUES (@username, @loggedInAs)"
        or "DELETE FROM phone_twitter_follows WHERE followed=@username AND follower=@loggedInAs"

    MySQL.Async.execute(sql, context, function(affected)
        if affected == 0 then return cb(not enabled) end

        local relevantSources = {}

        local targetSources = getSourcesForUsername(target)
        for _, src in ipairs(targetSources) do
            table.insert(relevantSources, src)
        end

        local userSources = getSourcesForUsername(username)
        for _, src in ipairs(userSources) do
            table.insert(relevantSources, src)
        end

        broadcastToRelevant("phone:twitter:updateProfileData", {target, "followers", enabled == true}, relevantSources)
        broadcastToRelevant("phone:twitter:updateProfileData", {username, "following", enabled == true}, relevantSources)

        if enabled then
            queueTwitterNotification(target, username, "follow")
        else
            MySQL.update.await("DELETE FROM phone_twitter_notifications WHERE username = ? AND `from` = ? AND `type` = 'follow'", { target, username })
        end

        invalidateProfileCache(target)
        invalidateProfileCache(username)
        
        invalidatePostCache("posts_"..username.."_following_.*")
        
        invalidatePostCache("posts_.*_.*_"..target.."_.*")

        cb(enabled)
    end)
end, { preventSpam = true, rateLimit = 30 })

RegisterLegacyCallback("birdy:getFollowRequests", function(source, cb, page)
    local username = getLoggedInTwitterAccount(source)
    if not username then return cb({}) end

    MySQL.Async.fetchAll([[SELECT a.username, a.display_name AS `name`, a.profile_image AS profile_picture, a.verified,
            (
                SELECT CASE WHEN f.follower IS NULL THEN FALSE ELSE TRUE END
                    FROM phone_twitter_follows f
                    WHERE f.follower=a.username AND f.followed=@loggedInAs
            ) AS isFollowingYou
        FROM phone_twitter_follow_requests r
        INNER JOIN phone_twitter_accounts a ON a.username=r.requester
        WHERE r.requestee=@loggedInAs
        ORDER BY r.`timestamp` DESC
        LIMIT @page, @perPage]], {
        ["@loggedInAs"] = username,
        ["@page"] = (page or 0) * 15,
        ["@perPage"] = 15
    }, cb)
end)

RegisterLegacyCallback("birdy:handleFollowRequest", function(source, cb, requester, accept)
    local username = getLoggedInTwitterAccount(source)
    if not username then return cb(false) end

    local ctx = { ["@loggedInAs"] = username, ["@username"] = requester }
    local removed = MySQL.update.await(
    "DELETE FROM phone_twitter_follow_requests WHERE requestee=@loggedInAs AND requester=@username", ctx)
    if removed == 0 then return cb(false) end
    if not accept then return cb(true) end

    MySQL.update.await("INSERT IGNORE INTO phone_twitter_follows (follower, followed) VALUES (@username, @loggedInAs)",
        ctx)

    local relevantSources = {}

    local userSources = getSourcesForUsername(username)
    for _, src in ipairs(userSources) do
        table.insert(relevantSources, src)
    end

    local requesterSources = getSourcesForUsername(requester)
    for _, src in ipairs(requesterSources) do
        table.insert(relevantSources, src)
    end

    broadcastToRelevant("phone:twitter:updateProfileData", {username, "followers", true}, relevantSources)
    broadcastToRelevant("phone:twitter:updateProfileData", {requester, "following", true}, relevantSources)
    queueTwitterNotification(username, requester, "follow")

    invalidateProfileCache(username)
    invalidateProfileCache(requester)
    
    invalidatePostCache("posts_"..requester.."_following_.*")
    
    invalidatePostCache("posts_.*_.*_"..username.."_.*")

    for phone, src in pairs(getPhoneNumberToSourceMap(requester)) do
        SendNotification(phone,
            { app = "Twitter", content = L("BACKEND.TWITTER.FOLLOW_REQUEST_ACCEPTED_DESCRIPTION", { username = username }) })
    end

    cb(true)
end)

createAuthenticatedCallback("sendMessage", function(source, _, account, recipient, content, attachments, replyTo)
    if ContainsBlacklistedWord(source, "Birdy", content) then return false end

    local id = GenerateId("phone_twitter_messages", "id")
    local payloadAttachments = attachments and json.encode(attachments) or nil
    
    local query = [[INSERT INTO phone_twitter_messages (id, sender, recipient, content, attachments]]
    local values = [[VALUES (@id, @sender, @recipient, @content, @attachments]]
    local params = {
        ["@id"] = id,
        ["@sender"] = account,
        ["@recipient"] = recipient,
        ["@content"] = content,
        ["@attachments"] = payloadAttachments
    }
    
    if replyTo then
        query = query..[[, reply_to]]
        values = values..[[, @replyTo]]
        params["@replyTo"] = replyTo
    end
    
    query = query..[[) ]]..values..[[)]]
    
    local affected = MySQL.update.await(query, params)
    if affected == 0 then return false end

    local replyContent, replySender = nil, nil
    if replyTo then
        local replyMsg = MySQL.single.await("SELECT content, sender FROM phone_twitter_messages WHERE id = ?", { replyTo })
        if replyMsg then
            replyContent = replyMsg.content
            replySender = replyMsg.sender
        end
    end
    
    local messagePayload = {
        id = id,
        sender = account,
        recipient = recipient,
        content = content,
        attachments = attachments,
        reply_to = replyTo,
        reply_content = replyContent,
        reply_sender = replySender,
        timestamp = os.time() * 1000
    }
    
    for phone, src in pairs(getPhoneNumberToSourceMap(recipient)) do
        if src then
            TriggerClientEvent("phone:twitter:newMessage", src, messagePayload)
        end
    end
    
    for phone, src in pairs(getPhoneNumberToSourceMap(account)) do
        if src then
            TriggerClientEvent("phone:twitter:newMessage", src, messagePayload)
        end
    end

    local senderProfile = getTwitterProfile(account) or {}
    for phone, src in pairs(getPhoneNumberToSourceMap(recipient)) do
        SendNotification(phone, {
            source = src,
            app = "Twitter",
            title = senderProfile.name,
            content = content,
            thumbnail = attachments and attachments[1] or nil,
            avatar = senderProfile.profile_picture,
            showAvatar = true
        })
    end

    return true
end, nil, { preventSpam = true, rateLimit = 15 })

RegisterLegacyCallback("birdy:getMessages", function(source, cb, username, page)
    local loggedInAs = getLoggedInTwitterAccount(source)
    if not loggedInAs then return cb({}) end

    MySQL.Async.fetchAll([[SELECT m.id, m.sender, m.recipient, m.content, m.attachments, m.reply_to, m.`timestamp`,
        rm.content AS reply_content, rm.sender AS reply_sender
        FROM phone_twitter_messages m
        LEFT JOIN phone_twitter_messages rm ON m.reply_to = rm.id
        WHERE (m.sender=@loggedInAs AND m.recipient=@username) OR (m.sender=@username AND m.recipient=@loggedInAs)
        ORDER BY m.`timestamp` DESC
        LIMIT @page, @perPage]], {
        ["@loggedInAs"] = loggedInAs,
        ["@username"] = username,
        ["@page"] = (page or 0) * 25,
        ["@perPage"] = 25
    }, cb)
end)

RegisterLegacyCallback("birdy:getRecentMessages", function(source, cb, page)
    local loggedInAs = getLoggedInTwitterAccount(source)
    if not loggedInAs then return cb({}) end

    MySQL.Async.fetchAll([[SELECT
            m.content, m.attachments, m.sender, f_m.username, m.`timestamp`,
            a.display_name AS `name`, a.profile_image AS profile_picture, a.verified
        FROM phone_twitter_messages m
        JOIN ((
            SELECT (CASE WHEN recipient!=@loggedInAs THEN recipient ELSE sender END) AS username, MAX(`timestamp`) AS `timestamp`
            FROM phone_twitter_messages
            WHERE sender=@loggedInAs OR recipient=@loggedInAs
            GROUP BY username
        ) f_m) ON m.`timestamp`=f_m.`timestamp`
        INNER JOIN phone_twitter_accounts a ON a.username=f_m.username
        WHERE m.sender=@loggedInAs OR m.recipient=@loggedInAs
        GROUP BY f_m.username
        ORDER BY m.`timestamp` DESC
        LIMIT @page, @perPage]], {
        ["@loggedInAs"] = loggedInAs,
        ["@page"] = (page or 0) * 15,
        ["@perPage"] = 15
    }, cb)
end)

RegisterLegacyCallback("birdy:deleteMessage", function(source, cb, messageId)
    local account = getLoggedInTwitterAccount(source)
    if not account then
        return cb({ success = false, error = "not_logged_in" })
    end


    if not messageId then
        return cb({ success = false, error = "no_id" })
    end

    local messageData = MySQL.Sync.fetchAll(
        "SELECT sender, recipient FROM phone_twitter_messages WHERE id = ? AND sender = ?",
        { messageId, account }
    )

    if not messageData or #messageData == 0 then
        return cb({ success = false, error = "not_found" })
    end

    local sender = messageData[1].sender
    local recipient = messageData[1].recipient

    MySQL.Async.execute(
        "DELETE FROM phone_twitter_messages WHERE id = ?",
        { messageId },
        function(affectedRows)
            if affectedRows > 0 then
                cb({ success = true })

                local deleteData = {
                    messageId = messageId,
                    sender = sender,
                    recipient = recipient
                }

                for phone, src in pairs(getPhoneNumberToSourceMap(sender)) do
                    if src then
                        TriggerClientEvent("phone:twitter:messageDeleted", src, deleteData)
                    end
                end

                for phone, src in pairs(getPhoneNumberToSourceMap(recipient)) do
                    if src then
                        TriggerClientEvent("phone:twitter:messageDeleted", src, deleteData)
                    end
                end
            else
                cb({ success = false, error = "failed" })
            end
        end
    )
end)

createAuthenticatedCallback("sendCommentMessage", function(source, _, account, recipient, content, attachments, tweetId)
    if ContainsBlacklistedWord(source, "Birdy", content) then return false end

    local tweetAuthor = MySQL.scalar.await("SELECT username FROM phone_twitter_tweets WHERE id = ?", { tweetId })
    if not tweetAuthor then return false end

    local commentId = GenerateId("phone_twitter_tweets", "id")
    local payloadAttachments = attachments and json.encode(attachments) or nil

    local affected = MySQL.update.await(
    [[INSERT INTO phone_twitter_tweets (id, username, content, attachments, reply_to)
        VALUES (@id, @sender, @content, @attachments, @tweetId)]], {
        ["@id"] = commentId,
        ["@sender"] = account,
        ["@content"] = content,
        ["@attachments"] = payloadAttachments,
        ["@tweetId"] = tweetId
    })
    if affected == 0 then return false end

    MySQL.update.await("UPDATE phone_twitter_tweets SET reply_count = reply_count + 1 WHERE id = ?", { tweetId })

    local profile = MySQL.single.await(
        "SELECT display_name, profile_image, verified FROM phone_twitter_accounts WHERE username = ?", { account }) or
        { display_name = account }

    local payload = {
        id = commentId,
        username = account,
        content = content,
        attachments = attachments,
        like_count = 0,
        reply_count = 0,
        retweet_count = 0,
        reply_to = tweetId,
        timestamp = os.time() * 1000,
        liked = false,
        retweeted = false,
        display_name = profile.display_name,
        profile_image = profile.profile_image,
        verified = profile.verified,
        replyToAuthor = tweetAuthor
    }

    local relevantSources = getActiveTwitterSources()
    broadcastToRelevant("phone:twitter:newComment", {payload, tweetId}, relevantSources)

    local tweetData = MySQL.single.await([[
        WITH RECURSIVE thread_hierarchy AS (
            SELECT id, username, reply_to, 0 as depth
            FROM phone_twitter_tweets
            WHERE id = ?

            UNION ALL

            SELECT t.id, t.username, t.reply_to, th.depth + 1
            FROM phone_twitter_tweets t
            INNER JOIN thread_hierarchy th ON t.id = th.reply_to
            WHERE th.depth < 10
        )
        SELECT id, username FROM thread_hierarchy ORDER BY depth DESC LIMIT 1
    ]], { tweetId })

    local originalTweetId = tweetData and tweetData.id or tweetId

    local threadParticipants = ThreadCache[originalTweetId]

    if not threadParticipants or (GetGameTimer() - threadParticipants.timestamp) > 60000 then
        local participants = MySQL.query.await([[
            SELECT DISTINCT username FROM (
                SELECT username FROM phone_twitter_likes WHERE tweet_id = ?
                UNION
                SELECT username FROM phone_twitter_tweets WHERE reply_to = ?
                UNION
                SELECT username FROM phone_twitter_tweets
                WHERE reply_to IN (SELECT id FROM phone_twitter_tweets WHERE reply_to = ?)
            ) as all_participants
        ]], { originalTweetId, originalTweetId, originalTweetId }) or {}

        threadParticipants = {}
        for i = 1, #participants do
            threadParticipants[participants[i].username] = true
        end

        ThreadCache[originalTweetId] = {
            participants = threadParticipants,
            timestamp = GetGameTimer()
        }
    else
        threadParticipants = threadParticipants.participants
    end

    local notifiedUsers = {}

    if account ~= tweetAuthor then
        local senderProfile = getTwitterProfile(account) or {}
        for phone, src in pairs(getPhoneNumberToSourceMap(tweetAuthor)) do
            SendNotification(phone, {
                source = src,
                app = "Twitter",
                title = senderProfile.name.." commented on your tweet",
                content = content,
                thumbnail = attachments and attachments[1] or nil,
                avatar = senderProfile.profile_picture,
                showAvatar = true
            })
        end
        notifiedUsers[tweetAuthor] = true
    end

    local senderProfile = getTwitterProfile(account) or {}
    for participant, _ in pairs(threadParticipants) do
        if participant ~= account and not notifiedUsers[participant] then
            for phone, src in pairs(getPhoneNumberToSourceMap(participant)) do
                SendNotification(phone, {
                    source = src,
                    app = "Twitter",
                    title = senderProfile.name.." commented on a thread you're in",
                    content = content,
                    thumbnail = attachments and attachments[1] or nil,
                    avatar = senderProfile.profile_picture,
                    showAvatar = true
                })
            end
            notifiedUsers[participant] = true
        end
    end

    if content then
        local mentions = {}
        for mentionedUser in string.gmatch(content, "@(%w+)") do
            mentionedUser = mentionedUser:lower()
            if mentionedUser ~= account and not notifiedUsers[mentionedUser] then
                table.insert(mentions, mentionedUser)
            end
        end

        if #mentions > 0 then
            local placeholders = string.rep("?,", #mentions):sub(1, -2)
            local existingUsers = MySQL.query.await(
                "SELECT username FROM phone_twitter_accounts WHERE username IN ("..placeholders..")",
                mentions
            ) or {}

            for _, user in ipairs(existingUsers) do
                if not notifiedUsers[user.username] then
                    for phone, src in pairs(getPhoneNumberToSourceMap(user.username)) do
                        SendNotification(phone, {
                            source = src,
                            app = "Twitter",
                            title = senderProfile.name.." mentioned you",
                            content = content,
                            thumbnail = attachments and attachments[1] or nil,
                            avatar = senderProfile.profile_picture,
                            showAvatar = true
                        })
                    end
                    notifiedUsers[mentionedUser] = true
                end
            end
        end
    end

    return true
end, nil, { preventSpam = true, rateLimit = 15 })

RegisterLegacyCallback("birdy:getTweetMessages", function(source, cb, tweetId, page)
    local loggedInAs = getLoggedInTwitterAccount(source)
    if not loggedInAs then return cb({}) end

    local tweetExists = MySQL.scalar.await("SELECT id FROM phone_twitter_tweets WHERE id = ?", { tweetId })
    if not tweetExists then return cb({}) end

    MySQL.Async.fetchAll([[SELECT t.id, t.username, t.content, t.attachments, t.`timestamp`,
        a.display_name, a.profile_image, a.verified
        FROM phone_twitter_tweets t
        INNER JOIN phone_twitter_accounts a ON a.username = t.username
        WHERE t.reply_to=@tweetId
        ORDER BY t.`timestamp` ASC
        LIMIT @page, @perPage]], {
        ["@tweetId"] = tweetId,
        ["@page"] = (page or 0) * 25,
        ["@perPage"] = 25
    }, cb)
end)

RegisterLegacyCallback("birdy:getTweetCommentCount", function(source, cb, tweetId)
    local loggedInAs = getLoggedInTwitterAccount(source)
    if not loggedInAs then return cb(0) end

    local tweetExists = MySQL.scalar.await("SELECT id FROM phone_twitter_tweets WHERE id = ?", { tweetId })
    if not tweetExists then return cb(0) end

    local count = MySQL.scalar.await("SELECT COUNT(*) FROM phone_twitter_tweets WHERE reply_to = ?", { tweetId })
    cb(count or 0)
end)

CreateThread(function()
    if not (Config.BirdyTrending and Config.BirdyTrending.Enabled) then return end

    while not DatabaseCheckerFinished do
        Wait(500)
    end

    while true do
        local resetHours = (Config.BirdyTrending and Config.BirdyTrending.Reset) or 24
        local totalDeleted = 0
        
        repeat
            local deleted = MySQL.update.await(
                "DELETE FROM phone_twitter_hashtags WHERE last_used < DATE_SUB(NOW(), INTERVAL ? HOUR) LIMIT 100",
                { resetHours }
            )
            totalDeleted = totalDeleted + deleted
            
            if deleted > 0 then
                Wait(100)
            end
        until deleted == 0
        
        Wait(21600000)
    end
end)
