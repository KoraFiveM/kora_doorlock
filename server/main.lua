local states = {}
local linkedDoors = {}
local RESOURCE = GetCurrentResourceName()
local databaseReady = false

local function checksum(value)
    local hash = 2166136261
    for i = 1, #value do hash = ((hash ~ value:byte(i)) * 16777619) & 0xFFFFFFFF end
    return ('%08x'):format(hash)
end

local function isAdmin(source)
    local ok, allowed = pcall(function()
        return exports.qbcore:hasPermission(source, 'admin')
    end)
    return ok and allowed == true
end

local function leaves(door)
    return door.doors or { { model = door.model, coords = door.coords } }
end

local function copyCoords(coords)
    return { x = coords.x, y = coords.y, z = coords.z }
end

local function networkDefinition(door)
    local result = {
        label = door.label, locked = door.locked == true, distance = door.distance,
        groups = door.groups, citizenIds = door.citizenIds, items = door.items, autoLock = door.autoLock,
    }
    if door.doors then
        result.doors = {}
        for index, leaf in ipairs(door.doors) do
            result.doors[index] = { model = leaf.model, coords = copyCoords(leaf.coords) }
        end
    else
        result.model, result.coords = door.model, copyCoords(door.coords)
    end
    return result
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
            linkedTo = linkedDoors[id],
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

    local linkedId = linkedDoors[id]
    if linkedId and getDoor(linkedId) then
        states[linkedId] = states[id]
        TriggerClientEvent('qbdoorlock:client:sync', -1, linkedId, states[linkedId])
    end
end

local function addDoor(id, definition)
    Config.Doors[id] = definition
    states[id] = definition.locked == true
    TriggerClientEvent('qbdoorlock:client:addDoor', -1, id, networkDefinition(definition), states[id])
end

local function scheduleAutoLock(id, delay)
    SetTimeout(delay, function()
        if states[id] == false then setState(id, true) end
    end)
end

RegisterNetEvent('qbdoorlock:server:requestStates', function()
    TriggerClientEvent('qbdoorlock:client:states', source, states)
end)

