-- Clock app for LB Phone
-- Handles alarm management and time-related functionality

-- Register NUI callback for Clock actions
RegisterNUICallback("Clock", function(data, callback)
    local action = data.action
    debugprint("Clock:" .. (action or ""))
    
    if action == "getAlarms" then
        -- Get all user alarms
        TriggerCallback("clock:getAlarms", callback)
        
    elseif action == "createAlarm" then
        -- Create new alarm
        TriggerCallback("clock:createAlarm", callback, data.label, data.hours, data.minutes)
        
    elseif action == "deleteAlarm" then
        -- Delete existing alarm
        TriggerCallback("clock:deleteAlarm", callback, data.id)
        
    elseif action == "toggleAlarm" then
        -- Enable/disable alarm
        TriggerCallback("clock:toggleAlarm", callback, data.id, data.enabled)
        
    elseif action == "updateAlarm" then
        -- Update alarm settings
        TriggerCallback("clock:updateAlarm", callback, data.id, data.label, data.hours, data.minutes)
    end
end)
