if Config.Framework ~= "qb" then
    return
end

while not QB do
    Wait(500)
    debugprint("Services: Waiting for QB to load")
end

local playerJobs = {}
local jobCounts = {}
local jobDutyCounts = {}

---@param source number
---@return string
function GetJob(source)
    local qPlayer = QB.Functions.GetPlayer(tonumber(source))

    if not qPlayer then
        debugprint("GetJob: Failed to get player for source:", source)
        return "unemployed"
    end

    return qPlayer.PlayerData.job.name
end

---@param job string
---@return { firstname: string, lastname: string, grade: string, number: string }[] employees
function GetAllEmployees(job)
    -- Không dùng unique phone, chỉ dùng phone_phones
    local employees = MySQL.query.await(([[
        SELECT
            JSON_UNQUOTE(JSON_EXTRACT(u.charinfo, '$.firstname')) AS firstname,
            JSON_UNQUOTE(JSON_EXTRACT(u.charinfo, '$.lastname')) AS lastname,
            u.citizenid,
            JSON_UNQUOTE(JSON_EXTRACT(u.job, '$.grade.level')) AS grade,
            JSON_UNQUOTE(JSON_EXTRACT(u.job, '$.grade.name')) AS gradeLabel,
            p.phone_number AS `number`
        FROM players u
        LEFT JOIN phone_phones p ON u.citizenid = p.id COLLATE UTF8MB4_GENERAL_CI
        WHERE JSON_UNQUOTE(JSON_EXTRACT(u.job, '$.name')) = ?
    ]]):format(numberTable), { job })

    for i = 1, #employees do
        local employee = employees[i]
        local player = QB.Functions.GetPlayerByCitizenId(employee.citizenid)

        employee.citizenid = nil

        if player and player.PlayerData?.job then
            employee.duty = player.PlayerData.job.onduty
        end
    end

    return employees
end

