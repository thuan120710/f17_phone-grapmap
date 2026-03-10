---Adds a transaction to the wallet app and sends a notification
---@param phoneNumber string
---@param amount number
---@param company string
---@param logo? string
---@return nil
function AddTransaction(phoneNumber, amount, company, logo)
    if not phoneNumber or not amount or not company then
        return
    end

    MySQL.insert.await("INSERT INTO phone_wallet_transactions (phone_number, amount, company, logo) VALUES (@phoneNumber, @amount, @company, @logo)", {
        ["@phoneNumber"] = phoneNumber,
        ["@amount"] = amount,
        ["@company"] = company,
        ["@logo"] = logo
    })

    local source = GetSourceFromNumber(phoneNumber)
    local content = (amount < 0 and "-" or "") .. Config.CurrencyFormat:format(SeperateNumber(math.abs(amount)))

    SendNotification(phoneNumber, {
        app = "Wallet",
        title = company,
        content = content,
        thumbnail = logo
    })

    TriggerEvent("lb-phone:onAddTransaction", amount > 0 and "received" or "paid", phoneNumber, amount, company, logo)

    Log("Wallet", source or nil, amount > 0 and "success" or "error", L("BACKEND.LOGS." .. (amount > 0 and "RECEIVED" or "PAID") .. "_TITLE", { amount = math.abs(amount) }), L("BACKEND.LOGS.TRANSACTION", {
        number = FormatNumber(phoneNumber),
        amount = amount,
        company = company
    }), logo)

    if not source then
        return
    end

    TriggerClientEvent("phone:wallet:addTransaction", source, {
        amount = amount,
        company = company,
        logo = logo,
        timestamp = os.time()
    })
end

exports("AddTransaction", AddTransaction)

---@param phoneNumber string
---@param page? number
---@param perPage? number
local function GetTransactions(phoneNumber, page, perPage)
    page = math.max(page or 0, 0)
    perPage = math.max(perPage or 5, 1)

    return MySQL.query.await([[
        SELECT amount, company, logo, `timestamp`
        FROM phone_wallet_transactions
        WHERE phone_number = ?

        ORDER BY `timestamp` DESC

        LIMIT ?, ?
    ]], { phoneNumber, (page or 0) * perPage, perPage })
end

BaseCallback("wallet:getBalance", function(source, phoneNumber)
    return GetBalance(source)
end)

---@param page number
---@param recent? true
BaseCallback("wallet:getTransactions", function(source, phoneNumber, page, recent)
    return GetTransactions(phoneNumber, page, recent and 5 or 25)
end)

BaseCallback("wallet:doesNumberExist", function(source, phoneNumber, number)
    local sourceFromNumber = GetSourceFromNumber(number)

    if sourceFromNumber then
        return true
    end

    if Config.TransferOffline then
        return MySQL.scalar.await("SELECT 1 FROM phone_phones WHERE phone_number = ?", { number }) == 1
    end
end, false)

---@param data { amount: number, phoneNumber: string }
BaseCallback("wallet:sendPayment", function(source, phoneNumber, data)
    amount = tonumber(data.amount)

    if not amount or amount <= 0 then
        return { success = false, reason = "INVALID_AMOUNT" }
    end

    -- Check minimum transfer amount
    if Config.MinTransferAmount and amount < Config.MinTransferAmount then
        return { success = false, reason = "BELOW_MINIMUM_AMOUNT" }
    end

    if GetBalance(source) < amount then
        return { success = false, reason = "INSUFFICIENT_FUNDS" }
    end

    if type(Config.TransferLimits.Daily) == "number" and Config.TransferLimits.Daily > 0 then
        local spentToday = MySQL.scalar.await("SELECT -SUM(amount) FROM phone_wallet_transactions WHERE phone_number = ? AND amount < 0 AND `timestamp` > DATE_SUB(NOW(), INTERVAL 1 DAY)", { phoneNumber }) or 0

        if spentToday + amount > Config.TransferLimits.Daily then
            return { success = false, reason = "EXCEED_DAILY" }
        end
    elseif Config.TransferLimits?.Daily then
        infoprint("error", "TransferLimits.Daily must be a number and greater than 0, or false.")
    end

    if type(Config.TransferLimits.Weekly) == "number" and Config.TransferLimits.Weekly > 0 then
        local spentWeek = MySQL.scalar.await("SELECT -SUM(amount) FROM phone_wallet_transactions WHERE phone_number = ? AND amount < 0 AND `timestamp` > DATE_SUB(NOW(), INTERVAL 7 DAY)", { phoneNumber }) or 0

        if spentWeek + amount > Config.TransferLimits.Weekly then
            return { success = false, reason = "EXCEED_WEEKLY" }
        end
    elseif Config.TransferLimits?.Weekly then
        infoprint("error", "TransferLimits.Weekly must be a number and greater than 0, or false.")
    end

    local sendToSource = GetSourceFromNumber(data.phoneNumber)
    
    -- Prevent sending to self
    if sendToSource == source then
        debugprint("Can't send money to yourself (source).", source, sendToSource)
        return { success = false, reason = "CANNOT_SEND_TO_SELF" }
    end

    -- SECURITY FIX: Remove money from sender FIRST (prevent duplication if crash)
    local removed = RemoveMoney(source, amount, "Chuyển tiền qua ví điện thoại", "bank")
    
    if not removed then
        debugprint("Failed to remove money from sender:", source)
        return { success = false, reason = "FAILED_REMOVE" }
    end

    -- Now add money to recipient
    local added = false

    if sendToSource then
        -- Chuyển tiền wallet: tienkhoa -> tienkhoa
        added = AddMoney(sendToSource, amount, "tienkhoa")
    elseif Config.TransferOffline then
        local identifier = GetIdentifier(source)
        local sendToIdentifier = MySQL.scalar.await("SELECT owner_id FROM phone_phones WHERE phone_number = ?", { data.phoneNumber })

        if sendToIdentifier and sendToIdentifier ~= identifier then
            -- Chuyển tiền wallet offline: tienkhoa -> tienkhoa
            added = AddMoneyOffline and AddMoneyOffline(sendToIdentifier, amount, "tienkhoa")
        elseif sendToIdentifier == identifier then
            debugprint("Can't send money to yourself (identifier).", identifier, sendToIdentifier)
        end
    end

    -- SECURITY FIX: Rollback if add failed
    if not added then
        debugprint("Failed to add money to recipient, rolling back transaction")
        -- Return money to sender
        AddMoney(source, amount, "tienkhoa")
        return { success = false, reason = "NUMBER_DOES_NOT_EXIST" }
    end

    -- Transaction successful, send message
    SendMessage(phoneNumber, data.phoneNumber, "<!SENT-PAYMENT-" .. amount .. "!>")

    GetContact(data.phoneNumber, phoneNumber, function(contact)
        if contact then
            AddTransaction(phoneNumber, -amount, contact.name, contact.avatar)
        else
            AddTransaction(phoneNumber, -amount, data.phoneNumber)
        end
    end)

    GetContact(phoneNumber, data.phoneNumber, function(contact)
        if contact then
            AddTransaction(data.phoneNumber, amount, contact.name, contact.avatar)
        else
            AddTransaction(data.phoneNumber, amount, phoneNumber)
        end
    end)

    return { success = true }
end, nil, {
    defaultReturn = { success = false, reason = "UNKNOWN_ERROR" },
    preventSpam = true,
})
