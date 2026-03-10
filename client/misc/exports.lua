



exports("ToggleHomeIndicator", function(show)
    SendReactMessage("toggleShowHomeIndicator", show)
end)


exports("ToggleLandscape", function(enabled)
    SendReactMessage("toggleLandscape", enabled)
end)


exports("OpenApp", function(appName, metadata)
    SendReactMessage("setApp", {
        name = appName,
        metadata = metadata
    })
end)


exports("CloseApp", function(options)
    if not options then
        options = {}
    end
    
    debugprint("CloseApp: " .. (options.app or "nil") .. ", closeCompletely: " .. tostring(options.closeCompletely))
    
    SendReactMessage("closeApp", {
        app = options.app or nil,
        closeCompletely = options.closeCompletely == true
    })
end)
