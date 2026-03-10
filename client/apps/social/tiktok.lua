



local function formatVideoData(videoData)
    if videoData.metadata then
        videoData.metadata = json.decode(videoData.metadata)
    end

    if videoData.music then
        videoData.music = json.decode(videoData.music)
        

        if Music and Music.Songs and videoData.music and videoData.music.path then
            local song = Music.Songs[videoData.music.path]
            if song then
                local album = Music.Albums[song.album]
                if album and album.Cover then
                    song.Cover = album.Cover
                end
                
                local musicInfo = {}
                musicInfo.title = song.Title
                musicInfo.artist = song.Artist
                musicInfo.cover = song.Cover
                musicInfo.volume = videoData.music.volume
                musicInfo.path = videoData.music.path
                videoData.music = musicInfo
            end
        end
    end
    
    videoData.liked = (videoData.liked == 1)
    videoData.saved = (videoData.saved == 1)

    return videoData
end

RegisterNUICallback("TikTok", function(data, callback)
    if not currentPhone then
        return
    end
    
    local action = data.action
    debugprint("tiktok:" .. (action or ""))

    if action == "login" then
        local loginData = data.data
        TriggerCallback("tiktok:login", callback, loginData.username, loginData.password)
        
    elseif action == "signup" then
        local signupData = data.data
        TriggerCallback("tiktok:signup", callback, signupData.username, signupData.password, signupData.name)
        
    elseif action == "changePassword" then
        TriggerCallback("tiktok:changePassword", callback, data.oldPassword, data.newPassword)
        
    elseif action == "deleteAccount" then
        TriggerCallback("tiktok:deleteAccount", callback, data.password)
        
    elseif action == "logout" then
        return
        
    elseif action == "isLoggedIn" then
        TriggerCallback("tiktok:isLoggedIn", callback)
        

    elseif action == "getProfile" then
        TriggerCallback("tiktok:getProfile", callback, data.username)
        
    elseif action == "updateProfile" then
        TriggerCallback("tiktok:updateProfile", callback, data.data)
        
    elseif action == "changeDisplayName" then
        TriggerCallback("tiktok:changeDisplayName", callback, data.newDisplayName)
    
    elseif action == "changeUsername" then
        TriggerCallback("tiktok:changeUsername", callback, data.newUsername)
        
    elseif action == "searchAccounts" then
        TriggerCallback("tiktok:searchAccounts", callback, data.query, data.page)
    
    elseif action == "toggleFollow" then
        local followData = data.data
        TriggerCallback("tiktok:toggleFollow", callback, followData.username, followData.follow)
        
    elseif action == "getFollowing" then
        TriggerCallback("tiktok:getFollowing", callback, data.username, data.page)
        
    elseif action == "getFollowers" then
        TriggerCallback("tiktok:getFollowers", callback, data.username, data.page)

    elseif action == "uploadVideo" then
        local videoData = data.data

        if not videoData.src or not videoData.caption then
            return callback({
                success = false,
                error = "invalid_caption"
            })
        end
    
        if videoData.music then
            if not videoData.music.path or not videoData.music.volume then
                return callback({
                    success = false,
                    error = "invalid_music"
                })
            end
            videoData.music = json.encode(videoData.music)
        end
        

        if videoData.metadata then
            if type(videoData.metadata) == "table" then
                local isEmpty = true
                for _ in pairs(videoData.metadata) do
                    isEmpty = false
                    break
                end
                
                if isEmpty then
                    videoData.metadata = nil
                else
                    videoData.metadata = json.encode(videoData.metadata)
                end
            else
                videoData.metadata = nil
            end
        end
        
        print('Dang chay uploadVideo')
        TriggerCallback("tiktok:uploadVideo", callback, videoData)
        
    elseif action == "deleteVideo" then
        TriggerCallback("tiktok:deleteVideo", callback, data.id)
        
    elseif action == "togglePinnedVideo" then
        TriggerCallback("tiktok:togglePinnedVideo", callback, data.id, data.toggle)
        
    elseif action == "getVideos" then
        TriggerCallback("tiktok:getVideos", function(videos)

            for i = 1, #videos do
                videos[i] = formatVideoData(videos[i])
            end
            callback(videos)
        end, data.data, data.page or 0)
        
    elseif action == "getVideo" then
        TriggerCallback("tiktok:getVideo", function(result)
            if result.video then
                result.video = formatVideoData(result.video)
            end
            callback(result)
        end, data.id)
        
    elseif action == "setViewed" then
        TriggerServerEvent("phone:tiktok:setViewed", data.id)
        callback("ok")

    elseif action == "toggleLike" then
        TriggerCallback("tiktok:toggleVideoAction", callback, "like", data.id, data.toggle)
        
    elseif action == "toggleSave" then
        TriggerCallback("tiktok:toggleVideoAction", callback, "save", data.id, data.toggle)

    elseif action == "postComment" then
        local commentData = data.data

        if not commentData or not commentData.id or not commentData.comment or commentData.comment == "" then
            return callback({ success = false, error = "invalid_comment_data" })
        end

        TriggerCallback("tiktok:postComment", function(result)
            callback(result)
        end, commentData.id, commentData.replyTo, commentData.comment)
        
    elseif action == "getComments" then
        local commentData = data.data

        if not commentData or not commentData.id then
            return callback({ success = false, error = "invalid_params" })
        end

        local sortBy = data.sortBy or "newest"
        local page = data.page or 0
        local getReplies = commentData.replyTo and commentData.replyTo ~= "" and commentData.replyTo ~= nil

        TriggerCallback("tiktok:getComments", function(result)
            if result and result.success and result.comments then
                local processedComments = result.comments

                if processedComments and type(processedComments) == "table" then
                    for i = 1, #processedComments do
                        if processedComments[i] and type(processedComments[i]) == "table" then

                            processedComments[i].liked = processedComments[i].liked == true
                            processedComments[i].verified = processedComments[i].verified == true
                            processedComments[i].pinned = processedComments[i].pinned == true


                            processedComments[i].likes = tonumber(processedComments[i].likes) or 0
                            processedComments[i].replies = tonumber(processedComments[i].replies) or 0
                        end
                    end
                end

                SendNUIMessage({
                    action = "tiktokCommentsData",
                    videoId = commentData.id,
                    comments = processedComments,
                    getReplies = getReplies,
                    replyTo = commentData.replyTo,
                    page = page
                })

                callback(processedComments)
            else
                callback({ success = false, error = result and result.error or "server_error" })
            end
        end, commentData.id, commentData.replyTo, page, sortBy, getReplies)

    elseif action == "getReplies" then
        local commentId = data.commentId
        local page = data.page or 0

        if not commentId or commentId == "" then
            return callback({ success = false, error = "invalid_comment_id" })
        end

        TriggerCallback("tiktok:getReplies", function(result)
            if result and result.success and result.replies then
                SendNUIMessage({
                    action = "tiktokRepliesData",
                    commentId = commentId,
                    replies = result.replies,
                    page = page
                })


                callback({
                    success = true,
                    replies = result.replies,
                    commentId = commentId,
                    page = page
                })
            else
                callback({ success = false, error = result and result.error or "server_error" })
            end
        end, commentId, page)
        
    elseif action == "deleteComment" then
        TriggerCallback("tiktok:deleteComment", callback, data.id, data.videoId)

    elseif action == "deleteReply" then

        TriggerCallback("tiktok:getCommentVideoId", function(videoId)
            if videoId then
                TriggerCallback("tiktok:deleteComment", callback, data.id, videoId)
            else
                callback({ success = false, error = "parent_not_found" })
            end
        end, data.parentCommentId)

    elseif action == "setPinnedComment" then
        TriggerCallback("tiktok:setPinnedComment", callback, data.commentId, data.videoId)
        
    elseif action == "toggleLikeComment" then
        TriggerCallback("tiktok:toggleLikeComment", callback, data.id, data.toggle)
        

    elseif action == "getRecentMessages" then
        TriggerCallback("tiktok:getRecentMessages", callback)
        
    elseif action == "getMessages" then
        TriggerCallback("tiktok:getMessages", callback, data.id, data.page)
        
    elseif action == "sendMessage" then
        if not CanInteract() then
            return callback(false)
        end
        TriggerCallback("tiktok:sendMessage", callback, data.data)
        
    elseif action == "getChannelId" then
        TriggerCallback("tiktok:getChannelId", callback, data.username)
        
    elseif action == "getNotifications" then
        TriggerCallback("tiktok:getNotifications", callback, data.page)
        
    elseif action == "getUnreadMessages" then
        TriggerCallback("tiktok:getUnreadMessages", callback)
        
    elseif action == "clearUnreadMessages" then
        TriggerServerEvent("phone:tiktok:clearUnreadMessages", data.id)

    elseif action == "deleteMessage" then
        TriggerCallback("tiktok:deleteMessage", callback, data.id)
    end
end)

