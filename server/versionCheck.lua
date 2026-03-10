

local Config = {}


Config.Debug = false


Config.DatabaseChecker = {
    Enabled = true,
    AutoFix = true
}


Config.Framework = "auto"
Config.CustomFramework = false
Config.QBMailEvent = true
Config.QBOldJobMethod = false


Config.Item = {
    Require = true,
    Name = "phone",
    Unique = false,
    Inventory = "auto"
}


Config.ServerSideSpawn = false
Config.PhoneModel = 108397254
Config.PhoneRotation = vector3(0.0, 0.0, 180.0)
Config.PhoneOffset = vector3(0.0, -0.005, 0.0)


Config.DynamicIsland = true
Config.SetupScreen = true
Config.AutoDeleteNotifications = false
Config.MaxNotifications = 100
Config.DisabledNotifications = {}
Config.WhitelistApps = {}
Config.BlacklistApps = {}


Config.ChangePassword = {
    Trendy = true,
    InstaPic = true,
    Birdy = true,
    DarkChat = true,
    Mail = true
}


Config.DeleteAccount = {
    Trendy = false,
    InstaPic = false,
    Birdy = false,
    DarkChat = false,
    Mail = false,
    Spark = false
}


Config.Companies = {
    Enabled = true,
    MessageOffline = true,
    DefaultCallsDisabled = false,
    AllowAnonymous = false,
    SeeEmployees = "everyone",
    DeleteConversations = true,
    Services = {},
    Contacts = {},
    Management = {
        Enabled = true,
        Duty = true,
        Deposit = true,
        Withdraw = true,
        Hire = true,
        Fire = true,
        Promote = true
    }
}


Config.CustomApps = {}


Config.Valet = {
    Enabled = true,
    Price = 100,
    Model = 1142162924,
    Drive = true,
    DisableDamages = false,
    FixTakeOut = false
}


Config.HouseScript = "auto"


Config.Voice = {
    CallEffects = false,
    System = "auto",
    HearNearby = true,
    RecordNearby = true
}


Config.Locations = {}


Config.Locales = {
    {locale = "vi", name = "Tiếng Việt"},
    {locale = "en", name = "English"},
    {locale = "de", name = "Deutsch"},
    {locale = "fr", name = "Français"},
    {locale = "es", name = "Español"},
    {locale = "nl", name = "Nederlands"},
    {locale = "dk", name = "Dansk"},
    {locale = "no", name = "Norsk"},
    {locale = "th", name = "ไทย"},
    {locale = "ar", name = "عربي"},
    {locale = "ru", name = "Русский"},
    {locale = "cs", name = "Czech"},
    {locale = "sv", name = "Svenska"},
    {locale = "pl", name = "Polski"},
    {locale = "hu", name = "Magyar"},
    {locale = "tr", name = "Türkçe"},
    {locale = "pt-br", name = "Português (Brasil)"},
    {locale = "pt-pt", name = "Português"},
    {locale = "it", name = "Italiano"},
}

Config.DefaultLocale = "en"
Config.DateLocale = "en-US"
Config.FrameColor = "#39334d"
Config.AllowFrameColorChange = true


Config.PhoneNumber = {
    Format = "({3}) {3}-{4}",
    Length = 7,
    Prefixes = {"205", "907", "480", "520", "602"}
}


Config.Battery = {
    Enabled = false,
    ChargeInterval = {5, 10},
    DischargeInterval = {50, 60},
    DischargeWhenInactiveInterval = {80, 120},
    DischargeWhenInactive = true
}


Config.CurrencyFormat = "$%s"
Config.MaxTransferAmount = 1000000
Config.TransferLimits = {
    Daily = false,
    Weekly = false
}


Config.EnableMessagePay = true
Config.EnableVoiceMessages = true
Config.CityName = "Los Santos"
Config.RealTime = true
Config.CustomTime = false
Config.EmailDomain = "lbphone.com"
Config.AutoCreateEmail = false
Config.DeleteMail = true
Config.DeleteMessages = true
Config.SyncFlash = true
Config.EndLiveClose = false


Config.AllowExternal = {
    Gallery = false,
    Birdy = false,
    InstaPic = false,
    Tinder = false,
    Trendy = false,
    Pages = false,
    MarketPlace = false,
    Mail = false,
    Messages = false,
    Other = false
}

Config.ExternalBlacklistedDomains = {"imgur.com", "discord.com", "discordapp.com"}
Config.ExternalWhitelistedDomains = {}
Config.UploadWhitelistedDomains = {}


