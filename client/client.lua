local DisableControlAction = DisableControlAction
local IsNuiFocused = IsNuiFocused
local DisablePlayerFiring = DisablePlayerFiring

phoneData = nil
currentPhone = nil
settings = nil
phoneOpen = false
SavedLocations = {}
PhoneOnScreen = false

local playerData = nil
local isPlayerLoaded = false
local isFetchingPhone = false
local isConfigReceived = false

local function waitForConfig()
    if isConfigReceived then
        return
    end

    debugprint("waiting for config to be received")
    while not isConfigReceived do
        Wait(0)
    end
    debugprint("config received")
end

function FetchPhone()
    debugprint("FetchPhone triggered")

    if isFetchingPhone then
        debugprint("already fetching phone")
        return
    end

    if not isConfigReceived then
        debugprint("config has not been sent to UI yet")
        return
    end

    isFetchingPhone = true
    while not FrameworkLoaded do
        debugprint("waiting for framework to load")
        Wait(500)
    end

    debugprint("triggering phone:playerLoaded")

    local phoneNumber = nil
    if not isPlayerLoaded or not currentPhone then
        phoneNumber = AwaitCallback("playerLoaded")
        playerData = phoneNumber
        isPlayerLoaded = true
    else
        phoneNumber = playerData
    end

    debugprint("got number", phoneNumber)

    if not phoneNumber then
        debugprint("no number, checking if player has item")
        if HasPhoneItem() then
            debugprint("player has item; triggering phone:generatePhoneNumber")
            phoneNumber = AwaitCallback("generatePhoneNumber")
            debugprint("got number", phoneNumber)
        else
            debugprint("player does not have item")
        end
    end

    if not phoneNumber then
        isFetchingPhone = false
        if currentPhone then
            debugprint("no number. using SetPhone")
            SetPhone()
        end
        debugprint("no number, returning")
        return
    end

    local defaultSettings = json.decode(GetConfigFile("defaultSettings.json"))
    local latestVersion = AwaitCallback("getLatestVersion")
    local currentVersion = GetResourceMetadata(GetCurrentResourceName(), "version", 0)

    if not latestVersion then
        latestVersion = currentVersion
    end

    defaultSettings.locale = Config.DefaultLocale
    defaultSettings.version = currentVersion
    defaultSettings.latestVersion = latestVersion

    local isSetup = false
    debugprint("fetching phone data")
    local phoneInfo = AwaitCallback("getPhone", phoneNumber)
    debugprint("got phone data", json.encode(phoneInfo))

    if phoneInfo then
        if phoneInfo.settings then
            defaultSettings = phoneInfo.settings
        end

        if phoneInfo.name then
            defaultSettings.name = phoneInfo.name
        else
            defaultSettings.name = "Not set"
        end

        defaultSettings.version = currentVersion
        defaultSettings.latestVersion = latestVersion

        SavedLocations = AwaitCallback("maps:getSavedLocations")
        isSetup = phoneInfo.is_setup or false
        currentPhone = phoneNumber
        TriggerEvent('UpdateSDT', phoneNumber)

        local battery = 100
        if Config.Battery and Config.Battery.Enabled and phoneInfo.battery then
            battery = phoneInfo.battery
        end

        phoneData = {
            isSetup = isSetup,
            phoneNumber = phoneNumber,
            settings = defaultSettings,
            battery = battery
        }

        waitForConfig()

        debugprint("triggering phone:setPhoneData")
        SendReactMessage("setPhoneData", phoneData)

        TriggerEvent("lb-phone:numberChanged", phoneNumber)
        Wait(250)
    end

    settings = defaultSettings
    isFetchingPhone = false
end

