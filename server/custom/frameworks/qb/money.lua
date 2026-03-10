if Config.Framework ~= "qb" then
    return
end

while not QB do
    Wait(500)
    debugprint("Money: Waiting for QB to load")
end

function GetBalance(source)
    local qPlayer = QB.Functions.GetPlayer(tonumber(source))

    if not qPlayer then
        debugprint("GetBalance: Failed to get player for source:", source)
        return 0
    end

    return qPlayer.Functions.GetMoney("bank") or 0
end

function AddMoney(source, amount, moneyType)
    local qPlayer = QB.Functions.GetPlayer(tonumber(source))
    if not qPlayer or amount < 0 then
        return false
    end

    local thue = math.floor(amount * 0.05)
    local tiensauthue = math.floor(amount - thue)
    
    qPlayer.Functions.AddMoney("tienkhoa", tiensauthue, "Nhận tiền qua điện thoại")
    exports['Renewed-Banking']:addAccountMoney("thuebanking", 'tienkhoa', amount)
    return true
end

function AddMoneyOffline(identifier, amount, moneyType)
    if amount <= 0 then
        return false
    end

    local thue = math.floor(amount * 0.05)
    local tiensauthue = math.floor(amount - thue)

    exports['Renewed-Banking']:addAccountMoney("thuebanking", 'tienkhoa', amount)
    return MySQL.update.await("UPDATE players SET money = JSON_SET(money, '$.tienkhoa', JSON_EXTRACT(money, '$.tienkhoa') + ?) WHERE citizenid = ?", { tiensauthue, identifier }) > 0
end

function RemoveMoney(source, amount, reason, moneyType)
    local qPlayer = QB.Functions.GetPlayer(tonumber(source))
    if not qPlayer then
        return false
    end

    if amount < 0 then
        return false
    end

    reason = reason or "Chuyển tiền qua điện thoại"
    moneyType = moneyType or "bank"

    if moneyType == "priority" then
        local tienkhoa = qPlayer.Functions.GetMoney("tienkhoa") or 0
        local bank = qPlayer.Functions.GetMoney("bank") or 0
        local total = tienkhoa + bank

        if total < amount then
            return false
        end

        if tienkhoa >= amount then
            qPlayer.Functions.RemoveMoney("tienkhoa", amount, reason)
            return true
        else
            if tienkhoa > 0 then
                qPlayer.Functions.RemoveMoney("tienkhoa", tienkhoa, reason)
            end
            local remaining = amount - tienkhoa
            qPlayer.Functions.RemoveMoney("bank", remaining, reason)
            return true
        end
    
    elseif moneyType == "bank" then
        if GetBalance(source) < amount then
            return false
        end
        qPlayer.Functions.RemoveMoney("bank", amount, reason)
        return true
    else
        debugprint("RemoveMoney: Invalid moneyType:", moneyType)
        return false
    end
end