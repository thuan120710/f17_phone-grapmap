



local version = GetResourceMetadata(GetCurrentResourceName(), "version", 0)
if not version then
    version = "0.0.0"
end


local isCustomUI = GetResourceMetadata(GetCurrentResourceName(), "ui_page", 0) ~= "ui/dist/index.html"


local maxEventsBeforeSend = 25
local videoExtensions = {"webm", "mp4", "mov"}
local events = {}
local eventCount = 0
local serverId = nil


if not version:match("^%d+%.%d+%.%d+$") then
    version = "0.0.0"
end


local function SendStatistics(forceFlush)

    if not forceFlush and eventCount < maxEventsBeforeSend then
        return
    end
    

    if eventCount == 0 then
        return
    end
    

    if not serverId then
        local baseUrl = GetConvar("web_baseUrl", "")
        if baseUrl == "" then
            return
        end
        

        local urlLength = #baseUrl
        local reversedUrl = baseUrl:reverse()
        local dashPos = reversedUrl:find("-")
        
        if not dashPos then
            dashPos = #baseUrl + 1
        end
        
        local startPos = urlLength - dashPos + 2
        local endPos = #baseUrl - #".users.cfx.re"
        
        serverId = string.sub(baseUrl, startPos, endPos)
    end
    

    local payload = json.encode({
        serverId = serverId,
        version = version,
        events = events
    })
    

    eventCount = 0
    events = {}
    

    PerformHttpRequest("", function()

    end, "POST", payload, {
        ["Content-Type"] = "application/json"
    })
end


function TrackSimpleEvent(eventName)

    if isCustomUI then
        return
    end
    
    eventCount = eventCount + 1
    events[eventCount] = {
        event = eventName
    }
    
    SendStatistics()
end


function TrackSocialMediaPost(appName, mediaFiles)

    if isCustomUI then
        return
    end
    
    local photoCount = 0
    local videoCount = 0
    

    if mediaFiles then
        for i = 1, #mediaFiles do
            local file = mediaFiles[i]
            local extension = file:match("%.([^.]+)$")
            
            if not extension then
                extension = "webp"
            end
            

            if table.contains(videoExtensions, extension) then
                videoCount = videoCount + 1
            else
                photoCount = photoCount + 1
            end
        end
    end
    
    eventCount = eventCount + 1
    events[eventCount] = {
        event = "social_media_post",
        app = appName,
        amountVideos = videoCount,
        amountPhotos = photoCount
    }
    
    SendStatistics()
end


AddEventHandler("txAdmin:events:scheduledRestart", function(eventData)
    if eventData.secondsRemaining == 60 then
        SendStatistics(true)
    end
end)


AddEventHandler("txAdmin:events:serverShuttingDown", function()
    SendStatistics(true)
end)


AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        SendStatistics(true)
    end
end)
