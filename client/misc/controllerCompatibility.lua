


local cursorX = 0.5
local cursorY = 0.5
local sensitivity = 0.005
local keyboardToggled = false


local function isUsingController()
    return not IsUsingKeyboard(0)
end


local function getControllerInput(control)
    local input = GetDisabledControlNormal(0, control)
    local deadzone = 0.1
    
    if input < -deadzone or input > deadzone then
        return input
    end
    
    return 0.0
end


RegisterNUICallback("toggleInput", function(enabled)
    if not isUsingController() then
        return
    end
    
    keyboardToggled = enabled == true
    

    if not enabled then
        Wait(250)
        if keyboardToggled then
            return
        end
    end
    
    SendReactMessage("controller:toggleKeyboard", keyboardToggled)
end)


local function handleControllerInput()

    local leftStickX = getControllerInput(1)
    local leftStickY = getControllerInput(2)
    local rightStickY = getControllerInput(31)
    

    cursorX = cursorX + (leftStickX * sensitivity)
    cursorY = cursorY + (leftStickY * sensitivity)
    

    cursorX = math.min(0.99999, math.max(0, cursorX))
    cursorY = math.min(1.0, math.max(0, cursorY))
    

    if IsDisabledControlJustPressed(0, 18) then
        SendReactMessage("controller:press", {
            x = cursorX,
            y = cursorY
        })
    elseif IsDisabledControlJustReleased(0, 18) then
        SendReactMessage("controller:release", {
            x = cursorX,
            y = cursorY
        })
    elseif IsDisabledControlJustReleased(0, 199) or IsDisabledControlJustReleased(0, 177) then
        ToggleOpen(false)
    end
    

    if leftStickX ~= 0.0 or leftStickY ~= 0.0 then
        SetCursorLocation(cursorX, cursorY)
    end
    

    if rightStickY ~= 0.0 then
        SendReactMessage("controller:scroll", {
            amount = math.floor(rightStickY * 25),
            x = cursorX,
            y = cursorY
        })
    end
    

    DisableAllControlActions(0)
    DisableAllControlActions(1)
    DisableAllControlActions(2)
    InvalidateIdleCam()
end


function ControllerThread()
    while phoneOpen do
        Wait(0)
        
        if isUsingController() and IsNuiFocused() then
            handleControllerInput()
        else
            Wait(500)
        end
    end
    

    cursorX = 0.5
    cursorY = 0.5
    
    if isUsingController() then
        SetCursorLocation(cursorX, cursorY)
    end
end