RegisterNetEvent("phone:tiktok:updateFollowers", function(username, method)
    SendReactMessage("tiktok:updateFollowers", {
        username = username,
        method = method
    })
end)

RegisterNetEvent("phone:tiktok:updateFollowing", function(username, method)
    SendReactMessage("tiktok:updateFollowing", {
        username = username,
        method = method
    })
end)

RegisterNetEvent("phone:tiktok:updateVideoStats", function(statType, videoId, method, count)
    local updateData = {
        id = videoId,
        method = method,
        count = count
    }

    if statType == "like" then
        SendReactMessage("tiktok:updateLikes", updateData)
    elseif statType == "save" then
        SendReactMessage("tiktok:updateSaves", updateData)
    elseif statType == "comment" then
        SendReactMessage("tiktok:updateComments", updateData)
    end
end)

RegisterNetEvent("phone:tiktok:updateCommentStats", function(statType, commentId, method)
    if statType == "reply" then
        SendReactMessage("tiktok:updateReplies", {
            id = commentId,
            method = method
        })
    elseif statType == "like" then
        SendReactMessage("tiktok:updateCommentLikes", {
            id = commentId,
            method = method
        })
    end
end)

RegisterNetEvent("phone:tiktok:newComment", function(commentData, videoId)

    SendNUIMessage({
        action = "tiktokNewComment",
        comment = commentData,
        videoId = videoId
    })
end)

RegisterNetEvent("phone:tiktok:receivedMessage", function(messageData)
    SendReactMessage("tiktok:receivedMessage", messageData)
end)

RegisterNetEvent("phone:tiktok:messageSent", function(messageData)
    SendReactMessage("tiktok:messageSent", messageData)
end)

RegisterNetEvent("phone:tiktok:updateInbox", function(data)
    SendReactMessage("tiktok:updateInbox", data)
end)

RegisterNetEvent("phone:tiktok:messageDeleted", function(data)
    SendReactMessage("tiktok:messageDeleted", data)
end)


RegisterNetEvent("phone:tiktok:newVideo", function(videoData)
    TriggerEvent("lb-phone:trendy:newPost", videoData)
end)