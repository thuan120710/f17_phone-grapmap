



BaseCallback("backup:createBackup", function(source, phoneNumber)
    local success = MySQL.update.await([[
        INSERT INTO phone_backups (id, phone_number) VALUES (@identifier, @phoneNumber)
        ON DUPLICATE KEY UPDATE phone_number = @phoneNumber
    ]], {
        ["@identifier"] = GetIdentifier(source),
        ["@phoneNumber"] = phoneNumber
    })
    
    return success > 0
end)


BaseCallback("backup:applyBackup", function(source, currentPhoneNumber, backupPhoneNumber)
    local identifier = GetIdentifier(source)
    

    local backupExists = MySQL.scalar.await("SELECT 1 FROM phone_backups WHERE id = ? AND phone_number = ?", {
        identifier, backupPhoneNumber
    })
    
    if not backupExists or currentPhoneNumber == backupPhoneNumber then
        return false
    end
    
    local params = {
        ["@number"] = backupPhoneNumber,
        ["@phoneNumber"] = currentPhoneNumber
    }
    

    local phoneData = MySQL.query.await("SELECT settings, pin, face_id, phone_number FROM phone_phones WHERE phone_number = @number OR phone_number = @phoneNumber", params)
    

    local backupPhone = nil
    local currentPhone = nil
    
    for i = 1, #phoneData do
        if phoneData[i].phone_number == currentPhoneNumber then
            currentPhone = phoneData[i]
        elseif phoneData[i].phone_number == backupPhoneNumber then
            backupPhone = phoneData[i]
        end
    end
    
    if not backupPhone or not currentPhone then
        return false
    end
    

    backupPhone.settings = json.decode(currentPhone.settings)
    

    if backupPhone.settings.security.pinCode then
        if not backupPhone.pin then
            backupPhone.settings.security.pinCode = false
        end
    end
    
    if backupPhone.settings.security.faceId then
        if not backupPhone.face_id then
            backupPhone.settings.security.faceId = false
        end
    end
    

    MySQL.update.await("UPDATE phone_phones SET settings = ? WHERE phone_number = ?", {
        json.encode(backupPhone.settings),
        currentPhoneNumber
    })
    

    MySQL.update.await([[
        INSERT IGNORE INTO phone_photos (phone_number, link, is_video, size, `timestamp`)
        SELECT @phoneNumber, link, is_video, size, `timestamp`
        FROM phone_photos
        WHERE phone_number = @number AND link NOT IN (SELECT link FROM phone_photos WHERE phone_number = @phoneNumber)
    ]], params)
    

    MySQL.update.await([[
        INSERT IGNORE INTO phone_phone_contacts (contact_phone_number, firstname, lastname, profile_image, favourite, phone_number)
        SELECT contact_phone_number, firstname, lastname, profile_image, favourite, @phoneNumber
        FROM phone_phone_contacts
        WHERE phone_number = @number AND contact_phone_number NOT IN (SELECT contact_phone_number FROM phone_phone_contacts WHERE phone_number = @phoneNumber)
    ]], params)
    

    MySQL.update.await([[
        INSERT IGNORE INTO phone_maps_locations (id, phone_number, `name`, x_pos, y_pos)
        SELECT id, @phoneNumber, `name`, x_pos, y_pos
        FROM phone_maps_locations
        WHERE phone_number = @number AND id NOT IN (SELECT id FROM phone_maps_locations WHERE phone_number = @phoneNumber)
    ]], params)
    
    return true
end)


BaseCallback("backup:deleteBackup", function(source, currentPhoneNumber, backupPhoneNumber)
    local success = MySQL.update.await("DELETE FROM phone_backups WHERE id = ? AND phone_number = ?", {
        GetIdentifier(source),
        backupPhoneNumber
    })
    
    return success > 0
end)


BaseCallback("backup:getBackups", function(source, currentPhoneNumber)
    return MySQL.query.await("SELECT phone_number AS `number` FROM phone_backups WHERE id = ?", {
        GetIdentifier(source)
    })
end)
