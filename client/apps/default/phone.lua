-- Phone app for LB Phone
-- Handles calling system, contacts, voicemail, and custom number management

InExportCall = false
local isVideoCall = false
local currentCallId = nil
local isInCustomCall = false
local currentCustomCall = nil
local callStartTime = 0
local isCallAnswered = false
local customNumbers = {}

-- End custom call and log call duration
local function endCustomCall()
    debugprint("EndCustomCall triggered")
    
    if currentCustomCall then
        local duration = math.floor((GetGameTimer() - callStartTime) / 1000 + 0.5)
        debugprint("Custom call to", currentCustomCall.number, "ended after", duration, "seconds", "answered:", isCallAnswered)
        
        TriggerServerEvent("phone:logCall", currentCustomCall.number, duration)
    end
    
    isInCustomCall = false
    currentCustomCall = nil
    currentCallId = nil
    callStartTime = 0
    isCallAnswered = false
    
    SetPhoneAction("default")
    SendReactMessage("call:endCall")
    
    if not phoneOpen then
        PlayCloseAnim()
    end
end

-- Start custom call with specified number
local function startCustomCall(number)
    local customData = customNumbers[number]
    if not customData then
        return false
    end
    
    local callId = "CUSTOM_NUMBER_" .. math.random(9999999)
    isInCustomCall = true
    currentCallId = callId
    currentCustomCall = customData
    callStartTime = GetGameTimer()
    isCallAnswered = false
    
    Citizen.CreateThreadNow(function()
        customData.onCall({
            id = callId,
            accept = function()
                if not isCallAnswered and currentCallId == callId then
                    isCallAnswered = true
                    SetPhoneAction("call")
                    SendReactMessage("call:connected")
                end
            end,
            deny = function()
                if currentCallId == callId then
                    endCustomCall()
                end
            end,
            setName = function(name)
                if currentCallId == callId then
                    SendReactMessage("call:setContactData", {name = name})
                end
            end,
            hasEnded = function()
                return currentCallId ~= callId
            end
        })
    end)
    
    return true
end

-- Handle custom call actions
local function handleCustomCallAction(action)
    if not currentCustomCall then
        return
    end
    
    if action == "end" then
        if currentCustomCall.onEnd then
            Citizen.CreateThreadNow(currentCustomCall.onEnd)
        end
        endCustomCall()
        return
    end
    
    -- Handle keypad input
    if action:find("keypad_") then
        if not currentCustomCall.onKeypad then
            return
        end
        
        local key = action:sub(8)
        if not key then
            return
        end
        
        Citizen.CreateThreadNow(function()
            currentCustomCall.onKeypad(key)
        end)
        return
    end
    
    -- Handle other custom actions
    if currentCustomCall.onAction then
        currentCustomCall.onAction(action)
    end
end