RegisterNetEvent('qbdoorlock:server:requestDefinitions', function()
    local result = {}
    for id, door in pairs(Config.Doors) do result[id] = networkDefinition(door) end
    TriggerClientEvent('qbdoorlock:client:definitions', source, result, states)
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

QB.callback.register('qbdoorlock:managementLinkDoors', function(source, id, linkedId)
    if not isAdmin(source) then return nil, 'You do not have permission to manage door locks.' end
    if not databaseReady then return nil, 'Door storage is still starting.' end
    if type(id) ~= 'string' or type(linkedId) ~= 'string' or id == linkedId or not getDoor(id) or not getDoor(linkedId) then
        return nil, 'Choose two different configured doors.'
    end
    if linkedDoors[id] or linkedDoors[linkedId] then return nil, 'Unlink either door before creating a new pair.' end

    local saved, err = QB.sql.execute('INSERT INTO `qbdoorlock_links` (`door_id`, `linked_door_id`) VALUES (?, ?), (?, ?)', {
        id, linkedId, linkedId, id,
    })
    if not saved then return nil, err or 'Could not save the door link.' end

    linkedDoors[id], linkedDoors[linkedId] = linkedId, id
    setState(linkedId, states[id])
    return managementSnapshot(source)
end, { rateLimit = { max = 10, window = 10000 } })

QB.callback.register('qbdoorlock:managementUnlinkDoors', function(source, id)
    if not isAdmin(source) then return nil, 'You do not have permission to manage door locks.' end
    if not databaseReady then return nil, 'Door storage is still starting.' end
    if type(id) ~= 'string' or not getDoor(id) then return nil, 'That door is no longer configured.' end
    local linkedId = linkedDoors[id]
    if not linkedId then return nil, 'That door is not linked.' end

    local removed, err = QB.sql.update('DELETE FROM `qbdoorlock_links` WHERE `door_id` IN (?, ?)', { id, linkedId })
    if removed == nil then return nil, err or 'Could not remove the door link.' end

    linkedDoors[id], linkedDoors[linkedId] = nil, nil
    return managementSnapshot(source)
end, { rateLimit = { max = 10, window = 10000 } })

QB.callback.register('qbdoorlock:managementCreateDoor', function(source, data)
    if not isAdmin(source) then return nil, 'You do not have permission to create door locks.' end
    if not databaseReady then return nil, 'Door storage is still starting.' end
    if type(data) ~= 'table' then return nil, 'Invalid door data.' end

    local id = type(data.id) == 'string' and data.id:lower() or ''
    if not id:match('^[a-z0-9][a-z0-9_-]{0,63}$') then return nil, 'Door ID must use letters, numbers, dashes, or underscores.' end
    if Config.Doors[id] then return nil, 'That door ID is already in use.' end
    local label = type(data.label) == 'string' and data.label:gsub('^%s*(.-)%s*$', '%1') or ''
    if #label < 1 or #label > 64 then return nil, 'Door name must be between 1 and 64 characters.' end
    local ped = GetPlayerPed(source)
    local playerCoords = ped > 0 and GetEntityCoords(ped) or nil
    if not playerCoords then return nil, 'You must be standing near the selected door.' end

    local function validateLeaf(leaf)
        local model = type(leaf) == 'table' and tonumber(leaf.model) or nil
        local coords = type(leaf) == 'table' and leaf.coords or nil
        if not model or model == 0 or type(coords) ~= 'table' then return nil end
        local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
        if not x or not y or not z then return nil end
        local doorCoords = vector3(x, y, z)
        if #(playerCoords - doorCoords) > 12.0 then return nil end
        return { model = math.floor(model), coords = doorCoords }
    end

    local selectedDoor = validateLeaf(data)
    if not selectedDoor then return nil, 'Look directly at a valid nearby door and try again.' end

    local groups
    local group = type(data.group) == 'string' and data.group:lower():gsub('[^%w_-]', '') or ''
    if group ~= '' then groups = { [group] = math.max(0, math.floor(tonumber(data.grade) or 0)) } end
    local autoLock = tonumber(data.autoLock)
    if autoLock and (autoLock < 0 or autoLock > 3600) then return nil, 'Auto-lock must be between 0 and 3600 seconds.' end

    local definition = {
        label = label, model = selectedDoor.model, coords = selectedDoor.coords, locked = data.locked == true,
        groups = groups, autoLock = autoLock and math.floor(autoLock * 1000) or nil,
    }
    local stored = json.encode(networkDefinition(definition))
    -- `qbdoorlock_doors` has a string primary key, so a successful INSERT has
    -- no numeric insert ID. Use execute so success is represented by its
    -- result packet instead of the always-zero insert-ID compatibility value.
    local saved, err = QB.sql.execute('INSERT INTO `qbdoorlock_doors` (`id`, `definition`) VALUES (?, ?)', { id, stored })
    if saved == nil then return nil, err or 'Could not save the door.' end
    addDoor(id, definition)
    return managementSnapshot(source)
end, { rateLimit = { max = 5, window = 10000 } })

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

CreateThread(function()
    if not QB.sql.ready(60000) then return print('^1[qbdoorlock]^7 qbsql was not ready; in-game door creation is disabled.') end
    local doorsSql = assert(LoadResourceFile(RESOURCE, 'sql/001_doors.sql'), 'missing qbdoorlock door migration')
    local linksSql = assert(LoadResourceFile(RESOURCE, 'sql/002_links.sql'), 'missing qbdoorlock link migration')
    local _, migrationErr = QB.sql.migrate(RESOURCE, {
        { version = 1, name = 'doors', sql = doorsSql, checksum = checksum(doorsSql) },
        { version = 2, name = 'links', sql = linksSql, checksum = checksum(linksSql) },
    })
    if migrationErr then return print(('^1[qbdoorlock]^7 migration failed: %s'):format(migrationErr)) end
    local rows, queryErr = QB.sql.query('SELECT `id`, `definition` FROM `qbdoorlock_doors`')
    if queryErr then return print(('^1[qbdoorlock]^7 could not load created doors: %s'):format(queryErr)) end
    for _, row in ipairs(rows) do
        local ok, definition = pcall(json.decode, row.definition)
        if ok and type(definition) == 'table' and type(row.id) == 'string' and not Config.Doors[row.id]
            and definition.model and type(definition.coords) == 'table' and definition.label then
            definition.coords = vector3(definition.coords.x, definition.coords.y, definition.coords.z)
            addDoor(row.id, definition)
        else
            print(('^3[qbdoorlock]^7 skipped invalid or duplicate stored door %s'):format(tostring(row.id)))
        end
    end
    local links, linksErr = QB.sql.query('SELECT `door_id`, `linked_door_id` FROM `qbdoorlock_links`')
    if linksErr then return print(('^1[qbdoorlock]^7 could not load door links: %s'):format(linksErr)) end
    local candidates = {}
    for _, row in ipairs(links) do
        if type(row.door_id) == 'string' and type(row.linked_door_id) == 'string' and row.door_id ~= row.linked_door_id
            and getDoor(row.door_id) and getDoor(row.linked_door_id) then
            candidates[row.door_id] = row.linked_door_id
        end
    end
    for id, linkedId in pairs(candidates) do
        if candidates[linkedId] == id then linkedDoors[id] = linkedId end
    end
    databaseReady = true
end)
