



if not (Config.Crypto and Config.Crypto.Enabled) then
    debugprint("crypto disabled")
    return
end


local limits = Config.Crypto.Limits or {
    Buy = 1000000,
    Sell = 1000000
}


local requestCount = 0


local function MakeAPIRequest(endpoint)
    if requestCount >= 5 then
        return false
    end
    
    requestCount = requestCount + 1
    SetTimeout(60000, function()
        requestCount = requestCount - 1
    end)
    
    local p = promise.new()
    
    PerformHttpRequest("" .. endpoint, function(statusCode, responseData)
        local data = false
        if responseData then
            data = json.decode(responseData) or false
        end
        p:resolve(data)
    end, "GET", "", {
        ["Content-Type"] = "application/json"
    })
    
    return Citizen.Await(p)
end


local cryptoData = {
    hasFetched = false,
    coins = {},
    customCoins = {}
}


local coinList = nil
if Config.Crypto.Coins and #Config.Crypto.Coins > 0 then
    coinList = table.concat(Config.Crypto.Coins, ",")
end


local function FetchCoinData()
    local lastFetched = GetResourceKvpInt("lb-phone:crypto:lastFetched") or 0
    local currentTime = os.time()
    local refreshInterval = Config.Crypto.Refresh / 1000
    

    if lastFetched > (currentTime - refreshInterval) then
        local cachedData = GetResourceKvpString("lb-phone:crypto:coins")
        if cachedData then
            cryptoData.coins = json.decode(cachedData)
            

            for coinId, coinData in pairs(cryptoData.customCoins) do
                cryptoData.coins[coinId] = coinData
            end
            
            debugprint("crypto: using kvp cache")
            return
        end
    end
    

    local apiData = {}
    if coinList then
        apiData = MakeAPIRequest("coins/markets?vs_currency=" .. Config.Crypto.Currency .. 
                                "&sparkline=true&order=market_cap_desc&precision=full&per_page=100&page=1&ids=" .. coinList) or {}
    end
    
    if not apiData then
        debugprint("failed to fetch coins")
        return
    end
    

    for i = 1, #apiData do
        local coin = apiData[i]
        cryptoData.coins[coin.id] = {
            id = coin.id,
            name = coin.name,
            symbol = coin.symbol,
            image = coin.image,
            current_price = coin.current_price,
            prices = coin.sparkline_in_7d and coin.sparkline_in_7d.price,
            change_24h = coin.price_change_percentage_24h
        }
    end
    

    for coinId, coinData in pairs(cryptoData.customCoins) do
        cryptoData.coins[coinId] = coinData
    end
    

    SetResourceKvpInt("lb-phone:crypto:lastFetched", os.time())
    SetResourceKvp("lb-phone:crypto:coins", json.encode(cryptoData.coins))
    
    debugprint("fetched coins")
end


CreateThread(function()
    while true do
        FetchCoinData()
        cryptoData.hasFetched = true
        

        TriggerClientEvent("phone:crypto:updateCoins", -1, cryptoData.coins)
        
        Wait(Config.Crypto.Refresh)
    end
end)


local function AddCryptoToPortfolio(identifier, coinId, amount, invested)
    MySQL.update.await("INSERT INTO phone_crypto (id, coin, amount, invested) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount), invested = invested + VALUES(invested)", {
        identifier,
        coinId,
        amount,
        invested or 0
    })
end


RegisterCallback("crypto:get", function(source)
    local identifier = GetIdentifier(source)
    

    while not cryptoData.hasFetched or not DatabaseCheckerFinished do
        Wait(500)
    end
    

    local holdings = MySQL.query.await("SELECT coin, amount, invested FROM phone_crypto WHERE id = ?", {
        identifier
    })
    

    local portfolio = table.deep_clone(cryptoData.coins)
    
    for i = 1, #holdings do
        local holding = holdings[i]
        if holding and portfolio[holding.coin] then
            portfolio[holding.coin].owned = holding.amount
            portfolio[holding.coin].invested = holding.invested
        end
    end
    
    return portfolio
end)


