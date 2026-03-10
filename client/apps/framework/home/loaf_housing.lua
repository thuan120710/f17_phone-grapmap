if Config.HouseScript ~= "loaf_housing" then
    return
end

local lh = exports.loaf_housing

RegisterNUICallback("Home", function(data, cb)
    local action = data.action
    debugprint("loaf_housing - Home:" .. (action or ""))

    if action == "getHomes" then
        local ownedHouses = lh:GetOwnedHouses()
        local toSend = {}

        for _, v in pairs(ownedHouses) do
            if v then
                toSend[#toSend+1] = {
                    label = v.label .. " (" .. v.uniqueId .. ")",
                    id = v.id,
                    uniqueId = v.uniqueId,
                    locked = AwaitCallback("home:getLocked", v.id, v.uniqueId),
                    keyholders = v.keyHolders
                }
            end
        end

        cb(toSend)
    elseif action == "removeKeyholder" then
        cb(lh:RemoveKeyHolder(data.id, data.identifier))
    elseif action == "addKeyholder" then
        if lh:GiveKey(data.id, tonumber(data.source)) then
            SetTimeout(500, function()
                cb(lh:GetKeyHolders(data.id))
            end)
        end
    elseif action == "toggleLocked" then
        local locked = AwaitCallback("home:toggleLocked", data.id, data.uniqueId)
        cb(locked)
    elseif action == "setWaypoint" then
        lh:MarkProperty(data.id)
        cb(true)
    end
end)
