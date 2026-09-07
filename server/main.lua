local states = {}

local function isAdmin(source)
    local ok, allowed = pcall(function()
        return exports.qbcore:hasPermission(source, 'admin')
    end)
    return ok and allowed == true
end

local function leaves(door)
    return door.doors or { { model = door.model, coords = door.coords } }
end

local function managementSnapshot(source)
    if not isAdmin(source) then return nil, 'You do not have permission to manage door locks.' end

    local result = {}
    for id, door in pairs(Config.Doors) do
        result[#result + 1] = {
            id = id,
            label = door.label,
            locked = states[id] == true,
            leaves = #(leaves(door)),
            autoLock = door.autoLock or Config.DefaultAutoLock,
        }
    end
    table.sort(result, function(a, b) return a.label:lower() < b.label:lower() end)
    return result
end

local function getDoor(id)
    local door = Config.Doors[id]
    return type(door) == 'table' and door or nil
end

local function getPlayer(source)
    local ok, player = pcall(function() return exports.qbcore:getPlayer(source) end)
    return ok and type(player) == 'table' and player or nil
end

local function matchesGroup(player, groups)
    if type(groups) ~= 'table' then return false end
    for name, minimumGrade in pairs(groups) do
        for _, role in ipairs({ player.job, player.gang }) do
            if role and role.name == name and (role.grade and role.grade.level or 0) >= (tonumber(minimumGrade) or 0) then
                return true
            end
        end
    end
    return false
end

local function hasAccess(source, door)
    -- A door with no access restriction is public. Multiple configured methods
    -- are alternatives, matching ox_doorlock's usual groups/items behaviour.
    if not door.groups and not door.citizenIds and not door.items then return true end
    local player = getPlayer(source)
    if not player then return false end
    if matchesGroup(player, door.groups) then return true end
    if type(door.citizenIds) == 'table' then
        if door.citizenIds[player.citizenid] then return true end
        for _, citizenId in ipairs(door.citizenIds) do
            if citizenId == player.citizenid then return true end
        end
    end
    if door.items then
        local items = type(door.items) == 'string' and { door.items } or door.items
        for _, item in ipairs(items) do
            local ok, hasItem = pcall(function() return exports.qbcore:hasItem(source, item) end)
            if ok and hasItem then return true end
        end
    end
    return false
end

local function isNearDoor(source, door)
    local ped = GetPlayerPed(source)
    if ped <= 0 then return false end
    local pos = GetEntityCoords(ped)
    local maxDistance = (door.distance or Config.InteractionDistance) + 1.0
    for _, leaf in ipairs(leaves(door)) do
        if #(pos - leaf.coords) <= maxDistance then return true end
    end
    return false
end

local function setState(id, locked)
    states[id] = locked == true
    TriggerClientEvent('qbdoorlock:client:sync', -1, id, states[id])
end

local function scheduleAutoLock(id, delay)
    SetTimeout(delay, function()
        if states[id] == false then setState(id, true) end
    end)
end

RegisterNetEvent('qbdoorlock:server:requestStates', function()
    TriggerClientEvent('qbdoorlock:client:states', source, states)
end)

RegisterNetEvent('qbdoorlock:server:toggle', function(id)
    if type(id) ~= 'string' then return end
    local door = getDoor(id)
    if not door or not isNearDoor(source, door) then return end
    if not hasAccess(source, door) then
        TriggerClientEvent('qbdoorlock:client:denied', source)
        return
    end
    local locked = not states[id]
    setState(id, locked)
    if not locked then
        local delay = door.autoLock or Config.DefaultAutoLock
        if type(delay) == 'number' and delay > 0 then scheduleAutoLock(id, delay) end
    end
end)

QB.callback.register('qbdoorlock:managementSnapshot', function(source)
    return managementSnapshot(source)
end, { rateLimit = { max = 10, window = 10000 } })

QB.callback.register('qbdoorlock:managementSetState', function(source, id, locked)
    if not isAdmin(source) then return nil, 'You do not have permission to manage door locks.' end
    if type(id) ~= 'string' or type(locked) ~= 'boolean' or not getDoor(id) then
        return nil, 'That door is no longer configured.'
    end

    setState(id, locked)
    return managementSnapshot(source)
end, { rateLimit = { max = 20, window = 10000 } })

-- Useful for other server resources (alarms, heists, admin tooling). This is
-- deliberately server-only: clients cannot set a door state by calling it.
exports('setDoorState', function(id, locked)
    if not getDoor(id) or type(locked) ~= 'boolean' then return false end
    setState(id, locked)
    return true
end)

exports('getDoorState', function(id)
    return states[id]
end)

for id, door in pairs(Config.Doors) do states[id] = door.locked == true end