RegisterCallback("crypto:buy", function(source, coinId, amount)
    local identifier = GetIdentifier(source)
    local balance = GetBalance(source)
    

    if amount <= 0 then
        return {
            success = false,
            msg = "INVALID_AMOUNT"
        }
    end
    

    if amount > limits.Buy then
        debugprint(amount, "is above crypto buy limit")
        return {
            success = false,
            msg = "INVALID_AMOUNT"
        }
    end
    

    if amount > balance then
        return {
            success = false,
            msg = "NO_MONEY"
        }
    end
    

    local coin = cryptoData.coins[coinId]
    if not coin then
        return {
            success = false,
            msg = "INVALID_COIN"
        }
    end
    

    if not identifier then
        return {
            success = false,
            msg = "NO_IDENTIFIER"
        }
    end
    

    local cryptoAmount = amount / coin.current_price
    

    AddCryptoToPortfolio(identifier, coinId, cryptoAmount, amount)
    

    RemoveMoney(source, amount, "Mua tiền điện tử", "priority")
    

    Log("Crypto", source, "success",
        L("BACKEND.LOGS.BOUGHT_CRYPTO"),
        L("BACKEND.LOGS.CRYPTO_DETAILS", {
            coin = coinId,
            amount = cryptoAmount,
            price = amount
        })
    )
    
    return {
        success = true
    }
end, {
    preventSpam = true
})


RegisterCallback("crypto:sell", function(source, coinId, amount)
    local identifier = GetIdentifier(source)
    

    if amount <= 0 then
        return {
            success = false,
            msg = "INVALID_AMOUNT"
        }
    end
    

    local holding = MySQL.single.await("SELECT amount, invested FROM phone_crypto WHERE id = ? AND coin = ?", {
        identifier,
        coinId
    })
    
    if not holding then
        return {
            success = false,
            msg = "NO_COINS"
        }
    end
    

    if amount > holding.amount then
        return {
            success = false,
            msg = "NOT_ENOUGH_COINS"
        }
    end
    

    local coin = cryptoData.coins[coinId]
    if not coin then
        return {
            success = false,
            msg = "INVALID_COIN"
        }
    end
    

    local saleValue = amount * coin.current_price
    

    if saleValue > limits.Sell then
        debugprint(saleValue, "is above crypto sell limit")
        return {
            success = false,
            msg = "INVALID_AMOUNT"
        }
    end
    

    MySQL.update.await("UPDATE phone_crypto SET amount = amount - ?, invested = invested - ? WHERE id = ? AND coin = ?", {
        amount,
        saleValue,
        identifier,
        coinId
    })
    

    AddMoney(source, saleValue, "tienkhoa")
    

    Log("Crypto", source, "error",
        L("BACKEND.LOGS.SOLD_CRYPTO"),
        L("BACKEND.LOGS.CRYPTO_DETAILS", {
            coin = coinId,
            amount = amount,
            price = saleValue
        })
    )
    
    return {
        success = true
    }
end, {
    preventSpam = true
})


