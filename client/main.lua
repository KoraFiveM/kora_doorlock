local APP_ID = 'qbdoorlock:management'
local doors, activeDoors, streamedDoors, entityDoors = {}, {}, {}, {}
local targetModels, pendingTargetModels = {}, {}
local nearbyDoor, prompt, pickingLock, lockpickTarget
local managementSnapshotData, managementClosestFirst = nil, false
local selection, toggleBinding, selectBinding, cancelBinding
local spriteDicts = {}

local function translate(key, replacements)
    return QB.lang(key, replacements)
end

local function notify(message, notificationType)
    QB.notify.send({ title = translate('title'), message = message, type = notificationType or 'info' })
end

local function doorLeaves(door)
    return door.doors or { { model = door.model, coords = door.coords, heading = door.heading } }
end

local function doorHash(id, index)
    return joaat(('qbdoorlock:%s:%s'):format(id, index))
end

local function doorDistance(door, position)
    local closest = math.huge
    for _, leaf in ipairs(doorLeaves(door)) do closest = math.min(closest, #(position - leaf.coords)) end
    return closest
end

local function stateText(door)
    return translate(door.locked and 'unlock_door' or 'lock_door', { door = door.label })
end

local function hidePrompt()
    if prompt then QB.textui.hide(prompt); prompt = nil end
end

local function updatePrompt()
    local door = nearbyDoor and doors[nearbyDoor]
    if not door or door.hideUi or not Config.DrawTextUI then return hidePrompt() end
    local options = { key = 'E', icon = door.locked and 'Lock' or 'Unlock', position = 'right-center' }
    if prompt then QB.textui.update(prompt, stateText(door), options)
    else prompt = QB.textui.show(stateText(door), options) end
end

local function clearDoorEntities(door)
    if not door or not door.entities then return end
    for _, entity in pairs(door.entities) do
        entityDoors[entity] = nil
        if DoesEntityExist(entity) then
            pcall(function()
                Entity(entity).state:set('qbdoorlock:id', false, false)
                Entity(entity).state:set('doorId', false, false)
            end)
        end
    end
    door.entities = {}
end

local function removeDoor(id)
    local door = doors[id]
    if not door then return end
    if door.interactionZone then door.interactionZone.remove() end
    if door.streamZone then door.streamZone.remove() end
    clearDoorEntities(door)
    for index = 1, #doorLeaves(door) do RemoveDoorFromSystem(doorHash(id, index)) end
    activeDoors[id], streamedDoors[id], doors[id] = nil, nil, nil
    if nearbyDoor == id then nearbyDoor = nil; hidePrompt() end
end

local function playDoorSound(door, locked)
    local fallback = Config.DefaultSounds and Config.DefaultSounds[locked and 'locked' or 'unlocked'] or nil
    local name = locked and door.lockSound or door.unlockSound
    local set = locked and door.lockSoundSet or door.unlockSoundSet
    name, set = name or (fallback and fallback.name), set or (fallback and fallback.set)
    if name and set then QB.sound.playFromCoords(door.coords, name, set, { range = 20.0, releaseAfter = 3000 }) end
end

local function applyState(id, locked, source, silent)
    local door = doors[id]
    if not door then return end
    local changed = door.locked ~= (locked == true)
    door.locked = locked == true
    door.state = door.locked and 1 or 0
    for index in ipairs(doorLeaves(door)) do
        local hash = doorHash(id, index)
        DoorSystemSetDoorState(hash, door.locked and 1 or 0, false, false)
        if door.holdOpen then DoorSystemSetHoldOpen(hash, not door.locked) end
    end
    if changed and not silent and QB.distance.player(door.coords, 20.0) then playDoorSound(door, door.locked) end
    if nearbyDoor == id then updatePrompt() end

    if door.locked then
        CreateThread(function()
            local deadline = GetGameTimer() + 5000
            while GetGameTimer() < deadline do
                local closed = true
                for index in ipairs(doorLeaves(door)) do if not IsDoorClosed(doorHash(id, index)) then closed = false; break end end
                if closed then return end
                Wait(0)
            end
        end)
    end
end

local function getDoorIdFromEntity(entity)
    if type(entity) ~= 'number' or entity == 0 then return nil end
    if entityDoors[entity] then return entityDoors[entity] end
    local ok, state = pcall(function() return Entity(entity).state end)
    local id = ok and state and (state['qbdoorlock:id'] or state.doorId) or nil
    return type(id) == 'string' and id or nil
end

local function canTargetLockpick(entity)
    local id = getDoorIdFromEntity(entity)
    local door = id and doors[id]
    if not door or pickingLock or not door.lockpick or (not Config.CanPickUnlockedDoors and not door.locked) then return false end
    lockpickTarget = id
    return true
end

local function pickDoor(id)
    if pickingLock then return false end
    local door = id and doors[id]
    if not door or not door.lockpick or (not Config.CanPickUnlockedDoors and not door.locked) then return false end
    pickingLock = true
    CreateThread(function()
        local authorization, err = QB.callback.trigger('qbdoorlock:server:lockpickStarted', id)
        if not authorization then pickingLock = false; return notify(err or translate('cannot_pick'), 'error') end
        local playerPed = QB.cache.ped()
        TaskTurnPedToFaceCoord(playerPed, door.coords.x, door.coords.y, door.coords.z, 1000)
        Wait(400)
        local animation = QB.anim.play(playerPed, 'mp_common_heist', 'pick_door', {
            blendInSpeed = 3.0, blendOutSpeed = 1.0, flag = 49,
        })
        local result = QB.minigames.play('lockpick', nil, authorization)
        if animation then QB.anim.stopHandle(animation, 0) end
        QB.events.trigger('qbdoorlock:server:lockpickFinished', id, authorization, result and result.proof or nil)
        if not result or not result.success then notify(translate('lock_resisted'), 'error') end
        pickingLock = false
    end)
    return true
end

local function registerTargetModel(model)
    if targetModels[model] or GetResourceState('qbtarget') ~= 'started' then pendingTargetModels[model] = true; return end
    local ok, targetId = pcall(QB.interact.addModel, model, {
        {
            label = translate('pick_lock'), icon = 'LockKeyhole', distance = 1.5,
            canInteract = function(entity) return canTargetLockpick(entity) end,
            action = function() if lockpickTarget then pickDoor(lockpickTarget) end end,
        },
    }, 1.5)
    if ok then targetModels[model], pendingTargetModels[model] = targetId, nil
    else pendingTargetModels[model] = true end
end

local function registerPendingTargets()
    for model in pairs(pendingTargetModels) do registerTargetModel(model) end
end

local function setupDoor(id, raw, locked)
    local door, err = DoorlockSchema.normalize(raw, Config.InteractionDistance)
    if not door then return print(('^3[qbdoorlock]^7 rejected client door %s: %s'):format(tostring(id), err)) end
    removeDoor(id)
    door.id, door.locked, door.state, door.maxDistance, door.entities = id, locked == true, locked and 1 or 0, door.distance, {}
    doors[id] = door
    for index, leaf in ipairs(doorLeaves(door)) do
        local hash = doorHash(id, index)
        AddDoorToSystem(hash, leaf.model, leaf.coords.x, leaf.coords.y, leaf.coords.z, false, false, false)
        DoorSystemSetDoorState(hash, 4, false, false)
        DoorSystemSetDoorState(hash, door.locked and 1 or 0, false, false)
        if door.doorRate or not door.automatic then DoorSystemSetAutomaticRate(hash, door.doorRate or 10.0, false, false) end
        if door.holdOpen then DoorSystemSetHoldOpen(hash, not door.locked) end
        pendingTargetModels[leaf.model] = true
    end
    door.interactionZone = QB.zones.point({
        coords = door.coords, radius = door.distance, debug = Config.Debug,
        onEnter = function() activeDoors[id] = true end,
        onExit = function() activeDoors[id] = nil; if nearbyDoor == id then nearbyDoor = nil; hidePrompt() end end,
    })
    door.streamZone = QB.zones.point({
        coords = door.coords, radius = 80.0, debug = false,
        onEnter = function() streamedDoors[id] = true end,
        onExit = function() streamedDoors[id] = nil; clearDoorEntities(door) end,
    })
    registerPendingTargets()
end

local function targetedLeaf()
    local hit, _, entity = QB.raycast.fromCamera(6.0)
    if not hit or not entity or entity == 0 or GetEntityType(entity) ~= 3 then return nil end
    if getDoorIdFromEntity(entity) then return nil end
    local coords = GetEntityCoords(entity)
    return { entity = entity, model = GetEntityModel(entity), coords = { x = coords.x, y = coords.y, z = coords.z }, heading = GetEntityHeading(entity) }
end

local function finishSelection(value)
    local current = selection
    if not current then return end
    selection = nil
    selectBinding.disable(true)
    cancelBinding.disable(true)
    toggleBinding.disable(false)
    if current.prompt then QB.textui.hide(current.prompt) end
    current.promise:resolve(value)
end

local function selectSecondLeaf(first)
    local promise = promise.new()
    selection = {
        first = first,
        promise = promise,
        prompt = QB.textui.show(translate('select_second'), { key = 'E', icon = 'DoorOpen', position = 'right-center' }),
    }
    toggleBinding.disable(true)
    selectBinding.disable(false)
    cancelBinding.disable(false)
    return Citizen.Await(promise)
end

local function splitList(value)
    local result = {}
    for entry in tostring(value or ''):gmatch('[^,]+') do
        entry = entry:gsub('^%s*(.-)%s*$', '%1')
        if entry ~= '' then result[#result + 1] = entry end
    end
    return result
end

local function parseGroups(value)
    local groups = {}
    for _, entry in ipairs(splitList(value)) do
        local name, grade = entry:match('^([^:]+):?(%d*)$')
        if name then groups[name:lower()] = tonumber(grade) or 0 end
    end
    return next(groups) and groups or nil
end

local function parseItems(value)
    local items = {}
    for _, entry in ipairs(splitList(value)) do
        local name, metadata, remove = entry:match('^([^|]+)|?([^|]*)|?([^|]*)$')
        if name then
            items[#items + 1] = { name = name:lower(), metadata = metadata ~= '' and metadata or nil, remove = remove == 'remove' or remove == 'true' or remove == '1' }
        end
    end
    return #items > 0 and items or nil
end

local function joinGroups(groups)
    local result = {}
    for name, grade in pairs(groups or {}) do result[#result + 1] = ('%s:%d'):format(name, grade) end
    table.sort(result)
    return table.concat(result, ', ')
end

local function joinCharacters(characters) return table.concat(characters or {}, ', ') end

local function joinItems(items)
    local result = {}
    for _, item in ipairs(items or {}) do
        local metadata = type(item.metadata) == 'table' and item.metadata.type or item.metadata
        result[#result + 1] = ('%s|%s|%s'):format(item.name, metadata or '', item.remove and 'remove' or '')
    end
    return table.concat(result, ', ')
end

local function editorFields(door, includeId, allowDouble)
    door = door or {}
    local difficulty = type(door.lockpickDifficulty) == 'table' and door.lockpickDifficulty or {}
    local fields = {}
    if includeId then fields[#fields + 1] = { id = 'id', label = 'Door ID', type = 'text', required = true, maxLength = 64, placeholder = 'city-hall-office' } end
    fields[#fields + 1] = { id = 'label', label = 'Door name', type = 'text', required = true, maxLength = 96, default = door.label }
    fields[#fields + 1] = { id = 'locked', label = 'Locked', type = 'checkbox', default = door.locked ~= false }
    if allowDouble then fields[#fields + 1] = { id = 'double', label = 'Double door', type = 'checkbox', default = door.doors ~= nil } end
    fields[#fields + 1] = { id = 'distance', label = 'Interaction distance', type = 'number', min = 0.5, max = 20, default = door.distance or Config.InteractionDistance }
    fields[#fields + 1] = { id = 'autoLock', label = 'Auto-lock seconds (0 disables)', type = 'number', min = 0, max = 86400, default = door.autoLock and door.autoLock / 1000 or 0 }
    fields[#fields + 1] = { id = 'doorRate', label = 'Door movement rate (0-10)', type = 'number', min = 0, max = 10, default = door.doorRate }
    fields[#fields + 1] = { id = 'automatic', label = 'Automatic/sliding door', type = 'checkbox', default = door.automatic == true }
    fields[#fields + 1] = { id = 'holdOpen', label = 'Hold open while unlocked', type = 'checkbox', default = door.holdOpen == true }
    fields[#fields + 1] = { id = 'hideUi', label = 'Hide interaction indicator', type = 'checkbox', default = door.hideUi == true }
    fields[#fields + 1] = { id = 'passcode', label = 'Passcode (blank disables)', type = 'password', maxLength = 128, default = door.passcode }
    fields[#fields + 1] = { id = 'groups', label = 'Groups (name:grade, comma separated)', type = 'textarea', default = joinGroups(door.groups) }
    fields[#fields + 1] = { id = 'characters', label = 'Character IDs (comma separated)', type = 'textarea', default = joinCharacters(door.characters) }
    fields[#fields + 1] = { id = 'items', label = 'Items (name|metadata type|remove, comma separated)', type = 'textarea', default = joinItems(door.items) }
    fields[#fields + 1] = { id = 'lockpick', label = 'Can be lockpicked', type = 'checkbox', default = door.lockpick == true }
    fields[#fields + 1] = { id = 'pinCount', label = 'Lockpick pins', type = 'number', min = 1, max = 12, default = difficulty.pinCount or 5 }
    fields[#fields + 1] = { id = 'tolerance', label = 'Lockpick tolerance (0.03-0.35)', type = 'number', min = 0.03, max = 0.35, default = difficulty.tolerance or 0.14 }
    fields[#fields + 1] = { id = 'speed', label = 'Lockpick speed (0.3-4)', type = 'number', min = 0.3, max = 4, default = difficulty.speed or 1 }
    fields[#fields + 1] = { id = 'lockSound', label = 'Lock sound name', type = 'text', maxLength = 96, default = door.lockSound }
    fields[#fields + 1] = { id = 'lockSoundSet', label = 'Lock sound set', type = 'text', maxLength = 96, default = door.lockSoundSet }
    fields[#fields + 1] = { id = 'unlockSound', label = 'Unlock sound name', type = 'text', maxLength = 96, default = door.unlockSound }
    fields[#fields + 1] = { id = 'unlockSoundSet', label = 'Unlock sound set', type = 'text', maxLength = 96, default = door.unlockSoundSet }
    return fields
end

local function definitionFromValues(values, geometry)
    local definition = {
        label = values.label, locked = values.locked == true, distance = tonumber(values.distance),
        autoLock = (tonumber(values.autoLock) or 0) > 0 and math.floor(tonumber(values.autoLock) * 1000) or nil,
        doorRate = tonumber(values.doorRate), automatic = values.automatic == true, holdOpen = values.holdOpen == true,
        hideUi = values.hideUi == true, passcode = values.passcode ~= '' and values.passcode or nil,
        groups = parseGroups(values.groups), characters = splitList(values.characters), items = parseItems(values.items),
        lockpick = values.lockpick == true,
        lockpickDifficulty = { pinCount = tonumber(values.pinCount), tolerance = tonumber(values.tolerance), speed = tonumber(values.speed), attempts = 1, timeLimit = 15000 },
        lockSound = values.lockSound ~= '' and values.lockSound or nil,
        lockSoundSet = values.lockSoundSet ~= '' and values.lockSoundSet or nil,
        unlockSound = values.unlockSound ~= '' and values.unlockSound or nil,
        unlockSoundSet = values.unlockSoundSet ~= '' and values.unlockSoundSet or nil,
    }
    if geometry.doors then definition.doors = geometry.doors
    else definition.model, definition.coords, definition.heading = geometry.model, geometry.coords, geometry.heading end
    return definition
end

local function createTargetedDoor(template)
    local first = targetedLeaf()
    if not first then return notify(translate('look_at_door'), 'error') end
    local result = QB.nui.openInputDialog(editorFields(template, true, true), 'Create door lock', 'All access and behaviour settings can be changed later.')
    if not result or result.cancelled or type(result.values) ~= 'table' then return end
    local geometry = first
    if result.values.double == true then
        local second = selectSecondLeaf(first)
        if not second then return notify(translate('double_cancelled'), 'error') end
        geometry = { doors = {
            { model = first.model, coords = first.coords, heading = first.heading },
            { model = second.model, coords = second.coords, heading = second.heading },
        } }
    end
    local definition = definitionFromValues(result.values, geometry)
    local snapshot, err = QB.callback.trigger('qbdoorlock:server:managementDoorSaved', result.values.id, definition, true)
    if not snapshot then return notify(err or 'Could not save the door.', 'error') end
    managementSnapshotData = snapshot
    notify(translate('door_saved'), 'success')
end

local function replaceDoorGeometry(snapshotDoor, double)
    local first = targetedLeaf()
    if not first then return notify(translate('look_at_door'), 'error') end
    local geometry = first
    if double then
        local second = selectSecondLeaf(first)
        if not second then return notify(translate('double_cancelled'), 'error') end
        geometry = { doors = {
            { model = first.model, coords = first.coords, heading = first.heading },
            { model = second.model, coords = second.coords, heading = second.heading },
        } }
    end

    local definition = snapshotDoor.definition
    definition.model, definition.coords, definition.heading, definition.doors = nil, nil, nil, nil
    if geometry.doors then definition.doors = geometry.doors
    else definition.model, definition.coords, definition.heading = geometry.model, geometry.coords, geometry.heading end
    local snapshot, err = QB.callback.trigger('qbdoorlock:server:managementDoorSaved', snapshotDoor.id, definition, false)
    if not snapshot then return notify(err or 'Could not retarget the door.', 'error') end
    managementSnapshotData = snapshot
    notify(translate('door_saved'), 'success')
end

local function findSnapshotDoor(id)
    for _, door in ipairs(managementSnapshotData or {}) do if door.id == id then return door end end
end

local function managementDefinition(snapshot, closestFirst, asUpdate)
    local rows, linkedLabels, lockedCount = {}, {}, 0
    for _, door in ipairs(snapshot) do linkedLabels[door.id] = door.label end
    local playerCoords = QB.cache.coords()
    for _, door in ipairs(snapshot) do
        if door.locked then lockedCount = lockedCount + 1 end
        local localDoor = doors[door.id]
        local distance = localDoor and doorDistance(localDoor, playerCoords) or math.huge
        local definition = door.definition
        local access = {}
        if definition.groups then access[#access + 1] = 'groups' end
        if definition.characters then access[#access + 1] = 'characters' end
        if definition.items then access[#access + 1] = 'items' end
        if definition.passcode then access[#access + 1] = 'passcode' end
        rows[#rows + 1] = {
            id = door.id, label = door.label,
            description = ('%s · %s · %s'):format(door.locked and 'Locked' or 'Unlocked', door.leaves == 2 and 'Double door' or 'Single door', #access > 0 and table.concat(access, ', ') or 'Public'),
            icon = door.leaves == 2 and 'DoorOpen' or 'DoorClosed', tone = door.locked and 'warning' or 'success', distance = distance,
            metadata = {
                { label = 'Distance', value = distance < math.huge and ('%.1f m'):format(distance) or 'Unknown' },
                { label = 'Auto-lock', value = door.autoLock and ('%d sec'):format(math.floor(door.autoLock / 1000)) or 'Off' },
                { label = 'Linked door', value = door.linkedTo and (linkedLabels[door.linkedTo] or door.linkedTo) or 'None' },
                { label = 'Lockpick', value = definition.lockpick and 'Enabled' or 'Disabled' },
            },
            data = { linkedTo = door.linkedTo },
        }
    end
    if closestFirst then table.sort(rows, function(a, b) return a.distance < b.distance end) end
    for _, row in ipairs(rows) do
        local door = findSnapshotDoor(row.id)
        row.actions = {
            { id = 'doorlock:toggle', label = door.locked and 'Unlock' or 'Lock', icon = door.locked and 'Unlock' or 'Lock', variant = 'secondary' },
            { id = 'doorlock:edit', label = 'Edit settings', icon = 'Settings', variant = 'outline', fields = editorFields(door.definition, false, false) },
            { id = 'doorlock:retarget-single', label = 'Retarget as single', icon = 'ScanSearch', variant = 'outline', closeBeforeAction = true },
            { id = 'doorlock:retarget-double', label = 'Retarget as double', icon = 'PanelsTopLeft', variant = 'outline', closeBeforeAction = true },
            { id = 'doorlock:teleport', label = 'Teleport', icon = 'MapPin', variant = 'outline', closeBeforeAction = true },
            { id = 'doorlock:duplicate', label = 'Duplicate settings', icon = 'Copy', variant = 'outline', closeBeforeAction = true },
            { id = 'doorlock:delete', label = 'Delete', icon = 'Trash2', variant = 'destructive', confirm = 'Delete this door lock permanently?' },
        }
        if row.data.linkedTo then
            row.actions[#row.actions + 1] = { id = 'doorlock:unlink', label = 'Unlink', icon = 'Unlink', variant = 'outline' }
        else
            local options = {}
            for _, candidate in ipairs(snapshot) do if candidate.id ~= row.id and not candidate.linkedTo then options[#options + 1] = { value = candidate.id, label = candidate.label } end end
            row.actions[#row.actions + 1] = {
                id = 'doorlock:link', label = 'Link states', icon = 'Link', variant = 'outline', disabled = #options == 0,
                fields = { { id = 'linkedDoorId', label = 'Link with', type = 'select', required = true, options = options } },
            }
        end
    end

    local app = {
        title = 'Door Lock Control', description = 'Full qblib-native door management', icon = 'LockKeyhole', defaultView = 'doors',
        footer = 'Every mutation is permission-checked and synchronized by the server.',
        navigation = { {
            id = 'doors', label = 'Doors', icon = 'DoorOpen', content = {
                title = 'Configured doors', description = 'Create, edit, inspect, link, teleport to, or delete any door.',
                actions = {
                    { id = 'doorlock:create', label = 'Create targeted door', icon = 'Plus', variant = 'primary', closeBeforeAction = true },
                    { id = 'doorlock:closest', label = 'Closest to me', icon = 'MapPin', variant = closestFirst and 'primary' or 'secondary' },
                    { id = 'doorlock:refresh', label = 'Refresh', icon = 'RefreshCw', variant = 'secondary' },
                },
                blocks = {
                    { type = 'stats', items = {
                        { label = 'Configured', value = #snapshot, icon = 'DoorOpen' },
                        { label = 'Locked', value = lockedCount, icon = 'Lock', tone = 'warning' },
                        { label = 'Unlocked', value = #snapshot - lockedCount, icon = 'Unlock', tone = 'success' },
                    } },
                    { id = 'door-list', type = 'list', title = 'Door states', searchable = true, searchPlaceholder = 'Search doors…', pageSize = 12, layout = 'cards', items = rows, empty = 'No doors configured.' },
                },
            },
        } },
    }
    if not asUpdate then
        app.id = APP_ID
        app.onAction = function(actionId, context)
            local updated, err
            local id = context and context.itemId
            if actionId == 'doorlock:refresh' then
                updated, err = QB.callback.trigger('qbdoorlock:server:managementSnapshotRequested')
            elseif actionId == 'doorlock:create' then
                CreateThread(function() createTargetedDoor() end)
                return { close = true }
            elseif actionId == 'doorlock:closest' then
                managementClosestFirst = true
                return { update = managementDefinition(managementSnapshotData or snapshot, true, true), notice = { tone = 'success', message = 'Sorted by current distance.' } }
            elseif actionId == 'doorlock:toggle' and id then
                local door = findSnapshotDoor(id)
                updated, err = door and QB.callback.trigger('qbdoorlock:server:managementStateSet', id, not door.locked)
            elseif actionId == 'doorlock:edit' and id and type(context.value) == 'table' then
                local door = findSnapshotDoor(id)
                updated, err = door and QB.callback.trigger('qbdoorlock:server:managementDoorSaved', id, definitionFromValues(context.value, door.definition), false)
            elseif actionId == 'doorlock:delete' and id then
                updated, err = QB.callback.trigger('qbdoorlock:server:managementDoorDeleted', id)
            elseif actionId == 'doorlock:teleport' and id then
                QB.events.trigger('qbdoorlock:server:teleportRequested', id)
                return { close = true }
            elseif actionId == 'doorlock:duplicate' and id then
                local door = findSnapshotDoor(id)
                CreateThread(function() createTargetedDoor(door and door.definition) end)
                return { close = true }
            elseif (actionId == 'doorlock:retarget-single' or actionId == 'doorlock:retarget-double') and id then
                local door = findSnapshotDoor(id)
                CreateThread(function() if door then replaceDoorGeometry(door, actionId == 'doorlock:retarget-double') end end)
                return { close = true }
            elseif actionId == 'doorlock:link' and id and type(context.value) == 'table' then
                updated, err = QB.callback.trigger('qbdoorlock:server:managementDoorsLinked', id, context.value.linkedDoorId)
            elseif actionId == 'doorlock:unlink' and id then
                updated, err = QB.callback.trigger('qbdoorlock:server:managementDoorsUnlinked', id)
            else
                error('That door action is no longer available.')
            end
            if not updated then error(err or 'The door lock service did not answer.') end
            managementSnapshotData = updated
            return { update = managementDefinition(updated, managementClosestFirst, true), notice = { tone = 'success', message = 'Door lock updated.' } }
        end
    end
    return app
end

local function openManagement(closestFirst)
    CreateThread(function()
        local snapshot, err = QB.callback.trigger('qbdoorlock:server:managementSnapshotRequested')
        if not snapshot then return notify(err or 'The door lock service did not answer.', 'error') end
        managementSnapshotData, managementClosestFirst = snapshot, closestFirst == true
        QB.nui.registerApp(managementDefinition(snapshot, managementClosestFirst))
        QB.nui.openApp(APP_ID)
    end)
end

QB.callback.register('qbdoorlock:client:passcodeRequested', function(label)
    local result = QB.nui.openInputDialog({ { id = 'passcode', label = 'Passcode', type = 'password', required = true, maxLength = 128 } }, label or 'Door lock')
    return result and not result.cancelled and result.values and result.values.passcode or nil
end)

QB.events.onPush('qbdoorlock:client:doorStateChanged', function(id, locked, source) applyState(id, locked, source, false) end)
QB.events.onPush('qbdoorlock:client:doorDefinitionUpdated', function(id, definition, locked) setupDoor(id, definition, locked) end)
QB.events.onPush('qbdoorlock:client:doorDefinitionRemoved', removeDoor)
QB.events.onPush('qbdoorlock:client:managementOpened', openManagement)
QB.events.onPush('qbdoorlock:client:targetedCreationRequested', function() CreateThread(function() createTargetedDoor() end) end)
QB.events.onPush('qbdoorlock:client:teleported', function(coords) QB.teleport.player(coords) end)

toggleBinding = QB.keybind.add({
    name = 'qbdoorlock_toggle', description = 'Lock or unlock the nearby door', defaultKey = 'E', defaultMapper = 'keyboard',
    onPressed = function() if nearbyDoor then QB.events.trigger('qbdoorlock:server:doorToggled', nearbyDoor) end end,
})
selectBinding = QB.keybind.add({
    name = 'qbdoorlock_select_door', description = 'Select an additional door', defaultKey = 'E', defaultMapper = 'keyboard', disabled = true,
    onPressed = function()
        if not selection then return end
        local leaf = targetedLeaf()
        if not leaf or leaf.entity == selection.first.entity then return notify(translate('different_door'), 'error') end
        finishSelection(leaf)
    end,
})
cancelBinding = QB.keybind.add({
    name = 'qbdoorlock_cancel_selection', description = 'Cancel door selection', defaultKey = 'X', defaultMapper = 'keyboard', disabled = true,
    onPressed = function() finishSelection(nil) end,
})

CreateThread(function()
    local spriteConfig = Config.DrawSprite
    if spriteConfig then
        for _, sprite in pairs(spriteConfig) do
            if sprite.dict and QB.stream.loadTextureDict(sprite.dict) then spriteDicts[sprite.dict] = true end
        end
    end
    local definitions, serverStates = QB.callback.trigger('qbdoorlock:server:doorsRequested')
    if type(definitions) ~= 'table' then return notify(translate('definitions_failed'), 'error') end
    for id, definition in pairs(definitions) do setupDoor(id, definition, type(serverStates) == 'table' and serverStates[id] == true) end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for dictionary in pairs(spriteDicts) do SetStreamedTextureDictAsNoLongerNeeded(dictionary) end
end)

CreateThread(function()
    while true do
        local position = GetEntityCoords(PlayerPedId())
        local closestId, closestDistance
        for id in pairs(activeDoors) do
            local door = doors[id]
            if door then
                local distance = doorDistance(door, position)
                if distance <= door.distance and (not closestDistance or distance < closestDistance) then closestId, closestDistance = id, distance end
                if not door.hideUi and Config.DrawSprite then
                    local sprite = Config.DrawSprite[door.locked and 'locked' or 'unlocked']
                    if sprite then
                        local color = sprite.color or { 255, 255, 255, 100 }
                        SetDrawOrigin(door.coords.x, door.coords.y, door.coords.z, 0)
                        DrawSprite(sprite.dict, sprite.name, 0.0, 0.0, sprite.width or 0.018, (sprite.height or 0.018) * GetAspectRatio(true), 0.0, color[1], color[2], color[3], color[4])
                        ClearDrawOrigin()
                    end
                end
            end
        end
        if nearbyDoor ~= closestId then nearbyDoor = closestId; updatePrompt() end
        Wait(next(activeDoors) and 0 or 200)
    end
end)

CreateThread(function()
    while true do
        for id in pairs(streamedDoors) do
            local door = doors[id]
            if door then
                for index, leaf in ipairs(doorLeaves(door)) do
                    local entity = door.entities[index]
                    if not entity or not DoesEntityExist(entity) then
                        if entity then entityDoors[entity] = nil end
                        entity = QB.world.getClosestEntity('object', leaf.coords, {
                            radius = 1.0, models = { leaf.model }, includeInvisible = true,
                        })
                        if entity then
                            door.entities[index], entityDoors[entity] = entity, id
                            pcall(function()
                                Entity(entity).state:set('qbdoorlock:id', id, false)
                                Entity(entity).state:set('doorId', id, false)
                            end)
                        end
                    end
                end
            end
        end
        Wait(next(streamedDoors) and 500 or 1000)
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName) if resourceName == 'qbtarget' then registerPendingTargets() end end)

---@param id string
---@return boolean? locked
exports('getDoorState', function(id)
    local door = doors[id]
    if not door then return nil end
    return door.locked
end)

---@return string? id
exports('getClosestDoorId', function() return nearbyDoor end)

---@return QBDoorlockDefinition? door
exports('getClosestDoor', function() return nearbyDoor and doors[nearbyDoor] or nil end)

---@param entity integer
---@return string? id
exports('getDoorIdFromEntity', getDoorIdFromEntity)

---@return boolean used
exports('useClosestDoor', function()
    if not nearbyDoor then return false end
    QB.events.trigger('qbdoorlock:server:doorToggled', nearbyDoor)
    return true
end)

---@return boolean started
exports('pickClosestDoor', function() return pickDoor(nearbyDoor) end)