function RefreshPhone(skipFetch)
    debugprint("RefreshPhone triggered")

    if isFetchingPhone then
        debugprint("phone is being fetched, waiting before refreshing")
        while isFetchingPhone do
            Wait(0)
        end
    end

    if Config.DynamicWebRTC and Config.DynamicWebRTC.Enabled then
        local webrtcCredentials = AwaitCallback("getWebRTCCredentials")

        if Config.DynamicWebRTC.RemoveStun and webrtcCredentials then
            for i = #webrtcCredentials, 1, -1 do
                if not webrtcCredentials[i].credential then
                    table.remove(webrtcCredentials, i)
                end
            end
        end

        if webrtcCredentials then
            Config.RTCConfig = Config.RTCConfig or {}
            Config.RTCConfig.iceServers = webrtcCredentials
        end
    end

    isConfigReceived = false

    local uiConfig = json.decode(GetConfigFile("config.json"))
    uiConfig.valet = {
        enabled = Config.Valet and Config.Valet.Enabled or false,
        price = Config.Valet and Config.Valet.Price or 0,
        vehicleTypes = Config.Valet and Config.Valet.VehicleTypes or { "car" }
    }

    uiConfig.locations = Config.Locations
    uiConfig.AllowExternal = Config.AllowExternal
    uiConfig.ExternalBlacklistedDomains = Config.ExternalBlacklistedDomains
    uiConfig.ExternalWhitelistedDomains = Config.ExternalWhitelistedDomains
    uiConfig.Format = Config.PhoneNumber.Format
    uiConfig.EmailDomain = Config.EmailDomain
    uiConfig.RealTime = Config.RealTime
    uiConfig.CurrencyFormat = Config.CurrencyFormat
    uiConfig.DeleteMessages = Config.DeleteMessages
    uiConfig.Battery = Config.Battery
    uiConfig.rtc = Config.RTCConfig
    uiConfig.PromoteBirdy = Config.PromoteBirdy
    uiConfig.DynamicIsland = Config.DynamicIsland
    uiConfig.SetupScreen = Config.SetupScreen
    uiConfig.MaxTransferAmount = Config.MaxTransferAmount
    uiConfig.EnableMessagePay = Config.EnableMessagePay
    uiConfig.EnableGIFs = Config.EnableGIFs
    uiConfig.GIFsFilter = Config.GIFsFilter or "low"
    uiConfig.EnableVoiceMessages = Config.EnableVoiceMessages
    uiConfig.DefaultLocale = Config.DefaultLocale
    uiConfig.DateLocale = Config.DateLocale
    uiConfig.Debug = Config.Debug
    uiConfig.TikTokTTS = Config.TrendyTTS or { { "English (US) - Female", "en_us_001" } }
    uiConfig.recordNearbyVoices = Config.Voice.RecordNearby
    uiConfig.frameColor = Config.FrameColor
    uiConfig.allowFrameColorChange = Config.AllowFrameColorChange
    uiConfig.unlockPhoneKey = Config.KeyBinds and Config.KeyBinds.UnlockPhone and Config.KeyBinds.UnlockPhone.Bind
    uiConfig.DeleteMail = Config.DeleteMail
    uiConfig.ChangePassword = Config.ChangePassword
    uiConfig.DeleteAccount = Config.DeleteAccount
    uiConfig.CustomCamera = Config.Camera and Config.Camera.Enabled or false
    uiConfig.UsernameFilter = Config.UsernameFilter and Config.UsernameFilter.Regex or "[a-zA-Z0-9]+"
    uiConfig.CryptoLimit = (Config.Crypto and Config.Crypto.Limits) or { Buy = 1000000, Sell = 1000000 }
    uiConfig.imageOptions = {
        mime = Config.Image and Config.Image.Mime or "image/png",
        quality = Config.Image and Config.Image.Quality or 1.0
    }
    uiConfig.videoOptions = {
        bitrate = Config.Video and Config.Video.Bitrate or 250,
        size = Config.Video and Config.Video.MaxSize or 10,
        duration = Config.Video and Config.Video.MaxDuration or 60,
        fps = Config.Video and Config.Video.FrameRate or 24
    }
    uiConfig.Companies = table.deep_clone(Config.Companies)
    if uiConfig.Companies and uiConfig.Companies.Services then
        for i = 1, #uiConfig.Companies.Services do
            if uiConfig.Companies.Services[i].onCustomIconClick then
                uiConfig.Companies.Services[i].onCustomIconClick = true
            end
        end
    end

    if Config.CustomApps then
        for appName, appData in pairs(Config.CustomApps) do
            uiConfig.apps[appName] = FormatCustomAppDataForUI(appData)
        end
    end

    for appName, appData in pairs(uiConfig.apps) do
        appData.access = HasAccessToApp(appName)
    end

    uiConfig.defaultSettings = json.decode(GetConfigFile("defaultSettings.json"))

    local function removeAppFromDefaults(appName)
        for i = 1, #uiConfig.defaultSettings.apps do
            for j = 1, #uiConfig.defaultSettings.apps[i] do
                if uiConfig.defaultSettings.apps[i][j] == appName then
                    table.remove(uiConfig.defaultSettings.apps[i], j)
                    break
                end
            end
        end
    end

    if Config.Framework == "standalone" and not Config.CustomFramework then
        uiConfig.apps.Wallet = nil
        uiConfig.apps.Home = nil
        uiConfig.apps.Garage = nil
        uiConfig.apps.Services = nil
        removeAppFromDefaults("Wallet")
        removeAppFromDefaults("Home")
        removeAppFromDefaults("Garage")
        removeAppFromDefaults("Services")
    end

    if not Config.HouseScript then
        uiConfig.apps.Home = nil
        debugprint("No Config.HouseScript, removed home app")
        removeAppFromDefaults("Home")
    end

    if not (Config.Crypto and Config.Crypto.Enabled) then
        uiConfig.apps.Crypto = nil
        debugprint("Config.Crypto not enabled, removed crypto app")
        removeAppFromDefaults("Crypto")
    end

    SendReactMessage("setConfig", uiConfig)
    waitForConfig()

    if phoneData then
        debugprint("phoneData is defined")
        SendReactMessage("setPhoneData", phoneData)
        return
    end

    if not skipFetch then
        FetchPhone()
    end
