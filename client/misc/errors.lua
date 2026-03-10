



RegisterNUICallback("logError", function(data, callback)
    local uiPage = GetResourceMetadata(GetCurrentResourceName(), "ui_page", 0)
    

    if uiPage == "ui/dist/index.html" then
        local errorMessage = data.error or "No error message"
        local stackTrace = data.stack or "No stack"
        local componentStack = data.componentStack or "No component stack"
        

        TriggerServerEvent("phone:logError", errorMessage, stackTrace, componentStack)
    end
    
    local wasPhoneOpen = phoneOpen
    

    OnDeath()
    

    if wasPhoneOpen then
        debugprint("Opening phone due to error")
        ToggleOpen(true)
    end
    

    Wait(5000)
    

    TriggerEvent("phone:sendNotification", {
        app = "Settings",
        title = "System Crash",
        content = "Your phone crashed. Press F8 for more info."
    })
    
    callback("ok")
end)
