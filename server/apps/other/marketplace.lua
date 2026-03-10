


local POSTS_PER_PAGE = 15


local function GetMarketplacePosts(page, filters)
    if not page then
        page = 0
    end
    
    local params = {}
    local whereConditions = {}
    

    if filters and filters.search then
        table.insert(whereConditions, "(title LIKE ? OR description LIKE ?)")
        table.insert(params, "%" .. filters.search .. "%")
        table.insert(params, "%" .. filters.search .. "%")
        

        if not filters.from then
            table.insert(whereConditions, "OR phone_number LIKE ?")
            table.insert(params, "%" .. filters.search .. "%")
        end
    end
    

    if filters and filters.from then
        local condition = "phone_number = ?"
        if #whereConditions > 0 then
            condition = "AND " .. condition
        end
        table.insert(whereConditions, condition)
        table.insert(params, filters.from)
    end
    

    local query = [[
        SELECT
            id,
            phone_number AS `number`,
            title,
            description,
            attachments,
            price,
            `timestamp`
        FROM
            phone_marketplace_posts
        {WHERE}
        ORDER BY
            `timestamp` DESC
        LIMIT ?, ?
    ]]
    

    local whereClause = ""
    if #whereConditions > 0 then
        whereClause = "WHERE " .. table.concat(whereConditions, " ")
    end
    query = query:gsub("{WHERE}", whereClause)
    

    table.insert(params, (page or 0) * POSTS_PER_PAGE)
    table.insert(params, POSTS_PER_PAGE)
    
    return MySQL.query.await(query, params)
end


BaseCallback("marketplace:getPosts", function(source, phoneNumber, data)
    return GetMarketplacePosts(data.page, {
        from = data.from,
        search = data.query
    })
end)


BaseCallback("marketplace:createPost", function(source, phoneNumber, postData)
    local title = postData.title
    local description = postData.description
    local attachments = postData.attachments
    local price = postData.price
    

    if not (title and description and attachments and price) or price < 0 then
        return false
    end
    

    if ContainsBlacklistedWord(source, "MarketPlace", title) or 
       ContainsBlacklistedWord(source, "MarketPlace", description) then
        return false
    end
    

    local postId = MySQL.insert.await("INSERT INTO phone_marketplace_posts (phone_number, title, description, attachments, price) VALUES (?, ?, ?, ?, ?)", {
        phoneNumber,
        title,
        description,
        json.encode(attachments),
        price
    })
    
    if not postId then
        return false
    end
    

    postData.number = phoneNumber
    postData.id = postId
    

    TriggerClientEvent("phone:marketplace:newPost", -1, postData)
    

    TriggerEvent("lb-phone:marketplace:newPost", postData)
    

    Log("Marketplace", source, "info", 
        L("BACKEND.LOGS.MARKETPLACE_NEW_TITLE"),
        L("BACKEND.LOGS.MARKETPLACE_NEW_DESCRIPTION", {
            seller = FormatNumber(phoneNumber),
            title = title,
            price = price,
            description = description,
            attachments = json.encode(attachments),
            id = postId
        })
    )
    
    return postId
end)


BaseCallback("marketplace:deletePost", function(source, phoneNumber, postId)
    local isAdmin = IsAdmin(source)
    local params = {postId}
    local query = "DELETE FROM phone_marketplace_posts WHERE id = ?"
    

    if not isAdmin then
        query = query .. " AND phone_number = ?"
        table.insert(params, phoneNumber)
    end
    
    local deleted = MySQL.update.await(query, params)
    
    if deleted > 0 then

        Log("Marketplace", source, "error",
            L("BACKEND.LOGS.MARKETPLACE_DELETED"),
            string.format("**ID**: %s", postId)
        )
        return true
    end
    
    return false
end)
