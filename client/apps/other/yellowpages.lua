



RegisterNUICallback("YellowPages", function(data, callback)
    local action = data.action
    
    debugprint("Pages:" .. (action or ""))
    
    if action == "getPosts" then

        local searchData = {
            search = data.query
        }
        TriggerCallback("yellowPages:getPosts", callback, data.page, searchData)
        
    elseif action == "sendPost" then

        TriggerCallback("yellowPages:createPost", callback, data.data)
        
    elseif action == "deletePost" then

        TriggerCallback("yellowPages:deletePost", callback, data.id)
    end
end)


RegisterNetEvent("phone:yellowPages:newPost", function(postData)

    TriggerEvent("lb-phone:pages:newPost", postData)
    

    SendReactMessage("yellowPages:newPost", postData)
end)