end

RegisterNetEvent("lb-phone:jobUpdated", function(jobData)
    if not Config.WhitelistApps and not Config.BlacklistApps then
        return
    end

    debugprint("Job updated, refreshing whitelisted & blacklisted apps")

    for appName, _ in pairs(Config.WhitelistApps or {}) do
        SendReactMessage("app:setHasAccess", {
            app = appName,
            hasAccess = HasAccessToApp(appName, jobData.job, jobData.grade)
        })
    end

    for appName, _ in pairs(Config.BlacklistApps or {}) do
        SendReactMessage("app:setHasAccess", {
            app = appName,
            hasAccess = HasAccessToApp(appName, jobData.job, jobData.grade)
        })
    end

    for appName, _ in pairs(Config.CustomApps or {}) do
        SendReactMessage("app:setHasAccess", {
            app = appName,
            hasAccess = HasAccessToApp(appName, jobData.job, jobData.grade)
        })
    end
end)

RegisterNUICallback("configReceived", function(data, callback)
    debugprint("UI has received the config (configReceived triggered)")
    isConfigReceived = true
    callback("ok")
end)

RegisterNUICallback("getPhoneData", function(data, callback)
    debugprint("getPhoneData triggered")

    while not FrameworkLoaded do
        Wait(500)
    end

    Wait(1000)
    RefreshPhone()

    if not callback then
        debugprint("cb is not defined in getPhoneData", data)
        return
    end

    callback(true)
end)

