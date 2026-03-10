
local lives = {}
local calls = {}


local function BroadcastUpdateLives()

    local players = GetPlayers()
    local count = 0
    
    for i = 1, #players do
        local src = tonumber(players[i])
        if src then

            local phone = GetEquippedPhoneNumber(src)
            if phone then
                TriggerClientEvent("phone:instagram:updateLives", src, lives)
                count = count + 1
            end
        end
    end
    

    if count == 0 then
        TriggerClientEvent("phone:instagram:updateLives", -1, lives)
    end
end






local ProfileCache = {}
local CACHE_TTL = 300000

local function clearExpiredCache()
    local now = GetGameTimer()
    if ProfileCache then
        for key, cache in pairs(ProfileCache) do
            if cache and (now - cache.timestamp) > CACHE_TTL then
                ProfileCache[key] = nil
            end
        end
    end
end


CreateThread(function()
    while true do
        Wait(300000)
        clearExpiredCache()
    end
end)


local function getPhoneNumberToSourceMap(username)
    local map = {}
    local rows = MySQL.query.await(
        "SELECT phone_number FROM phone_logged_in_accounts WHERE username = ? AND app = 'Instagram' AND `active` = 1",
        { username }
    )
    for i = 1, (rows and #rows or 0) do
        local phoneNumber = rows[i].phone_number
        local src = GetSourceFromNumber(phoneNumber)
        if src then
            map[phoneNumber] = src
        end
    end
    return map
end


local function getLoggedInInstagramAccount(source)
    local phone = GetEquippedPhoneNumber(source)
    if not phone then return false end
    return GetLoggedInAccount(phone, "Instagram")
end

local function createAuthenticatedInstagramCallback(name, handler, defaultReturn, options)
    BaseCallback("instagram:" .. name, function(source, phoneNumber, ...)
        local account = GetLoggedInAccount(phoneNumber, "Instagram")
        if not account then
            return defaultReturn
        end
        return handler(source, phoneNumber, account, ...)
    end, defaultReturn, options)
end


local function CanGoLive(source, username)

    if lives[username] then
        return false, L("BACKEND.INSTAGRAM.ALREADY_LIVE")
    end
    


    
    return true
end

local function CanCreateStory(source, username)

    local hasStory = MySQL.scalar.await("SELECT TRUE FROM phone_instagram_stories WHERE username = @username AND timestamp > DATE_SUB(NOW(), INTERVAL 24 HOUR)", { 
        ["@username"] = username
    })
    if hasStory then
        return false, L("BACKEND.INSTAGRAM.ALREADY_HAS_STORY")
    end
    
    return true
end

local function EndLive(username, endedBy)
    local live = lives[username]
    if not live then return end
    

    lives[username] = nil
    

    for i = 1, #live.participants do
        local participant = live.participants[i]
        if lives[participant.username] then
            lives[participant.username] = nil
            if participant.source then
                Player(participant.source).state.instapicIsLive = nil
            end
        end
    end
    

    BroadcastUpdateLives()
    TriggerClientEvent("phone:instagram:endLive", -1, username, endedBy)
end

local function getActiveNumbersByUsername(username)
    local numbers = {}
    local rows = MySQL.query.await("SELECT phone_number FROM phone_logged_in_accounts WHERE app = 'Instagram' AND `active` = 1 AND username = ?", {username})
    for i = 1, #rows do
        numbers[i] = rows[i].phone_number
    end
    return numbers
end

local function notifyInstagramDevices(username, notification, excludePhoneNumber)
    notification.app = "Instagram"
    local numbers = getActiveNumbersByUsername(username)
    for i = 1, #numbers do
        if numbers[i] ~= excludePhoneNumber then
            SendNotification(numbers[i], notification)
        end
    end
end


local function getInstagramProfile(username, loggedInPhone)
    username = username:lower()
    local acc = MySQL.single.await([[SELECT display_name, bio, profile_image, verified, private,
        follower_count, following_count, date_joined FROM phone_instagram_accounts WHERE username = ?]], {username})
    if not acc then return false end

    local result = {
        name = acc.display_name,
        username = username,
        bio = acc.bio,
        verified = acc.verified == true,
        private = acc.private == true,
        profile_picture = acc.profile_image,
        followers = acc.follower_count or 0,
        following = acc.following_count or 0,
        date_joined = acc.date_joined
    }

    local loggedInAs = nil
    if loggedInPhone then
        loggedInAs = GetLoggedInAccount(loggedInPhone, "Instagram")
    end
    
    if loggedInAs then
        result.isFollowing = MySQL.scalar.await("SELECT TRUE FROM phone_instagram_follows WHERE follower=@f AND followed=@u", { ["@f"] = loggedInAs, ["@u"] = username }) ~= nil
        result.isFollowingYou = MySQL.scalar.await("SELECT TRUE FROM phone_instagram_follows WHERE follower=@u AND followed=@f", { ["@u"] = username, ["@f"] = loggedInAs }) ~= nil
        result.requested = MySQL.scalar.await("SELECT TRUE FROM phone_instagram_follow_requests WHERE requester=@f AND requestee=@u", { ["@f"] = loggedInAs, ["@u"] = username }) ~= nil
    end


    result.storyViews = MySQL.scalar.await([[SELECT COUNT(*) FROM phone_instagram_stories_views WHERE viewer = ? AND story_id IN (SELECT id FROM phone_instagram_stories WHERE username=?)]], { loggedInAs, username }) or 0

    return result
end


RegisterLegacyCallback("instagram:createAccount", function(source, cb, displayName, username, password)
    local phone = GetEquippedPhoneNumber(source)
    if not phone then return cb({ success = false, error = "UNKNOWN" }) end

    username = username:lower()
    if not IsUsernameValid(username) then
        return cb({ success = false, error = "USERNAME_NOT_ALLOWED" })
    end

    debugprint("INSTAGRAM", "%s wants to create an account", phone)
    

    local exists = MySQL.scalar.await("SELECT username FROM phone_instagram_accounts WHERE username = ?", { username })
    if exists then
        debugprint("INSTAGRAM", "%s tried to create an account with an existing username", phone)
        return cb({ success = false, error = "USERNAME_TAKEN" })
    end

    MySQL.insert.await("INSERT INTO phone_instagram_accounts (display_name, username, password, phone_number) VALUES (?, ?, ?, ?)", {
        displayName,
        username,
        GetPasswordHash(password),
        phone,
    })

    debugprint("INSTAGRAM", "%s created an account", phone)
    AddLoggedInAccount(phone, "Instagram", username)
    cb({ success = true })

    if Config.AutoFollow and Config.AutoFollow.Enabled and Config.AutoFollow.InstaPic and Config.AutoFollow.InstaPic.Accounts then
        for i = 1, #Config.AutoFollow.InstaPic.Accounts do
            MySQL.update.await("INSERT INTO phone_instagram_follows (followed, follower) VALUES (?, ?)", { Config.AutoFollow.InstaPic.Accounts[i], username })
        end
    end
end, { preventSpam = true, rateLimit = 4 })

RegisterLegacyCallback("instagram:logIn", function(source, cb, username, password)
    local phone = GetEquippedPhoneNumber(source)
    if not phone then return cb({ success = false, error = "UNKNOWN" }) end

    debugprint("INSTAGRAM", "%s wants to log in on account %s", phone, username)
    debugprint("INSTAGRAM", "%s is not logged in, checking if account exists", phone)
    
    username = username:lower()
    MySQL.Async.fetchScalar("SELECT password FROM phone_instagram_accounts WHERE username=@username", { ["@username"] = username }, function(hashed)
        if not hashed then
            debugprint("INSTAGRAM", "%s tried to log in on non-existing account %s", phone, username)
            return cb({ success = false, error = "UNKNOWN_ACCOUNT" })
        end
        
        if not VerifyPasswordHash(password, hashed) then
            debugprint("INSTAGRAM", "%s tried to log in on account %s with wrong password", phone, username)
            return cb({ success = false, error = "INCORRECT_PASSWORD" })
        end
        
        debugprint("INSTAGRAM", "%s logged in on account %s", phone, username)
        AddLoggedInAccount(phone, "Instagram", username)
        
        MySQL.Async.fetchAll([[
            SELECT
                display_name AS name, username, profile_image AS avatar, verified
            FROM phone_instagram_accounts
            WHERE username = @username
        ]], { ["@username"] = username }, function(rows)
            debugprint("INSTAGRAM", "%s got account data", phone)
            cb({ success = true, account = rows and rows[1] })
        end)
    end)
end)

RegisterLegacyCallback("instagram:isLoggedIn", function(source, cb)
    local phone = GetEquippedPhoneNumber(source)
    if not phone then return cb(false) end

    local username = GetLoggedInAccount(phone, "Instagram")
    

    if username then
        local accountExists = MySQL.scalar.await(
            "SELECT TRUE FROM phone_instagram_accounts WHERE username = ?",
            { username }
        )
        if not accountExists then
            RemoveLoggedInAccount(phone, "Instagram", username)
            username = nil
        end
    end
    

    if not username then

        local existingUsername = MySQL.scalar.await(
            "SELECT username FROM phone_instagram_accounts WHERE phone_number = ?",
            { phone }
        )
        
        if existingUsername then

            AddLoggedInAccount(phone, "Instagram", existingUsername)
            username = existingUsername
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


            username = characterName:gsub("%s+", ""):sub(1, 8):lower()
            

            local baseUsername = username
            local counter = 1
            while MySQL.scalar.await("SELECT TRUE FROM phone_instagram_accounts WHERE username = ?", { username }) do
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

            MySQL.insert.await(
                "INSERT INTO phone_instagram_accounts (display_name, username, password, phone_number) VALUES (?, ?, ?, ?)",
                { displayName, username, GetPasswordHash(password), phone }
            )


            AddLoggedInAccount(phone, "Instagram", username)


            if Config.AutoFollow and Config.AutoFollow.Enabled and Config.AutoFollow.InstaPic and Config.AutoFollow.InstaPic.Accounts then
                for i = 1, #Config.AutoFollow.InstaPic.Accounts do
                    MySQL.update.await("INSERT INTO phone_instagram_follows (followed, follower) VALUES (?, ?)", {
                        Config.AutoFollow.InstaPic.Accounts[i],
                        username
                    })
                end
            end
        end
    end


    local account = MySQL.single.await([[
        SELECT display_name AS `name`, username, profile_image AS avatar, verified
        FROM phone_instagram_accounts
        WHERE username = ?
    ]], { username })
    
    if not account then return cb(false) end  
    
    cb(account)
end)

RegisterLegacyCallback("instagram:signOut", function(source, cb)


    cb(false)
end)

RegisterLegacyCallback("instagram:getProfile", function(source, cb, target)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb(false) end
    
    MySQL.Async.fetchAll([[
        SELECT display_name AS name, username, profile_image AS avatar, bio, verified, private, follower_count as followers, following_count as following, post_count as posts,
            (
                IF((SELECT TRUE FROM phone_instagram_follows f WHERE f.followed=@username AND f.follower=@loggedInAs), TRUE, FALSE)
            ) AS isFollowing,
            (
                IF((SELECT TRUE FROM phone_instagram_follow_requests fr WHERE fr.requester=@loggedInAs AND fr.requestee=@username), TRUE, FALSE)
            ) AS requested,

            (SELECT a.story_count > 0) AS hasStory,
            (SELECT a.story_count = (
                SELECT COUNT(*) FROM phone_instagram_stories_views
                WHERE viewer=@loggedInAs
                    AND story_id IN (SELECT id FROM phone_instagram_stories WHERE username=@username)
            )) AS seenStory

        FROM phone_instagram_accounts a

        WHERE a.username=@username
    ]], {
        ["@username"] = target,
        ["@loggedInAs"] = me
    }, function(rows)
        local account = rows and rows[1]
        if account then
            account.isLive = lives[target] and true or false
        end
        cb(account or false)
    end)
end)


createAuthenticatedInstagramCallback("changePassword", function(source, phoneNumber, account, oldPassword, newPassword)
    if not (Config.ChangePassword and Config.ChangePassword.InstaPic) then
        infoprint("warning", ("%s tried to change password on InstaPic, but it's not enabled in the config."):format(source))
        return false
    end
    
    if oldPassword == newPassword or #tostring(newPassword) < 3 then
        debugprint("same password / too short")
        return false
    end
    
    if lives[account] then
        debugprint("Can't change password when live")
        return false
    end
    
    local current = MySQL.scalar.await("SELECT password FROM phone_instagram_accounts WHERE username = ?", { account })
    if not current or not VerifyPasswordHash(oldPassword, current) then return false end
    
    local ok = MySQL.update.await("UPDATE phone_instagram_accounts SET password = ? WHERE username = ?", { GetPasswordHash(newPassword), account }) > 0
    if not ok then return false end

    notifyInstagramDevices(account, { 
        title = L("BACKEND.MISC.LOGGED_OUT_PASSWORD.TITLE"), 
        content = L("BACKEND.MISC.LOGGED_OUT_PASSWORD.DESCRIPTION") 
    }, phoneNumber)
    
    MySQL.update.await("DELETE FROM phone_logged_in_accounts WHERE username = ? AND app = 'Instagram' AND phone_number != ?", { account, phoneNumber })
    ClearActiveAccountsCache("Instagram", account, phoneNumber)
    
    Log("InstaPic", source, "info", L("BACKEND.LOGS.CHANGED_PASSWORD.TITLE"), L("BACKEND.LOGS.CHANGED_PASSWORD.DESCRIPTION", { 
        number = phoneNumber, 
        username = account, 
        app = "InstaPic" 
    }))
    

    for phone, src in pairs(getPhoneNumberToSourceMap(account)) do
        if src then
            TriggerClientEvent("phone:logoutFromApp", src, { 
                username = account, 
                app = "instagram", 
                reason = "password", 
                number = phoneNumber 
            })
        end
    end
    return true
end, false)

createAuthenticatedInstagramCallback("deleteAccount", function(source, phoneNumber, account, password)
    if not (Config.DeleteAccount and Config.DeleteAccount.InstaPic) then
        infoprint("warning", ("%s tried to delete their account on InstaPic, but it's not enabled in the config."):format(source))
        return false
    end
    
    if lives[account] then
        debugprint("Can't delete account when live")
        return false
    end
    
    local current = MySQL.scalar.await("SELECT password FROM phone_instagram_accounts WHERE username = ?", { account })
    if not current or not VerifyPasswordHash(password, current) then return false end
    
    local ok = MySQL.update.await("DELETE FROM phone_instagram_accounts WHERE username = ?", { account }) > 0
    if not ok then return false end

    notifyInstagramDevices(account, { 
        title = L("BACKEND.MISC.DELETED_NOTIFICATION.TITLE"), 
        content = L("BACKEND.MISC.DELETED_NOTIFICATION.DESCRIPTION") 
    })
    
    MySQL.update.await("DELETE FROM phone_logged_in_accounts WHERE username = ? AND app = 'Instagram'", { account })
    ClearActiveAccountsCache("Instagram", account)
    
    Log("InstaPic", source, "info", L("BACKEND.LOGS.DELETED_ACCOUNT.TITLE"), L("BACKEND.LOGS.DELETED_ACCOUNT.DESCRIPTION", { 
        number = phoneNumber, 
        username = account, 
        app = "InstaPic" 
    }))
    

    for phone, src in pairs(getPhoneNumberToSourceMap(account)) do
        if src then
            TriggerClientEvent("phone:logoutFromApp", src, { 
                username = account, 
                app = "instagram", 
                reason = "deleted" 
            })
        end
    end
    return true
end, false)


local function sendInstagramNotification(toUser, fromUser, notifType, postId)
    if toUser == fromUser then return end
    

    CreateThread(function()

        local base = "SELECT TRUE FROM phone_instagram_notifications WHERE username = ? AND `from` = ? AND `type` = ?"
        local dedupParams = { toUser, fromUser, notifType }
        

        if notifType ~= "follow" and notifType ~= "started_live" then 
            base = base .. " AND post_id = ?"
            table.insert(dedupParams, postId)
        end
        
        local exists = MySQL.scalar.await(base, dedupParams)
        if exists then return end


        MySQL.insert.await("INSERT INTO phone_instagram_notifications (id, username, `from`, `type`, post_id) VALUES (?, ?, ?, ?, ?)", {
            GenerateId("phone_instagram_notifications", "id"),
            toUser,
            fromUser,
            notifType,
            postId
        })


        local thumb = nil
        if postId then
            thumb = MySQL.scalar.await("SELECT TRIM(BOTH '\"' FROM JSON_EXTRACT(media, '$[0]')) FROM phone_instagram_posts WHERE id = ?", { postId })
        end
        
        notifyInstagramDevices(toUser, { title = L("BACKEND.INSTAGRAM." .. notifType:upper(), { username = fromUser }), thumbnail = thumb })
    end)
end

createAuthenticatedInstagramCallback("createPost", function(source, phoneNumber, account, mediaJson, caption, location)
    if ContainsBlacklistedWord(source, "InstaPic", caption or "") then return false end
    local id = GenerateId("phone_instagram_posts", "id")

    MySQL.insert.await("INSERT INTO phone_instagram_posts (id, username, media, caption, location) VALUES (?, ?, ?, ?, ?)", {
        id, 
        account, 
        mediaJson, 
        caption, 
        location
    })


    local postData = {
        username = account,
        media = mediaJson,
        caption = caption,
        location = location,
        id = id
    }

    TriggerEvent("lb-phone:instapic:newPost", postData)

    local followers = MySQL.query.await("SELECT follower FROM phone_instagram_follows WHERE followed = ?", { account })
    if followers then
        for i = 1, #followers do
            sendInstagramNotification(followers[i].follower, account, "new_post", id)
        end
    end

    local mediaArray = json.decode(mediaJson) or {}
    local logMessage = "**Caption**: " .. (caption or "") .. "\n\n**Photos**:\n"
    for i = 1, #mediaArray do
        logMessage = logMessage .. string.format("[Photo %s](%s)\n", i, mediaArray[i])
    end
    logMessage = logMessage .. "**ID:** " .. id

    Log("InstaPic", source, "info", "New post", logMessage)
    TrackSocialMediaPost("instapic", mediaArray)

    if Config.Post and Config.Post.InstaPic and INSTAPIC_WEBHOOK and INSTAPIC_WEBHOOK:find("/api/webhooks/") then
        local avatar = MySQL.scalar.await("SELECT profile_image FROM phone_instagram_accounts WHERE username = ?", { account })
        local mediaUrl = mediaArray[1]
        local isVideo = mediaUrl and string.find(mediaUrl:lower(), "%.mp4")
        local isImage = mediaUrl and (string.find(mediaUrl:lower(), "%.webp") or string.find(mediaUrl:lower(), "%.png") or string.find(mediaUrl:lower(), "%.jpg"))

        local payload = {
            username = Config.Post.Accounts.InstaPic.Username or "InstaPic",
            avatar_url = Config.Post.Accounts.InstaPic.Avatar or "https://loaf-scripts.com/fivem/lb-phone/icons/InstaPic.png",
            embeds = {{
                title = 'Bài đăng mới',
                description = caption and #caption > 0 and caption or nil,
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

        PerformHttpRequest(INSTAPIC_WEBHOOK, function() end, "POST", json.encode(payload), { ["Content-Type"] = "application/json" })
    end

    return true
end, nil, { preventSpam = true, rateLimit = 6 })

RegisterLegacyCallback("instagram:deletePost", function(source, cb, id)
    local username = getLoggedInInstagramAccount(source)
    if not username then return cb(false) end

    local isAdmin = IsAdmin and IsAdmin(source)
    local owns = MySQL.scalar.await("SELECT TRUE FROM phone_instagram_posts WHERE id = ? AND username = ?", { id, username })
    if not (owns or isAdmin) then return cb(false) end


    local success = MySQL.transaction.await({
        { query = "DELETE FROM phone_instagram_likes WHERE id = ?", values = { id } },
        { query = "DELETE FROM phone_instagram_notifications WHERE post_id = ?", values = { id } },
        { query = "DELETE FROM phone_instagram_comments WHERE post_id = ?", values = { id } },
        { query = "DELETE FROM phone_instagram_posts WHERE id = ?", values = { id } }
    })
    
    if success then
        Log("InstaPic", source, "error", "Deleted post", "**ID**: " .. id)

        TriggerClientEvent("phone:instagram:postDeleted", -1, id)
        cb(true)
    else
        cb(false)
    end
end)

RegisterLegacyCallback("instagram:getPost", function(source, cb, id)
    local loggedInAs = getLoggedInInstagramAccount(source)
    if not loggedInAs then return cb(false) end

    MySQL.Async.fetchAll([[
        SELECT
            p.id, p.media, p.caption, p.username, p.timestamp, p.like_count, p.comment_count, p.location,

            a.verified, a.profile_image AS avatar,

            (IF((
                SELECT TRUE FROM phone_instagram_likes l
                WHERE l.id=p.id AND l.username=@loggedInAs AND l.is_comment=FALSE
            ), TRUE, FALSE)) AS liked

        FROM phone_instagram_posts p

        INNER JOIN phone_instagram_accounts a
            ON p.username = a.username

        WHERE p.id=@id
    ]], {
        ["@id"] = id,
        ["@loggedInAs"] = loggedInAs
    }, function(rows)
        local row = rows and rows[1]
    if not row then return cb(false) end
    cb(row)
    end)
end)

RegisterLegacyCallback("instagram:getPosts", function(source, cb, filters, page)
    local loggedInAs = getLoggedInInstagramAccount(source)
    if not loggedInAs then return cb({}) end
    filters = filters or {}

    local whereClause = ""
    local orderClause = "p.timestamp DESC"
    
    if filters.following then
        whereClause = [[
            JOIN phone_instagram_follows f
            WHERE f.follower=@loggedInAs
                AND f.followed=p.username
        ]]
    elseif filters.profile then
        whereClause = "WHERE p.username=@username"
    else
        whereClause = [[
            WHERE a.private=FALSE
        ]]
    end

    local sql = ([[
        SELECT
            p.id, p.media, p.caption, p.username, p.timestamp, p.like_count, p.comment_count, p.location,

            a.verified, a.profile_image AS avatar,

            (IF((
                SELECT TRUE FROM phone_instagram_likes l
                WHERE l.id=p.id AND l.username=@loggedInAs AND l.is_comment=FALSE
            ), TRUE, FALSE)) AS liked

        FROM phone_instagram_posts p

        INNER JOIN phone_instagram_accounts a
            ON p.username = a.username

        %s

        ORDER BY %s

        LIMIT @page, @perPage
    ]]):format(whereClause, orderClause)

    MySQL.Async.fetchAll(sql, {
        ["@loggedInAs"] = loggedInAs,
        ["@username"] = filters.username,
        ["@page"] = (page or 0) * 15,
        ["@perPage"] = 15
    }, cb)
end)


RegisterLegacyCallback("instagram:getComments", function(source, cb, postId, page)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb({}) end
    MySQL.Async.fetchAll([[
        SELECT
            c.id, c.comment, c.`timestamp`, c.like_count,
            a.username, a.profile_image, a.verified,

            (IF((
                SELECT TRUE FROM phone_instagram_likes l
                WHERE l.id=c.id AND l.username=@loggedInAs AND l.is_comment=TRUE
            ), TRUE, FALSE)) AS liked,

            (IF((
                SELECT TRUE FROM phone_instagram_follows f
                WHERE f.follower=@loggedInAs AND f.followed=a.username
            ), TRUE, FALSE)) AS following

        FROM phone_instagram_comments c

        INNER JOIN phone_instagram_accounts a
            ON c.username = a.username

        WHERE c.post_id=@postId

        ORDER BY following DESC, c.like_count DESC, c.`timestamp` DESC

        LIMIT @page, @perPage
    ]], {
        ["@loggedInAs"] = me, 
        ["@postId"] = postId, 
        ["@page"] = (page or 0) * 25, 
        ["@perPage"] = 25
    }, cb)
end)

RegisterLegacyCallback("instagram:postComment", function(source, cb, postId, content)
    local account = getLoggedInInstagramAccount(source)
    if not account then return cb(false) end

    if ContainsBlacklistedWord(source, "InstaPic", content or "") then return cb(false) end


    if not content or content == "" or not postId then
        return cb(false)
    end

    local postExists = MySQL.scalar.await("SELECT TRUE FROM phone_instagram_posts WHERE id = ?", {postId})
    if not postExists then
        return cb(false)
    end

    local id = GenerateId("phone_instagram_comments", "id")


    local affected = MySQL.update.await("INSERT INTO phone_instagram_comments (id, post_id, username, comment) VALUES (?, ?, ?, ?)", {
        id, postId, account, content
    })

    if affected == 0 then return cb(false) end



    local commentRows = MySQL.query.await([[
        SELECT
            c.id, c.comment, c.timestamp, c.like_count,
            a.username, a.profile_image, a.verified,
            a.display_name,
            (SELECT COUNT(*) FROM phone_instagram_likes l WHERE l.id = c.id AND l.username = ? AND l.is_comment = TRUE) as liked,
            (SELECT COUNT(*) FROM phone_instagram_follows f WHERE f.follower = ? AND f.followed = a.username) as following
        FROM phone_instagram_comments c
        INNER JOIN phone_instagram_accounts a ON c.username = a.username
        WHERE c.id = ?
    ]], { account, account, id })

    if commentRows and commentRows[1] then
        local commentData = commentRows[1]


        local formattedComment = {
            user = {
                username = commentData.username,
                avatar = commentData.profile_image,
                verified = commentData.verified == 1 or commentData.verified == true,
                name = commentData.display_name or commentData.username
            },
            comment = {
                content = commentData.comment,
                timestamp = commentData.timestamp,
                likes = commentData.like_count or 0,
                liked = commentData.liked == 1 or commentData.liked == true,
                id = commentData.id
            }
        }


        TriggerClientEvent("phone:instagram:newComment", -1, postId, formattedComment)
        TriggerClientEvent("phone:instagram:commentAdded", source, postId, formattedComment)

        debugprint("INSTAGRAM", "New comment posted: ID=" .. id .. ", PostID=" .. postId .. ", User=" .. account .. ", CommentID=" .. commentData.id)


        local owner = MySQL.scalar.await("SELECT username FROM phone_instagram_posts WHERE id = ?", { postId })
        if owner then
            sendInstagramNotification(owner, account, "comment", id)
        end


        TriggerClientEvent("phone:instagram:updatePostData", -1, postId, "comment_count", true)

        return cb(id)
    else
        return cb(false)
    end
end, { 
    preventSpam = true, 
    rateLimit = 10,
    rateLimitNotification = true,
    rateLimitMessage = "Bạn đã đạt giới hạn bình luận. Vui lòng quay lại sau 1 phút",
    rateLimitApp = "Instagram"
})

RegisterLegacyCallback("instagram:deleteComment", function(source, cb, commentId, postId)
    local account = getLoggedInInstagramAccount(source)
    if not account then 
        debugprint("INSTAGRAM", "deleteComment: No logged in account")
        return cb(false) 
    end

    debugprint("INSTAGRAM", "deleteComment: User=" .. account .. ", CommentID=" .. tostring(commentId) .. ", PostID=" .. tostring(postId))


    local isAdmin = IsAdmin and IsAdmin(source)
    local commentData = MySQL.single.await("SELECT username, post_id FROM phone_instagram_comments WHERE id = ?", { commentId })
    
    if not commentData then 
        debugprint("INSTAGRAM", "deleteComment: Comment not found")
        return cb(false) 
    end
    

    local postOwner = MySQL.scalar.await("SELECT username FROM phone_instagram_posts WHERE id = ?", { commentData.post_id })
    local canDelete = (commentData.username == account) or (postOwner == account) or isAdmin
    
    debugprint("INSTAGRAM", "deleteComment: CommentOwner=" .. commentData.username .. ", PostOwner=" .. tostring(postOwner) .. ", CurrentUser=" .. account .. ", IsAdmin=" .. tostring(isAdmin) .. ", CanDelete=" .. tostring(canDelete))
    
    if not canDelete then 
        debugprint("INSTAGRAM", "deleteComment: User does not have permission to delete")
        return cb(false) 
    end


    local success = MySQL.transaction.await({
        { query = "DELETE FROM phone_instagram_likes WHERE id = ? AND is_comment = TRUE", values = { commentId } },
        { query = "DELETE FROM phone_instagram_notifications WHERE post_id = ?", values = { commentId } },
        { query = "DELETE FROM phone_instagram_comments WHERE id = ?", values = { commentId } }
    })
    
    if success then
        debugprint("INSTAGRAM", "Comment deleted: ID=" .. commentId .. ", PostID=" .. postId .. ", DeletedBy=" .. account)
        

        TriggerClientEvent("phone:instagram:updatePostData", -1, postId, "comment_count", false)
        

        TriggerClientEvent("phone:instagram:commentDeleted", -1, postId, commentId)
        
        return cb(true)
    end
    
    return cb(false)
end)

RegisterLegacyCallback("instagram:toggleLike", function(source, cb, postId, enabled, isComment)
    if not postId then return cb(false) end
    
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb(false) end


    local affected = 0
    if enabled then
        affected = MySQL.update.await("INSERT IGNORE INTO phone_instagram_likes (id, username, is_comment) VALUES (?, ?, ?)", { 
            postId, me, isComment 
        })
    else
        affected = MySQL.update.await("DELETE FROM phone_instagram_likes WHERE id=? AND username=? AND is_comment=?", { 
            postId, me, isComment 
        })
    end
    
    if affected == 0 then return cb(enabled) end
    
    cb(enabled)
    
    if isComment then


        debugprint("INSTAGRAM", "Sending updateCommentLikes: commentId=" .. postId .. ", increment=" .. tostring(enabled))
        TriggerClientEvent("phone:instagram:updateCommentLikes", -1, postId, enabled)
    else
        TriggerClientEvent("phone:instagram:updatePostData", -1, postId, "like_count", enabled)
    end
    
    if enabled then
        local tableName = isComment and "phone_instagram_comments" or "phone_instagram_posts"
        local owner = MySQL.scalar.await("SELECT username FROM " .. tableName .. " WHERE id=?", { postId })
        if owner then
            local notifType = "like_" .. (isComment and "comment" or "photo")
            sendInstagramNotification(owner, me, notifType, postId)
        end
    end
end)


RegisterLegacyCallback("instagram:getData", function(source, cb, kind, data)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb({}) end

    local tableName, joinCol, whereClause, orderCol = "", "", "", ""

    if kind == "likes" then
        tableName = "phone_instagram_likes"
        joinCol = "username"
        whereClause = "id=@postId AND is_comment=@isComment"
        orderCol = "a.username"
    elseif kind == "followers" then
        tableName = "phone_instagram_follows"
        joinCol = "follower"
        whereClause = "q.followed=@username"
        orderCol = "q.follower"
    elseif kind == "following" then
        tableName = "phone_instagram_follows"
        joinCol = "followed"
        whereClause = "q.follower=@username"
        orderCol = "q.followed"
    end

    local sql = ([[SELECT a.username, a.display_name AS name, a.profile_image AS avatar, a.verified,
        (IF((
            SELECT TRUE FROM phone_instagram_follows f
            WHERE f.followed=a.username AND f.follower=@loggedInAs
        ), TRUE, FALSE)) AS isFollowing
        FROM phone_instagram_accounts a
        INNER JOIN %s q ON q.%s=a.username
        WHERE %s
        ORDER BY %s DESC
        LIMIT @page, @perPage]]):format(tableName, joinCol, whereClause, orderCol)

    MySQL.Async.fetchAll(sql, {
        ["@username"] = data.username,
        ["@postId"] = data.postId,
        ["@isComment"] = data.isComment == true,
        ["@loggedInAs"] = me,
        ["@page"] = (data.page or 0) * 20,
        ["@perPage"] = 20
    }, cb)
end)

RegisterLegacyCallback("instagram:toggleFollow", function(source, cb, target, enabled)
    local me = getLoggedInInstagramAccount(source)
    if not me or me == target then return cb(not enabled) end

    local function onComplete(affected)
        if affected == 0 then return cb(enabled) end
        




        if enabled then
            sendInstagramNotification(target, me, "follow")
        else

            MySQL.update.await("DELETE FROM phone_instagram_notifications WHERE username = ? AND `from` = ? AND `type` = 'follow'", { target, me })
        end
        cb(enabled)
    end

    local params = {
        ["@username"] = target,
        ["@loggedInAs"] = me
    }
    

    local isPrivate = MySQL.scalar.await("SELECT private FROM phone_instagram_accounts WHERE username = ?", { target })

    if isPrivate then
        if enabled then
            MySQL.Async.execute("INSERT IGNORE INTO phone_instagram_follow_requests (requester, requestee) VALUES (@loggedInAs, @username)", params, function(affected)
                cb(enabled)
                if affected == 0 then return end
                

                local displayName = MySQL.scalar.await("SELECT display_name FROM phone_instagram_accounts WHERE username = ?", { me })
                local numbers = getActiveNumbersByUsername(target)
                for i = 1, #numbers do
                    SendNotification(numbers[i], {
                        app = "Instagram",
                        title = L("BACKEND.INSTAGRAM.NEW_FOLLOW_REQUEST_TITLE"),
                        content = L("BACKEND.INSTAGRAM.NEW_FOLLOW_REQUEST_DESCRIPTION", { 
                            displayName = displayName, 
                            username = me 
                        })
                    })
                end
            end)
            return
        else
            MySQL.Async.execute("DELETE FROM phone_instagram_follow_requests WHERE requester=@loggedInAs AND requestee=@username", params)
        end
    end

    local sql = enabled and "INSERT IGNORE INTO phone_instagram_follows (followed, follower) VALUES (@username, @loggedInAs)" or "DELETE FROM phone_instagram_follows WHERE followed=@username AND follower=@loggedInAs"
    MySQL.Async.execute(sql, params, onComplete)
end)

RegisterLegacyCallback("instagram:getFollowRequests", function(source, cb, page)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb({}) end
    MySQL.Async.fetchAll([[
        SELECT a.username, a.display_name AS `name`, a.profile_image AS avatar, a.verified
        FROM phone_instagram_follow_requests r
        INNER JOIN phone_instagram_accounts a
            ON a.username = r.requester
        WHERE r.requestee=@loggedInAs
        ORDER BY r.`timestamp` DESC
        LIMIT @page, @perPage
    ]], {
        ["@loggedInAs"] = me, 
        ["@page"] = (page or 0) * 15, 
        ["@perPage"] = 15
    }, cb)
end)

RegisterLegacyCallback("instagram:handleFollowRequest", function(source, cb, requester, accept)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb(false) end

    local params = {
        ["@loggedInAs"] = me,
        ["@username"] = requester
    }
    

    local removed = MySQL.update.await("DELETE FROM phone_instagram_follow_requests WHERE requestee = ? AND requester = ?", { me, requester })
    if removed == 0 then return cb(false) end
    if not accept then return cb(true) end

    MySQL.insert.await("INSERT IGNORE INTO phone_instagram_follows (follower, followed) VALUES (?, ?)", { requester, me })




    

    local displayName = MySQL.scalar.await("SELECT display_name FROM phone_instagram_accounts WHERE username = ?", { me })
    if displayName then
        local numbers = getActiveNumbersByUsername(requester)
        for i = 1, #numbers do
            SendNotification(numbers[i], {
                app = "Instagram",
                title = L("BACKEND.INSTAGRAM.FOLLOW_REQUEST_ACCEPTED_TITLE"),
                content = L("BACKEND.INSTAGRAM.FOLLOW_REQUEST_ACCEPTED_DESCRIPTION", { 
                    displayName = displayName, 
                    username = me 
                })
            })
        end
    end
    
    cb(true)
end)


RegisterLegacyCallback("instagram:getNotifications", function(source, cb, page)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb({ notifications = {}, requests = { recent = {}, total = 0 } }) end


    local rows = MySQL.query.await([[
        SELECT
            (
                SELECT CASE WHEN f.followed IS NULL THEN FALSE ELSE TRUE END
                    FROM phone_instagram_follows f
                    WHERE f.follower=@username AND f.followed=n.`from`
            ) AS isFollowing,

            n.`from` AS username,
            n.`type`,
            n.`timestamp`,

            TRIM(BOTH '"' FROM JSON_EXTRACT(p.media, '$[0]')) AS photo,
            p.id AS postId,

            c.`comment`,
            c.id AS commentId,

            a.profile_image AS avatar,
            a.verified

        FROM phone_instagram_notifications n

        LEFT JOIN phone_instagram_comments c
            ON n.post_id = c.id AND n.`type` IN ('comment', 'like_comment')

        LEFT JOIN phone_instagram_posts p
            ON p.id = (CASE
                WHEN n.`type`="like_photo"
                THEN n.post_id

                WHEN n.`type`="new_post"
                THEN n.post_id

                WHEN n.`type`="comment"
                THEN c.post_id

                WHEN n.`type`="like_comment"
                THEN c.post_id


                WHEN n.`type`="started_live"
                THEN NULL
                
                WHEN n.`type`="follow"
                THEN NULL

                ELSE NULL
                END
            )

        LEFT JOIN phone_instagram_accounts a
            ON a.username=n.`from`

        WHERE n.username=@username

        ORDER BY n.`timestamp` DESC

        LIMIT @page, @perPage
    ]], { 
        ["@username"] = me, 
        ["@page"] = (page or 0) * 15, 
        ["@perPage"] = 15 
    }) or {}

    local requestData = { recent = {}, total = 0 }
    if (page or 0) == 0 then

        local recentRequests = MySQL.query.await([[
            SELECT a.username, a.profile_image AS avatar
            FROM phone_instagram_follow_requests r
            INNER JOIN phone_instagram_accounts a
                ON a.username = r.requester
            WHERE r.requestee = ?
            ORDER BY r.`timestamp` DESC
            LIMIT 2
        ]], { me }) or {}
        
        local totalRequests = MySQL.scalar.await("SELECT COUNT(1) FROM phone_instagram_follow_requests WHERE requestee = ?", { me }) or 0
        
        requestData = { recent = recentRequests, total = totalRequests }
    end

    cb({ notifications = rows, requests = requestData })
end)


RegisterLegacyCallback("instagram:getRecentMessages", function(source, cb, page)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb({}) end
    MySQL.Async.fetchAll([[SELECT m.content, m.attachments, m.sender, f_m.username, m.`timestamp`, a.display_name AS name, a.profile_image AS avatar, a.verified
        FROM phone_instagram_messages m JOIN ((SELECT (CASE WHEN recipient!=@me THEN recipient ELSE sender END) AS username, MAX(`timestamp`) AS `timestamp` FROM phone_instagram_messages WHERE sender=@me OR recipient=@me GROUP BY username) f_m)
            ON m.`timestamp`=f_m.`timestamp`
        INNER JOIN phone_instagram_accounts a ON a.username=f_m.username
        WHERE m.sender=@me OR m.recipient=@me GROUP BY f_m.username ORDER BY m.`timestamp` DESC LIMIT @page, @perPage]], { ["@me"] = me, ["@page"] = (page or 0) * 15, ["@perPage"] = 15 }, cb)
end)

RegisterLegacyCallback("instagram:getMessages", function(source, cb, username, page)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb({}) end
    MySQL.Async.fetchAll([[SELECT m.id, m.sender, m.recipient, m.content, m.attachments, m.reply_to, m.`timestamp`,
        rm.content AS reply_content, rm.sender AS reply_sender
        FROM phone_instagram_messages m
        LEFT JOIN phone_instagram_messages rm ON m.reply_to = rm.id
        WHERE (m.sender=@me AND m.recipient=@u) OR (m.sender=@u AND m.recipient=@me)
        ORDER BY m.`timestamp` DESC
        LIMIT @page, @perPage]], {
        ["@me"] = me, ["@u"] = username, ["@page"] = (page or 0) * 25, ["@perPage"] = 25
    }, cb)
end)


createAuthenticatedInstagramCallback("deleteMessage", function(source, phoneNumber, account, messageId)

    local messageData = MySQL.single.await(
        "SELECT sender, recipient FROM phone_instagram_messages WHERE id = ? AND sender = ?",
        { messageId, account }
    )
    
    if not messageData then 
        debugprint("INSTAGRAM", "deleteMessage: User does not own message")
        return false 
    end
    

    local deleted = MySQL.update.await(
        "DELETE FROM phone_instagram_messages WHERE id = ?",
        { messageId }
    ) > 0
    
    if deleted then
        debugprint("INSTAGRAM", "Message deleted: ID=" .. messageId .. ", DeletedBy=" .. account)
        


        TriggerClientEvent("phone:instagram:messageDeleted", -1, messageId)
        
        return true
    end
    
    return false
end, false)

createAuthenticatedInstagramCallback("sendMessage", function(source, _, me, recipient, messageData)
    if ContainsBlacklistedWord(source, "InstaPic", messageData.content or "") then return false end
    local id = GenerateId("phone_instagram_messages", "id")
    local attachments = messageData.attachments and json.encode(messageData.attachments) or nil
    

    local query = "INSERT INTO phone_instagram_messages (id, sender, recipient, content, attachments"
    local values = "VALUES (@id, @s, @r, @c, @att"
    local params = { 
        ["@id"] = id, 
        ["@s"] = me, 
        ["@r"] = recipient, 
        ["@c"] = messageData.content,
        ["@att"] = attachments
    }
    
    if messageData.replyTo then
        query = query .. ", reply_to"
        values = values .. ", @replyTo"
        params["@replyTo"] = messageData.replyTo
    end
    
    query = query .. ") " .. values .. ")"
    
    local ok = MySQL.update.await(query, params) > 0
    if not ok then return false end


    local senderInfo = MySQL.single.await("SELECT display_name, username, profile_image FROM phone_instagram_accounts WHERE username = ?", { me })
    if not senderInfo then return false end


    local replyContent = nil
    local replySender = nil
    if messageData.replyTo then
        local replyData = MySQL.single.await(
            "SELECT content, sender FROM phone_instagram_messages WHERE id = ?",
            { messageData.replyTo }
        )
        if replyData then
            replyContent = replyData.content
            replySender = replyData.sender
        end
    end


    local numbers = getActiveNumbersByUsername(recipient)
    for i = 1, #numbers do
        local src = GetSourceFromNumber(numbers[i])
        if src then
            TriggerClientEvent("phone:instagram:newMessage", src, { 
                id = id,
                sender = me, 
                recipient = recipient, 
                content = messageData.content, 
                attachments = messageData.attachments,
                reply_to = messageData.replyTo,
                reply_content = replyContent,
                reply_sender = replySender,
                timestamp = os.time() * 1000 
            })
        end
        

        local notificationContent = messageData.content
        if string.find(messageData.content, "<!REPLIED_STORY-DATA=") then
            notificationContent = L("APPS.INSTAGRAM.REPLIED_TO_YOUR_STORY")
        end
        
        SendNotification(numbers[i], { 
            app = "Instagram", 
            title = senderInfo.display_name, 
            content = notificationContent,
            thumbnail = messageData.attachments and messageData.attachments[1] or nil,
            avatar = senderInfo.profile_image,
            showAvatar = true
        })
    end


    return id
end, nil, { preventSpam = true, rateLimit = 15 })


createAuthenticatedInstagramCallback("updateProfile", function(source, phoneNumber, account, profileData)
    local updates = {}
    if profileData.name then
        updates[#updates + 1] = "display_name=@displayName"
    end
    if profileData.bio then
        updates[#updates + 1] = "bio=@bio"
    end
    if profileData.avatar then
        updates[#updates + 1] = "profile_image=@avatar"
    end
    if type(profileData.private) == "boolean" then
        updates[#updates + 1] = "private=@private"
    end
    
    if #updates == 0 then return false end
    
    local updateStr = table.concat(updates, ",")
    local sql = "UPDATE phone_instagram_accounts SET " .. updateStr .. " WHERE username=@username"
    

    local affected = MySQL.update.await(sql, {
        ["@displayName"] = profileData.name,
        ["@bio"] = profileData.bio,
        ["@avatar"] = profileData.avatar,
        ["@username"] = account,
        ["@private"] = profileData.private
    })
    
    return affected > 0
end, false)


createAuthenticatedInstagramCallback("changeDisplayName", function(source, phoneNumber, account, newDisplayName)
    if not newDisplayName or type(newDisplayName) ~= "string" or #newDisplayName < 1 then
        return { success = false, error = "INVALID_DISPLAY_NAME" }
    end

    if #newDisplayName > 20 then
        return { success = false, error = "DISPLAY_NAME_TOO_LONG" }
    end

    local cost = Config.InstaPicChangeName.DisplayNameCost
    local success = RemoveMoney(source, cost, "Đổi tên hiển thị Instagram", "priority")
    
    if not success then
        return { success = false, error = "INSUFFICIENT_FUNDS" }
    end

    local affected = MySQL.update.await(
        "UPDATE phone_instagram_accounts SET display_name = ? WHERE username = ?",
        { newDisplayName, account }
    )

    if affected > 0 then

        if ProfileCache[account] then
            ProfileCache[account] = nil
        end
        

        local title = L("BACKEND.INSTAGRAM.DISPLAY_NAME_CHANGED_TITLE")
        if not title or title:find("BACKEND") then
            title = "Tên hiển thị đã được thay đổi"
        end
        local content = L("BACKEND.INSTAGRAM.DISPLAY_NAME_CHANGED_DESCRIPTION", { displayName = newDisplayName })
        if not content or content:find("BACKEND") then
            content = "Tên hiển thị của bạn đã được đổi thành " .. newDisplayName
        end
        
        notifyInstagramDevices(account, {
            title = title,
            content = content
        })

        return { success = true, newDisplayName = newDisplayName }
    else

        AddMoney(source, cost, "tienkhoa")
        return { success = false, error = "UPDATE_FAILED" }
    end
end, { success = false, error = "NOT_LOGGED_IN" })


createAuthenticatedInstagramCallback("changeUsername", function(source, phoneNumber, account, newUsername)
    if not newUsername or type(newUsername) ~= "string" or #newUsername < 1 then
        return { success = false, error = "INVALID_USERNAME" }
    end


    newUsername = newUsername:lower()


    if #newUsername < 3 then
        return { success = false, error = "USERNAME_TOO_SHORT" }
    end

    if #newUsername > 8 then
        return { success = false, error = "USERNAME_TOO_LONG" }
    end


    if not newUsername:match("^[a-z0-9_.]+$") then
        return { success = false, error = "USERNAME_NOT_ALLOWED" }
    end


    local exists = MySQL.scalar.await(
        "SELECT TRUE FROM phone_instagram_accounts WHERE username = ? AND username != ?",
        { newUsername, account }
    )
    
    if exists then
        if phoneNumber then
            SendNotification(phoneNumber, {
                app = "Instagram",
                title = "Username đã được sử dụng",
                content = "Username @" .. newUsername .. " đã có người sử dụng"
            })
        end
        return { success = false, error = "USERNAME_TAKEN" }
    end


    local cost = Config.InstaPicChangeName.UsernameCost
    local success = RemoveMoney(source, cost, "Đổi username Instagram", "priority")
    
    if not success then
        if phoneNumber then
            SendNotification(phoneNumber, {
                app = "Instagram",
                title = "Không đủ tiền",
                content = "Bạn cần $1 IC để đổi username"
            })
        end
        return { success = false, error = "INSUFFICIENT_FUNDS" }
    end


    -- Sử dụng phone_number để đảm bảo cập nhật đúng account
    local affected = MySQL.update.await(
        "UPDATE phone_instagram_accounts SET username = ? WHERE username = ? AND phone_number = ?",
        { newUsername, account, phoneNumber }
    )

    if affected > 0 then

        MySQL.Async.execute("UPDATE phone_instagram_posts SET username = ? WHERE username = ?", { newUsername, account })
        MySQL.Async.execute("UPDATE phone_instagram_follows SET follower = ? WHERE follower = ?", { newUsername, account })
        MySQL.Async.execute("UPDATE phone_instagram_follows SET followed = ? WHERE followed = ?", { newUsername, account })
        MySQL.Async.execute("UPDATE phone_instagram_likes SET username = ? WHERE username = ?", { newUsername, account })
        MySQL.Async.execute("UPDATE phone_instagram_comments SET username = ? WHERE username = ?", { newUsername, account })
        MySQL.Async.execute("UPDATE phone_instagram_notifications SET username = ? WHERE username = ?", { newUsername, account })
        MySQL.Async.execute("UPDATE phone_instagram_notifications SET `from` = ? WHERE `from` = ?", { newUsername, account })
        MySQL.Async.execute("UPDATE phone_instagram_stories SET username = ? WHERE username = ?", { newUsername, account })
        MySQL.Async.execute("UPDATE phone_instagram_messages SET sender = ? WHERE sender = ?", { newUsername, account })
        MySQL.Async.execute("UPDATE phone_instagram_messages SET recipient = ? WHERE recipient = ?", { newUsername, account })
        MySQL.Async.execute("UPDATE phone_logged_in_accounts SET username = ? WHERE username = ? AND app = 'Instagram'", { newUsername, account })
        

        if ProfileCache[account] then
            ProfileCache[account] = nil
        end
        if ProfileCache[newUsername] then
            ProfileCache[newUsername] = nil
        end
        

        RemoveLoggedInAccount(phoneNumber, "Instagram", account)
        AddLoggedInAccount(phoneNumber, "Instagram", newUsername)
        

        local title = L("BACKEND.INSTAGRAM.USERNAME_CHANGED_TITLE")
        if not title or title:find("BACKEND") then
            title = "Username đã được thay đổi"
        end
        local content = L("BACKEND.INSTAGRAM.USERNAME_CHANGED_DESCRIPTION", { username = newUsername })
        if not content or content:find("BACKEND") then
            content = "Username của bạn đã được đổi thành @" .. newUsername
        end
        
        notifyInstagramDevices(newUsername, {
            title = title,
            content = content
        })


        local newProfile = getInstagramProfile(newUsername, phoneNumber)
        return { success = true, newUsername = newUsername, profile = newProfile, needReload = true }
    else

        AddMoney(source, cost, "Hoàn tiền đổi username Instagram")
        return { success = false, error = "UPDATE_FAILED" }
    end
end, { success = false, error = "NOT_LOGGED_IN" })


RegisterLegacyCallback("instagram:search", function(_, cb, query)
    MySQL.Async.fetchAll([[SELECT display_name, username, profile_image, verified, private FROM phone_instagram_accounts WHERE username LIKE CONCAT(@q, "%") OR display_name LIKE CONCAT("%", @q, "%")]], { ["@q"] = query }, cb)
end)


local lives = {}

RegisterLegacyCallback("instagram:getLives", function(source, cb)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb({}) end

    local visible = {}
    for username, data in pairs(lives) do
        if data.private then

            local follows = MySQL.scalar.await("SELECT TRUE FROM phone_instagram_follows WHERE follower = ? AND followed = ?", { me, username })
            if follows then
                visible[username] = data
            end
        else
            visible[username] = data
        end
    end

    cb(visible)
end)

RegisterLegacyCallback("instagram:getLiveViewers", function(_, cb, username)
    local live = lives[username]
    if not live then return cb({}) end

    local viewers = live.viewers or {}
    local results = {}
    

    local viewerSources = {}
    if type(next(viewers)) == "number" then

        for src in pairs(viewers) do
            viewerSources[#viewerSources + 1] = src
        end
    else

        viewerSources = viewers
    end
    
    for i = 1, #viewerSources do
        local number = GetEquippedPhoneNumber(viewerSources[i])
        if number then

            local rows = MySQL.query.await([[SELECT a.profile_image AS avatar, a.verified, a.display_name AS `name`, a.username
                FROM phone_logged_in_accounts l INNER JOIN phone_instagram_accounts a ON l.username = a.username
                WHERE l.phone_number = ? AND l.active = 1 AND l.app = 'Instagram']], { number })
            if rows and rows[1] then
                results[#results + 1] = rows[1]
            end
        end
    end

    cb(results)
end)

RegisterLegacyCallback("instagram:canGoLive", function(source, cb)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb(false) end

    local allowed, reason = CanGoLive(source, me)
    if not allowed then
        local number = GetEquippedPhoneNumber(source)
        if number then
            SendNotification(number, { app = "Instagram", title = reason or L("BACKEND.INSTAGRAM.NOT_ALLOWED_LIVE") })
        end
    end
    cb(allowed)
end)

RegisterLegacyCallback("instagram:getLives", function(source, cb)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb({}) end

    local result = {}
    for username, live in pairs(lives) do
        local canSee = false
        if not live.private then
            canSee = true
        else
            local follows = MySQL.scalar.await("SELECT TRUE FROM phone_instagram_follows WHERE follower=@follower AND followed=@followed", {
                ["@follower"] = me,
                ["@followed"] = username
            })
            canSee = follows and true or false
        end

        if canSee then

            local viewerCount = 0
            local viewerList = {}
            if live.viewers then
                if type(next(live.viewers)) == "number" then

                    for src in pairs(live.viewers) do
                        viewerCount = viewerCount + 1
                        viewerList[#viewerList + 1] = src
                    end
                else

                    viewerCount = #live.viewers
                    viewerList = live.viewers
                end
            end
            

            result[username] = {
                id = live.id,
                avatar = live.avatar,
                verified = live.verified,
                name = live.name,
                private = live.private,
                host = live.host,
                viewers = viewerList,
                viewer_count = viewerCount,
                participants = live.participants or {},
                nearby = live.nearby or {},
                invites = live.invites or {},

                is_own_live = (username == me)
            }
        end
    end
    cb(result)
end)

RegisterLegacyCallback("instagram:canCreateStory", function(source, cb)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb(false) end

    local allowed, reason = CanCreateStory(source, me)
    if not allowed then
        local number = GetEquippedPhoneNumber(source)
        if number then
            SendNotification(number, { app = "Instagram", title = reason or L("BACKEND.INSTAGRAM.NOT_ALLOWED_STORY") })
        end
    end
    cb(allowed)
end)

RegisterLegacyCallback("instagram:addToStory", function(source, cb, media, metadata)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb(false) end
    
    local allowed = CanCreateStory(source, me)
    if not allowed then return cb(false) end
    
    local id = GenerateId("phone_instagram_stories", "id")
    

    local metadataJson = metadata
    if type(metadata) == "table" then
        metadataJson = json.encode(metadata)
    end
    
    MySQL.update.await([[
        INSERT INTO phone_instagram_stories (id, username, image, metadata)
        VALUES (@id, @username, @image, @metadata)
    ]], {
        ["@id"] = id,
        ["@username"] = me,
        ["@image"] = media,
        ["@metadata"] = metadataJson
    })
    

    local followers = MySQL.query.await("SELECT follower FROM phone_instagram_follows WHERE followed = ?", { me })
    if followers then
        for i = 1, #followers do
            sendInstagramNotification(followers[i].follower, me, "new_story", id)
        end
    end
    
    cb(true)
end)

RegisterLegacyCallback("instagram:removeFromStory", function(source, cb, id)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb(false) end
    
    local deleted = MySQL.update.await("DELETE FROM phone_instagram_stories WHERE id = ? AND username = ?", { id, me }) > 0
    
    if deleted then
        debugprint("INSTAGRAM", "Story deleted: ID=" .. id .. ", User=" .. me)
        

        TriggerClientEvent("phone:instagram:storyDeleted", -1, me, id)
    end
    
    cb(deleted)
end)

RegisterLegacyCallback("instagram:getStories", function(source, cb)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb({}) end

    MySQL.Async.fetchAll([[
        SELECT
            s.id, s.username, s.image, s.metadata, s.timestamp,
            a.display_name, a.profile_image, a.verified,
            (SELECT COUNT(*) FROM phone_instagram_stories_views sv WHERE sv.story_id = s.id) as views,
            (SELECT COUNT(*) FROM phone_instagram_stories_views sv WHERE sv.story_id = s.id AND sv.viewer = ?) as is_viewed
        FROM phone_instagram_stories s
        INNER JOIN phone_instagram_accounts a ON a.username = s.username
        WHERE s.timestamp > DATE_SUB(NOW(), INTERVAL 24 HOUR)
        ORDER BY s.timestamp DESC
    ]], { me }, cb)
end)

RegisterLegacyCallback("instagram:getStory", function(source, cb, username)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb({}) end

    MySQL.Async.fetchAll([[
        SELECT
            s.id, s.username, s.image, s.metadata, s.timestamp,
            a.display_name, a.profile_image, a.verified,
            (SELECT COUNT(*) FROM phone_instagram_stories_views sv WHERE sv.story_id = s.id) as views,
            (SELECT COUNT(*) FROM phone_instagram_stories_views sv WHERE sv.story_id = s.id AND sv.viewer = ?) as is_viewed
        FROM phone_instagram_stories s
        INNER JOIN phone_instagram_accounts a ON a.username = s.username
        WHERE s.username = @username AND s.timestamp > DATE_SUB(NOW(), INTERVAL 24 HOUR)
        ORDER BY s.timestamp DESC
    ]], { ["@username"] = username, ["@viewer"] = me }, cb)
end)

RegisterLegacyCallback("instagram:getViewers", function(source, cb, id, page)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb({}) end
    
    MySQL.Async.fetchAll([[
        SELECT v.viewer as username, v.timestamp as viewed_at,
            a.display_name, a.profile_image, a.verified
        FROM phone_instagram_stories_views v
        INNER JOIN phone_instagram_accounts a ON a.username = v.viewer
        WHERE v.story_id = @id
        ORDER BY v.timestamp DESC
        LIMIT @page, @perPage
    ]], {
        ["@id"] = id,
        ["@page"] = (page or 0) * 15,
        ["@perPage"] = 15
    }, cb)
end)

RegisterLegacyCallback("instagram:viewedStory", function(source, cb, id)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb(false) end
    

    local alreadyViewed = MySQL.scalar.await("SELECT TRUE FROM phone_instagram_stories_views WHERE story_id = @id AND viewer = @viewer", {
        ["@id"] = id,
        ["@viewer"] = me
    })
    
    if not alreadyViewed then
        MySQL.update.await("INSERT INTO phone_instagram_stories_views (story_id, viewer) VALUES (@id, @viewer)", {
            ["@id"] = id,
            ["@viewer"] = me
        })
    end
    
    cb(true)
end)

RegisterLegacyCallback("instagram:viewLive", function(source, cb, username)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb(false) end

    local live = lives[username]
    if not live then return cb(false) end


    if live.private then
        local follows = MySQL.scalar.await("SELECT TRUE FROM phone_instagram_follows WHERE follower=@follower AND followed=@followed", {
            ["@follower"] = me,
            ["@followed"] = username
        })
        if not follows then return cb(false) end
    end


    if not live.viewers then
        live.viewers = {}
    end
    

    if #live.viewers > 0 and type(live.viewers[1]) == "number" then
        local oldViewers = live.viewers
        live.viewers = {}
        for i = 1, #oldViewers do
            live.viewers[oldViewers[i]] = true
        end
    end


    local alreadyViewing = live.viewers[source]
    if not alreadyViewing then
        live.viewers[source] = true
        

        local viewerCount = 0
        for _ in pairs(live.viewers) do
            viewerCount = viewerCount + 1
        end
        
        debugprint("INSTAGRAM", "Viewer joined live stream: " .. me .. " watching " .. username .. " (Total viewers: " .. viewerCount .. ")")


        TriggerClientEvent("phone:instagram:updateViewers", -1, username, viewerCount)
        BroadcastUpdateLives()
        

        TriggerClientEvent("phone:instagram:viewerJoined", live.host, source)
        for i = 1, #live.participants do
            if live.participants[i].source then
                TriggerClientEvent("phone:instagram:viewerJoined", live.participants[i].source, source)
            end
        end
    end


    local viewerCount = 0
    local viewerList = {}
    for src in pairs(live.viewers) do
        viewerCount = viewerCount + 1
        viewerList[#viewerList + 1] = src
    end

    cb({
        id = live.id,
        username = username,
        title = live.title or "Live Stream",
        host = live.host,
        participants = live.participants,
        viewers = viewerList,
        viewer_count = viewerCount
    })
end)

RegisterLegacyCallback("instagram:stopViewing", function(source, cb, username)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb(false) end

    local live = lives[username]
    if not live then return cb(false) end


    if live.viewers then
        if type(live.viewers[source]) == "boolean" then

            if live.viewers[source] then
                live.viewers[source] = nil
                

                local viewerCount = 0
                for _ in pairs(live.viewers) do
                    viewerCount = viewerCount + 1
                end
                
                debugprint("INSTAGRAM", "Viewer left live stream: " .. me .. " stopped watching " .. username .. " (Total viewers: " .. viewerCount .. ")")


                TriggerClientEvent("phone:instagram:updateViewers", -1, username, viewerCount)
                BroadcastUpdateLives()
                

                TriggerClientEvent("phone:instagram:viewerLeft", live.host, source)
                for i = 1, #live.participants do
                    if live.participants[i].source then
                        TriggerClientEvent("phone:instagram:viewerLeft", live.participants[i].source, source)
                    end
                end
            end
        else

            for i = #live.viewers, 1, -1 do
                if live.viewers[i] == source then
                    table.remove(live.viewers, i)
                    debugprint("INSTAGRAM", "Viewer left live stream: " .. me .. " stopped watching " .. username .. " (Total viewers: " .. #live.viewers .. ")")


                    TriggerClientEvent("phone:instagram:updateViewers", -1, username, math.max(0, #live.viewers))
                    BroadcastUpdateLives()
                    break
                end
            end
        end
    end

    cb(true)
end)

RegisterLegacyCallback("instagram:joinLive", function(source, cb, username, streamId)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb(false) end
    
    local live = lives[username]
    if not live or not live.participants then return cb(false) end
    

    if lives[me] then return cb(false) end
    

    if live.invites and live.invites[me] then
        live.invites[me] = nil
    end
    


    if #live.participants >= 3 then return cb(false) end
    

    for i = 1, #live.participants do
        if live.participants[i].username == me then
            return cb(false)
        end
    end
    
    local acc = MySQL.single.await("SELECT profile_image, verified, display_name FROM phone_instagram_accounts WHERE username=@username", { ["@username"] = me })
    if not acc then return cb(false) end
    

    if #live.participants >= 3 then 
        debugprint("INSTAGRAM", "joinLive: Participant limit reached during join process for " .. me)
        return cb(false) 
    end
    

    live.participants[#live.participants + 1] = {
        username = me,
        name = acc.display_name,
        avatar = acc.profile_image,
        verified = acc.verified,
        id = streamId,
        source = source
    }
    

    if #live.participants > 3 then
        debugprint("INSTAGRAM", "joinLive: RACE CONDITION DETECTED - Removing " .. me .. " from participants")

        for i = #live.participants, 1, -1 do
            if live.participants[i].username == me then
                table.remove(live.participants, i)
                break
            end
        end
        return cb(false)
    end
    

    lives[me] = {
        id = streamId,
        avatar = acc.profile_image,
        verified = acc.verified,
        name = acc.display_name,
        host = source,
        nearby = {},
        viewers = {},
        participant = username
    }
    
    Player(source).state.instapicIsLive = me
    BroadcastUpdateLives()
    

    local followers = MySQL.query.await("SELECT follower FROM phone_instagram_follows WHERE followed = @username", { ["@username"] = me })
    for i = 1, #followers do
        notifyInstagramDevices(followers[i].follower, { 
            title = L("APPS.INSTAGRAM.TITLE"), 
            content = L("BACKEND.INSTAGRAM.JOINED_LIVE", { invitee = me, inviter = username }) 
        })
    end
    
    cb(true)
end)

RegisterLegacyCallback("instagram:endLive", function(source, cb)
    local me = getLoggedInInstagramAccount(source)
    if not me then return cb(false) end
    
    local live = lives[me]
    if not live then return cb(false) end
    
    local wasHost = live.host == source
    local participant = live.participant
    

    lives[me] = nil
    Player(source).state.instapicIsLive = nil
    

    if wasHost then
        if participant then
            EndLive(participant, me)
        else
            EndLive(me, me)
        end
    else

        if participant and lives[participant] then
            for i = #lives[participant].participants, 1, -1 do
                if lives[participant].participants[i].username == me then
                    table.remove(lives[participant].participants, i)
                    break
                end
            end
        end
    end
    
    BroadcastUpdateLives()
    TriggerClientEvent("phone:instagram:endLive", -1, me, me)
    
    cb(true)
end)

RegisterNetEvent("phone:instagram:startLive", function(streamId)
    local src = source
    local me = getLoggedInInstagramAccount(src)
    if not me then return end
    if lives[me] then return end

    local allowed = CanGoLive(src, me)
    if not allowed then return end

    local acc = MySQL.single.await("SELECT profile_image, verified, display_name, private FROM phone_instagram_accounts WHERE username = ?", { me })
    if not acc then return end

    lives[me] = {
        id = streamId,
        avatar = acc.profile_image,
        verified = acc.verified,
        name = acc.display_name,
        private = acc.private,
        host = src,
        viewers = {},
        viewer_count = 0,
        nearby = {},
        invites = {},
        participants = {}
    }

    Player(src).state.instapicIsLive = me

    BroadcastUpdateLives()
    TriggerClientEvent("phone:instagram:updateViewers", -1, me, 0)

    debugprint("INSTAGRAM", "Live stream started: " .. me .. " (Viewers: 0)")

    Log("InstaPic", src, "success", L("BACKEND.LOGS.LIVE_TITLE"), L("BACKEND.LOGS.STARTED_LIVE", { username = me }))
    TrackSimpleEvent("go_live")


    local followers = MySQL.query.await("SELECT follower FROM phone_instagram_follows WHERE followed = @username", { ["@username"] = me })
    


    if Config.InstaPicLiveNotifications and followers and #followers > 0 then

        for i = 1, #followers do
            local followerNumbers = getActiveNumbersByUsername(followers[i].follower)
            for j = 1, #followerNumbers do
                SendNotification(followerNumbers[j], { 
                    app = "Instagram", 
                    title = L("APPS.INSTAGRAM.TITLE"), 
                    content = L("BACKEND.INSTAGRAM.STARTED_LIVE", { username = me }) 
                })
            end
        end
    end
    

    for i = 1, #followers do
        sendInstagramNotification(followers[i].follower, me, "started_live", nil)
    end
end)

RegisterNetEvent("phone:instagram:sendLiveMessage", function(messageData)
    local src = source
    local me = getLoggedInInstagramAccount(src)
    if not me then return end
    
    messageData.username = me
    messageData.timestamp = os.time()
    
    TriggerClientEvent("phone:instagram:addLiveMessage", -1, messageData)
end)

RegisterNetEvent("phone:instagram:addCall", function(callId)
    local src = source
    local me = getLoggedInInstagramAccount(src)
    if not me then return end
    

    TriggerClientEvent("phone:instagram:addCall", -1, {
        id = callId,
        username = me,
        source = src
    })
end)

RegisterNetEvent("phone:instagram:inviteLive", function(username)
    local src = source
    local me = getLoggedInInstagramAccount(src)
    if not me then return end
    
    local live = lives[me]
    if not live then return end
    

    if not live.invites then live.invites = {} end
    live.invites[username] = true
    

    TriggerClientEvent("phone:instagram:invitedLive", -1, {
        from = me,
        to = username,
        source = src
    })
end)

RegisterNetEvent("phone:instagram:removeLive", function(username)
    local src = source
    local me = getLoggedInInstagramAccount(src)
    if not me then return end
    
    local live = lives[me]
    if not live then return end
    

    for i = #live.participants, 1, -1 do
        if live.participants[i].username == username then
            local participant = live.participants[i]
            table.remove(live.participants, i)
            

            if lives[username] then
                lives[username] = nil
                local participantSrc = participant.source
                if participantSrc then
                    Player(participantSrc).state.instapicIsLive = nil
                    TriggerClientEvent("phone:instagram:removedLive", participantSrc)
                end
            end
            break
        end
    end
    
    BroadcastUpdateLives()
end)


AddEventHandler("playerDropped", function()
    local src = source
    

    for username, live in pairs(lives) do

        if live.viewers then
            if type(live.viewers[src]) == "boolean" then

                if live.viewers[src] then
                    live.viewers[src] = nil
                    local viewerCount = 0
                    for _ in pairs(live.viewers) do
                        viewerCount = viewerCount + 1
                    end
                    TriggerClientEvent("phone:instagram:updateViewers", -1, username, viewerCount)
                end
            else

                for i = #live.viewers, 1, -1 do
                    if live.viewers[i] == src then
                        table.remove(live.viewers, i)
                        TriggerClientEvent("phone:instagram:updateViewers", -1, username, math.max(0, #live.viewers))
                        break
                    end
                end
            end
        end
        

        if live.host == src then
            local participant = live.participant
            if participant then
                EndLive(participant, username)
            else
                EndLive(username, username)
            end
        else

            if live.participants then
                for i = #live.participants, 1, -1 do
                    if live.participants[i].source == src then
                        local participant = live.participants[i]
                        table.remove(live.participants, i)
                        

                        if lives[participant.username] then
                            lives[participant.username] = nil
                            TriggerClientEvent("phone:instagram:leftLive", -1, username, participant.username, src)
                        end
                        break
                    end
                end
            end
        end
    end

    BroadcastUpdateLives()


    for username, live in pairs(lives) do
        if live.viewers then
            local viewerCount = 0
            if type(next(live.viewers)) == "number" then

                for _ in pairs(live.viewers) do
                    viewerCount = viewerCount + 1
                end
            else

                viewerCount = #live.viewers
            end
            TriggerClientEvent("phone:instagram:updateViewers", -1, username, math.max(0, viewerCount))
        end
    end
end)