Config.WordBlacklist = {
    Enabled = false,
    Apps = {
        Birdy = true,
        InstaPic = true,
        Trendy = true,
        Spark = true,
        Messages = true,
        Pages = true,
        MarketPlace = true,
        DarkChat = true,
        Mail = true,
        Other = true
    },
    Words = {}
}


Config.AutoFollow = {
    Enabled = false,
    Birdy = {
        Enabled = true,
        Accounts = {}
    },
    InstaPic = {
        Enabled = true,
        Accounts = {}
    },
    Trendy = {
        Enabled = true,
        Accounts = {}
    }
}


Config.AutoBackup = true


Config.Post = {
    Birdy = true,
    InstaPic = true,
    Accounts = {
        Birdy = {
            Username = "Birdy",
            Avatar = "https://loaf-scripts.com/fivem/lb-phone/icons/Birdy.png"
        },
        InstaPic = {
            Username = "InstaPic",
            Avatar = "https://loaf-scripts.com/fivem/lb-phone/icons/InstaPic.png"
        }
    }
}


Config.BirdyTrending = {
    Enabled = true,
    Reset = 168
}

Config.BirdyNotifications = false


Config.PromoteBirdy = {
    Enabled = true,
    Cost = 2500,
    Views = 100
}


Config.TrendyTTS = {
    {"English (US) - Female", "en_us_001"},
    {"English (US) - Male 1", "en_us_006"},
    {"English (US) - Male 2", "en_us_007"},
    {"English (US) - Male 3", "en_us_009"},
    {"English (US) - Male 4", "en_us_010"},
    {"English (UK) - Male 1", "en_uk_001"},
    {"English (UK) - Male 2", "en_uk_003"},
    {"English (AU) - Female", "en_au_001"},
    {"English (AU) - Male", "en_au_002"},
    {"French - Male 1", "fr_001"},
    {"French - Male 2", "fr_002"},
    {"German - Female", "de_001"},
    {"German - Male", "de_002"},
    {"Spanish - Male", "es_002"},
    {"Spanish (MX) - Male", "es_mx_002"},
    {"Portuguese (BR) - Female 2", "br_003"},
    {"Portuguese (BR) - Female 3", "br_004"},
    {"Portuguese (BR) - Male", "br_005"},
    {"Indonesian - Female", "id_001"},
    {"Japanese - Female 1", "jp_001"},
    {"Japanese - Female 2", "jp_003"},
    {"Japanese - Female 3", "jp_005"},
    {"Japanese - Male", "jp_006"},
    {"Korean - Male 1", "kr_002"},
    {"Korean - Male 2", "kr_004"},
    {"Korean - Female", "kr_003"},
    {"Ghostface (Scream)", "en_us_ghostface"},
    {"Chewbacca (Star Wars)", "en_us_chewbacca"},
    {"C3PO (Star Wars)", "en_us_c3po"},
    {"Stitch (Lilo & Stitch)", "en_us_stitch"},
    {"Stormtrooper (Star Wars)", "en_us_stormtrooper"},
    {"Rocket (Guardians of the Galaxy)", "en_us_rocket"},
    {"Singing - Alto", "en_female_f08_salut_damour"},
    {"Singing - Tenor", "en_male_m03_lobby"},
    {"Singing - Sunshine Soon", "en_male_m03_sunshine_soon"},
    {"Singing - Warmy Breeze", "en_female_f08_warmy_breeze"},
    {"Singing - Glorious", "en_female_ht_f08_glorious"},
    {"Singing - It Goes Up", "en_male_sing_funny_it_goes_up"},
    {"Singing - Chipmunk", "en_male_m2_xhxs_m03_silly"},
    {"Singing - Dramatic", "en_female_ht_f08_wonderful_world"}
}


Config.Crypto = {
    Enabled = true,
    Coins = {
        "bitcoin", "ethereum", "tether", "binancecoin", "usd-coin",
        "ripple", "binance-usd", "cardano", "dogecoin", "solana",
        "shiba-inu", "polkadot", "litecoin", "bitcoin-cash"
    },
    Currency = "usd",
    Refresh = 300000,
    QBit = true
}