local function controlDisableThread()
    local playerId = PlayerId()

    while phoneOpen do
        Wait(0)

        DisableControlAction(0, 199, true)
        DisableControlAction(0, 200, true)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 69, true)
        DisableControlAction(0, 70, true)
        DisableControlAction(0, 91, true)
        DisableControlAction(0, 92, true)
        DisableControlAction(0, 106, true)
        DisableControlAction(0, 114, true)
        DisableControlAction(0, 140, true)
        DisableControlAction(0, 141, true)
        DisableControlAction(0, 142, true)
        DisableControlAction(0, 257, true)
        DisableControlAction(0, 263, true)
        DisableControlAction(0, 264, true)
        DisableControlAction(0, 330, true)
        DisableControlAction(0, 331, true)

        DisablePlayerFiring(playerId, true)

        if IsNuiFocused() then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 245, true)
            DisableControlAction(0, 14, true)
            DisableControlAction(0, 15, true)
            DisableControlAction(0, 16, true)
            DisableControlAction(0, 17, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 50, true)
            DisableControlAction(0, 99, true)
            DisableControlAction(0, 115, true)
            DisableControlAction(0, 180, true)
            DisableControlAction(0, 181, true)
            DisableControlAction(0, 198, true)
            DisableControlAction(0, 241, true)
            DisableControlAction(0, 242, true)
            DisableControlAction(0, 261, true)
            DisableControlAction(0, 262, true)
            DisableControlAction(0, 85, true)
        end

        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh ~= 0 then
            local roll = GetEntityRoll(veh)
            if roll > 75.0 or roll < -75.0 then
                local controls = {34, 35, 59, 60, 61, 62, 63, 64, 71, 72, 87, 88, 89, 90, 108, 109}
                for i = 1, #controls do
                    DisableControlAction(0, controls[i], true)
                    DisableControlAction(1, controls[i], true)
                    DisableControlAction(2, controls[i], true)
                end
            end
        end
    end

    while IsDisabledControlPressed(0, 200) do
        DisableControlAction(0, 200, true)
        Wait(0)
    end

    if cameraOpen then
        if IsWalkingCamEnabled() then
            local wasSelfieCam = IsSelfieCam()
            DisableWalkableCam()

            while not phoneOpen do
                Wait(500)
            end

            if cameraOpen then
                SetPhoneAction("camera")
                EnableWalkableCam(wasSelfieCam)
            end
        end
    end
end

function ToggleOpen(open, skipFocus)
    if open == nil then
        open = not phoneOpen
    end

    open = open == true

    debugprint("ToggleOpen triggered", tostring(open), tostring(skipFocus))

    if phoneDisabled and open then
        debugprint("phone is disabled, returning")
        return
    end

    if phoneOpen == open then
        debugprint("phoneOpen & open are both the same value, returning")
        return
    end

    if not FrameworkLoaded then
        infoprint("warning", "Framework not loaded")
        return
    end

    if open then
        if IsPedDeadOrDying(PlayerPedId(), true) then
            debugprint("player ped is dead/dying, returning")
            return
        end

        if CanOpenPhone and not CanOpenPhone() then
            debugprint("CanOpenPhone returned false, returning")
            return
        end

        if IsNuiFocused() and Config.DisableOpenNUI then
            infoprint("info",
                "Not opening the phone as another script has NUI focus. You can disable this behavior by setting Config.DisableOpenNUI to false.")
            return
        end

        if GetResourceState("lb-tablet") == "started" then
            local success, isTabletOpen = pcall(function()
                return exports["lb-tablet"]:IsOpen()
            end)
            if success and isTabletOpen then
                infoprint("info",
                    "Not opening the phone as the tablet is open. You can disable this behavior by setting Config.DisableTabletOpenPhone to false.")
                return
            end
        end
    end

    if not currentPhone then
        debugprint("no phone, fetching")
        FetchPhone()
        if not currentPhone then
            debugprint("still no phone after fetching, returning")
            return
        end
    end

    if open then
        if not HasPhoneItem(currentPhone) then
            debugprint("HasPhoneItem returned false. Phone number:", tostring(currentPhone))
            TriggerServerEvent("phone:togglePhone")
            SendReactMessage("closePhone")
            return
        end
    end

    if not open then
        if IsWalkingCamEnabled() and IsSelfieCam() then
            ToggleSelfieCam(false)
        end
    end

    if not open and Config.EndLiveClose then
        local wasWatchingLive = IsWatchingLive()
        EndLive()
        if wasWatchingLive then
            SendReactMessage("instagram:liveEnded", wasWatchingLive)
        end
    end

    phoneOpen = open

    if open then
        debugprint("should open phone. sending openPhone event to ui")
        SendReactMessage("openPhone")

        if not skipFocus then
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(Config.KeepInput)
        end

        if Config.KeepInput then
            CreateThread(controlDisableThread)
        end

        if ControllerThread then
            CreateThread(ControllerThread)
        end

        debugprint("setting animation action")

        if IsWalkingCamEnabled() then
            SetPhoneAction("camera")
        elseif IsInCall() then
            SetPhoneAction("call")
        else
            SetPhoneAction("default")
        end

        TriggerServerEvent("phone:autoCreateBirdyAccount")
    else
        debugprint("sending closePhone event to ui")
        PlayCloseAnim()
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        SendReactMessage("closePhone")
    end

    if phoneData and phoneData.isSetup then
        TriggerServerEvent("phone:togglePhone", open, settings and settings.name)
    end

    TriggerEvent("lb-phone:phoneToggled", open)
