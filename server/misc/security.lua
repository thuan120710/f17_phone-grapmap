



RegisterLegacyCallback("security:getIdentifier", function(source, callback)
    callback(GetIdentifier(source))
end)


BaseCallback("security:setPin", function(source, phoneNumber, newPin, currentPin)

    if type(newPin) ~= "string" or #newPin ~= 4 then
        debugprint("Failed to set pin: invalid type or length")
        return false
    end
    

    local updated = MySQL.update.await("UPDATE phone_phones SET pin = ? WHERE phone_number = ? AND (pin = ? OR pin IS NULL)", {
        newPin,
        phoneNumber,
        currentPin or ""
    })
    
    local success = updated > 0
    debugprint("phone:security:setPin", GetPlayerName(source), success, phoneNumber, newPin, currentPin)
    
    return success
end, false)


BaseCallback("security:removePin", function(source, phoneNumber, currentPin)

    if type(currentPin) ~= "string" or #currentPin ~= 4 then
        debugprint("Failed to remove pin: invalid type or length")
        return false
    end
    

    local updated = MySQL.update.await("UPDATE phone_phones SET pin = NULL, face_id = NULL WHERE phone_number = ? AND (pin = ? OR pin IS NULL)", {
        phoneNumber,
        currentPin
    })
    
    return updated > 0
end, false)


BaseCallback("security:verifyPin", function(source, phoneNumber, inputPin)

    if type(inputPin) ~= "string" or #inputPin ~= 4 then
        debugprint("Failed to verify pin: invalid type or length")
        return false
    end
    

    local storedPin = MySQL.scalar.await("SELECT pin FROM phone_phones WHERE phone_number = ?", {
        phoneNumber
    })
    

    local isValid = storedPin == nil or storedPin == inputPin
    debugprint("phone:security:verifyPin", GetPlayerName(source), isValid, storedPin, inputPin)
    
    return isValid
end, false)


BaseCallback("security:enableFaceUnlock", function(source, phoneNumber, pin)

    if type(pin) ~= "string" or #pin ~= 4 then
        debugprint("Failed to enable face unlock: invalid type or length")
        return false
    end
    
    local identifier = GetIdentifier(source)
    

    local updated = MySQL.update.await("UPDATE phone_phones SET face_id = ? WHERE phone_number = ? AND pin = ?", {
        identifier,
        phoneNumber,
        pin
    })
    
    return updated > 0
end, false)


BaseCallback("security:disableFaceUnlock", function(source, phoneNumber, pin)

    if type(pin) ~= "string" or #pin ~= 4 then
        debugprint("Failed to disable face unlock: invalid type or length")
        return false
    end
    

    return MySQL.update.await("UPDATE phone_phones SET face_id = NULL WHERE phone_number = ? AND (pin = ? OR pin IS NULL)", {
        phoneNumber,
        pin
    })
end, false)


BaseCallback("security:verifyFace", function(source, phoneNumber)
    local identifier = GetIdentifier(source)
    

    local storedFaceId = MySQL.scalar.await("SELECT face_id FROM phone_phones WHERE phone_number = ?", {
        phoneNumber
    })
    
    debugprint("phone:security:verifyFace", GetPlayerName(source), storedFaceId, identifier)
    

    return storedFaceId == identifier
end, false)


function ResetSecurity(phoneNumber)
    assert(type(phoneNumber) == "string", "Invalid argument #1 to ResetSecurity, expected string, got " .. type(phoneNumber))
    

    MySQL.update.await("UPDATE phone_phones SET pin = NULL, face_id = NULL WHERE phone_number = ?", {
        phoneNumber
    })
    

    local source = GetSourceFromNumber(phoneNumber)
    if source then
        TriggerClientEvent("phone:security:reset", source, phoneNumber)
    end
end


exports("GetPin", function(phoneNumber)
    assert(type(phoneNumber) == "string", "Invalid argument #1 to GetPin, expected string, got " .. type(phoneNumber))
    
    return MySQL.scalar.await("SELECT pin FROM phone_phones WHERE phone_number = ?", {
        phoneNumber
    })
end)


exports("ResetSecurity", ResetSecurity)
