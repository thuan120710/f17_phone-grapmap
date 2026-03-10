


RegisterNetEvent("lb-phone:customApp", function(appName)
    local source = source
    local customApp = Config.CustomApps[appName]
    

    if customApp and customApp.onServerUse then
        customApp.onServerUse(source)
    end
end)
