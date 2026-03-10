



local activeAccounts = {}


local supportedApps = {
    Twitter = true,
    Instagram = true,
    Mail = true,
    TikTok = true,
    DarkChat = true
}


local appNameMapping = {
    instapic = "Instagram",
    birdy = "Twitter",
    trendy = "TikTok",
    darkchat = "DarkChat",
    mail = "Mail"
}


for appName, _ in pairs(supportedApps) do
    activeAccounts[appName] = {}
end

BaseCallback("accountSwitcher:switchAccount", function(source, phoneNumber, appName, username)

    if appName == "Instagram" or appName == "TikTok" then
        return false
    end
    

    if not supportedApps[appName] then
        return false
    end
    

    local isLoggedIn = MySQL.scalar.await("SELECT TRUE FROM phone_logged_in_accounts WHERE phone_number = ? AND app = ? AND username = ?", {
        phoneNumber, appName, username
    })
    
    if not isLoggedIn then
        print(string.format("Possible abuse? %s (%i) tried to switch to an account they aren't logged into.", GetPlayerName(source), source))
        return false
    end
    

    local updated = MySQL.update.await("UPDATE phone_logged_in_accounts SET `active` = (username = ?) WHERE phone_number = ? AND app = ?", {
        username, phoneNumber, appName
    })
    
    if updated > 0 then

        activeAccounts[appName][phoneNumber] = username
        

        TriggerEvent("phone:loggedInToAccount", appName, phoneNumber, username)
    end
    
    return updated > 0
end)

BaseCallback("accountSwitcher:getAccounts", function(source, phoneNumber, appName)

    if appName == "TikTok" then
        return {}
    end
    

    if not supportedApps[appName] then
        return {}
    end
    

    return MySQL.query.await("SELECT username FROM phone_logged_in_accounts WHERE phone_number = ? AND app = ?", {
        phoneNumber, appName
    })
end)

function AddLoggedInAccount(phoneNumber, appName, username)
    assert(supportedApps[appName], "Invalid app: " .. appName)
    assert(type(phoneNumber) == "string", "Invalid phone number. Expected string.")
    assert(type(username) == "string", "Invalid username. Expected string.")
    

    MySQL.update.await("UPDATE phone_logged_in_accounts SET `active` = 0 WHERE phone_number = ? AND app = ? AND username != ?", {
        phoneNumber, appName, username
    })
    

    local updated = MySQL.update.await("INSERT INTO phone_logged_in_accounts (phone_number, app, username, active) VALUES (?, ?, ?, 1) ON DUPLICATE KEY UPDATE active = 1", {
        phoneNumber, appName, username
    })
    
    if updated > 0 then

        activeAccounts[appName][phoneNumber] = username
        

        TriggerEvent("phone:loggedInToAccount", appName, phoneNumber, username)
    end
    
    return updated > 0
end


function RemoveLoggedInAccount(phoneNumber, appName, username)
    assert(supportedApps[appName], "Invalid app: " .. appName)
    assert(type(phoneNumber) == "string", "Invalid phone number. Expected string.")
    assert(type(username) == "string", "Invalid username. Expected string.")
    

    local deleted = MySQL.update.await("DELETE FROM phone_logged_in_accounts WHERE phone_number = ? AND app = ? AND username = ?", {
        phoneNumber, appName, username
    })
    
    if deleted > 0 then

        if activeAccounts[appName][phoneNumber] == username then
            activeAccounts[appName][phoneNumber] = nil
        end
        

        TriggerEvent("phone:loggedOutFromAccount", appName, username, phoneNumber)
    end
    
    return deleted > 0
end


function GetLoggedInAccount(phoneNumber, appName, skipCache)
    assert(supportedApps[appName], "Invalid app: " .. appName)
    assert(type(phoneNumber) == "string", "Invalid phone number. Expected string.")
    

    if activeAccounts[appName][phoneNumber] then
        return activeAccounts[appName][phoneNumber]
    end
    

    local username = MySQL.scalar.await("SELECT username FROM phone_logged_in_accounts WHERE phone_number = ? AND app = ? AND active = 1", {
        phoneNumber, appName
    })
    

    if username and not skipCache then
        debugprint("AccountSwitcher: Setting cache for " .. phoneNumber .. ", logged in as " .. username .. " on " .. appName)
        activeAccounts[appName][phoneNumber] = username
    end
    
    return username or false
end


function GetLoggedInNumbers(appName, username)
    assert(supportedApps[appName], "Invalid app: " .. appName)
    assert(type(username) == "string", "Invalid username. Expected string.")
    
    local results = MySQL.query.await("SELECT phone_number FROM phone_logged_in_accounts WHERE app = ? AND username = ?", {
        appName, username
    })
    
    if not results then
        return {}
    end
    
    local phoneNumbers = {}
    for i = 1, #results do
        phoneNumbers[#phoneNumbers + 1] = results[i].phone_number
    end
    
    return phoneNumbers
end


function GetActiveAccounts(appName)
    return activeAccounts[appName] or {}
end


function ClearActiveAccountsCache(appName, username, exceptPhoneNumber)
    assert(supportedApps[appName], "Invalid app: " .. appName)
    assert(type(username) == "string", "Invalid username. Expected string.")
    
    for phoneNumber, cachedUsername in pairs(activeAccounts[appName]) do
        if cachedUsername == username and phoneNumber ~= exceptPhoneNumber then
            activeAccounts[appName][phoneNumber] = nil
        end
    end
end


exports("GetSocialMediaUsername", function(phoneNumber, clientAppName)
    assert(type(phoneNumber) == "string", "Invalid phone number. Expected string.")
    assert(type(clientAppName) == "string", "Invalid app. Expected string.")
    assert(appNameMapping[clientAppName], "Invalid app: " .. clientAppName)
    
    return GetLoggedInAccount(phoneNumber, appNameMapping[clientAppName], true)
end)


AddEventHandler("playerDropped", function()
    local phoneNumber = GetEquippedPhoneNumber(source)
    if not phoneNumber then
        return
    end
    

    for appName, appCache in pairs(activeAccounts) do
        if appCache[phoneNumber] then
            appCache[phoneNumber] = nil
            debugprint("AccountSwitcher: Player dropped, logging out " .. phoneNumber .. " from " .. appName)
        end
    end
end)
