
BaseCallback("appstore:purchase", function(source, callback, data)
    local price = data.price
    local phoneNumber = GetEquippedPhoneNumber(source)
    
    if not phoneNumber then
        callback(false)
        return
    end
    

    local success = RemoveMoney(source, price, "Mua ứng dụng", "priority")
    callback(success)
end)
