-- The door lock creator. It works like the qbcrafting creator: a grid of doors,
-- a Create new door button, and one page per door with its own forms and cards.
-- The door runtime lives in client/main.lua and is reached through DoorlockClient.

local APP_ID = 'qbdoorlock:creator'
local TITLE = 'Door Lock Creator'

local doors = {}          -- the server snapshot, sorted by name
local selectedDoor = nil  -- id
local currentView = 'doors'
local closestFirst = false
local pendingTool = nil   -- aim at a door after the creator closes
local revision = 0

local function notice(message, tone)
    return { tone = tone or 'success', message = message }
end

local function text(value)
    return type(value) == 'string' and value:match('^%s*(.-)%s*$') or ''
end

local function optionalText(value)
    local result = text(value)
    return result ~= '' and result or nil
end

local function toast(message)
    QB.notify.send({ title = TITLE, message = message, type = 'error' })
end

local function confirmed(title, message)
    local answer = QB.nui.openAlert({ title = title, message = message, confirmLabel = 'Delete' })
    return answer and answer.confirmed == true
end

local function copyValue(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for key, entry in pairs(value) do copy[key] = copyValue(entry) end
    return copy
end

local function removedAt(list, index)
    local kept = {}
    for position, value in ipairs(list or {}) do
        if position ~= index then kept[#kept + 1] = value end
    end
    return kept
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function coordsLabel(c)
    return ('%.2f, %.2f, %.2f'):format(c.x, c.y, c.z)
end

local function blockId(name, id)
    return ('%s:%s:%d'):format(name, id, revision)
end

local function doorEntry(id)
    for _, door in ipairs(doors) do
        if door.id == id then return door end
    end
end

local function leavesOf(definition)
    return definition.doors or { { model = definition.model, coords = definition.coords, heading = definition.heading } }
end

local function accessList(definition)
    local access = {}
    if definition.groups then access[#access + 1] = 'groups' end
    if definition.characters then access[#access + 1] = 'characters' end
    if definition.items then access[#access + 1] = 'items' end
    if definition.passcode then access[#access + 1] = 'passcode' end
    return access
end

local function stateText(door)
    local access = accessList(door.definition)
    return ('%s · %s · %s'):format(
        door.locked and 'Locked' or 'Unlocked',
        door.leaves == 2 and 'Double door' or 'Single door',
        #access > 0 and table.concat(access, ', ') or 'Public')
end

local function metadataText(metadata)
    if type(metadata) ~= 'table' then return nil end
    local parts = {}
    for _, key in ipairs(sortedKeys(metadata)) do parts[#parts + 1] = ('%s=%s'):format(key, tostring(metadata[key])) end
    return #parts > 0 and table.concat(parts, ', ') or nil
end

local function distanceTo(door, position)
    return DoorlockClient.distanceTo(door.id, position)
end

local function doorsView()
    local linkedLabels, lockedCount = {}, 0
    for _, door in ipairs(doors) do
        linkedLabels[door.id] = door.label
        if door.locked then lockedCount = lockedCount + 1 end
    end

    local position = QB.cache.coords()
    local rows = {}
    for _, door in ipairs(doors) do
        local distance = distanceTo(door, position)
        rows[#rows + 1] = {
            id = door.id,
            label = door.label,
            description = stateText(door),
            icon = door.leaves == 2 and 'DoorOpen' or 'DoorClosed',
            tone = door.locked and 'warning' or 'success',
            distance = distance,
            metadata = {
                { label = 'ID', value = door.id },
                { label = 'Distance', value = distance < math.huge and ('%.1f m'):format(distance) or 'Unknown' },
                { label = 'Auto-lock', value = door.autoLock and door.autoLock > 0 and ('%d sec'):format(math.floor(door.autoLock / 1000)) or 'Off' },
                { label = 'Linked door', value = door.linkedTo and (linkedLabels[door.linkedTo] or door.linkedTo) or 'None' },
                { label = 'Lockpick', value = door.definition.lockpick and 'Enabled' or 'Disabled' },
            },
            action = 'door:select:' .. door.id,
        }
    end
    if closestFirst then table.sort(rows, function(a, b) return a.distance < b.distance end) end

    return {
        id = 'doors', label = 'Doors', icon = 'DoorOpen',
        content = {
            title = 'Doors',
            description = 'Pick a door to change it, or create a new one by aiming at it.',
            blocks = {
                {
                    type = 'actions',
                    actions = {
                        { id = 'door:new', label = 'Create new door', icon = 'Plus', variant = 'primary' },
                        { id = 'door:closest', label = closestFirst and 'Sort by name' or 'Closest to me', icon = 'MapPin', variant = 'secondary' },
                        { id = 'door:refresh', label = 'Refresh', icon = 'RefreshCw', variant = 'secondary' },
                    },
                },
                {
                    type = 'stats',
                    items = {
                        { label = 'Configured', value = #doors, icon = 'DoorOpen' },
                        { label = 'Locked', value = lockedCount, icon = 'Lock', tone = 'warning' },
                        { label = 'Unlocked', value = #doors - lockedCount, icon = 'Unlock', tone = 'success' },
                    },
                },
                {
                    type = 'list', id = 'door-list', layout = 'cards', columns = 3,
                    title = ('Doors (%d)'):format(#rows), items = rows,
                    searchable = true, searchPlaceholder = 'Search doors…', pageSize = 12,
                    empty = 'No doors yet. Create one to get started.',
                },
            },
        },
    }
end

local function detailsForm(door)
    local definition = door.definition
    return {
        type = 'form', id = blockId('door-details', door.id), title = 'Details',
        fields = {
            { id = 'label', label = 'Door name', type = 'text', required = true, maxLength = 96, default = definition.label },
            { id = 'distance', label = 'Interaction distance', type = 'number', min = 0.5, max = 20, default = definition.distance or Config.InteractionDistance,
                description = 'How close a player must be to use the door, in metres.' },
            { id = 'autoLock', label = 'Auto-lock seconds', type = 'number', min = 0, max = 86400,
                default = definition.autoLock and definition.autoLock / 1000 or 0,
                description = 'The door locks itself this long after it was unlocked. 0 turns it off.' },
            { id = 'doorRate', label = 'Door movement rate', type = 'number', min = 0, max = 10, default = definition.doorRate,
                description = 'Optional. 0 to 10. Leave empty for the game default.' },
            { id = 'automatic', label = 'Automatic or sliding door', type = 'checkbox', default = definition.automatic == true },
            { id = 'holdOpen', label = 'Hold open while unlocked', type = 'checkbox', default = definition.holdOpen == true },
            { id = 'hideUi', label = 'Hide the interaction indicator', type = 'checkbox', default = definition.hideUi == true },
        },
        action = { id = 'door:details', label = 'Save' },
    }
end

local function groupCards(definition)
    local cards = {}
    for _, name in ipairs(sortedKeys(definition.groups)) do
        local grade = definition.groups[name]
        cards[#cards + 1] = {
            id = name, label = name, icon = 'Users',
            description = grade > 0 and ('Grade %d or higher'):format(grade) or 'Any grade',
            actions = {
                { id = 'door:group:edit:' .. name, label = 'Edit', icon = 'Pencil', variant = 'primary' },
                { id = 'door:group:remove:' .. name, label = 'Remove', icon = 'Trash2', variant = 'destructive' },
            },
        }
    end
    return cards
end

local function characterCards(definition)
    local cards = {}
    for _, character in ipairs(definition.characters or {}) do
        cards[#cards + 1] = {
            id = character, label = character, icon = 'User', description = 'Character ID',
            actions = { { id = 'door:character:remove:' .. character, label = 'Remove', icon = 'Trash2', variant = 'destructive' } },
        }
    end
    return cards
end

local function itemCards(definition)
    local cards = {}
    for index, item in ipairs(definition.items or {}) do
        local metadata = {}
        local extra = metadataText(item.metadata)
        if extra then metadata[#metadata + 1] = { label = 'Metadata', value = extra } end
        metadata[#metadata + 1] = { label = 'Used up', value = item.remove and 'Yes' or 'No, kept' }
        cards[#cards + 1] = {
            id = tostring(index), label = item.name, icon = 'KeyRound', description = 'Key item', metadata = metadata,
            actions = {
                { id = 'door:item:edit:' .. index, label = 'Edit', icon = 'Pencil', variant = 'primary' },
                { id = 'door:item:remove:' .. index, label = 'Remove', icon = 'Trash2', variant = 'destructive' },
            },
        }
    end
    return cards
end

local function accessBlocks(door)
    local definition = door.definition
    local groups, characters, items = groupCards(definition), characterCards(definition), itemCards(definition)
    return {
        {
            type = 'form', id = blockId('door-passcode', door.id), title = 'Access',
            fields = { { id = 'passcode', label = 'Passcode', type = 'password', maxLength = 128, default = definition.passcode,
                description = 'Anyone who enters it can use the door. Any one way in is enough: a group, a character, a key item, or this passcode. With none of them the door is public. Leave empty for no passcode.' } },
            action = { id = 'door:passcode', label = 'Save' },
        },
        {
            type = 'actions',
            actions = { { id = 'door:group:add', label = 'Add job or gang', icon = 'Plus', variant = 'primary' } },
        },
        {
            type = 'list', id = 'door-groups', layout = 'cards', columns = 3,
            title = ('Jobs and gangs (%d)'):format(#groups), items = groups,
            empty = 'No job or gang can use this door yet.',
        },
        {
            type = 'actions',
            actions = { { id = 'door:character:add', label = 'Add character', icon = 'Plus', variant = 'primary' } },
        },
        {
            type = 'list', id = 'door-characters', layout = 'cards', columns = 3,
            title = ('Characters (%d)'):format(#characters), items = characters,
            empty = 'No single character is let in by ID.',
        },
        {
            type = 'actions',
            actions = { { id = 'door:item:add', label = 'Add key item', icon = 'Plus', variant = 'primary' } },
        },
        {
            type = 'list', id = 'door-items', layout = 'cards', columns = 3,
            title = ('Key items (%d)'):format(#items), items = items,
            empty = 'No item opens this door.',
        },
    }
end

local function lockpickForm(door)
    local definition = door.definition
    local list = type(definition.lockpickDifficulty) == 'table' and definition.lockpickDifficulty or {}
    local legacy = list.pinCount == nil and list.tolerance == nil and list.speed == nil and next(list) ~= nil
    return {
        type = 'form', id = blockId('door-lockpick', door.id), title = 'Lockpicking',
        fields = {
            { id = 'lockpick', label = 'Can be lockpicked', type = 'checkbox', default = definition.lockpick == true },
            { id = 'pinCount', label = 'Pins', type = 'number', min = 1, max = 12, default = list.pinCount or 5,
                description = legacy and 'This door uses an easy/medium/hard list. Saving replaces it with these values.' or nil },
            { id = 'tolerance', label = 'Tolerance', type = 'number', min = 0.03, max = 0.35, default = list.tolerance or 0.14,
                description = 'How forgiving the pins are. 0.03 to 0.35, higher is easier.' },
            { id = 'speed', label = 'Speed', type = 'number', min = 0.3, max = 4, default = list.speed or 1,
                description = '0.3 to 4, higher is harder.' },
        },
        action = { id = 'door:lockpick', label = 'Save' },
    }
end

local function soundsForm(door)
    local definition = door.definition
    return {
        type = 'form', id = blockId('door-sounds', door.id), title = 'Sounds',
        fields = {
            { id = 'lockSound', label = 'Lock sound name', type = 'text', maxLength = 96, default = definition.lockSound or '',
                description = 'Optional. Leave all four empty for the default sounds.' },
            { id = 'lockSoundSet', label = 'Lock sound set', type = 'text', maxLength = 96, default = definition.lockSoundSet or '' },
            { id = 'unlockSound', label = 'Unlock sound name', type = 'text', maxLength = 96, default = definition.unlockSound or '' },
            { id = 'unlockSoundSet', label = 'Unlock sound set', type = 'text', maxLength = 96, default = definition.unlockSoundSet or '' },
        },
        action = { id = 'door:sounds', label = 'Save' },
    }
end

local function leafCards(definition)
    local cards = {}
    local leaves = leavesOf(definition)
    for index, leaf in ipairs(leaves) do
        cards[#cards + 1] = {
            id = tostring(index),
            label = #leaves == 2 and ('Door %d'):format(index) or 'Door',
            icon = 'MapPin',
            description = coordsLabel(leaf.coords),
            metadata = {
                { label = 'Model', value = tostring(leaf.model) },
                { label = 'Heading', value = leaf.heading and ('%.1f'):format(leaf.heading) or 'Unknown' },
            },
        }
    end
    return cards
end

local function linkBlocks(door)
    if door.linkedTo then
        local other = doorEntry(door.linkedTo)
        local actions = {}
        if other then actions[#actions + 1] = { id = 'door:select:' .. door.linkedTo, label = 'Open', icon = 'ExternalLink', variant = 'primary' } end
        actions[#actions + 1] = { id = 'door:unlink', label = 'Unlink', icon = 'Unlink', variant = 'destructive' }
        return { {
            type = 'list', id = 'door-link', layout = 'cards', columns = 3, title = 'Linked door',
            items = { {
                id = door.linkedTo, label = other and other.label or door.linkedTo, icon = 'Link',
                description = 'Locks and unlocks together with this door.',
                actions = actions,
            } },
        } }
    end

    local options = {}
    for _, candidate in ipairs(doors) do
        if candidate.id ~= door.id and not candidate.linkedTo then options[#options + 1] = { value = candidate.id, label = candidate.label } end
    end
    if #options == 0 then
        return { { type = 'list', id = 'door-link', layout = 'cards', columns = 3, title = 'Linked door', items = {},
            empty = 'No other door is free to link with.' } }
    end
    return { {
        type = 'form', id = blockId('door-link', door.id), title = 'Link with another door',
        fields = { { id = 'linkedDoorId', label = 'Link with', type = 'select', required = true, options = options,
            description = 'Linked doors always lock and unlock together.' } },
        action = { id = 'door:link', label = 'Link' },
    } }
end

local function doorView()
    local door = doorEntry(selectedDoor)
    if not door then
        return {
            id = 'door', label = 'Door', icon = 'DoorOpen',
            content = { title = 'Door', blocks = { { type = 'empty', title = 'Pick a door first.' } } },
        }
    end

    local blocks = {
        {
            type = 'actions',
            actions = {
                { id = 'door:toggle', label = door.locked and 'Unlock' or 'Lock', icon = door.locked and 'Unlock' or 'Lock', variant = 'primary' },
                { id = 'door:teleport', label = 'Teleport to door', icon = 'MapPin', variant = 'secondary' },
            },
        },
        detailsForm(door),
    }
    for _, block in ipairs(accessBlocks(door)) do blocks[#blocks + 1] = block end
    blocks[#blocks + 1] = lockpickForm(door)
    blocks[#blocks + 1] = soundsForm(door)

    local leaves = leafCards(door.definition)
    blocks[#blocks + 1] = {
        type = 'list', id = 'door-geometry', layout = 'cards', columns = 3,
        title = ('Where it is (%d)'):format(#leaves), items = leaves,
    }
    blocks[#blocks + 1] = {
        type = 'actions',
        actions = {
            { id = 'door:retarget:single', label = 'Aim at a different single door', icon = 'ScanSearch', variant = 'secondary' },
            { id = 'door:retarget:double', label = 'Aim at a different double door', icon = 'PanelsTopLeft', variant = 'secondary' },
        },
    }
    for _, block in ipairs(linkBlocks(door)) do blocks[#blocks + 1] = block end
    blocks[#blocks + 1] = {
        type = 'actions',
        actions = { { id = 'door:duplicate', label = 'Duplicate door (settings only)', icon = 'Copy', variant = 'primary' } },
    }
    blocks[#blocks + 1] = {
        type = 'actions', title = 'Danger zone',
        actions = { { id = 'door:delete', label = 'Delete door', variant = 'destructive' } },
    }

    return {
        id = 'door', label = door.label, icon = door.leaves == 2 and 'DoorOpen' or 'DoorClosed',
        content = {
            title = door.label,
            description = ('%s. ID: %s.'):format(stateText(door), door.id),
            blocks = blocks,
        },
    }
end

local function buildNavigation()
    local navigation = { doorsView() }
    if selectedDoor and doorEntry(selectedDoor) then navigation[#navigation + 1] = doorView() end
    return navigation
end

local function refresh(message)
    local navigation = buildNavigation()
    QB.nui.updateApp(APP_ID, { navigation = navigation })
    return { update = { navigation = navigation }, notice = message }
end

local function fail(message)
    return refresh(notice(message, 'destructive'))
end

local function setData(snapshot)
    doors = type(snapshot) == 'table' and snapshot or {}
    if selectedDoor and not doorEntry(selectedDoor) then
        selectedDoor = nil
        if currentView == 'door' then currentView = 'doors' end
    end
end

local function change(callback, ...)
    local result, err = QB.callback.trigger(callback, ...)
    if not result then return nil, err end
    setData(result)
    revision = revision + 1
    return result
end

local function openDoor(id, message)
    selectedDoor = id
    revision = revision + 1
    currentView = 'door'
    return refresh(message)
end

-- Changes one part of a door: copy its definition, let `mutate` edit the copy
-- (return a message to refuse), and let the server validate and save it.
local function edit(door, mutate, message)
    local definition = copyValue(door.definition)
    local refusal = mutate(definition)
    if refusal then return fail(refusal) end

    local result, err = change('qbdoorlock:server:managementDoorSaved', door.id, definition, false)
    if not result then return fail(err or 'Failed to save.') end
    return refresh(notice(message or 'Saved.'))
end

local function askNewDoor(title, name, double)
    local result = QB.nui.openInputDialog({
        { id = 'name', label = 'Door name', type = 'text', required = true, maxLength = 96, default = name },
        { id = 'double', label = 'Double door', type = 'checkbox', default = double == true },
    }, title, 'You will aim at the door next. You can change everything later.')
    if not result or result.cancelled then return nil end

    local label = optionalText(result.values and result.values.name)
    if not label then return nil end
    return { name = label, double = result.values.double == true }
end

local function askGroup(current)
    local fields = {}
    if not current then
        fields[#fields + 1] = { id = 'name', label = 'Job or gang name', type = 'text', required = true, maxLength = 64, placeholder = 'police' }
    end
    fields[#fields + 1] = { id = 'grade', label = 'Minimum grade', type = 'number', min = 0, max = 1000, required = true,
        default = current and current.grade or 0 }

    local result = QB.nui.openInputDialog(fields, current and ('Edit %s'):format(current.name) or 'Add job or gang',
        'Members of this job or gang can use the door from this grade up.')
    if not result or result.cancelled then return nil end

    local values = result.values or {}
    local grade = tonumber(values.grade)
    local name = current and current.name or optionalText(values.name)
    if not grade or not name then return nil end
    return { name = name:lower(), grade = math.max(0, math.floor(grade)) }
end

local function askCharacter()
    local result = QB.nui.openInputDialog({
        { id = 'character', label = 'Character ID', type = 'text', required = true, maxLength = 96 },
    }, 'Add character', 'This one character can always use the door.')
    if not result or result.cancelled then return nil end
    return optionalText(result.values and result.values.character)
end

local function askItem(current)
    local metadataType = current and type(current.metadata) == 'table' and current.metadata.type or nil
    local result = QB.nui.openInputDialog({
        { id = 'name', label = 'Item name', type = 'text', required = true, maxLength = 64, default = current and current.name or '' },
        { id = 'type', label = 'Metadata type', type = 'text', maxLength = 128, default = metadataType and tostring(metadataType) or '',
            description = 'Optional. Only items whose type matches are accepted.' },
        {
            id = 'remove', label = 'Used up when opening?', type = 'select',
            default = current and current.remove and 'use' or 'keep',
            options = { { value = 'keep', label = 'No, the player keeps it' }, { value = 'use', label = 'Yes, used up' } },
        },
    }, current and 'Edit key item' or 'Add key item', 'A player holding this item can use the door.')
    if not result or result.cancelled then return nil end

    local values = result.values or {}
    local name = optionalText(values.name)
    if not name then return nil end

    local metadata = current and type(current.metadata) == 'table' and copyValue(current.metadata) or {}
    metadata.type = optionalText(values.type)
    return { name = name:lower(), metadata = next(metadata) and metadata or nil, remove = values.remove == 'use' or nil }
end

local function detailsInput(definition, values)
    local seconds = tonumber(values.autoLock) or 0
    definition.label = text(values.label)
    definition.distance = tonumber(values.distance)
    definition.autoLock = seconds > 0 and math.floor(seconds * 1000) or nil
    definition.doorRate = tonumber(values.doorRate)
    definition.automatic = values.automatic == true
    definition.holdOpen = values.holdOpen == true
    definition.hideUi = values.hideUi == true
end

local function lockpickInput(definition, values)
    local previous = type(definition.lockpickDifficulty) == 'table' and definition.lockpickDifficulty or {}
    definition.lockpick = values.lockpick == true
    definition.lockpickDifficulty = {
        pinCount = tonumber(values.pinCount),
        tolerance = tonumber(values.tolerance),
        speed = tonumber(values.speed),
        attempts = previous.attempts or 1,
        timeLimit = previous.timeLimit or 15000,
    }
end

local function applyGeometry(definition, geometry)
    definition.model, definition.coords, definition.heading, definition.doors = nil, nil, nil, nil
    if geometry.doors then
        definition.doors = geometry.doors
    else
        definition.model, definition.coords, definition.heading = geometry.model, geometry.coords, geometry.heading
    end
end

local function leafOf(leaf)
    return { model = leaf.model, coords = leaf.coords, heading = leaf.heading }
end

-- Runs with the creator closed: aim at one door, or two for a double door.
local function captureGeometry(double)
    local first = DoorlockClient.selectLeaf(nil, 'select_first')
    if not first then
        DoorlockClient.notify(DoorlockClient.translate('selection_cancelled'), 'error')
        return nil
    end
    if not double then return leafOf(first) end

    local second = DoorlockClient.selectLeaf(first, 'select_second')
    if not second then
        DoorlockClient.notify(DoorlockClient.translate('selection_cancelled'), 'error')
        return nil
    end
    return { doors = { leafOf(first), leafOf(second) } }
end

local function runTool(tool)
    local geometry = captureGeometry(tool.double)
    if not geometry then return end

    if tool.kind == 'retarget' then
        local door = doorEntry(tool.id)
        if not door then return end

        local definition = copyValue(door.definition)
        applyGeometry(definition, geometry)
        local result, err = change('qbdoorlock:server:managementDoorSaved', door.id, definition, false)
        if not result then return toast(err or 'Could not retarget the door.') end
        return DoorlockClient.notify(DoorlockClient.translate('door_retargeted'), 'success')
    end

    local definition = tool.template and copyValue(tool.template)
        or { locked = true, lockpick = false, distance = Config.InteractionDistance }
    definition.label = tool.name
    applyGeometry(definition, geometry)

    local result, err = QB.callback.trigger('qbdoorlock:server:managementDoorCreated', definition)
    if not result then return toast(err or 'Could not save the door.') end

    setData(result.doors)
    revision = revision + 1
    selectedDoor, currentView = result.id, 'door'
    DoorlockClient.notify(DoorlockClient.translate('door_saved'), 'success')
end

local function groupAction(door, actionId)
    if actionId == 'door:group:add' then
        local group = askGroup()
        if not group then return refresh() end
        return edit(door, function(definition)
            definition.groups = definition.groups or {}
            definition.groups[group.name] = group.grade
        end, ('%s added.'):format(group.name))
    end

    local editName = actionId:match('^door:group:edit:(.+)$')
    if editName then
        local grade = door.definition.groups and door.definition.groups[editName]
        if not grade then return refresh() end

        local group = askGroup({ name = editName, grade = grade })
        if not group then return refresh() end
        return edit(door, function(definition) definition.groups[editName] = group.grade end,
            ('%s now needs grade %d.'):format(editName, group.grade))
    end

    local removeName = actionId:match('^door:group:remove:(.+)$')
    if removeName then
        return edit(door, function(definition)
            if definition.groups then definition.groups[removeName] = nil end
            if definition.groups and not next(definition.groups) then definition.groups = nil end
        end, ('%s removed.'):format(removeName))
    end

    return refresh()
end

local function characterAction(door, actionId)
    if actionId == 'door:character:add' then
        local character = askCharacter()
        if not character then return refresh() end
        return edit(door, function(definition)
            definition.characters = definition.characters or {}
            for _, existing in ipairs(definition.characters) do
                if existing == character then return 'That character is already on the door.' end
            end
            definition.characters[#definition.characters + 1] = character
        end, 'Character added.')
    end

    local removeId = actionId:match('^door:character:remove:(.+)$')
    if removeId then
        return edit(door, function(definition)
            local kept = {}
            for _, existing in ipairs(definition.characters or {}) do
                if existing ~= removeId then kept[#kept + 1] = existing end
            end
            definition.characters = #kept > 0 and kept or nil
        end, 'Character removed.')
    end

    return refresh()
end

local function itemAction(door, actionId)
    if actionId == 'door:item:add' then
        local item = askItem()
        if not item then return refresh() end
        return edit(door, function(definition)
            definition.items = definition.items or {}
            definition.items[#definition.items + 1] = item
        end, ('%s added.'):format(item.name))
    end

    local editIndex = tonumber(actionId:match('^door:item:edit:(%d+)$'))
    if editIndex then
        local current = door.definition.items and door.definition.items[editIndex]
        if not current then return refresh() end

        local item = askItem(current)
        if not item then return refresh() end
        return edit(door, function(definition) definition.items[editIndex] = item end, ('%s saved.'):format(item.name))
    end

    local removeIndex = tonumber(actionId:match('^door:item:remove:(%d+)$'))
    if removeIndex then
        return edit(door, function(definition)
            local kept = removedAt(definition.items, removeIndex)
            definition.items = #kept > 0 and kept or nil
        end, 'Key item removed.')
    end

    return refresh()
end

local function doorAction(actionId, values)
    if actionId == 'door:new' then
        local new = askNewDoor('New door', '', false)
        if not new then return refresh() end
        pendingTool = { kind = 'create', name = new.name, double = new.double }
        return { close = true }
    end

    if actionId == 'door:refresh' then
        local result, err = change('qbdoorlock:server:managementSnapshotRequested')
        if not result then return fail(err or 'The door lock service did not answer.') end
        return refresh(notice('Refreshed.'))
    end

    if actionId == 'door:closest' then
        closestFirst = not closestFirst
        return refresh(notice(closestFirst and 'Sorted by distance.' or 'Sorted by name.'))
    end

    local selectId = actionId:match('^door:select:(.+)$')
    if selectId then
        if not doorEntry(selectId) then return fail('Unknown door.') end
        return openDoor(selectId)
    end

    local door = doorEntry(selectedDoor)
    if not door then return fail('Pick a door first.') end

    if actionId == 'door:toggle' then
        local result, err = change('qbdoorlock:server:managementStateSet', door.id, not door.locked)
        if not result then return fail(err or 'Failed to change the door.') end
        return refresh(notice(door.locked and 'Door unlocked.' or 'Door locked.'))
    end

    if actionId == 'door:teleport' then
        QB.events.trigger('qbdoorlock:server:teleportRequested', door.id)
        return { close = true }
    end

    if actionId == 'door:details' then
        return edit(door, function(definition) detailsInput(definition, values) end)
    end

    if actionId == 'door:passcode' then
        return edit(door, function(definition) definition.passcode = optionalText(values.passcode) end)
    end

    if actionId:match('^door:group:') then return groupAction(door, actionId) end
    if actionId:match('^door:character:') then return characterAction(door, actionId) end
    if actionId:match('^door:item:') then return itemAction(door, actionId) end

    if actionId == 'door:lockpick' then
        return edit(door, function(definition) lockpickInput(definition, values) end)
    end

    if actionId == 'door:sounds' then
        return edit(door, function(definition)
            definition.lockSound, definition.lockSoundSet = optionalText(values.lockSound), optionalText(values.lockSoundSet)
            definition.unlockSound, definition.unlockSoundSet = optionalText(values.unlockSound), optionalText(values.unlockSoundSet)
        end)
    end

    if actionId == 'door:retarget:single' or actionId == 'door:retarget:double' then
        pendingTool = { kind = 'retarget', id = door.id, double = actionId == 'door:retarget:double' }
        return { close = true }
    end

    if actionId == 'door:link' then
        local linkedId = values.linkedDoorId
        if type(linkedId) ~= 'string' or linkedId == '' then return fail('Pick a door to link with.') end
        local result, err = change('qbdoorlock:server:managementDoorsLinked', door.id, linkedId)
        if not result then return fail(err or 'Failed to link the doors.') end
        return refresh(notice('Doors linked.'))
    end

    if actionId == 'door:unlink' then
        local result, err = change('qbdoorlock:server:managementDoorsUnlinked', door.id)
        if not result then return fail(err or 'Failed to unlink the doors.') end
        return refresh(notice('Doors unlinked.'))
    end

    if actionId == 'door:duplicate' then
        local new = askNewDoor('Duplicate door', door.label .. ' copy', door.leaves == 2)
        if not new then return refresh() end
        pendingTool = { kind = 'create', name = new.name, double = new.double, template = door.definition }
        return { close = true }
    end

    if actionId == 'door:delete' then
        if not confirmed('Delete door?', ('This removes %s for good, and unlinks it from any door it is paired with.'):format(door.label)) then
            return refresh()
        end
        local result, err = change('qbdoorlock:server:managementDoorDeleted', door.id)
        if not result then return fail(err or 'Failed to delete the door.') end
        selectedDoor, currentView = nil, 'doors'
        return refresh(notice('Door deleted.'))
    end

    return refresh()
end

local function onAction(actionId, context)
    local values = context and type(context.value) == 'table' and context.value or {}
    if actionId:match('^door:') then return doorAction(actionId, values) end
    return refresh()
end

QB.nui.registerApp({
    id = APP_ID,
    title = TITLE,
    icon = 'LockKeyhole',
    layout = 'standard',
    width = 1200,
    height = 800,
    defaultView = 'doors',
    navigation = { { id = 'doors', label = 'Doors', icon = 'DoorOpen', content = { title = 'Doors', blocks = {} } } },
    onAction = onAction,
})

---@param options? { closestFirst?: boolean, create?: boolean }
local function open(options)
    options = options or {}
    local result, err = QB.callback.trigger('qbdoorlock:server:managementSnapshotRequested')
    if not result then
        toast(err or 'Admin permission required.')
        return
    end

    setData(result)
    if options.closestFirst ~= nil then closestFirst = options.closestFirst end

    if options.create then
        local new = askNewDoor('New door', '', false)
        if not new then return end
        pendingTool = { kind = 'create', name = new.name, double = new.double }
    end

    while true do
        if pendingTool then
            local tool = pendingTool
            pendingTool = nil
            runTool(tool)
        end

        QB.nui.updateApp(APP_ID, { navigation = buildNavigation() })
        QB.nui.openApp(APP_ID, { viewId = currentView })
        if not pendingTool then break end
    end
end

QB.events.onPush('qbdoorlock:client:managementOpened', function(closest)
    CreateThread(function() open({ closestFirst = closest == true }) end)
end)

QB.events.onPush('qbdoorlock:client:targetedCreationRequested', function()
    CreateThread(function() open({ create = true }) end)
end)