---Get an array of player sources with a specific job
---@param job string
---@return table # Player sources
function GetEmployees(job)
    local employees = {}
    local players = QB.Functions.GetQBPlayers()

    for _, v in pairs(players) do
        if v?.PlayerData.job.name == job and v.PlayerData.job.onduty then
            employees[#employees+1] = v.PlayerData.source
        end
    end

    return employees
end

function RefreshCompanies()
    if Config.QBOldJobMethod then
        debugprint("using old method to refresh companies")

        local openJobs = {}
        local players = QB.Functions.GetQBPlayers()

        for _, v in pairs(players) do
            if not v?.PlayerData.job.onduty then
                goto continue
            end

            local job = v.PlayerData.job.name

            if not openJobs[job] then
                openJobs[job] = true
            end

            ::continue::
        end

        for i = 1, #Config.Companies.Services do
            local jobData = Config.Companies.Services[i]

            jobData.open = openJobs[jobData.job] or false
        end

        return
    end

    for i = 1, #Config.Companies.Services do
        local jobData = Config.Companies.Services[i]

        jobData.open = (jobDutyCounts[jobData.job] or 0) > 0
    end
end

CreateThread(function()
    local players = QB.Functions.GetQBPlayers()

    for _, player in pairs(players) do
        local playerData = player.PlayerData
        local job = playerData.job
        local jobName = job.name
        local onDuty = job.onduty

        playerJobs[playerData.source] = {
            name = jobName,
            onduty = onDuty
        }

        jobCounts[jobName] = (jobCounts[jobName] or 0) + 1
        jobDutyCounts[jobName] = (jobDutyCounts[jobName] or 0) + (onDuty and 1 or 0)
    end

    debugprint("qb jobs: initial data", playerJobs, jobCounts, jobDutyCounts)
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local job = Player.PlayerData.job
    local src = Player.PlayerData.source
    local jobName = job?.name
    local onDuty = job?.onduty

    if not jobName then
        return
    end

    playerJobs[src] = {
        name = jobName,
        onduty = onDuty
    }

    jobCounts[jobName] = (jobCounts[jobName] or 0) + 1
    jobDutyCounts[jobName] = (jobDutyCounts[jobName] or 0) + (onDuty and 1 or 0)

    debugprint("qb jobs: player loaded update (src, job, duty)", src, job.name, job.onduty)
end)

AddEventHandler("QBCore:Server:OnJobUpdate", function(src, job)
    local shouldRefresh = false
    local lastJob = playerJobs[src]
    local lastName = lastJob and lastJob.name
    local lastDuty = lastJob and lastJob.onduty
    local jobName = job.name
    local onDuty = job.onduty

    Wait(0)
    debugprint("qb jobs: job update (src, job, duty)", src, job.name, job.onduty)

    if lastJob and lastName == jobName then
        if lastJob.onduty == onDuty then
            return
        end

        jobDutyCounts[jobName] = (jobDutyCounts[jobName] or 0) + (onDuty and 1 or -1)
    else
        if lastJob then
            jobCounts[lastName] = (jobCounts[lastName] or 0) - 1
            jobDutyCounts[lastName] = (jobDutyCounts[lastName] or 0) - (lastDuty and 1 or 0)

            local oldCount = jobDutyCounts[lastName]

            if oldCount == 0 or oldCount == 1 then
                TriggerClientEvent("phone:services:updateOpen", -1, lastName, oldCount == 1)
                shouldRefresh = true
            end
        end

        jobCounts[jobName] = (jobCounts[jobName] or 0) + 1
        jobDutyCounts[jobName] = (jobDutyCounts[jobName] or 0) + (onDuty and 1 or 0)
    end

    playerJobs[src] = {
        name = jobName,
        onduty = onDuty
    }

    local newCount = jobDutyCounts[jobName]

    if newCount == 0 or newCount == 1 then
        TriggerClientEvent("phone:services:updateOpen", -1, jobName, newCount == 1)
        shouldRefresh = true
    end

    if shouldRefresh then
        RefreshCompanies()
    end

    debugprint(playerJobs, jobCounts, jobDutyCounts)
end)

local function UnloadJob(src)
    local lastJob = playerJobs[src]

    if not lastJob then
        return
    end

    jobCounts[lastJob.name] = (jobCounts[lastJob.name] or 0) - 1
    jobDutyCounts[lastJob.name] = (jobDutyCounts[lastJob.name] or 0) - (lastJob.onduty and 1 or 0)

    playerJobs[src] = nil

    debugprint(playerJobs, jobCounts, jobDutyCounts)
end

AddEventHandler("QBCore:Server:OnPlayerUnload", function(src)
    Wait(0)
    debugprint("qb jobs: player unload", src)

    UnloadJob(src)
end)

AddEventHandler("playerDropped", function()
    local src = source

    debugprint("qb jobs: player dropped", src)
    UnloadJob(src)
end)

RegisterCallback("services:getPlayerData", function(_, player)
    local first, last = GetCharacterName(player)

    return {
        name = first .. " " .. last,
        id = GetIdentifier(player),
    }
end)

local function GetSocietyMoney(job)
    return exports['Renewed-Banking']:getAccountMoney(job) or 0
end

RegisterCallback("services:getAccount", function(source)
    local Player = QB.Functions.GetPlayer(source)
    if not Player then return 0 end

    local job = Player.PlayerData.job
    local jobName = job.name

    if not job.isboss then
        return 0
    end

    local money = GetSocietyMoney(jobName)
    return money
end)

RegisterCallback("services:addMoney", function(source, amount)
    local job = GetJob(source)

    if amount <= 0 or GetBalance(source) < amount then
        return false
    end

    local success = exports['Renewed-Banking']:addAccountMoney(job, amount)

    if success then
        RemoveMoney(source, amount, "Nộp tiền vào công ty", "priority")
        return GetSocietyMoney(job)
    end

    return false
end)

RegisterCallback("services:removeMoney", function(source, amount)
    local job = GetJob(source)

    if amount <= 0 or GetSocietyMoney(job) < amount then
        return false
    end

    local success = exports['Renewed-Banking']:removeAccountMoney(job, amount)

    if success then
        AddMoney(source, amount, "tienkhoa")
        return GetSocietyMoney(job)
    end

    return false
end)