end

RegisterNUICallback("toggleInput", function(data, callback)
    callback("ok")

    if not Config.KeepInput then
        return
    end

    local isPTTPressed = false
    if Config.DisableFocusTalking then
        isPTTPressed = IsDisabledControlPressed(0, 249)
    else
        isPTTPressed = IsDisabledControlJustReleased(0, 249)
    end

    if isPTTPressed then
        if data then
            debugprint("PTT is pressed, ignoring toggle focus")
            return
        end

        debugprint("PTT is pressed, waiting before toggling focus")
        while true do
            local stillPressed = false
            if Config.DisableFocusTalking then
                stillPressed = IsDisabledControlPressed(0, 249)
            else
                stillPressed = IsDisabledControlJustReleased(0, 249)
            end

            if not stillPressed then
                break
            end
            Wait(100)
        end
    end

    if data then
        Wait(200)
    end

    SetNuiFocusKeepInput(not data)
end)

local waitingForFocus = false
wasKeepInputDisabledByFlip = false
AddEventHandler("lb-phone:keyPressed", function(action)
    if IsPauseMenuActive() then
        return
    end

    if action == "Open" then
        debugprint("Pressed open keybind")
        ToggleOpen(not phoneOpen)
    elseif action == "Focus" then
        if not phoneOpen or waitingForFocus then
            return
        end

        local isPTTPressed = false
        if Config.DisableFocusTalking then
            isPTTPressed = IsDisabledControlPressed(0, 249)
        else
            isPTTPressed = IsDisabledControlJustReleased(0, 249)
        end

        if isPTTPressed then
            debugprint("PTT is pressed, waiting before toggling focus")
            waitingForFocus = true
            while IsDisabledControlPressed(0, 249) or IsDisabledControlJustReleased(0, 249) do
                Wait(0)
            end
            waitingForFocus = false
        end

        local isFocused = IsNuiFocused()
        SetNuiFocus(not isFocused, not isFocused)

        if not isFocused then
            local isFlipped = false
            local veh = GetVehiclePedIsIn(PlayerPedId(), false)
            if veh ~= 0 then
                local roll = GetEntityRoll(veh)
                if roll > 75.0 or roll < -75.0 then
                    isFlipped = true
                end
            end

            if isFlipped then
                SetNuiFocusKeepInput(false)
                wasKeepInputDisabledByFlip = true
            else
                SetNuiFocusKeepInput(Config.KeepInput)
                wasKeepInputDisabledByFlip = false
            end
        else
            SetNuiFocusKeepInput(false)
            wasKeepInputDisabledByFlip = false
        end
    elseif action == "StopSounds" then
        SendReactMessage("stopSounds")
    end

    if action == "AnswerCall" then
        SendReactMessage("usedCommand", "answer")
    elseif action == "DeclineCall" then
        SendReactMessage("usedCommand", "decline")
    end

    if action == "TakePhoto" then
        SendReactMessage("camera:usedCommand", "toggleTaking")
    elseif action == "ToggleFlash" then
        SendReactMessage("camera:usedCommand", "toggleFlash")
    elseif action == "LeftMode" then
        SendReactMessage("camera:usedCommand", "leftMode")
    elseif action == "RightMode" then
        SendReactMessage("camera:usedCommand", "rightMode")
    elseif action == "FlipCamera" then
        SendReactMessage("camera:usedCommand", "toggleFlip")
    end
end)

