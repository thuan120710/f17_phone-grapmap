
local popupCallbacks = {}
local validColors = {
    blue = true,
    red = true,
    green = true,
    yellow = true
}

local componentTypes = {
    gallery = {"image"},
    gif = {"gif"},
    emoji = {"emoji"},
    camera = {"url"},
    colorpicker = {"color"},
    contactselector = {"contact"}
}


local function generateId()
    local id = math.random(999999999)
    while popupCallbacks[id] do
        id = math.random(999999999)
    end
    return id
end


RegisterNUICallback("GrabApp", function(data, callback)
    local action = data.action
    
    if not action then
        debugprint("GrabApp: invalid action")
        callback("error")
        return
    end
    
    -- Forward to grab.lua callback
    TriggerEvent("grab:handleNUICallback", data, callback)
end)

RegisterNUICallback("CustomApp", function(data, callback)
    local appName = data.app
    local action = data.action
    
    callback("ok")
    
    if not action or not appName then
        debugprint("invalid data")
        return
    end
    
    local appConfig = Config.CustomApps[appName]
    
    if action == "open" then

        if appConfig and appConfig.onServerUse then
            TriggerServerEvent("lb-phone:customApp", appName)
        end
        

        if not (appConfig and appConfig.ui) then
            if not (appConfig and appConfig.keepOpen) then
                debugprint("Closing phone due to custom app without ui")
                ToggleOpen(false)
            end
        end
        

        if appConfig and appConfig.onUse then
            Citizen.CreateThreadNow(function()
                appConfig.onUse()
            end)
        end
        

        if appConfig and appConfig.onOpen then
            Citizen.CreateThreadNow(function()
                appConfig.onOpen()
            end)
        end
        
    elseif action == "close" then
        if appConfig and appConfig.onClose then
            appConfig.onClose()
        end
        
    elseif action == "install" then
        if appConfig and appConfig.onInstall then
            appConfig.onInstall()
        end
        
    elseif action == "uninstall" then
        if appConfig and appConfig.onDelete then
            appConfig.onDelete()
        end
    end
end)

RegisterNUICallback("PopUp", function(callbackId, callback)
    local popupCallback = popupCallbacks[callbackId]
    if not popupCallback then
        return
    end
    
    callback("ok")
    popupCallback()
    popupCallbacks[callbackId] = nil
end)


RegisterNUICallback("PopUpInputChanged", function(data, callback)
    local callbackId = data.id
    local value = data.value
    local inputCallback = popupCallbacks[callbackId]
    
    if not inputCallback then
        return
    end
    
    callback("ok")
    inputCallback(value)
end)

