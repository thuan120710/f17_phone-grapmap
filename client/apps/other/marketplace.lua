



RegisterNUICallback("MarketPlace", function(data, callback)
    local action = data.action
    
    debugprint("MarketPlace:" .. (action or ""))
    
    if action == "getPosts" then

        local posts = AwaitCallback("marketplace:getPosts", data)
        

        for i = 1, #posts do
            local post = posts[i]
            if post.attachments then
                post.attachments = json.decode(post.attachments)
            end
        end
        
        callback(posts)
        
    elseif action == "sendPost" then

        TriggerCallback("marketplace:createPost", callback, data.data)
        
    elseif action == "deletePost" then

        TriggerCallback("marketplace:deletePost", callback, data.id)
    end
end)


RegisterNetEvent("phone:marketplace:newPost", function(postData)

    TriggerEvent("lb-phone:marketplace:newPost", postData)
    

    SendReactMessage("marketPlace:newPost", postData)
end)