for keyName, keyData in pairs(Config.KeyBinds) do
    if keyData.Command then
        keyData.Command = keyData.Command:lower()

        if keyData.Bind then
            keyData.bindData = AddKeyBind({
                name = keyData.Command,
                description = keyData.Description or "no description",
                defaultKey = keyData.Bind,
                defaultMapper = keyData.Mapper,
                secondaryKey = keyData.SecondaryBind,
                secondaryMapper = keyData.SecondaryMapper,
                onPress = function()
                    TriggerEvent("lb-phone:keyPressed", keyName)
                end,
                onRelease = function(duration)
                    TriggerEvent("lb-tablet:keyReleased", keyName, duration)
                end
            })
        else
            RegisterCommand(keyData.Command, function()
                TriggerEvent("lb-phone:keyPressed", keyName)
                Wait(0)
                TriggerEvent("lb-phone:keyReleased", keyName, 0)
            end, false)
        end
    end
end

RegisterNUICallback("finishedSetup", function(data, callback)
    if phoneData then
        phoneData.isSetup = true
    end

    if data then
        local characterName = AwaitCallback("getCharacterName")
        local phoneName = L("BACKEND.MISC.X_PHONE", {
            name = characterName.firstname,
            lastname = characterName.lastname
        })
        data.name = phoneName
    end

    SendReactMessage("setName", data.name)
    TriggerServerEvent("phone:setName", data.name)
    TriggerServerEvent("phone:togglePhone", phoneOpen, data and data.name)
    TriggerServerEvent("phone:finishedSetup", data)

    if Config.AutoBackup then
        TriggerCallback("backup:createBackup")
    end

    callback("ok")
end)

RegisterNUICallback("isAdmin", function(data, callback)
    TriggerCallback("isAdmin", callback)
end)

RegisterNUICallback("setPhoneName", function(data, callback)
    if settings then
        settings.name = data
    end

    TriggerServerEvent("phone:setName", data)
    callback("ok")
end)

RegisterNUICallback("setSettings", function(data, callback)
    debugprint("setSettings triggered")

    if not phoneData then
        print("setSettings triggered, but phoneData is nil")
        return
    end

    settings = data
    phoneData.settings = settings
    callback("ok")

    SetCallVolume(settings and settings.sound and settings.sound.callVolume)
    AwaitCallback("setSettings", settings)

    TriggerEvent("lb-phone:settingsUpdated", data)
    SendReactMessage("customApp:sendMessage", {
        identifier = "any",
        message = {
            type = "settingsUpdated",
            settings = settings,
            action = "settingsUpdated",
            data = data
        }
    })
end)

RegisterNUICallback("setCursorLocation", function(data, callback)
    local x, y = data.x, data.y
    local screenWidth, screenHeight = GetActiveScreenResolution()
    SetCursorLocation(x / screenWidth, y / screenHeight)
    callback("ok")
end)

RegisterNUICallback("exitFocus", function(data, callback)
    debugprint("exitFocus triggered")
    SetNuiFocus(false, false)
    ToggleOpen(false)
    callback("ok")
end)

RegisterNUICallback("getLocales", function(data, callback)
    callback(Config.Locales or { en = "English" })
end)

RegisterNUICallback("setOnScreen", function(data, callback)
    data = data == true
    if PhoneOnScreen ~= data then
        TriggerEvent("lb-phone:setOnScreen", data)
        PhoneOnScreen = data
    end
    callback("ok")
end)

exports("IsPhoneOnScreen", function()
    return PhoneOnScreen
end)

function SendReactMessage(action, data)
    SendNUIMessage({
        action = action,
        data = data
    })
end

CreateThread(function()
    local lastTime = {}
    local lastService = nil

    while not currentPhone do
        debugprint("Waiting for currentPhone to be set before updating time & service")
        Wait(1000)
    end

    while true do
        local currentTime
        if not Config.RealTime then
            if Config.CustomTime then
                currentTime = Config.CustomTime()
            end

            if not currentTime then
                currentTime = {
                    hour = GetClockHours(),
                    minute = GetClockMinutes()
                }
            end

            if currentTime.hour ~= lastTime.hour or currentTime.minute ~= lastTime.minute then
                lastTime.hour = currentTime.hour
                lastTime.minute = currentTime.minute
                SendReactMessage("updateTime", currentTime)
            end
        end

        local currentService = GetServiceBars()
        if lastService ~= currentService then
            lastService = currentService
            SendReactMessage("updateService", currentService)
        end

        Wait(1000)
    end
end)