local function setupPopup(popupData, isExport)
    assert(popupData.buttons and #popupData.buttons > 0, "You need at least one button")
    
    for _, button in pairs(popupData.buttons) do
        assert(button.title, "You need a title for each button")
        assert(validColors[button.color or "blue"], "Invalid color")
        
        if isExport then
            if button.cb then
                local callbackId = generateId()
                local originalCallback = button.cb
                popupCallbacks[callbackId] = function()
                    originalCallback(button.callbackId)
                end
                button.cb = callbackId
            end
        else
            if button.callbackId then
                local callbackId = generateId()
                popupCallbacks[callbackId] = function()
                    isExport(button.callbackId)
                end
                button.cb = callbackId
            end
        end
    end
    

    local input = popupData.input
    if input and input.onChange then
        local callbackId = generateId()
        
        if isExport then
            local originalCallback = input.onChange
            popupCallbacks[callbackId] = originalCallback
        else
            popupCallbacks[callbackId] = function(value)
                SendReactMessage("customApp:sendMessage", {
                    identifier = "any",
                    message = {
                        type = "popUpInputChanged",
                        value = value
                    }
                })
            end
        end
        
        input.onChange = callbackId
    end
    
    SendReactMessage("onComponentUse", {
        type = "popup",
        data = popupData
    })
end


RegisterNUICallback("SetPopUp", setupPopup)


exports("SetPopUp", function(popupData)
    setupPopup(popupData, true)
end)


RegisterNUICallback("ContextMenu", function(callbackId, callback)
    local contextCallback = popupCallbacks[callbackId]
    if not contextCallback then
        return
    end
    
    contextCallback()
    popupCallbacks[callbackId] = nil
    callback("ok")
end)


local function setupContextMenu(menuData, isExport)
    assert(menuData.buttons and #menuData.buttons > 0, "You need at least one button")
    
    for _, button in pairs(menuData.buttons) do
        assert(button.title, "You need a title for each button")
        assert(validColors[button.color or "blue"], "Invalid colour")
        
        if isExport then
            assert(button.cb, "You need a callback for each button")
        else
            assert(button.callbackId, "You need a callback for each button")
        end
        
        local callbackId = generateId()
        local originalCallback = button.cb
        
        popupCallbacks[callbackId] = function()
            if isExport then
                originalCallback()
            else
                isExport(button.callbackId)
            end
        end
        
        button.cb = callbackId
    end
    
    SendReactMessage("onComponentUse", {
        type = "contextmenu",
        data = menuData
    })
end


RegisterNUICallback("SetContextMenu", setupContextMenu)


exports("SetContextMenu", function(menuData)
    setupContextMenu(menuData, true)
end)


local function setupCameraComponent(cameraData, callback)
    if type(cameraData) ~= "table" or not cameraData then
        cameraData = {}
    end
    
    local promise = nil
    local wasPhoneOpen = phoneOpen
    local callbackId = generateId()
    
    cameraData.id = callbackId
    

    if not wasPhoneOpen then
        debugprint("Opening phone due to camera component")
        ToggleOpen(true)
    end
    

    if not callback then
        promise = promise.new()
    end
    
    popupCallbacks[callbackId] = function(data)
        if callback then
            callback(data.url)
        else
            promise:resolve(data.url)
        end
        

        if not wasPhoneOpen then
            debugprint("Closing phone due to camera component")
            ToggleOpen(false)
        end
    end
    
    SendReactMessage("onComponentUse", {
        type = "camera",
        data = cameraData
    })
    
    if not callback then
        return Citizen.Await(promise)
    end
end


exports("SetCameraComponent", setupCameraComponent)


local function setupContactModal(phoneNumber)
    assert(phoneNumber, "You need to provide a phone number")
    
    SendReactMessage("onComponentUse", {
        type = "contactmodal",
        data = phoneNumber
    })
end


RegisterNUICallback("SetContactModal", function(data, callback)
    setupContactModal(data)
    callback("ok")
end)


exports("SetContactModal", setupContactModal)


RegisterNUICallback("UsedComponent", function(data, callback)
    local callbackId = data and data.id
    
    if not callbackId or not popupCallbacks[callbackId] then
        return
    end
    
    popupCallbacks[callbackId](data)
    popupCallbacks[callbackId] = nil
    callback("ok")
end)


local function showComponent(componentData, callback)
    local componentType = componentData.component
    
    assert(componentType, "You need to specify a component")
    assert(componentTypes[componentType], "Invalid component")
    
    local callbackId = generateId()
    
    popupCallbacks[callbackId] = function(data)
        local results = {}
        for _, returnType in pairs(componentTypes[componentType]) do
            table.insert(results, data[returnType])
        end
        callback(table.unpack(results))
    end
    
    componentData.id = callbackId
    
    SendReactMessage("onComponentUse", {
        type = componentType,
        data = componentData
    })
end


RegisterNUICallback("ShowComponent", showComponent)


exports("ShowComponent", showComponent)


RegisterNUICallback("CreateCall", function(data, callback)
    CreateCall(data)
    callback("ok")
end)


RegisterNUICallback("GetSettings", function(data, callback)
    callback(settings)
end)


RegisterNUICallback("GetLocale", function(data, callback)
    callback(L(data.path, data.format))
end)


RegisterNUICallback("SendNotification", function(data, callback)

    if data and data.customData and data.customData.buttons then
        data.customData.buttons = nil
        debugprint("You cannot create notifications with buttons from the NUI.")
    end
    
    TriggerEvent("phone:sendNotification", data)
    callback(true)
end)