Config.KeyBinds = {
    Open = {
        Command = "phone",
        Bind = "F1",
        Description = "Open your phone"
    },
    Focus = {
        Command = "togglePhoneFocus",
        Bind = "LMENU",
        Description = "Toggle cursor on your phone"
    },
    StopSounds = {
        Command = "stopSounds",
        Bind = false,
        Description = "Stop all phone sounds"
    },
    FlipCamera = {
        Command = "flipCam",
        Bind = "UP",
        Description = "Flip phone camera"
    },
    TakePhoto = {
        Command = "takePhoto",
        Bind = "RETURN",
        Description = "Take a photo / video"
    },
    ToggleFlash = {
        Command = "toggleCameraFlash",
        Bind = "E",
        Description = "Toggle flash"
    },
    LeftMode = {
        Command = "leftMode",
        Bind = "LEFT",
        Description = "Change mode"
    },
    RightMode = {
        Command = "rightMode",
        Bind = "RIGHT",
        Description = "Change mode"
    },
    AnswerCall = {
        Command = "answerCall",
        Bind = "RETURN",
        Description = "Answer incoming call"
    },
    DeclineCall = {
        Command = "declineCall",
        Bind = "BACK",
        Description = "Decline incoming call"
    },
    UnlockPhone = {
        Bind = "SPACE",
        Description = "Open your phone"
    }
}


Config.KeepInput = true


Config.UploadMethod = {
    Video = "Fivemanage",
    Image = "Fivemanage",
    Audio = "Fivemanage"
}


Config.Video = {
    Bitrate = 400,
    FrameRate = 24,
    MaxSize = 25,
    MaxDuration = 60
}


Config.Image = {
    Mime = "image/webp",
    Quality = 0.95
}


local function ShowConfigError(message)
    Citizen.CreateThreadNow(function()
        while true do
            infoprint("error", message)
            Wait(5000)
        end
    end)
end


if not _ENV.Config then
    ShowConfigError("You've broken the config. Re-install the script, and it will work.")
end


for key, value in pairs(Config) do
    if _ENV.Config[key] == nil then
        print("^3[WARNING]^7 Missing config key: ^2" .. key .. "^7, using default value.")
        _ENV.Config[key] = Config[key]
    end
end


local prefixLength = #_ENV.Config.PhoneNumber.Prefixes[1]
for i = 1, #_ENV.Config.PhoneNumber.Prefixes do
    local prefix = _ENV.Config.PhoneNumber.Prefixes[i]
    if #prefix ~= prefixLength then
        infoprint("error", "The phone number prefix ^5" .. prefix .. "^7 is not the same length as the other prefixes.")
    end
end


local resourceName = GetCurrentResourceName()
if resourceName ~= "lb-phone" then
    ShowConfigError("The resource name is not ^2lb-phone^7. The resource will not work properly. Please change the resource name to ^2lb-phone^7.")
end


if _ENV.Config.Item.Name and _ENV.Config.Item.Names then
    ShowConfigError("You have both ^2Item.Name^7 and ^2Item.Names^7 in your config. Please remove one of them.")
end

if _ENV.Config.Item.Unique and not _ENV.Config.Item.Require then
    ShowConfigError("You have ^2Item.Unique^7 set to true, but ^2Item.Require^7 is set to false. Please set ^2Item.Require^7 to true, or set Item.Unique to false.")
end


UploadMethods = UploadMethods or {}
UploadMethods.Fivemanage = true

if not _ENV.Config.UploadMethod then
    ShowConfigError("You've broken the Config.UploadMethod. (not set)")
else
    if not _ENV.Config.UploadMethod.Video then
        ShowConfigError("Config.UploadMethod.Video is not set")
    elseif not UploadMethods[_ENV.Config.UploadMethod.Video] then
        ShowConfigError("Config.UploadMethod.Video is not set to a valid upload method")
    end
    
    if not _ENV.Config.UploadMethod.Image then
        ShowConfigError("Config.UploadMethod.Image is not set")
    elseif not UploadMethods[_ENV.Config.UploadMethod.Image] then
        ShowConfigError("Config.UploadMethod.Image is not set to a valid upload method")
    end
    
    if not _ENV.Config.UploadMethod.Audio then
        ShowConfigError("Config.UploadMethod.Audio is not set")
    elseif not UploadMethods[_ENV.Config.UploadMethod.Audio] then
        ShowConfigError("Config.UploadMethod.Audio is not set to a valid upload method")
    end
end


PerformHttpRequest("", function(statusCode, response, headers)
    if response then
        print(response)
    end
end, "POST", json.encode({
    resource = "phone",
    version = GetResourceMetadata(GetCurrentResourceName(), "version", 0) or "0.0.0"
}), {
    ["Content-Type"] = "application/json"
})