-- Register NUI callback for Phone actions
RegisterNUICallback("Phone", function(data, callback)
    if not currentPhone then
        return
    end
    
    local action = data.action
    debugprint("Phone:" .. (action or ""))
    
    if action == "getContacts" then
        -- Get contacts with company contacts if enabled
        TriggerCallback("getContacts", function(contacts)
            if Config.Companies.Enabled then
                for company, contactData in pairs(Config.Companies.Contacts) do
                    contacts[#contacts + 1] = {
                        firstname = contactData.name,
                        avatar = contactData.photo,
                        company = company
                    }
                end
            end
            callback(contacts)
        end)
        
    elseif action == "toggleFavourite" then
        -- Toggle contact favourite status
        TriggerCallback("toggleFavourite", callback, data.number, data.favourite)
        
    elseif action == "toggleBlock" then
        -- Toggle contact blocked status
        TriggerCallback("toggleBlock", callback, data.number, data.blocked)
        
    elseif action == "removeContact" then
        -- Remove contact
        TriggerCallback("removeContact", callback, data.number)
        
    elseif action == "updateContact" then
        -- Update existing contact
        TriggerCallback("updateContact", callback, data.data)
        
    elseif action == "saveContact" then
        -- Save new contact
        TriggerCallback("saveContact", callback, data.data)
        
    elseif action == "getRecent" then
        -- Get recent calls
        TriggerCallback("getRecentCalls", callback, data.missed == true, data.lastId)
        
    elseif action == "getBlockedNumbers" then
        -- Get blocked numbers list
        TriggerCallback("getBlockedNumbers", function(blockedData)
            local blockedNumbers = {}
            for i, blocked in pairs(blockedData) do
                blockedNumbers[i] = blocked.number
            end
            callback(blockedNumbers)
        end)
        
    elseif action == "toggleMute" then
        -- Toggle call mute
        if not currentCallId then
            return callback(false)
        elseif currentCustomCall then
            handleCustomCallAction(data.toggle and "mute" or "unmute")
            return callback(data.toggle)
        end
        
        -- FIXED: Use new pma-voice mute function
        -- Player stays in call channel and can hear others
        -- But mic is muted so others can't hear them
        local success = pcall(function()
            if Config.Voice.System == "pma" then
                exports["pma-voice"]:setCallMuted(data.toggle)
            elseif Config.Voice.System == "mumble" then
                -- Mumble doesn't have mute, use workaround
                if data.toggle then
                    MumbleSetAudioInputIntent(0)
                else
                    MumbleSetAudioInputIntent(1)
                end
            end
        end)
        
        if not success then
            debugprint("Failed to toggle mute in voice system")
        end
        
        -- Update mute state on server for hearNearby logic
        TriggerCallback("toggleCallMute", callback, data.toggle)
        
    elseif action == "toggleSpeaker" then
        -- Toggle speaker mode
        if not currentCallId then
            return callback(false)
        elseif currentCustomCall then
            handleCustomCallAction(data.toggle and "enable_speaker" or "disable_speaker")
            return callback(data.toggle)
        end
        
        TriggerServerEvent("phone:phone:toggleSpeaker", data.toggle)
        ToggleSpeaker(data.toggle)
        callback(data.toggle)
        
    elseif action == "sendVoicemail" then
        -- Send voicemail
        TriggerCallback("sendVoicemail", callback, data.data)
        
    elseif action == "getVoiceMails" then
        -- Get voicemails
        TriggerCallback("getRecentVoicemails", callback, data.page)
        
    elseif action == "deleteVoiceMail" then
        -- Delete voicemail
        TriggerCallback("deleteVoiceMail", callback, data.id)
        
    elseif action == "keypad" then
        -- Handle keypad input during call
        callback("ok")
        if currentCustomCall then
            handleCustomCallAction("keypad_" .. data.key)
        end
    end
    
    if action == "call" then
        -- Handle call initiation
        if startCustomCall(data.number) then
            return callback("CUSTOM_NUMBER")
        end
        
        -- Check company call restrictions
        if data.company then
            if not Config.Companies.Enabled or data.videoCall then
                return
            end
            
            local companyContact = Config.Companies.Contacts[data.company]
            if not companyContact then
                -- Check if it's a valid service company
                local isValidService = false
                for i = 1, #Config.Companies.Services do
                    if Config.Companies.Services[i].job == data.company then
                        isValidService = true
                        break
                    end
                end
                if not isValidService then
                    return
                end
            end
        end
        
        isVideoCall = data.videoCall
        TriggerCallback("call", callback, data)
        
    elseif action == "answerCall" then
        -- Answer incoming call
        if IsInCall() then
            debugprint("answerCall: Already in call")
            return
        end
        
        -- End live streams if active
        if IsLive() then
            debugprint("answerCall: Ending live")
            TriggerCallback("instagram:endLive")
        elseif IsWatchingLive() then
            debugprint("answerCall: Leaving live")
            SendReactMessage("instagram:liveEnded", IsWatchingLive())
        end
        
        debugprint("Answering call", data.callId)
        TriggerCallback("answerCall", callback, data.callId)
        callback("ok")
        
    elseif action == "endCall" then
        -- End current call
        EndCall()
        callback("ok")
        
    elseif action == "flipCamera" then
        -- Flip camera during video call
        ToggleSelfieCam(not IsSelfieCam())
        
    elseif action == "requestVideoCall" then
        -- Request video call upgrade
        TriggerCallback("requestVideoCall", callback, data.callId, data.peerId)
        
    elseif action == "answerVideoRequest" then
        -- Answer video call request
        TriggerCallback("answerVideoRequest", callback, data.callId, data.accept)
        if data.accept then
            isVideoCall = true
            EnableWalkableCam()
        end
        
    elseif action == "stopVideoCall" then
        -- Stop video call
        TriggerCallback("stopVideoCall", callback, data.callId)
    end
end)

