-- TikTok Comments JavaScript Injector (Safe Version)
-- Only inject when needed, don't interfere with normal flow

-- Inject script when phone opens (safe way)
RegisterNetEvent('lb-phone:client:PhoneIsOpened', function()
    -- Send simple injection message to load comments handler
    SendNUIMessage({
        action = "loadTikTokCommentsHandler"
    })
    print("[TikTok Comments Fix] Loading comments handler...")
end)

print("[TikTok Comments Fix] Safe injector loaded")