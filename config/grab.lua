-- Grab App Configuration
Config = Config or {}

Config.Grab = {
    -- Pricing configuration
    pricePerMeter = 100, -- Price per meter in dollars
    minimumPrice = 50,   -- Minimum ride price
    maximumPrice = 5000, -- Maximum ride price
    
    -- Distance configuration
    maxSearchRadius = 1000, -- Maximum search radius for drivers (meters)
    arrivalDistance = 10,   -- Distance to consider driver "arrived" (meters)
    
    -- Timing configuration
    requestTimeout = 15000, -- Time for driver to respond to ride request (ms)
    
    -- Driver requirements
    requireVehicle = true,  -- Driver must be in vehicle to accept rides
    
    -- Blip configuration
    driverBlip = {
        sprite = 280,  -- Taxi icon
        color = 5,     -- Yellow
        scale = 0.7
    },
    
    passengerBlip = {
        sprite = 280,  -- Taxi icon
        color = 2,     -- Green
        scale = 0.9
    },
    
    -- Notification settings
    useF17Notify = true,    -- Use f17notify for short messages
    useQBNotify = true,     -- Use QBCore:Notify for detailed messages
}