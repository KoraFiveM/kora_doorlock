local RESOURCE = GetCurrentResourceName()
local doors, states, linkedDoors, configuredIds = {}, {}, {}, {}
local autoLockTimers, pendingLockpicks = {}, {}
local databaseReady, initializationComplete = false, false
local hooks, nextHookId = {}, 0

local function translate(key, replacements)
    return QB.lang(key, replacements)
end

local function checksum(value)
    local hash = 2166136261
    for index = 1, #value do hash = ((hash ~ value:byte(index)) * 16777619) & 0xFFFFFFFF end
    return ('%08x'):format(hash)
end

local function isAdmin(source)
    return QB.permissions.hasPermission(source, Config.AdminPermission or 'admin', Config.AdminPermissionPrefix or 'qbcore')
end

local function doorLeaves(door)
    return door.doors or { { model = door.model, coords = door.coords, heading = door.heading } }
end

local function getDoor(id)
    return type(id) == 'string' and doors[id] or nil
end

local function getPlayer(source)
    local ok, player = pcall(function() return exports.qbcore:getPlayer(source) end)
    return ok and type(player) == 'table' and player or nil
end

local function gradeLevel(role)
    if type(role) ~= 'table' then return 0 end
    if type(role.grade) == 'table' then return tonumber(role.grade.level) or 0 end
    return tonumber(role.grade) or tonumber(role.gradeLevel) or 0
end

local function matchesGroup(player, groups)
    if type(player) ~= 'table' or type(groups) ~= 'table' then return false end
    for name, minimumGrade in pairs(groups) do
        for _, role in ipairs({ player.job, player.gang }) do
            if role and role.name == name and gradeLevel(role) >= minimumGrade then return true end
        end
    end
    return false
end

local function matchesCharacter(player, characters)
    if type(player) ~= 'table' or type(characters) ~= 'table' then return false end
    local citizenId = tostring(player.citizenid or player.charid or '')
    for _, character in ipairs(characters) do if tostring(character) == citizenId then return true end end
    return false
end

local function metadataMatches(actual, required)
    if required == nil then return true end
    actual = type(actual) == 'table' and actual or {}
    for key, value in pairs(required) do if actual[key] ~= value then return false end end
    return true
end

local function findItem(source, requirements)
    if type(requirements) ~= 'table' then return nil end
    for _, requirement in ipairs(requirements) do
        local ok, items = pcall(function() return exports.qbcore:getItemsByName(source, requirement.name) end)
        if ok and type(items) == 'table' then
            for _, item in pairs(items) do
                if type(item) == 'table' and (tonumber(item.amount) or 0) > 0
                    and metadataMatches(item.info or item.metadata, requirement.metadata) then
                    return requirement, item.slot
                end
            end
        end
    end
end

local function removeItem(source, requirement, slot)
    if not requirement then return false end
    local ok, removed = pcall(function()
        return exports.qbcore:removeItem(source, requirement.name, 1, slot, 'qbdoorlock')
    end)
    return ok and removed == true
end

local hookOwnership = QB.resources.serverRegistry(function(hookId) hooks[hookId] = nil end)

local function triggerHooks(event, payload)
    local response
    for hookId, definition in pairs(hooks) do
        if definition.event == event and (not definition.nameFilter or payload.door.label:match(definition.nameFilter)) then
            if definition.print then
                print(('[qbdoorlock] triggering %s hook %d from %s'):format(event, hookId, definition.resource))
            end
            local ok, result = pcall(definition.callback, payload)
            if not ok then
                print(('^3[qbdoorlock]^7 %s hook %d failed: %s'):format(event, hookId, tostring(result)))
            elseif result ~= nil then
                response = result == true
            end
        end
    end
    return response
end

local function registerHook(event, callback, options)
    assert(event == 'doorAuthorization', 'qbdoorlock only supports the doorAuthorization hook.')
    assert(QB.compat.isCallable(callback), 'qbdoorlock hook callback must be callable.')
    assert(options == nil or type(options) == 'table', 'qbdoorlock hook options must be a table.')
    if options and options.nameFilter ~= nil then
        assert(type(options.nameFilter) == 'string' and options.nameFilter ~= '', 'qbdoorlock hook nameFilter must be a non-empty Lua pattern.')
        assert(pcall(string.match, '', options.nameFilter), 'qbdoorlock hook nameFilter is not a valid Lua pattern.')
    end
    local owner = GetInvokingResource() or RESOURCE
    nextHookId = nextHookId + 1
    hooks[nextHookId] = {
        event = event, callback = callback, resource = owner,
        nameFilter = options and options.nameFilter, print = options and options.print == true,
    }
    hookOwnership.track(owner, nextHookId)
    return nextHookId
