
local function formatTweetData(tweetData)
    if not tweetData then
        return {}
    end

    local attachments = tweetData.attachments
    if type(tweetData.attachments) == "string" then
        attachments = json.decode(tweetData.attachments)
    end

    if attachments then
        if type(attachments) == "table" and table.type(attachments) == "array" then
        else
            attachments = nil
        end
    end

    local formattedData = {}
    local user = {}
    user.profile_picture = tweetData.profile_image
    user.name = tweetData.display_name
    user.username = tweetData.username
    user.verified = tweetData.verified == true
    user.private = tweetData.private == true
    formattedData.user = user

    local tweet = {}
    tweet.id = tweetData.id
    tweet.content = tweetData.content
    tweet.date_created = tweetData.timestamp
    tweet.replies = tweetData.reply_count
    tweet.likes = tweetData.like_count
    tweet.retweets = tweetData.retweet_count
    tweet.attachments = attachments
    tweet.replyToId = tweetData.reply_to
    tweet.liked = tweetData.liked == true or tweetData.liked == 1
    tweet.retweeted = tweetData.retweeted == true or tweetData.retweeted == 1
    tweet.replyToAuthor = tweetData.replyToAuthor
    tweet.retweetedByName = tweetData.retweeted_by_display_name
    tweet.retweetedByUsername = tweetData.retweeted_by_username

    tweet.isReply = tweetData.reply_to ~= nil
    tweet.isOriginalTweet = tweetData.reply_to == nil

    formattedData.tweet = tweet

    return formattedData
end

local function getFormattedPosts(filters, page)
    local posts = AwaitCallback("birdy:getPosts", filters, page)
    local formattedPosts = {}

    for i = 1, #posts do
        formattedPosts[i] = formatTweetData(posts[i])
    end

    local promotedPosition = math.random(3, 6)
    if promotedPosition >= #formattedPosts then
        promotedPosition = #formattedPosts - 1
    end

    if Config.PromoteBirdy and Config.PromoteBirdy.Enabled then
        if #posts > 1 then
            local promotedPost = AwaitCallback("birdy:getRandomPromoted")
            if promotedPost then
                local formattedPromoted = formatTweetData(promotedPost)
                formattedPromoted.tweet.promoted = true
                table.insert(formattedPosts, promotedPosition, formattedPromoted)
            end
        end
    end

    return formattedPosts
end