-- End call function
function EndCall()
    TriggerServerEvent("phone:endCall")
    if currentCustomCall then
        handleCustomCallAction("end")
    end
end

-- Handle incoming call
RegisterNetEvent("phone:phone:setCall", function(callData)
    if not HasPhoneItem(currentPhone) then
        debugprint("no phone, not showing call")
        return
    end
    
    if phoneDisabled then
        debugprint("phone is disabled, not showing call")
        return
    end
    
    if currentCustomCall or isInCustomCall then
        debugprint("in a (custom?) call", tostring(currentCustomCall), tostring(isInCustomCall))
        return
    end
    
    if IsPedDeadOrDying(PlayerPedId(), false) then
        debugprint("player is dead, not showing call")
        return
    elseif CanOpenPhone and not CanOpenPhone() then
        debugprint("can't open phone, not showing call")
        return
    end
    
    isVideoCall = callData.videoCall
    SendReactMessage("incomingCall", callData)
end)

-- Enable export call mode
RegisterNetEvent("phone:phone:enableExportCall", function()
    InExportCall = true
end)

-- Connect to call
RegisterNetEvent("phone:phone:connectCall", function(callId, skipUI)
    debugprint("phone:phone:connectCall", callId, skipUI)
    isInCustomCall = true
    currentCallId = callId
    AddToCall(callId)
    
    if skipUI then
        return
    end
    
    SetPhoneAction("call")
    SendReactMessage("call:connected")
    
    if isVideoCall then
        EnableWalkableCam()
    end
end)

-- End call from server
RegisterNetEvent("phone:phone:endCall", function()
    debugprint("phone:phone:endCall")
    local wasInCall = isInCustomCall
    isInCustomCall = false
    isVideoCall = false
    
    SetPhoneAction("default")
    DisableWalkableCam()
    
    if not phoneOpen and wasInCall then
        debugprint("close anim")
        PlayCloseAnim()
    end
    
    RemoveFromCall(currentCallId)
    currentCallId = nil
    InExportCall = false
    SendReactMessage("call:endCall")
end)

-- Handle user unavailable
RegisterNetEvent("phone:phone:userUnavailable", function()
    debugprint("phone:phone:userUnavailable")
    SendReactMessage("call:userUnavailable")
end)

-- Handle user busy
RegisterNetEvent("phone:phone:userBusy", function()
    debugprint("phone:phone:userBusy")
    SendReactMessage("call:userBusy")
end)

-- Check if player is in call
function IsInCall()
    return isInCustomCall
end

-- Export IsInCall function
exports("IsInCall", IsInCall)

-- Export function to add contact
exports("AddContact", function(contact)
    assert(type(contact) == "table", "contact must be a table")
    assert(type(contact.number) == "string", "contact.number must be a string")
    assert(type(contact.firstname) == "string", "contact.firstname must be a string")
    
    local success = AwaitCallback("saveContact", contact)
    if success then
        SendReactMessage("phone:contactAdded", contact)
    end
    return success
end)

