-- Voice Memo app for LB Phone
-- Handles voice recording, playback, and memo management

-- Register NUI callback for Voice Memo actions
RegisterNUICallback("VoiceMemo", function(data, callback)
    if not currentPhone then
        return
    end
    
    local action = data.action
    debugprint("VoiceMemo:" .. (action or ""))
    
    if action == "upload" then
        -- Save voice recording
        TriggerCallback("voiceMemo:saveRecording", callback, data.data)
        
    elseif action == "get" then
        -- Get all voice memos
        TriggerCallback("voiceMemo:getMemos", callback)
        
    elseif action == "delete" then
        -- Delete voice memo
        TriggerCallback("voiceMemo:deleteMemo", callback, data.id)
        
    elseif action == "rename" then
        -- Rename voice memo
        TriggerCallback("voiceMemo:renameMemo", callback, data.id, data.title)
    end
end)
