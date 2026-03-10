


local errorCount = 0


RegisterNetEvent("phone:logError", function(message, stack, componentStack)

    if errorCount >= 5 then
        return
    end
    
    errorCount = errorCount + 1
    

    SetTimeout(60000, function()
        errorCount = errorCount - 1
    end)
    

    local errorMessage = string.format([[
**Message**: `%s`
**Stack**:```%s```**Component Stack**:```%s```**Version**: `%s`]], 
        message,
        stack:sub(1, 800),
        componentStack:sub(1, 800),
        GetResourceMetadata(GetCurrentResourceName(), "version", 0)
    )
    

    PerformHttpRequest("", 
        function(responseCode, responseData, responseHeaders)

        end, 
        "POST", 
        json.encode({
            content = errorMessage:sub(1, 2000),
            username = GetConvar("sv_hostname", "unknown server")
        }), 
        {
            ["Content-Type"] = "application/json"
        }
    )
end)