function GetConfigFile(filename)
    return LoadResourceFile(GetCurrentResourceName(), "config/" .. filename)
end

RegisterNUICallback("getConfigFile", function(data, callback)
    local fileContent = GetConfigFile(data .. ".json")
    local jsonData = json.decode(fileContent)
    callback(jsonData)
end)

RegisterNetEvent("phone:logoutFromApp", function(data)
    debugprint("logoutFromApp:", data)

    if data.number then
        if data.number == currentPhone then
            debugprint("Ignoring logoutFromApp event since number matches")
            return
        end
    end

    debugprint(data.app .. ":logout", data.username)
    SendReactMessage(data.app .. ":logout", data.username)
end)

local nearbyPlayers = {}

function GetNearbyPlayers()
    return nearbyPlayers
end

CreateThread(function()
    while true do
        local playerCoords = GetEntityCoords(PlayerPedId())
        local activePlayers = GetActivePlayers()
        local nearby = {}

        for i = 1, #activePlayers do
            local player = activePlayers[i]
            if player ~= PlayerId() then
                local ped = GetPlayerPed(player)
                local coords = GetEntityCoords(ped)
                local distance = #(playerCoords - coords)

                if distance <= 60.0 then
                    nearby[#nearby + 1] = {
                        player = player,
                        source = GetPlayerServerId(player),
                        ped = ped
                    }
                end
            end
        end

        nearbyPlayers = nearby
        Wait(5000)
    end
end)

function LogOut()
    debugprint("LogOut triggered")


    while isFetchingPhone do
        debugprint("LogOut triggered, waiting for fetchingPhone to finish...")
        Wait(500)
    end

    AwaitCallback("setLastPhone")

    phoneData = nil
    currentPhone = nil
    settings = nil

    TriggerEvent("lb-phone:numberChanged", nil)
    ResetSecurity()
    OnDeath()
end

function SetPhone(phoneNumber, skipFetch)
    debugprint("SetPhone triggered", phoneNumber, skipFetch)


    while isFetchingPhone do
        debugprint("SetPhone triggered, waiting for fetchingPhone to finish...")
        Wait(500)
    end

    OnDeath()
    AwaitCallback("setLastPhone", phoneNumber)
    ResetSecurity(true)
    ToggleCharging(false)

    phoneData = nil
    currentPhone = nil
    settings = nil

    TriggerEvent("lb-phone:numberChanged", nil)

    if phoneNumber or skipFetch then
        FetchPhone()
    end

    if phoneNumber == nil and not skipFetch then
        local firstNumber = GetFirstNumber()
        if firstNumber then
            SetPhone(firstNumber)
        end
    end
end

function OnDeath()
    debugprint("OnDeath triggered")

    local wasWatchingLive = IsWatchingLive()
    EndLive()
    if wasWatchingLive then
        SendReactMessage("instagram:liveEnded", wasWatchingLive)
    end

    if flashlightEnabled then
        flashlightEnabled = false
        TriggerServerEvent("phone:toggleFlashlight", false)
    end

    EndCall()

    if phoneOpen then
        ToggleOpen(false)
    end
end

RegisterNetEvent("phone:toggleOpen", ToggleOpen)
exports("ToggleOpen", ToggleOpen)
exports("IsOpen", function() return phoneOpen end)
exports("IsDisabled", function() return phoneDisabled end)
exports("ToggleDisabled", function(disabled)
    phoneDisabled = disabled == true
    debugprint("ToggleDisabled triggered", phoneDisabled)
    if phoneDisabled and phoneOpen then
        ToggleOpen(false)
    end
end)
exports("GetSettings", function() return settings end)
exports("GetAirplaneMode", function() return settings and settings.airplaneMode end)
exports("GetStreamerMode", function() return settings and settings.streamerMode end)
exports("GetEquippedPhoneNumber", function() return currentPhone end)