BaseCallback("crypto:transfer", function(source, phoneNumber, coinId, amount, targetNumber)

    local coin = cryptoData.coins[coinId]
    if not coin then
        return {
            success = false,
            msg = "INVALID_COIN"
        }
    end
    

    local targetSource = GetSourceFromNumber(targetNumber)
    local targetIdentifier = nil
    
    if targetSource then
        targetIdentifier = GetIdentifier(targetSource)
    else
        targetIdentifier = MySQL.scalar.await("SELECT id FROM phone_phones WHERE phone_number = ?", {
            targetNumber
        })
    end
    
    if not targetIdentifier then
        return {
            success = false,
            msg = "INVALID_NUMBER"
        }
    end
    
    local senderIdentifier = GetIdentifier(source)
    

    if amount <= 0 then
        return {
            success = false,
            msg = "INVALID_AMOUNT"
        }
    end
    

    local senderAmount = MySQL.scalar.await("SELECT amount FROM phone_crypto WHERE id = ? AND coin = ?", {
        senderIdentifier,
        coinId
    }) or 0
    
    if amount > senderAmount then
        return {
            success = false,
            msg = "INVALID_AMOUNT"
        }
    end
    

    MySQL.update.await("UPDATE phone_crypto SET amount = amount - ? WHERE id = ? AND coin = ?", {
        amount,
        senderIdentifier,
        coinId
    })
    

    AddCryptoToPortfolio(targetIdentifier, coinId, amount)
    

    SendNotification(targetNumber, {
        app = "Crypto",
        title = L("BACKEND.CRYPTO.RECEIVED_TRANSFER_TITLE", {
            coin = coin.name
        }),
        content = L("BACKEND.CRYPTO.RECEIVED_TRANSFER_DESCRIPTION", {
            amount = amount,
            coin = coin.name,
            value = math.floor(amount * coin.current_price + 0.5)
        })
    })
    

    Log("Crypto", source, "error",
        L("BACKEND.LOGS.TRANSFERRED_CRYPTO"),
        L("BACKEND.LOGS.TRANSFERRED_CRYPTO_DETAILS", {
            coin = coinId,
            amount = amount,
            to = targetNumber,
            from = phoneNumber
        })
    )
    

    if targetSource then
        TriggerClientEvent("phone:crypto:changeOwnedAmount", targetSource, coinId, amount)
    end
    
    return {
        success = true
    }
end, {
    preventSpam = true
})


exports("AddCrypto", function(source, coinId, amount)
    local identifier = GetIdentifier(source)
    local coin = cryptoData.coins[coinId]
    
    if not coin then
        print("invalid coin", coinId)
        return false
    end
    
    if not identifier then
        print("no identifier")
        return false
    end
    
    AddCryptoToPortfolio(identifier, coinId, amount)
    TriggerClientEvent("phone:crypto:changeOwnedAmount", source, coinId, amount)
    
    return true
end)


exports("RemoveCrypto", function(source, coinId, amount)
    local identifier = GetIdentifier(source)
    local coin = cryptoData.coins[coinId]
    
    if not coin then
        print("invalid coin", coinId)
        return false
    end
    
    if not identifier then
        print("no identifier")
        return false
    end
    
    MySQL.Async.execute("UPDATE phone_crypto SET amount = amount - ? WHERE id = ? AND coin = ?", {
        amount,
        identifier,
        coinId
    })
    
    TriggerClientEvent("phone:crypto:changeOwnedAmount", source, coinId, -amount)
    
    return true
end)


exports("AddCustomCoin", function(id, name, symbol, image, currentPrice, prices, change24h)
    assert(type(id) == "string", "id must be a string")
    assert(type(name) == "string", "name must be a string")
    assert(type(symbol) == "string", "symbol must be a string")
    assert(type(image) == "string", "image must be a string")
    assert(type(currentPrice) == "number", "currentPrice must be a number")
    assert(type(prices) == "table", "prices must be a table")
    assert(type(change24h) == "number", "change24h must be a number")
    
    local coinData = {
        id = id,
        name = name,
        symbol = symbol,
        image = image,
        current_price = currentPrice,
        prices = prices,
        change_24h = change24h
    }
    
    cryptoData.customCoins[id] = coinData
    cryptoData.coins[id] = coinData
    

    SetResourceKvp("lb-phone:crypto:coins", json.encode(cryptoData.coins))
    

    TriggerClientEvent("phone:crypto:updateCoins", -1, cryptoData.coins)
end)


exports("GetCoin", function(coinId)
    return cryptoData.coins[coinId]
end)
