-- Notes app for LB Phone
-- Handles note creation, editing, and management

-- Register NUI callback for Notes actions
RegisterNUICallback("Notes", function(data, callback)
    if not currentPhone then
        return
    end
    
    local action = data.action
    debugprint("Notes:" .. (action or ""))
    
    -- Use data.data if available (nested data structure)
    if data.data then
        data = data.data
    end
    
    if action == "create" then
        -- Create new note
        TriggerCallback("notes:createNote", callback, data.title, data.content)
        
    elseif action == "save" then
        -- Save existing note
        TriggerCallback("notes:saveNote", callback, data.id, data.title, data.content)
        
    elseif action == "fetch" then
        -- Get all notes
        TriggerCallback("notes:getNotes", callback)
        
    elseif action == "remove" then
        -- Delete note
        TriggerCallback("notes:removeNote", callback, data.id)
    end
end)

-- Handle note added event (from AirShare)
RegisterNetEvent("phone:notes:noteAdded", function(noteData)
    debugprint("phone:notes:noteAdded", noteData)
    SendReactMessage("notes:noteAdded", noteData)
end)
