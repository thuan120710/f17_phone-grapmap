
local supportedApps = {
    twitter = true,
    instagram = true,
    tiktok = true
}


local appNameMapping = {
    birdy = "twitter",
    instapic = "instagram",
    trendy = "tiktok"
}


local appDisplayNames = {
    twitter = "Twitter",
    instagram = "Instagram",
    tiktok = "TikTok"
}

function ToggleVerified(appName, username, verified)
    assert(type(appName) == "string", "Invalid app")
    

    appName = appName:lower()
    if not supportedApps[appName] then
        appName = tostring(appNameMapping[appName])
    end
    
    assert(supportedApps[appName], "Invalid app")
    assert(type(username) == "string", "Invalid username")
    

    TriggerEvent("lb-phone:toggleVerified", appName, username, verified)
    

    local updated = MySQL.Sync.execute(string.format("UPDATE phone_%s_accounts SET verified=@verified WHERE username=@username", appName), {
        ["@username"] = username,
        ["@verified"] = verified
    })
    
    local success = updated > 0
    

    if success and verified and appDisplayNames[appName] then
        local phoneNumbers = MySQL.query.await("SELECT phone_number FROM phone_logged_in_accounts WHERE app = ? AND username = ? AND `active` = 1", {
            appName, username
        })
        
        for i = 1, #phoneNumbers do
            local phoneNumber = phoneNumbers[i].phone_number
            SendNotification(phoneNumber, {
                app = appDisplayNames[appName],
                title = L("BACKEND.MISC.VERIFIED")
            })
        end
    end
    
    return success
end


exports("ToggleVerified", ToggleVerified)

exports("IsVerified", function(appName, username)
    assert(type(appName) == "string", "Invalid app")
    

    appName = appName:lower()
    if not supportedApps[appName] then
        appName = tostring(appNameMapping[appName])
    end
    
    assert(supportedApps[appName], "Invalid app")
    assert(type(username) == "string", "Invalid username")
    
    local verified = MySQL.Sync.fetchScalar(string.format("SELECT verified FROM phone_%s_accounts WHERE username=@username", appName), {
        ["@username"] = username
    })
    
    return verified or false
end)

local usernameFields = {
    twitter = "username",
    instagram = "username", 
    tiktok = "username",
    mail = "address",
    darkchat = "username"
}


function ChangePassword(appName, username, newPassword)
    assert(type(appName) == "string", "Invalid app")
    

    appName = appName:lower()
    if not usernameFields[appName] then
        appName = tostring(appNameMapping[appName])
    end
    
    assert(usernameFields[appName], "Invalid app")
    assert(type(username) == "string", "Invalid username")
    assert(type(newPassword) == "string", "Invalid password")
    

    local updated = MySQL.Sync.execute(string.format("UPDATE phone_%s_accounts SET password=@password WHERE %s=@username", appName, usernameFields[appName]), {
        ["@username"] = username,
        ["@password"] = GetPasswordHash(newPassword)
    })
    
    if updated <= 0 then
        return false
    end
    

    MySQL.update("DELETE FROM phone_logged_in_accounts WHERE app = ? AND username = ?", {
        appName, username
    })
    
    return true
end


exports("ChangePassword", ChangePassword)

exports("GetEquippedPhoneNumber", function(sourceOrIdentifier)
    if type(sourceOrIdentifier) == "number" then
        return GetEquippedPhoneNumber(sourceOrIdentifier)
    end
    
    local source = nil
    if GetSourceFromIdentifier then
        source = GetSourceFromIdentifier(sourceOrIdentifier)
    end
    
    if source then
        return GetEquippedPhoneNumber(source)
    end
    
    return MySQL.scalar.await("SELECT phone_number FROM phone_phones WHERE id = ?", {
        sourceOrIdentifier
    })
end)