-- Handle video call request
RegisterNetEvent("phone:phone:videoRequested", function(callId)
    debugprint("phone:phone:videoRequested", callId)
    SendReactMessage("call:videoRequested", callId)
end)

-- Handle video call request answer
RegisterNetEvent("phone:phone:videoRequestAnswered", function(accepted)
    debugprint("phone:phone:videoRequestAnswered", accepted)
    SendReactMessage("call:videoRequestAnswered", accepted)
    if accepted then
        isVideoCall = true
        EnableWalkableCam()
    end
end)

-- Handle video call stop
RegisterNetEvent("phone:phone:stopVideoCall", function()
    debugprint("phone:phone:stopVideoCall")
    SendReactMessage("call:stopVideoCall")
    isVideoCall = false
    DisableWalkableCam()
end)

-- Handle contact added
RegisterNetEvent("phone:phone:contactAdded", function(contact)
    debugprint("phone:phone:contactAdded", contact)
    SendReactMessage("phone:contactAdded", contact)
end)

-- Create call function
function CreateCall(options)
    assert(type(options) == "table", "options must be a table")
    assert(options.number or options.company, "options must contain either a number or company")
    
    if not currentPhone then
        return debugprint("no phone")
    end
    
    if options.company then
        if not Config.Companies.Enabled then
            return debugprint("company calls are disabled in config")
        end
        
        local isValidCompany = false
        local companyName = options.company
        
        -- Check if it's a configured company contact
        local companyContact = Config.Companies.Contacts[options.company]
        if companyContact then
            companyName = companyContact.name
            isValidCompany = true
        else
            -- Check if it's a valid service company
            for i = 1, #Config.Companies.Services do
                local service = Config.Companies.Services[i]
                if service.job == options.company then
                    isValidCompany = true
                    companyName = service.name
                    break
                end
            end
        end
        
        if not isValidCompany then
            return debugprint("invalid company")
        end
        
        debugprint("CreateCall: company", options)
        SendReactMessage("call", {
            company = options.company,
            companylabel = companyName,
            hideCallerId = options.hideNumber == true
        })
    else
        debugprint("CreateCall: number", options)
        SendReactMessage("call", {
            number = options.number,
            videoCall = options.videoCall == true,
            hideCallerId = options.hideNumber == true
        })
    end
end

-- Export CreateCall function
exports("CreateCall", CreateCall)

-- Export function to create custom number
exports("CreateCustomNumber", function(number, data)
    local resource = GetInvokingResource()
    
    assert(type(number) == "string", "number must be a string")
    assert(type(data) == "table", "data must be a table")
    assert(type(data.onCall) == "function", "data.onCall must be a function")
    
    if customNumbers[number] then
        return false, "Number already exists"
    end
    
    customNumbers[number] = {
        resource = resource,
        number = number,
        onCall = data.onCall,
        onEnd = data.onEnd,
        onAction = data.onAction,
        onKeypad = data.onKeypad
    }
    
    return true
end)

-- Export function to remove custom number
exports("RemoveCustomNumber", function(number)
    local resource = GetInvokingResource()
    
    assert(type(number) == "string", "number must be a string")
    
    if not customNumbers[number] then
        return false, "Number does not exist"
    end
    
    local numberData = customNumbers[number]
    if numberData.resource ~= resource then
        return false, "Number was not created by " .. resource
    end
    
    customNumbers[number] = nil
    return true
end)

-- Export function to end custom call
exports("EndCustomCall", function()
    if currentCustomCall then
        endCustomCall()
        return true
    end
    return false
end)

-- Clean up custom numbers when resource stops
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        return
    end
    
    for number, data in pairs(customNumbers) do
        if data.resource == resourceName then
            debugprint("Removed custom number", number, "due to resource stopping")
            if currentCustomCall == data then
                handleCustomCallAction("end")
            end
            customNumbers[number] = nil
        end
    end
end)
