-- App Store for LB Phone
-- Handles app purchases and store functionality

-- Register NUI callback for App Store actions
RegisterNUICallback("AppStore", function(data, callback)
    if not currentPhone then
        return
    end
    
    local action = data.action
    debugprint("AppStore:" .. (action or ""))
    
    if action == "buyApp" then
        -- Purchase app from store
        TriggerCallback("appstore:buyApp", callback, data.price)
    end
end)