end

local function removeHook(hookId)
    local definition = hooks[hookId]
    if not definition then return false end
    local caller = GetInvokingResource()
    if caller and definition.resource ~= caller then return false end
    hooks[hookId] = nil
    hookOwnership.untrack(hookId)
    return true
end

---@param event 'doorAuthorization'
---@param callback fun(payload: table): boolean?
---@param options? {nameFilter?: string, print?: boolean}
---@return integer hookId
exports('registerHook', registerHook)

---@param hookId integer
---@return boolean removed
exports('removeHook', removeHook)

local function isNearDoor(source, door)
    local maxDistance = door.distance + 1.0
    for _, leaf in ipairs(doorLeaves(door)) do if QB.distance.player(source, leaf.coords, maxDistance) then return true end end
    return false
end

local function hasDoorAce(source, id, door)
    if Config.PlayerAceAuthorised and QB.permissions.hasPermission(source, Config.PlayerAcePermission or 'doorlock') then return true end
    return QB.permissions.hasPermission(source, id, 'doorlock')
        or QB.permissions.hasPermission(source, door.label, 'doorlock')
end

local function hasAccess(source, id, door, lockpick)
    local player = getPlayer(source)
    local authorised, usedRequirement, usedSlot = hasDoorAce(source, id, door), nil, nil
    if lockpick then
        local requirements = {}
        for _, name in ipairs(Config.LockpickItems or {}) do requirements[#requirements + 1] = { name = name } end
        usedRequirement, usedSlot = findItem(source, requirements)
        authorised = usedRequirement ~= nil
    elseif not authorised and player then
        authorised = matchesCharacter(player, door.characters) or matchesGroup(player, door.groups)
        if not authorised then
            usedRequirement, usedSlot = findItem(source, door.items)
            authorised = usedRequirement ~= nil
        end
    end

    local restricted = door.passcode or door.characters or door.groups or door.items
    if not lockpick and not authorised and not restricted then authorised = true end
    if not lockpick and not authorised and door.passcode then
        local supplied = QB.callback.trigger(source, 'qbdoorlock:client:passcodeRequested', door.label)
        authorised = type(supplied) == 'string' and supplied == door.passcode
    end
    local hookResult = triggerHooks('doorAuthorization', {
        source = source, door = DoorlockSchema.forNetwork(door),
        lockpick = lockpick == true, authorised = authorised == true,
    })
    if hookResult == true then authorised = true end
    return authorised == true, usedRequirement, usedSlot
end

local function clientDefinition(door)
    local definition = DoorlockSchema.forNetwork(door)
    definition.hasPasscode, definition.passcode = door.passcode ~= nil, nil
    return definition
end

local function publicDoor(id, includeDefinition)
    local door = getDoor(id)
    if not door then return nil end
    local result = {
        id = id, name = door.label, label = door.label,
        state = states[id] and 1 or 0, locked = states[id] == true,
        coords = DoorlockSchema.copyCoords(door.coords), characters = door.characters,
        citizenIds = door.characters, groups = door.groups, items = door.items,
        maxDistance = door.distance, distance = door.distance,
    }
    if includeDefinition then result.definition = clientDefinition(door) end
    return result
end

local function pushDefinition(id)
    local door = getDoor(id)
    if door then QB.events.push(-1, 'qbdoorlock:client:doorDefinitionUpdated', id, clientDefinition(door), states[id]) end
end

local function clearAutoLock(id)
    local timer = autoLockTimers[id]
    if timer then QB.timers.clearTimeout(timer); autoLockTimers[id] = nil end
end

local setDoorState

local function applyOneState(id, locked, source, usedItem)
    local door = getDoor(id)
    if not door then return end
    clearAutoLock(id)
    states[id] = locked
    QB.events.push(-1, 'qbdoorlock:client:doorStateChanged', id, locked, source)
    TriggerEvent('qbdoorlock:stateChanged', source, id, locked, usedItem)
    local delay = not locked and (door.autoLock or Config.DefaultAutoLock) or nil
    if type(delay) == 'number' and delay > 0 then
        autoLockTimers[id] = QB.timers.setTimeout(function()
            autoLockTimers[id] = nil
            if states[id] == false then setDoorState(id, true, nil) end
        end, delay)
    end
end

setDoorState = function(id, locked, source, usedItem)
    if not getDoor(id) or type(locked) ~= 'boolean' then return false end
    applyOneState(id, locked, source, usedItem)
    local linkedId = linkedDoors[id]
    if linkedId and getDoor(linkedId) and states[linkedId] ~= locked then applyOneState(linkedId, locked, source, usedItem) end
    if source and source > 0 and Config.Notify then
        QB.notify.send(source, { title = translate('title'), message = translate(locked and 'locked' or 'unlocked'), type = 'success' })
    end
    return true
end

local function encodeDefinition(door) return json.encode(DoorlockSchema.forNetwork(door)) end

local function persistDoor(id, door)
    if not databaseReady then return false, 'Door storage is not ready.' end
    local saved, err = QB.sql.execute(
        'INSERT INTO `qbdoorlock_doors` (`id`, `definition`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `definition` = VALUES(`definition`)',
        { id, encodeDefinition(door) })
    if saved == nil then return false, err or 'Could not save the door.' end
    return true
end

local function installDoor(id, raw, preserveState)
    local door, err = DoorlockSchema.normalize(raw, Config.InteractionDistance)
    if not door then return nil, err end
    doors[id] = door
    if not preserveState or states[id] == nil then states[id] = door.locked end
    pushDefinition(id)
    return door
end

local function validId(value, lowerCase)
    local id = type(value) == 'string' and value or ''
    if lowerCase then id = id:lower() end
    if #id < 1 or #id > 64 or not id:match('^[A-Za-z0-9][A-Za-z0-9_-]*$') then return nil end
    return id
end

local function validateCreationDistance(source, door)
    for _, leaf in ipairs(doorLeaves(door)) do if not QB.distance.player(source, leaf.coords, 12.0) then return false end end
    return true
end

local function managementSnapshot(source)
    if not isAdmin(source) then return nil, 'You do not have permission to manage door locks.' end
    local result = {}
    for id, door in pairs(doors) do
        local definition = DoorlockSchema.forNetwork(door)
        definition.locked = states[id] == true
        result[#result + 1] = {
            id = id, label = door.label, locked = states[id] == true, leaves = #doorLeaves(door),
            autoLock = door.autoLock or Config.DefaultAutoLock, linkedTo = linkedDoors[id], definition = definition,
        }
    end
    table.sort(result, function(a, b) return a.label:lower() < b.label:lower() end)
    return result
end

local function unlinkDoor(id)
    local linkedId = linkedDoors[id]
    if not linkedId then return true end
    local removed, err = QB.sql.update('DELETE FROM `qbdoorlock_links` WHERE `door_id` IN (?, ?)', { id, linkedId })
    if removed == nil then return false, err end
    linkedDoors[id], linkedDoors[linkedId] = nil, nil
    return true
end

local function deleteDoor(id)
    if not getDoor(id) then return false, 'That door is not configured.' end
    local unlinked, unlinkErr = unlinkDoor(id)
    if not unlinked then return false, unlinkErr end
    local query, parameters
    if configuredIds[id] then
        query = 'INSERT INTO `qbdoorlock_doors` (`id`, `definition`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `definition` = VALUES(`definition`)'
        parameters = { id, json.encode({ deleted = true }) }
    else
        query, parameters = 'DELETE FROM `qbdoorlock_doors` WHERE `id` = ?', { id }
    end
    local removed, err = QB.sql.execute(query, parameters)
    if removed == nil then return false, err or 'Could not delete the door.' end
    clearAutoLock(id)
    doors[id], states[id] = nil, nil
    QB.events.push(-1, 'qbdoorlock:client:doorDefinitionRemoved', id)
    return true
end

local function difficultyOptions(door)
    local difficulty = door.lockpickDifficulty or Config.LockpickDifficulty
    if type(difficulty) == 'table' and (difficulty.pinCount or difficulty.tolerance or difficulty.speed) then
        return {
            attempts = difficulty.attempts or 1, pinCount = difficulty.pinCount, tolerance = difficulty.tolerance,
            speed = difficulty.speed, timeLimit = difficulty.timeLimit,
        }
    end
    local entries = type(difficulty) == 'table' and difficulty or { difficulty }
    local scores, tolerances, speeds = { easy = 1, medium = 2, hard = 3 }, 0, 0
    for _, entry in ipairs(entries) do
        if type(entry) == 'table' then
            local area = tonumber(entry.areaSize) or 15
            if area > 1 then area = area / 100 end
            tolerances = tolerances + math.max(0.03, math.min(0.35, area))
            speeds = speeds + math.max(0.3, math.min(4, tonumber(entry.speedMultiplier) or 1))
        else
            local score = scores[entry] or 2
            tolerances = tolerances + ({ 0.24, 0.14, 0.08 })[score]
            speeds = speeds + ({ 0.75, 1.0, 1.35 })[score]
        end
    end
    local count = math.max(1, #entries)
    return { attempts = 1, pinCount = math.max(3, math.min(12, count + 2)), tolerance = tolerances / count, speed = speeds / count, timeLimit = 15000 }
end

QB.callback.register('qbdoorlock:server:doorsRequested', function()
    while not initializationComplete do Wait(50) end
    local definitions = {}
    for id, door in pairs(doors) do definitions[id] = clientDefinition(door) end
    return definitions, states
end, { rateLimit = { max = 5, window = 10000 } })

QB.callback.register('qbdoorlock:server:managementSnapshotRequested', function(source) return managementSnapshot(source) end,
    { rateLimit = { max = 10, window = 10000 } })

QB.callback.register('qbdoorlock:server:managementStateSet', function(source, id, locked)
    if not isAdmin(source) then return nil, 'You do not have permission to manage door locks.' end
    if type(locked) ~= 'boolean' or not getDoor(id) then return nil, 'That door is no longer configured.' end
    setDoorState(id, locked, source)
    return managementSnapshot(source)
end, { rateLimit = { max = 20, window = 10000 } })

QB.callback.register('qbdoorlock:server:managementDoorSaved', function(source, requestedId, raw, creating)
    if not isAdmin(source) then return nil, 'You do not have permission to save door locks.' end
    if not databaseReady then return nil, 'Door storage is still starting.' end
    local id = validId(requestedId, creating == true)
    if not id then return nil, 'Door ID must use letters, numbers, dashes, or underscores.' end
    if creating and doors[id] then return nil, 'That door ID is already in use.' end
    if not creating and not doors[id] then return nil, 'That door is no longer configured.' end
    local door, err = DoorlockSchema.normalize(raw, Config.InteractionDistance)
    if not door then return nil, err end
    if creating and not validateCreationDistance(source, door) then return nil, 'All selected doors must be within 12 metres of you.' end
    local saved, saveErr = persistDoor(id, door)
    if not saved then return nil, saveErr end
    installDoor(id, door, false)
    states[id] = door.locked
    setDoorState(id, door.locked, source)
    return managementSnapshot(source)
end, { rateLimit = { max = 8, window = 10000 } })

QB.callback.register('qbdoorlock:server:managementDoorDeleted', function(source, id)
    if not isAdmin(source) then return nil, 'You do not have permission to delete door locks.' end
    if not databaseReady then return nil, 'Door storage is still starting.' end
    local deleted, err = deleteDoor(id)
    if not deleted then return nil, err end
    return managementSnapshot(source)
end, { rateLimit = { max = 5, window = 10000 } })

QB.callback.register('qbdoorlock:server:managementDoorsLinked', function(source, id, linkedId)
    if not isAdmin(source) then return nil, 'You do not have permission to manage door locks.' end
    if not databaseReady then return nil, 'Door storage is still starting.' end
    if type(id) ~= 'string' or type(linkedId) ~= 'string' or id == linkedId or not getDoor(id) or not getDoor(linkedId) then
        return nil, 'Choose two different configured doors.'
    end
    if linkedDoors[id] or linkedDoors[linkedId] then return nil, 'Unlink either door before creating a new pair.' end
    local saved, err = QB.sql.execute('INSERT INTO `qbdoorlock_links` (`door_id`, `linked_door_id`) VALUES (?, ?), (?, ?)', { id, linkedId, linkedId, id })
    if saved == nil then return nil, err or 'Could not save the door link.' end
    linkedDoors[id], linkedDoors[linkedId] = linkedId, id
    setDoorState(linkedId, states[id], source)
    return managementSnapshot(source)
end, { rateLimit = { max = 10, window = 10000 } })

QB.callback.register('qbdoorlock:server:managementDoorsUnlinked', function(source, id)
    if not isAdmin(source) then return nil, 'You do not have permission to manage door locks.' end
    if not databaseReady then return nil, 'Door storage is still starting.' end
    local unlinked, err = unlinkDoor(id)
    if not unlinked then return nil, err or 'Could not remove the door link.' end
    return managementSnapshot(source)
end, { rateLimit = { max = 10, window = 10000 } })

QB.callback.register('qbdoorlock:server:lockpickStarted', function(source, id)
    local door = getDoor(id)
    if not door or not door.lockpick or not isNearDoor(source, door) then return nil, 'That door cannot be picked.' end
    if not Config.CanPickUnlockedDoors and not states[id] then return nil, 'That door is already unlocked.' end
    local authorised, requirement, slot = hasAccess(source, id, door, true)
    if not authorised then return nil, 'You need a lockpick.' end
    local authorization = QB.minigames.authorizeProof(source, 'lockpick', difficultyOptions(door))
    if not authorization then return nil, 'The lockpick challenge could not start.' end
    pendingLockpicks[source] = { id = id, authorization = authorization, requirement = requirement, slot = slot }
    return authorization
end, { rateLimit = { max = 4, window = 10000 } })

QB.events.register('qbdoorlock:server:doorToggled', function(source, id)
    local door = getDoor(id)
    if not door or not isNearDoor(source, door) then return end
    local authorised, requirement, slot = hasAccess(source, id, door, false)
    if not authorised then
        QB.notify.send(source, { title = translate('title'), message = translate('access_denied'), type = 'error' })
        return
    end
    local locked = not states[id]
    setDoorState(id, locked, source, requirement and requirement.name)
    if requirement and requirement.remove then removeItem(source, requirement, slot) end
end, { rateLimit = { max = 10, window = 5000 } })

QB.events.register('qbdoorlock:server:lockpickFinished', function(source, id, authorization, proof)
    local pending = pendingLockpicks[source]
    pendingLockpicks[source] = nil
    if not pending or pending.id ~= id or pending.authorization ~= authorization then return end
    local door = getDoor(id)
    if not door or not door.lockpick or not isNearDoor(source, door) then return end
    local successful = type(proof) == 'string' and QB.minigames.consumeProof(source, proof, 'lockpick', authorization) == true
    if successful then
        local requirement, slot = findItem(source, { pending.requirement })
        if not requirement then return end
        pending.slot = slot
        setDoorState(id, not states[id], source, pending.requirement.name)
    end
    local chances = Config.LockpickBreakChance or {}
    local chance = tonumber(successful and chances.success or chances.failure) or 0
    if chance > 0 and math.random(100) <= chance and removeItem(source, pending.requirement, pending.slot) then
        QB.notify.send(source, { title = translate('title'), message = translate('lockpick_broke'), type = 'error' })
    end
end, { rateLimit = { max = 5, window = 10000 } })

QB.events.register('qbdoorlock:server:teleportRequested', function(source, id)
    if not isAdmin(source) then return end
    local door = getDoor(id)
    if not door then return end
    QB.events.push(source, 'qbdoorlock:client:teleported', DoorlockSchema.copyCoords(door.coords))
end, { rateLimit = { max = 5, window = 10000 } })

local function commandPermission(source) return source > 0 and isAdmin(source) end

QB.commands.add(Config.AdminCommand or 'doorlocks', translate('manage_help'), {
    { name = 'closest', help = 'Sort the editor by the closest door.' },
}, false, function(source, args)
    QB.events.push(source, 'qbdoorlock:client:managementOpened', args[1] == 'closest')
end, { permission = Config.AdminPermission or 'admin', checkPermission = commandPermission })

QB.commands.add(Config.CreateCommand or 'adddoor', translate('create_help'), nil, false, function(source)
    QB.events.push(source, 'qbdoorlock:client:targetedCreationRequested')
end, { permission = Config.AdminPermission or 'admin', checkPermission = commandPermission })

local function importOxDoors()
    if not databaseReady then return nil, 'Door storage is not ready.' end
    local exists, existsErr = QB.sql.scalar(
        "SELECT COUNT(*) FROM `information_schema`.`tables` WHERE `table_schema` = DATABASE() AND `table_name` = 'ox_doorlock'"
    )
    if existsErr or tonumber(exists) ~= 1 then return nil, existsErr or 'The ox_doorlock table does not exist.' end
    local rows, queryErr = QB.sql.query('SELECT `id`, `name`, `data` FROM `ox_doorlock` ORDER BY `id`')
    if queryErr then return nil, queryErr end
    local imported, skipped = 0, 0
    for _, row in ipairs(rows) do
        local id = ('ox-%s'):format(tostring(row.id))
        local ok, raw = pcall(json.decode, row.data)
        if doors[id] or not ok or type(raw) ~= 'table' then
            skipped = skipped + 1
        else
            raw.label = raw.label or row.name
            local door = DoorlockSchema.normalize(raw, Config.InteractionDistance)
            if door and persistDoor(id, door) then
                installDoor(id, door, false)
                imported = imported + 1
            else
                skipped = skipped + 1
            end
        end
    end
    return imported, skipped
end

QB.commands.add(Config.ImportCommand or 'importoxdoors', translate('import_help'), nil, false, function(source)
    local imported, err = importOxDoors()
    if imported == nil then
        QB.notify.send(source, { title = translate('title'), message = translate('import_failed', { error = err }), type = 'error' })
        return
    end
    QB.notify.send(source, { title = translate('title'), message = translate('imported', { count = imported }), type = 'success' })
end, { permission = Config.AdminPermission or 'admin', checkPermission = commandPermission })

---@param id string
---@return boolean? locked
exports('getDoorState', function(id) return states[id] end)

---@param id string
---@return table|false door
exports('getDoor', function(id)
    if type(id) == 'table' then id = id.id end
    return publicDoor(id, true) or false
end)

---@return table[] doors
exports('getAllDoors', function()
    local result = {}
    for id in pairs(doors) do result[#result + 1] = publicDoor(id, true) end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end)

---@param name string
---@return table? door
exports('getDoorFromName', function(name)
    for id, door in pairs(doors) do if door.label == name then return publicDoor(id, true) end end
    return nil
end)

---@param id string
---@param state boolean|0|1
---@return boolean changed
exports('setDoorState', function(id, state)
    if state ~= true and state ~= false and state ~= 0 and state ~= 1 then return false end
    return setDoorState(id, state == true or state == 1, nil)
end)

---@param id string
---@param patch table
---@return boolean edited
exports('editDoor', function(id, patch)
    local door = getDoor(id)
    if not door or type(patch) ~= 'table' or not databaseReady then return false end
    local raw = DoorlockSchema.forNetwork(door)
    for key, value in pairs(patch) do
        if key == 'state' then raw.locked = value == true or value == 1
        elseif key == 'name' then raw.label = value
        elseif key == 'maxDistance' then raw.distance = value
        elseif key == 'autolock' then
            if value == '' then raw.autoLock = nil
            else
                local seconds = tonumber(value)
                raw.autoLock = seconds and seconds * 1000 or value
            end
        elseif key == 'auto' then raw.automatic = value
        elseif key ~= 'id' then
            if value == '' then raw[key] = nil else raw[key] = value end
        end
    end
    local normalized = DoorlockSchema.normalize(raw, Config.InteractionDistance)
    if not normalized or not persistDoor(id, normalized) then return false end
    local stateChanged = patch.locked ~= nil or patch.state ~= nil
    installDoor(id, normalized, not stateChanged)
    setDoorState(id, stateChanged and normalized.locked or states[id], nil)
    return true
end)

---@param raw table
---@return string|false id
exports('createDoor', function(raw)
    if type(raw) ~= 'table' or not databaseReady then return false end
    local door = DoorlockSchema.normalize(raw, Config.InteractionDistance)
    if not door then return false end
    local id = validId(raw.id, true)
    if not id then
        local base = door.label:lower():gsub('[^a-z0-9]+', '-'):gsub('^-', ''):gsub('-$', '')
        if base == '' then base = 'door' end
        id = base:sub(1, 56)
        local suffix = 1
        while doors[id] do suffix = suffix + 1; id = ('%s-%d'):format(base:sub(1, 56), suffix) end
    end
    if doors[id] or not persistDoor(id, door) then return false end
    installDoor(id, door, false)
    return id
end)

---@param id string
---@return boolean removed
---@return string? error
exports('removeDoor', function(id) if not databaseReady then return false end; return deleteDoor(id) end)

---@return integer? imported
---@return integer|string skippedOrError
exports('importOxDoors', importOxDoors)

AddEventHandler('qbdoorlock:setState', function(id, state)
    if state == true or state == false or state == 0 or state == 1 then setDoorState(id, state == true or state == 1, nil) end
end)
AddEventHandler('playerDropped', function() pendingLockpicks[source] = nil end)

for id, raw in pairs(Config.Doors) do
    assert(type(id) == 'string', 'qbdoorlock Config.Doors keys must be strings.')
    local normalized, err = DoorlockSchema.normalize(raw, Config.InteractionDistance)
    assert(normalized, ('Invalid qbdoorlock door %s: %s'):format(id, err))
    configuredIds[id], doors[id], states[id] = true, normalized, normalized.locked
end

CreateThread(function()
    if not QB.sql.ready(60000) then
        initializationComplete = true
        return print('^1[qbdoorlock]^7 qbsql was not ready; persistent door management is disabled.')
    end
    local doorsSql = assert(LoadResourceFile(RESOURCE, 'sql/001_doors.sql'), 'missing qbdoorlock door migration')
    local linksSql = assert(LoadResourceFile(RESOURCE, 'sql/002_links.sql'), 'missing qbdoorlock link migration')
    local _, migrationErr = QB.sql.migrate(RESOURCE, {
        { version = 1, name = 'doors', sql = doorsSql, checksum = checksum(doorsSql) },
        { version = 2, name = 'links', sql = linksSql, checksum = checksum(linksSql) },
    })
    if migrationErr then initializationComplete = true; return print(('^1[qbdoorlock]^7 migration failed: %s'):format(migrationErr)) end
    local rows, queryErr = QB.sql.query('SELECT `id`, `definition` FROM `qbdoorlock_doors`')
    if queryErr then initializationComplete = true; return print(('^1[qbdoorlock]^7 could not load doors: %s'):format(queryErr)) end
    for _, row in ipairs(rows) do
        local ok, raw = pcall(json.decode, row.definition)
        if ok and type(raw) == 'table' and type(row.id) == 'string' then
            if raw.deleted == true and configuredIds[row.id] then
                doors[row.id], states[row.id] = nil, nil
            else
                local door, err = DoorlockSchema.normalize(raw, Config.InteractionDistance)
                if door then doors[row.id], states[row.id] = door, door.locked
                else print(('^3[qbdoorlock]^7 skipped invalid stored door %s: %s'):format(row.id, err)) end
            end
        else
            print(('^3[qbdoorlock]^7 skipped malformed stored door %s'):format(tostring(row.id)))
        end
    end
    local links, linksErr = QB.sql.query('SELECT `door_id`, `linked_door_id` FROM `qbdoorlock_links`')
    if linksErr then initializationComplete = true; return print(('^1[qbdoorlock]^7 could not load door links: %s'):format(linksErr)) end
    local candidates = {}
    for _, row in ipairs(links) do
        if type(row.door_id) == 'string' and type(row.linked_door_id) == 'string' and row.door_id ~= row.linked_door_id
            and doors[row.door_id] and doors[row.linked_door_id] then candidates[row.door_id] = row.linked_door_id end
    end
    for id, linkedId in pairs(candidates) do if candidates[linkedId] == id then linkedDoors[id] = linkedId end end
    databaseReady, initializationComplete = true, true
    TriggerEvent('qbdoorlock:loaded')
end)