local restrictedActions = { "login", "toggleFollow", "toggleLike", "toggleRetweet", "sendMessage" }
RegisterNUICallback("Twitter", function(data, callback)
    if not currentPhone then
        return
    end

    local action = data.action

    if table.contains(restrictedActions, action) then
        if not CanInteract() then
            return callback(false)
        end
    end

    if action == "createAccount" then
        local accountData = data.data
        TriggerCallback("birdy:createAccount", callback, accountData.name, accountData.username, accountData.password)
    elseif action == "changePassword" then
        TriggerCallback("birdy:changePassword", callback, data.oldPassword, data.newPassword)
    elseif action == "deleteAccount" then
        TriggerCallback("birdy:deleteAccount", callback, data.password)
    elseif action == "login" then
        local loginData = data.data
        TriggerCallback("birdy:login", callback, loginData.username, loginData.password)
    elseif action == "isLoggedIn" then
        TriggerCallback("birdy:isLoggedIn", callback)
    elseif action == "sendTweet" then
        local tweetData = data.data
        TriggerCallback("birdy:sendPost", callback, tweetData.content, tweetData.attachments, tweetData.replyTo, tweetData.hashtags)
    elseif action == "updateProfile" then
        local profileData = data.data
        TriggerCallback("birdy:updateProfile", callback, profileData)
    elseif action == "changeDisplayName" then
        TriggerCallback("birdy:changeDisplayName", callback, data.newDisplayName)
    elseif action == "changeUsername" then
        TriggerCallback("birdy:changeUsername", callback, data.newUsername)
    elseif action == "searchAccounts" then
        TriggerCallback("birdy:searchAccounts", function(results)
            local formattedResults = {}
            for i = 1, #results do
                local account = results[i]
                local formatted = {}
                formatted.username = account.username
                formatted.name = account.display_name
                formatted.profile_picture = account.profile_image
                formatted.verified = account.verified == true
                formatted.private = account.private == true
                formattedResults[i] = formatted
            end
            callback(formattedResults)
        end, data.query)
    elseif action == "searchTweets" then
        TriggerCallback("birdy:searchTweets", function(results)
            local formattedResults = {}
            for i = 1, #results do
                formattedResults[i] = formatTweetData(results[i])
            end
            callback(formattedResults)
        end, data.query, data.page)
    elseif action == "getProfile" then
        TriggerCallback("birdy:getProfile", function(profile)
            if not profile then
                return callback()
            end

            if profile.pinnedTweet then
                profile.pinnedTweet = formatTweetData(profile.pinnedTweet)
            end

            callback(profile)
        end, data.data.username)
    elseif action == "getFollowers" then
        TriggerCallback("birdy:getData", callback, "followers", data.data.username, data.data.page)
    elseif action == "getFollowing" then
        TriggerCallback("birdy:getData", callback, "following", data.data.username, data.data.page)
    elseif action == "getLikes" then
        TriggerCallback("birdy:getData", callback, "likes", data.data.tweet_id, data.data.page)
    elseif action == "getRetweeters" then
        TriggerCallback("birdy:getData", callback, "retweeters", data.data.tweet_id, data.data.page)
    elseif action == "getTweets" then
        local filters = data.filter or data.filters
        data.filter = filters
        if filters and next(filters) == nil then
            data.filter = nil
        end

        if data.filter and data.filter.type == "replyTo" and data.filter.tweet_id then
            local tweetId = data.filter.tweet_id
            local page = data.page or 0
        
            TriggerCallback("birdy:getReplies", function(replies)
                local formattedReplies = {}
                for i, reply in ipairs(replies) do
                    formattedReplies[i] = formatTweetData(reply)
                end
                callback(formattedReplies)
            end, tweetId, page)
        
        else
            local result = getFormattedPosts(data.filter, data.page)
            callback(result)
        end
    elseif action == "getTweet" then
        TriggerCallback("birdy:getPost", function(tweet)
            callback(formatTweetData(tweet))
        end, data.tweetId)
    elseif action == "getAuthor" then
        TriggerCallback("birdy:getAuthor", callback, data.tweetId)
    elseif action == "getReplies" then
        TriggerCallback("birdy:getReplies", function(replies)
            local formattedReplies = {}
            for i = 1, #replies do
                formattedReplies[i] = formatTweetData(replies[i])
            end
            callback(formattedReplies)
        end, data.filter.tweet_id, data.page)
    elseif action == "toggleFollow" then
        TriggerCallback("birdy:toggleFollow", callback, data.data.username, data.data.following)
    elseif action == "toggleNotifications" then
        TriggerCallback("birdy:toggleNotifications", callback, data.data.username, data.data.toggle)
    elseif action == "toggleLike" then
        TriggerCallback("birdy:toggleInteraction", callback, "like", data.tweet_id, data.liked)
    elseif action == "toggleRetweet" then
        TriggerCallback("birdy:toggleInteraction", callback, "retweet", data.tweet_id, data.retweeted)
    elseif action == "deleteTweet" then
        TriggerCallback("birdy:deletePost", callback, data.tweet_id)
    elseif action == "promoteTweet" then
        TriggerCallback("birdy:promotePost", callback, data.tweet_id)
    elseif action == "sendMessage" then
        local messageData = data.data
        TriggerCallback("birdy:sendMessage", callback, messageData.recipient, messageData.content, messageData.attachments, messageData.replyTo)
    elseif action == "getMessages" then
        local messageData = data.data
        TriggerCallback("birdy:getMessages", function(messages)
            for i = 1, #messages do
                local message = messages[i]
                if message.attachments then
                    message.attachments = json.decode(message.attachments)
                end
            end
            callback(messages)
        end, messageData.username, messageData.page)
    elseif action == "getRecentMessages" then
        TriggerCallback("birdy:getRecentMessages", callback, data.page)
    elseif action == "deleteMessage" then
        TriggerCallback("birdy:deleteMessage", callback, data.id)
    elseif action == "signOut" then
        return
    elseif action == "getNotifications" then
        TriggerCallback("birdy:getNotifications", function(notifications)
            for _, notification in pairs(notifications.notifications) do
                if notification.attachments then
                    notification.attachments = json.decode(notification.attachments)
                end
            end
            callback(notifications)
        end, data.page)
    elseif action == "getRecentHashtags" then
        TriggerCallback("birdy:getRecentHashtags", callback)
    elseif action == "pinTweet" then
        TriggerCallback("birdy:pinPost", callback, data.toggle and data.tweet_id or nil)
    elseif action == "getFollowRequests" then
        TriggerCallback("birdy:getFollowRequests", callback, data.page or 0)
    elseif action == "handleFollowRequest" then
        TriggerCallback("birdy:handleFollowRequest", callback, data.username, data.accept)
    end
end)

RegisterNetEvent("phone:twitter:updateTweetData", function(data, field, count)
    local updateData
    if type(data) == "table" and data.tweetId then
        updateData = data
    else
        updateData = {
            tweetId = data,
            field = field,
            count = count
        }
    end
    
    SendReactMessage("twitter:updateTweetData", updateData)
end)

RegisterNetEvent("phone:twitter:updateProfileData", function(username, data, increment)
    SendReactMessage("twitter:updateProfileData", {
        username = username,
        data = data,
        increment = increment
    })
end)

RegisterNetEvent("phone:twitter:newMessage", function(messageData)
    SendReactMessage("twitter:newMessage", messageData)
end)

RegisterNetEvent("phone:twitter:messageDeleted", function(data)
    SendReactMessage("twitter:messageDeleted", data)
end)

RegisterNetEvent("phone:twitter:newtweet", function(tweetData)
    TriggerEvent("lb-phone:birdy:newPost", tweetData)
    SendReactMessage("twitter:newTweet", formatTweetData(tweetData))
end)

RegisterNetEvent("phone:twitter:newComment", function(commentData, tweetId)
    local formattedComment = formatTweetData(commentData)
    SendReactMessage("twitter:newComment", {
        comment = formattedComment,
        tweetId = tweetId
    })
end)

RegisterNetEvent("phone:twitter:deleteTweet", function(tweetId)
    SendReactMessage("twitter:deleteTweet", tweetId)
end)

function SendTweet(data)
    assert(type(data) == "table", "Expected table for data, got " .. type(data))
    assert(type(data.content) == "string", "Expected string for data.content, got " .. type(data.content))
    assert(type(data.attachments) == "table", "Expected table / nil for data.attachments, got " .. type(data.attachments))
    assert(type(data.replyTo) == "string", "Expected string / nil for data.replyTo, got " .. type(data.replyTo))
    assert(type(data.hashtags) == "table", "Expected table / nil for data.hashtags, got " .. type(data.hashtags))

    if not CanInteract() then
        return
    end

    return AwaitCallback("birdy:sendPost", data.content, data.attachments, data.replyTo, data.hashtags)
end

exports("SendTweet", SendTweet)
exports("PostBirdy", SendTweet)
