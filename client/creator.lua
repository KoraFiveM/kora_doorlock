-- The door lock creator. It works like the kora_crafting creator: a grid of doors,
-- a Create new door button, and one page per door with its own forms and cards.
-- Categories are optional: a category (a building, say) holds default settings for new doors and places
-- doors in bulk as category-1, category-2 ... Each door keeps its own copy, so it can still be changed alone.
-- The door runtime lives in client/main.lua and is reached through DoorlockClient.

local APP_ID = 'qbdoorlock:creator'

-- All player-facing text comes from locales/*.json through the door runtime (client/main.lua).
local function T(key, replacements)
    return DoorlockClient.translate(key, replacements)
end

local doors = {}          -- the server snapshot, sorted by name
local categories = {}     -- { id, label, defaults }, sorted by name
local selectedDoor = nil  -- id
local selectedCategory = nil -- id
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
    Kora.notify.send({ title = T('creator_title'), message = message, type = 'error' })
end

local function confirmed(title, message)
    local answer = Kora.nui.openAlert({ title = title, message = message, confirmLabel = T('delete') })
    return answer and answer.confirmed == true
end

local copyValue = Kora.util.deepClone

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

local function categoryEntry(id)
    for _, category in ipairs(categories) do
        if category.id == id then return category end
    end
end

-- The id the next door placed in a category will get: one above the highest category-N that exists.
local function nextCategoryId(category)
    local ids = {}
    for _, door in ipairs(doors) do ids[#ids + 1] = door.id end
    local highest = DoorlockSchema.highestCategorySuffix(ids, category.id)
    return ('%s-%d'):format(category.id, highest + 1), highest + 1
end

-- The forms and cards that edit "a door" also edit a category's defaults. The defaults are shown as a stand-in
-- door; its action ids start with cd: instead of door: so the two can never be mixed up.
local function categoryTarget(category)
    return { id = category.id, blockKey = 'cat-' .. category.id, label = category.label, definition = category.defaults, isCategory = true, locked = false, leaves = 1 }
end

local function prefixOf(door)
    return door.isCategory and 'cd:' or 'door:'
end

local leavesOf = DoorlockSchema.leaves

local function accessList(definition)
    local access = {}
    if definition.groups then access[#access + 1] = T('access_groups') end
    if definition.characters then access[#access + 1] = T('access_characters') end
    if definition.items then access[#access + 1] = T('access_items') end
    if definition.hasPasscode then access[#access + 1] = T('access_passcode') end
    return access
end

local function stateText(door)
    local access = accessList(door.definition)
    return ('%s · %s · %s'):format(
        door.locked and T('state_locked') or T('state_unlocked'),
        door.leaves == 2 and T('state_double') or T('state_single'),
        #access > 0 and table.concat(access, ', ') or T('access_public'))
end

local function metadataText(metadata)
    if type(metadata) ~= 'table' then return nil end
    local parts = {}
    for _, key in ipairs(sortedKeys(metadata)) do parts[#parts + 1] = ('%s=%s'):format(key, tostring(metadata[key])) end
    return #parts > 0 and table.concat(parts, ', ') or nil
end

local function doorSummary(door)
    local category = door.definition.category and categoryEntry(door.definition.category)
    if category then return ('%s · %s'):format(stateText(door), category.label) end
    return stateText(door)
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

    local position = Kora.cache.coords()
    local rows = {}
    for _, door in ipairs(doors) do
        local distance = distanceTo(door, position)
        rows[#rows + 1] = {
            id = door.id,
            label = door.label,
            description = doorSummary(door),
            icon = door.leaves == 2 and 'DoorOpen' or 'DoorClosed',
            tone = door.locked and 'warning' or 'success',
            distance = distance,
            metadata = {
                { label = T('meta_id'), value = door.id },
                { label = T('category'), value = (door.definition.category and categoryEntry(door.definition.category) or { label = T('meta_none') }).label },
                { label = T('meta_distance'), value = distance < math.huge and ('%.1f m'):format(distance) or T('meta_unknown') },
                { label = T('meta_auto_lock'), value = door.autoLock and door.autoLock > 0 and T('seconds_short', { count = math.floor(door.autoLock / 1000) }) or T('meta_off') },
                { label = T('meta_linked_door'), value = door.linkedTo and (linkedLabels[door.linkedTo] or door.linkedTo) or T('meta_none') },
                { label = T('meta_lockpick'), value = door.definition.lockpick and T('meta_enabled') or T('meta_disabled') },
            },
            action = 'door:select:' .. door.id,
        }
    end
    if closestFirst then table.sort(rows, function(a, b) return a.distance < b.distance end) end

    return {
        id = 'doors', label = T('doors_label'), icon = 'DoorOpen',
        content = {
            title = T('doors_label'),
            description = T('doors_description'),
            blocks = {
                {
                    type = 'actions',
                    actions = {
                        { id = 'door:new', label = T('door_new'), icon = 'Plus', variant = 'primary' },
                        { id = 'door:closest', label = closestFirst and T('sort_name') or T('sort_closest'), icon = 'MapPin', variant = 'secondary' },
                        { id = 'door:refresh', label = T('refresh'), icon = 'RefreshCw', variant = 'secondary' },
                    },
                },
                {
                    type = 'stats',
                    items = {
                        { label = T('stat_configured'), value = #doors, icon = 'DoorOpen' },
                        { label = T('state_locked'), value = lockedCount, icon = 'Lock', tone = 'warning' },
                        { label = T('state_unlocked'), value = #doors - lockedCount, icon = 'Unlock', tone = 'success' },
                    },
                },
                {
                    type = 'list', id = 'door-list', layout = 'cards', columns = 3,
                    title = T('doors_title', { count = #rows }), items = rows,
                    searchable = true, searchPlaceholder = T('search_doors'), pageSize = 12,
                    empty = T('doors_empty'),
                },
            },
        },
    }
end

local function detailsForm(door)
    local definition, prefix = door.definition, prefixOf(door)
    local fields = {}
    if not door.isCategory then
        fields[#fields + 1] = { id = 'label', label = T('field_door_name'), type = 'text', required = true, maxLength = 96, default = definition.label }
    end
    local shared = {
            { id = 'distance', label = T('field_distance'), type = 'number', min = 0.5, max = 20, default = definition.distance or Config.InteractionDistance,
                description = T('field_distance_help') },
            { id = 'autoLock', label = T('field_autolock'), type = 'number', min = 0, max = 86400,
                default = definition.autoLock and definition.autoLock / 1000 or 0,
                description = T('field_autolock_help') },
            { id = 'doorRate', label = T('field_doorrate'), type = 'number', min = 0, max = 10, default = definition.doorRate,
                description = T('field_doorrate_help') },
            { id = 'automatic', label = T('field_automatic'), type = 'checkbox', default = definition.automatic == true },
            { id = 'holdOpen', label = T('field_holdopen'), type = 'checkbox', default = definition.holdOpen == true },
            { id = 'hideUi', label = T('field_hideui'), type = 'checkbox', default = definition.hideUi == true },
    }
    for _, field in ipairs(shared) do fields[#fields + 1] = field end

    return {
        type = 'form', id = blockId(door.isCategory and 'category-details' or 'door-details', door.blockKey or door.id),
        title = door.isCategory and T('details_new_doors_title') or T('details_title'),
        fields = fields,
        action = { id = prefix .. 'details', label = T('save') },
    }
end

local function groupCards(definition, prefix)
    local cards = {}
    for _, name in ipairs(sortedKeys(definition.groups)) do
        local grade = definition.groups[name]
        cards[#cards + 1] = {
            id = name, label = name, icon = 'Users',
            description = grade > 0 and T('grade_min', { grade = grade }) or T('grade_any'),
            actions = {
                { id = prefix .. 'group:edit:' .. name, label = T('edit'), icon = 'Pencil', variant = 'primary' },
                { id = prefix .. 'group:remove:' .. name, label = T('remove'), icon = 'Trash2', variant = 'destructive' },
            },
        }
    end
    return cards
end

local function characterCards(definition, prefix)
    local cards = {}
    for _, character in ipairs(definition.characters or {}) do
        cards[#cards + 1] = {
            id = character, label = character, icon = 'User', description = T('character_id'),
            actions = { { id = prefix .. 'character:remove:' .. character, label = T('remove'), icon = 'Trash2', variant = 'destructive' } },
        }
    end
    return cards
end

local function itemCards(definition, prefix)
    local cards = {}
    for index, item in ipairs(definition.items or {}) do
        local metadata = {}
        local extra = metadataText(item.metadata)
        if extra then metadata[#metadata + 1] = { label = T('metadata'), value = extra } end
        metadata[#metadata + 1] = { label = T('used_up'), value = item.remove and T('used_yes') or T('used_no_kept') }
        cards[#cards + 1] = {
            id = tostring(index), label = item.name, icon = 'KeyRound', description = T('key_item'), metadata = metadata,
            actions = {
                { id = prefix .. 'item:edit:' .. index, label = T('edit'), icon = 'Pencil', variant = 'primary' },
                { id = prefix .. 'item:remove:' .. index, label = T('remove'), icon = 'Trash2', variant = 'destructive' },
            },
        }
    end
    return cards
end

local function accessBlocks(door)
    local definition, prefix = door.definition, prefixOf(door)
    local groups, characters, items = groupCards(definition, prefix), characterCards(definition, prefix), itemCards(definition, prefix)
    local blocks = {
        {
            type = 'form', id = blockId('door-passcode', door.blockKey or door.id), title = T('access_title'),
            fields = { { id = 'passcode', label = T('passcode_label'), type = 'password', maxLength = 128, default = '',
                description = definition.hasPasscode and T('passcode_set_help') or T('passcode_unset') } },
            action = { id = prefix .. 'passcode', label = T('save') },
        },
        {
            type = 'actions',
            actions = { { id = prefix .. 'group:add', label = T('add_group'), icon = 'Plus', variant = 'primary' } },
        },
        {
            type = 'list', id = 'door-groups', layout = 'cards', columns = 3,
            title = T('groups_title', { count = #groups }), items = groups,
            empty = T('groups_empty'),
        },
        {
            type = 'actions',
            actions = { { id = prefix .. 'character:add', label = T('add_character'), icon = 'Plus', variant = 'primary' } },
        },
        {
            type = 'list', id = 'door-characters', layout = 'cards', columns = 3,
            title = T('characters_title', { count = #characters }), items = characters,
            empty = T('characters_empty'),
        },
        {
            type = 'actions',
            actions = { { id = prefix .. 'item:add', label = T('add_item'), icon = 'Plus', variant = 'primary' } },
        },
        {
            type = 'list', id = 'door-items', layout = 'cards', columns = 3,
            title = T('items_title', { count = #items }), items = items,
            empty = T('items_empty'),
        },
    }
    if definition.hasPasscode then
        table.insert(blocks, 2, {
            type = 'actions',
            actions = { { id = prefix .. 'passcode:clear', label = T('passcode_remove'), icon = 'Trash2', variant = 'destructive' } },
        })
    end
    return blocks
end

local function lockpickForm(door)
    local definition, prefix = door.definition, prefixOf(door)
    local list = type(definition.lockpickDifficulty) == 'table' and definition.lockpickDifficulty or {}
    local legacy = list.pinCount == nil and list.tolerance == nil and list.speed == nil and next(list) ~= nil
    return {
        type = 'form', id = blockId('door-lockpick', door.blockKey or door.id), title = T('lockpicking_title'),
        fields = {
            { id = 'lockpick', label = T('lockpick_can'), type = 'checkbox', default = definition.lockpick == true },
            { id = 'pinCount', label = T('lockpick_pins'), type = 'number', min = 1, max = 12, default = list.pinCount or 5,
                description = legacy and T('lockpick_legacy_help') or nil },
            { id = 'tolerance', label = T('lockpick_tolerance'), type = 'number', min = 0.03, max = 0.35, default = list.tolerance or 0.14,
                description = T('lockpick_tolerance_help') },
            { id = 'speed', label = T('lockpick_speed'), type = 'number', min = 0.3, max = 4, default = list.speed or 1,
                description = T('lockpick_speed_help') },
        },
        action = { id = prefix .. 'lockpick', label = T('save') },
    }
end

local function soundsForm(door)
    local definition, prefix = door.definition, prefixOf(door)
    return {
        type = 'form', id = blockId('door-sounds', door.blockKey or door.id), title = T('sounds_title'),
        fields = {
            { id = 'lockSound', label = T('sound_lock_name'), type = 'text', maxLength = 96, default = definition.lockSound or '',
                description = T('sound_help') },
            { id = 'lockSoundSet', label = T('sound_lock_set'), type = 'text', maxLength = 96, default = definition.lockSoundSet or '' },
            { id = 'unlockSound', label = T('sound_unlock_name'), type = 'text', maxLength = 96, default = definition.unlockSound or '' },
            { id = 'unlockSoundSet', label = T('sound_unlock_set'), type = 'text', maxLength = 96, default = definition.unlockSoundSet or '' },
        },
        action = { id = prefix .. 'sounds', label = T('save') },
    }
end

local function leafCards(definition)
    local cards = {}
    local leaves = leavesOf(definition)
    for index, leaf in ipairs(leaves) do
        cards[#cards + 1] = {
            id = tostring(index),
            label = #leaves == 2 and T('leaf_numbered', { index = index }) or T('leaf_single'),
            icon = 'MapPin',
            description = coordsLabel(leaf.coords),
            metadata = {
                { label = T('leaf_model'), value = tostring(leaf.model) },
                { label = T('leaf_heading'), value = leaf.heading and ('%.1f'):format(leaf.heading) or T('meta_unknown') },
            },
        }
    end
    return cards
end

local function linkBlocks(door)
    if door.linkedTo then
        local other = doorEntry(door.linkedTo)
        local actions = {}
        if other then actions[#actions + 1] = { id = 'door:select:' .. door.linkedTo, label = T('link_open'), icon = 'ExternalLink', variant = 'primary' } end
        actions[#actions + 1] = { id = 'door:unlink', label = T('unlink'), icon = 'Unlink', variant = 'destructive' }
        return { {
            type = 'list', id = 'door-link', layout = 'cards', columns = 3, title = T('meta_linked_door'),
            items = { {
                id = door.linkedTo, label = other and other.label or door.linkedTo, icon = 'Link',
                description = T('link_together'),
                actions = actions,
            } },
        } }
    end

    local options = {}
    for _, candidate in ipairs(doors) do
        if candidate.id ~= door.id and not candidate.linkedTo then options[#options + 1] = { value = candidate.id, label = candidate.label } end
    end
    if #options == 0 then
        return { { type = 'list', id = 'door-link', layout = 'cards', columns = 3, title = T('meta_linked_door'), items = {},
            empty = T('link_none_free') } }
    end
    return { {
        type = 'form', id = blockId('door-link', door.id), title = T('link_form_title'),
        fields = { { id = 'linkedDoorId', label = T('link_with'), type = 'select', required = true, options = options,
            description = T('link_help') } },
        action = { id = 'door:link', label = T('link') },
    } }
end

local function doorView()
    local door = doorEntry(selectedDoor)
    if not door then
        return {
            id = 'door', label = T('view_door'), icon = 'DoorOpen',
            content = { title = T('view_door'), blocks = { { type = 'empty', title = T('pick_door_first') } } },
        }
    end

    local blocks = {
        {
            type = 'actions',
            actions = {
                { id = 'door:toggle', label = door.locked and T('unlock') or T('lock'), icon = door.locked and 'Unlock' or 'Lock', variant = 'primary' },
                { id = 'door:teleport', label = T('teleport'), icon = 'MapPin', variant = 'secondary' },
            },
        },
        detailsForm(door),
    }
    if #categories > 0 then
        local options = { { value = 'none', label = T('category_none') } }
        for _, category in ipairs(categories) do options[#options + 1] = { value = category.id, label = category.label } end
        blocks[#blocks + 1] = {
            type = 'form', id = blockId('door-category', door.id), title = T('category'),
            fields = { { id = 'category', label = T('category'), type = 'select', options = options,
                default = door.definition.category or 'none',
                description = T('category_help') } },
            action = { id = 'door:category', label = T('save') },
        }
    end
    for _, block in ipairs(accessBlocks(door)) do blocks[#blocks + 1] = block end
    blocks[#blocks + 1] = lockpickForm(door)
    blocks[#blocks + 1] = soundsForm(door)

    local leaves = leafCards(door.definition)
    blocks[#blocks + 1] = {
        type = 'list', id = 'door-geometry', layout = 'cards', columns = 3,
        title = T('where_title', { count = #leaves }), items = leaves,
    }
    blocks[#blocks + 1] = {
        type = 'actions',
        actions = {
            { id = 'door:retarget:single', label = T('retarget_single'), icon = 'ScanSearch', variant = 'secondary' },
            { id = 'door:retarget:double', label = T('retarget_double'), icon = 'PanelsTopLeft', variant = 'secondary' },
        },
    }
    for _, block in ipairs(linkBlocks(door)) do blocks[#blocks + 1] = block end
    blocks[#blocks + 1] = {
        type = 'actions',
        actions = { { id = 'door:duplicate', label = T('duplicate'), icon = 'Copy', variant = 'primary' } },
    }
    blocks[#blocks + 1] = {
        type = 'actions', title = T('danger_zone'),
        actions = { { id = 'door:delete', label = T('delete_door'), variant = 'destructive' } },
    }

    return {
        id = 'door', label = door.label, icon = door.leaves == 2 and 'DoorOpen' or 'DoorClosed',
        content = {
            title = door.label,
            description = T('door_description', { state = stateText(door), id = door.id }),
            blocks = blocks,
        },
    }
end

-- A short description of what a category gives new doors.
local function defaultsText(defaults)
    local parts = { defaults.locked == false and T('defaults_unlocked') or T('defaults_locked') }
    local names = sortedKeys(defaults.groups)
    if #names > 0 then
        local groups = {}
        for _, name in ipairs(names) do groups[#groups + 1] = ('%s %d'):format(name, defaults.groups[name]) end
        parts[#parts + 1] = table.concat(groups, ', ')
    end
    if defaults.hasPasscode then parts[#parts + 1] = T('access_passcode') end
    if defaults.items then parts[#parts + 1] = T('defaults_key_items') end
    if defaults.characters then parts[#parts + 1] = T('access_characters') end
    if defaults.lockpick then parts[#parts + 1] = T('defaults_lockpickable') end
    return table.concat(parts, ' · ')
end

local function doorsOfCategory(category)
    local list = {}
    for _, door in ipairs(doors) do
        if door.definition.category == category.id then list[#list + 1] = door end
    end
    -- police-2 before police-10: by the number at the end of the id, then by name.
    local function number(door)
        return DoorlockSchema.categorySuffix(door.id, category.id) or math.huge
    end
    table.sort(list, function(a, b)
        local na, nb = number(a), number(b)
        if na ~= nb then return na < nb end
        return a.label:lower() < b.label:lower()
    end)
    return list
end

local function categoriesView()
    local rows = {}
    for _, category in ipairs(categories) do
        local count = #doorsOfCategory(category)
        rows[#rows + 1] = {
            id = category.id,
            label = category.label,
            icon = 'Building2',
            description = defaultsText(category.defaults),
            metadata = {
                { label = T('doors_label'), value = tostring(count) },
                { label = T('next_door'), value = (nextCategoryId(category)) },
            },
            action = 'cat:select:' .. category.id,
        }
    end

    return {
        id = 'categories', label = T('categories_label'), icon = 'Building2',
        content = {
            title = T('categories_label'),
            description = T('categories_description'),
            blocks = {
                {
                    type = 'actions',
                    actions = { { id = 'cat:new', label = T('category_new'), icon = 'Plus', variant = 'primary' } },
                },
                {
                    type = 'list', id = 'category-list', layout = 'cards', columns = 3,
                    title = T('categories_title', { count = #rows }), items = rows,
                    searchable = true, searchPlaceholder = T('search_categories'), pageSize = 12,
                    empty = T('categories_empty'),
                },
            },
        },
    }
end

local function categoryView()
    local category = categoryEntry(selectedCategory)
    if not category then
        return {
            id = 'category', label = T('category'), icon = 'Building2',
            content = { title = T('category'), blocks = { { type = 'empty', title = T('pick_category_first') } } },
        }
    end

    local rows = {}
    for _, door in ipairs(doorsOfCategory(category)) do
        local access = accessList(door.definition)
        rows[#rows + 1] = {
            id = door.id,
            label = door.label,
            description = stateText(door),
            icon = door.leaves == 2 and 'DoorOpen' or 'DoorClosed',
            tone = door.locked and 'warning' or 'success',
            metadata = {
                { label = T('meta_id'), value = door.id },
                { label = T('access_title'), value = #access > 0 and table.concat(access, ', ') or T('access_public') },
            },
            action = 'door:select:' .. door.id,
        }
    end

    local nextId = nextCategoryId(category)
    local blocks = {
        {
            type = 'list', id = 'category-doors', layout = 'cards', columns = 3,
            title = T('doors_in_category', { category = category.label, count = #rows }), items = rows,
            searchable = true, searchPlaceholder = T('search_these_doors'), pageSize = 12,
            empty = T('category_doors_empty', { id = nextId }),
        },
        {
            type = 'form', id = blockId('category-name', category.id), title = T('name_title'),
            fields = { { id = 'label', label = T('category_name'), type = 'text', required = true, maxLength = 64, default = category.label,
                description = T('category_name_help', { id = category.id }) } },
            action = { id = 'cat:rename', label = T('save') },
        },
    }

    local target = categoryTarget(category)
    blocks[#blocks + 1] = {
        type = 'list', id = 'category-defaults-note', layout = 'cards', columns = 1, title = T('defaults_title'),
        items = { {
            id = 'note', label = T('defaults_note_label'),
            icon = 'Copy', description = T('defaults_note_description'),
        } },
    }
    blocks[#blocks + 1] = detailsForm(target)
    for _, block in ipairs(accessBlocks(target)) do blocks[#blocks + 1] = block end
    blocks[#blocks + 1] = lockpickForm(target)
    blocks[#blocks + 1] = soundsForm(target)
    blocks[#blocks + 1] = {
        type = 'actions',
        actions = { { id = 'cat:place', label = T('place_doors'), icon = 'ScanSearch', variant = 'primary' } },
    }
    blocks[#blocks + 1] = {
        type = 'actions', title = T('danger_zone'),
        actions = { { id = 'cat:delete', label = T('delete_category'), variant = 'destructive' } },
    }

    return {
        id = 'category', label = category.label, icon = 'Building2',
        content = {
            title = category.label,
            description = T('category_summary', { count = #rows, id = nextId, defaults = defaultsText(category.defaults) }),
            blocks = blocks,
        },
    }
end

local function buildNavigation()
    local navigation = { doorsView(), categoriesView() }
    if selectedCategory and categoryEntry(selectedCategory) then navigation[#navigation + 1] = categoryView() end
    if selectedDoor and doorEntry(selectedDoor) then navigation[#navigation + 1] = doorView() end
    return navigation
end

local function refresh(message)
    local navigation = buildNavigation()
    Kora.nui.updateApp(APP_ID, { navigation = navigation })
    return { update = { navigation = navigation }, notice = message }
end

local function fail(message)
    return refresh(notice(message, 'destructive'))
end

local function setData(snapshot)
    snapshot = type(snapshot) == 'table' and snapshot or {}
    doors = type(snapshot.doors) == 'table' and snapshot.doors or {}
    categories = type(snapshot.categories) == 'table' and snapshot.categories or {}
    if selectedDoor and not doorEntry(selectedDoor) then
        selectedDoor = nil
        if currentView == 'door' then currentView = 'doors' end
    end
    if selectedCategory and not categoryEntry(selectedCategory) then
        selectedCategory = nil
        if currentView == 'category' then currentView = 'categories' end
    end
end

local function change(callback, ...)
    local result, err = DoorlockClient.trigger(callback, ...)
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

    local result, err
    if door.isCategory then
        result, err = change('qbdoorlock:server:managementCategoryDefaultsSaved', door.id, definition)
    else
        result, err = change('qbdoorlock:server:managementDoorSaved', door.id, definition, false)
    end
    if not result then return fail(err or T('save_failed')) end
    return refresh(notice(message or T('saved')))
end

local function askNewDoor(title, name, double)
    local result = Kora.nui.openInputDialog({
        { id = 'name', label = T('field_door_name'), type = 'text', required = true, maxLength = 96, default = name },
        { id = 'double', label = T('state_double'), type = 'checkbox', default = double == true },
    }, title, T('new_door_help'))
    if not result or result.cancelled then return nil end

    local label = optionalText(result.values and result.values.name)
    if not label then return nil end
    return { name = label, double = result.values.double == true }
end

local function askGroup(current)
    local fields = {}
    if not current then
        fields[#fields + 1] = { id = 'name', label = T('group_name'), type = 'text', required = true, maxLength = 64, placeholder = 'police' }
    end
    fields[#fields + 1] = { id = 'grade', label = T('min_grade'), type = 'number', min = 0, max = 1000, required = true,
        default = current and current.grade or 0 }

    local result = Kora.nui.openInputDialog(fields, current and T('edit_named', { name = current.name }) or T('add_group'),
        T('group_dialog_help'))
    if not result or result.cancelled then return nil end

    local values = result.values or {}
    local grade = tonumber(values.grade)
    local name = current and current.name or optionalText(values.name)
    if not grade or not name then return nil end
    return { name = name:lower(), grade = math.max(0, math.floor(grade)) }
end

local function askCharacter()
    local result = Kora.nui.openInputDialog({
        { id = 'character', label = T('character_id'), type = 'text', required = true, maxLength = 96 },
    }, T('add_character'), T('character_dialog_help'))
    if not result or result.cancelled then return nil end
    return optionalText(result.values and result.values.character)
end

local function askItem(current)
    local metadataType = current and type(current.metadata) == 'table' and current.metadata.type or nil
    local result = Kora.nui.openInputDialog({
        { id = 'name', label = T('item_name'), type = 'text', required = true, maxLength = 64, default = current and current.name or '' },
        { id = 'type', label = T('item_type'), type = 'text', maxLength = 128, default = metadataType and tostring(metadataType) or '',
            description = T('item_type_help') },
        {
            id = 'remove', label = T('item_remove'), type = 'select',
            default = current and current.remove and 'use' or 'keep',
            options = { { value = 'keep', label = T('item_keep') }, { value = 'use', label = T('item_use') } },
        },
    }, current and T('item_edit') or T('add_item'), T('item_dialog_help'))
    if not result or result.cancelled then return nil end

    local values = result.values or {}
    local name = optionalText(values.name)
    if not name then return nil end

    local metadata = current and type(current.metadata) == 'table' and copyValue(current.metadata) or {}
    metadata.type = optionalText(values.type)
    return { name = name:lower(), metadata = next(metadata) and metadata or nil, remove = values.remove == 'use' or nil }
end

local function detailsInput(definition, values, isCategory)
    local seconds = tonumber(values.autoLock) or 0
    if not isCategory then definition.label = text(values.label) end
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
-- Returns nil when it is cancelled, and at which door (`'first'` or `'second'`). `hint` replaces the on-screen
-- text; `quiet` skips the "cancelled" message (placing many doors ends by cancelling, so that is not an error).
local function captureGeometry(double, hint, quiet)
    local first = DoorlockClient.selectLeaf(nil, 'select_first', hint)
    if not first then
        if not quiet then DoorlockClient.notify(DoorlockClient.translate('selection_cancelled'), 'error') end
        return nil, 'first'
    end
    if not double then return leafOf(first) end

    local second = DoorlockClient.selectLeaf(first, 'select_second', hint and (hint .. ' · ' .. T('select_second')) or nil)
    if not second then
        if not quiet then DoorlockClient.notify(DoorlockClient.translate('selection_cancelled'), 'error') end
        return nil, 'second'
    end
    return { doors = { leafOf(first), leafOf(second) } }
end

-- Places doors in a category, in two stages, with the creator closed:
--   1. single doors, one after another. Each E saves a door (category-N) straight away. Backspace ends the stage.
--   2. a prompt for double doors. If accepted, two aims per door. Backspace at the first door ends the stage;
--      Backspace at the second door only drops that pair, so a wrong first door can be redone.
-- Afterwards the creator opens on the category, where every door can be changed on its own.
local function placeCategoryDoors(categoryId)
    local category = categoryEntry(categoryId)
    if not category then return end
    local placed = 0

    local function stage(double)
        while true do
            local current = categoryEntry(categoryId)
            if not current then return end
            local nextId = nextCategoryId(current)
            local hint = T('place_hint', { category = current.label, kind = double and T('kind_double') or T('kind_single'), id = nextId })

            local geometry, cancelledAt = captureGeometry(double, hint, true)
            if geometry then
                local result, err = DoorlockClient.trigger('qbdoorlock:server:managementCategoryDoorCreated', categoryId, geometry)
                if result then
                    setData(result.snapshot)
                    revision = revision + 1
                    placed = placed + 1
                    DoorlockClient.notify(T('placed_one', { label = result.label, id = result.id }), 'success')
                else
                    toast(err or T('creator_no_answer'))
                end
            elseif cancelledAt == 'second' then
                DoorlockClient.notify(T('pair_cancelled'), 'info')
            else
                return
            end
        end
    end

    stage(false)

    local answer = Kora.nui.openAlert({
        title = T('double_doors_title'),
        message = T('single_done', { category = category.label }),
        confirmLabel = T('place_double'),
    })
    if answer and answer.confirmed == true then stage(true) end

    selectedCategory, currentView = categoryId, 'category'
    revision = revision + 1
    DoorlockClient.notify(T('placed_total', { count = placed, category = category.label }), placed > 0 and 'success' or 'info')
end

local function runTool(tool)
    if tool.kind == 'category' then return placeCategoryDoors(tool.id) end

    local geometry = captureGeometry(tool.double)
    if not geometry then return end

    if tool.kind == 'retarget' then
        local door = doorEntry(tool.id)
        if not door then return end

        local definition = copyValue(door.definition)
        applyGeometry(definition, geometry)
        local result, err = change('qbdoorlock:server:managementDoorSaved', door.id, definition, false)
        if not result then return toast(err or T('creator_no_answer')) end
        return DoorlockClient.notify(DoorlockClient.translate('door_retargeted'), 'success')
    end

    local definition = tool.template and copyValue(tool.template)
        or { locked = true, lockpick = false, distance = Config.InteractionDistance }
    definition.label = tool.name
    applyGeometry(definition, geometry)

    local result, err = DoorlockClient.trigger('qbdoorlock:server:managementDoorCreated', definition, tool.sourceDoorId)
    if not result then return toast(err or T('creator_no_answer')) end

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
        end, T('added_named', { name = group.name }))
    end

    local editName = actionId:match('^door:group:edit:(.+)$')
    if editName then
        local grade = door.definition.groups and door.definition.groups[editName]
        if not grade then return refresh() end

        local group = askGroup({ name = editName, grade = grade })
        if not group then return refresh() end
        return edit(door, function(definition) definition.groups[editName] = group.grade end,
            T('group_grade', { name = editName, grade = group.grade }))
    end

    local removeName = actionId:match('^door:group:remove:(.+)$')
    if removeName then
        return edit(door, function(definition)
            if definition.groups then definition.groups[removeName] = nil end
            if definition.groups and not next(definition.groups) then definition.groups = nil end
        end, T('removed_named', { name = removeName }))
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
                if existing == character then return T('character_exists') end
            end
            definition.characters[#definition.characters + 1] = character
        end, T('character_added'))
    end

    local removeId = actionId:match('^door:character:remove:(.+)$')
    if removeId then
        return edit(door, function(definition)
            local kept = {}
            for _, existing in ipairs(definition.characters or {}) do
                if existing ~= removeId then kept[#kept + 1] = existing end
            end
            definition.characters = #kept > 0 and kept or nil
        end, T('character_removed'))
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
        end, T('added_named', { name = item.name }))
    end

    local editIndex = tonumber(actionId:match('^door:item:edit:(%d+)$'))
    if editIndex then
        local current = door.definition.items and door.definition.items[editIndex]
        if not current then return refresh() end

        local item = askItem(current)
        if not item then return refresh() end
        return edit(door, function(definition) definition.items[editIndex] = item end, T('saved_named', { name = item.name }))
    end

    local removeIndex = tonumber(actionId:match('^door:item:remove:(%d+)$'))
    if removeIndex then
        return edit(door, function(definition)
            local kept = removedAt(definition.items, removeIndex)
            definition.items = #kept > 0 and kept or nil
        end, T('item_removed'))
    end

    return refresh()
end

local function doorAction(actionId, values, target)
    if actionId == 'door:new' then
        local new = askNewDoor(T('new_door_title'), '', false)
        if not new then return refresh() end
        pendingTool = { kind = 'create', name = new.name, double = new.double }
        return { close = true }
    end

    if actionId == 'door:refresh' then
        local result, err = change('qbdoorlock:server:managementSnapshotRequested')
        if not result then return fail(err or T('refresh_failed')) end
        return refresh(notice(T('refreshed')))
    end

    if actionId == 'door:closest' then
        closestFirst = not closestFirst
        return refresh(notice(closestFirst and T('sorted_distance') or T('sorted_name')))
    end

    local selectId = actionId:match('^door:select:(.+)$')
    if selectId then
        if not doorEntry(selectId) then return fail(T('unknown_door')) end
        return openDoor(selectId)
    end

    local door = target or doorEntry(selectedDoor)
    if not door then return fail(T('pick_door_first')) end

    if actionId == 'door:toggle' then
        local result, err = change('qbdoorlock:server:managementStateSet', door.id, not door.locked)
        if not result then return fail(err or T('change_failed')) end
        return refresh(notice(door.locked and T('unlocked') or T('locked')))
    end

    if actionId == 'door:teleport' then
        Kora.events.trigger('qbdoorlock:server:teleportRequested', door.id)
        return { close = true }
    end

    if actionId == 'door:details' then
        return edit(door, function(definition) detailsInput(definition, values, door.isCategory) end)
    end

    if actionId == 'door:category' then
        local value = optionalText(values.category)
        return edit(door, function(definition) definition.category = value ~= 'none' and value or nil end,
            value ~= 'none' and T('category_saved') or T('category_removed_from'))
    end

    if actionId == 'door:passcode' then
        return edit(door, function(definition) definition.passcode = optionalText(values.passcode) end)
    end

    if actionId == 'door:passcode:clear' then
        return edit(door, function(definition) definition.clearPasscode = true end, T('passcode_removed'))
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
        if type(linkedId) ~= 'string' or linkedId == '' then return fail(T('pick_link_door')) end
        local result, err = change('qbdoorlock:server:managementDoorsLinked', door.id, linkedId)
        if not result then return fail(err or T('link_failed')) end
        return refresh(notice(T('doors_linked')))
    end

    if actionId == 'door:unlink' then
        local result, err = change('qbdoorlock:server:managementDoorsUnlinked', door.id)
        if not result then return fail(err or T('unlink_failed')) end
        return refresh(notice(T('doors_unlinked')))
    end

    if actionId == 'door:duplicate' then
        local new = askNewDoor(T('duplicate_title'), T('door_copy_name', { name = door.label }), door.leaves == 2)
        if not new then return refresh() end
        pendingTool = { kind = 'create', name = new.name, double = new.double, template = door.definition, sourceDoorId = door.id }
        return { close = true }
    end

    if actionId == 'door:delete' then
        if not confirmed(T('delete_door_title'), T('delete_door_body', { name = door.label })) then
            return refresh()
        end
        local result, err = change('qbdoorlock:server:managementDoorDeleted', door.id)
        if not result then return fail(err or T('delete_failed')) end
        selectedDoor, currentView = nil, 'doors'
        return refresh(notice(T('door_deleted')))
    end

    return refresh()
end

local function openCategory(id, message)
    selectedCategory = id
    revision = revision + 1
    currentView = 'category'
    return refresh(message)
end

local function askCategoryName()
    local result = Kora.nui.openInputDialog({
        { id = 'name', label = T('category_name'), type = 'text', required = true, maxLength = 64 },
    }, T('category_new_title'), T('category_new_help'))
    if not result or result.cancelled then return nil end
    return optionalText(result.values and result.values.name)
end

local function categoryAction(actionId, values)
    if actionId == 'cat:new' then
        local name = askCategoryName()
        if not name then return refresh() end
        local result, err = DoorlockClient.trigger('qbdoorlock:server:managementCategoryCreated', name)
        if not result then return fail(err or T('creator_no_answer')) end
        setData(result.snapshot)
        return openCategory(result.id, notice(T('category_created')))
    end

    local selectId = actionId:match('^cat:select:(.+)$')
    if selectId then
        if not categoryEntry(selectId) then return fail(T('unknown_category')) end
        return openCategory(selectId)
    end

    local category = categoryEntry(selectedCategory)
    if not category then return fail(T('pick_category_first')) end

    if actionId == 'cat:place' then
        pendingTool = { kind = 'category', id = category.id }
        return { close = true }
    end

    if actionId == 'cat:rename' then
        local result, err = change('qbdoorlock:server:managementCategoryRenamed', category.id, text(values.label))
        if not result then return fail(err or T('rename_failed')) end
        return refresh(notice(T('saved')))
    end

    if actionId == 'cat:delete' then
        if not confirmed(T('delete_category_title'), T('delete_category_body', { name = category.label })) then
            return refresh()
        end
        local result, err = change('qbdoorlock:server:managementCategoryDeleted', category.id)
        if not result then return fail(err or T('delete_category_failed')) end
        selectedCategory, currentView = nil, 'categories'
        return refresh(notice(T('category_deleted')))
    end

    return refresh()
end

-- Only the actions that edit settings are shared with a category's defaults.
local DEFAULTS_ACTIONS = {
    '^door:details$', '^door:passcode$', '^door:passcode:clear$', '^door:group:', '^door:character:', '^door:item:', '^door:lockpick$', '^door:sounds$',
}

local function defaultsAction(actionId, values)
    local category = categoryEntry(selectedCategory)
    if not category then return fail(T('pick_category_first')) end
    for _, pattern in ipairs(DEFAULTS_ACTIONS) do
        if actionId:match(pattern) then return doorAction(actionId, values, categoryTarget(category)) end
    end
    return refresh()
end

local function onAction(actionId, context)
    local values = context and type(context.value) == 'table' and context.value or {}
    if actionId:match('^cat:') then return categoryAction(actionId, values) end
    if actionId:match('^cd:') then return defaultsAction('door:' .. actionId:sub(4), values) end
    if actionId:match('^door:') then return doorAction(actionId, values) end
    return refresh()
end

Kora.nui.registerApp({
    id = APP_ID,
    title = T('creator_title'),
    icon = 'LockKeyhole',
    layout = 'standard',
    width = 1200,
    height = 800,
    defaultView = 'doors',
    navigation = { { id = 'doors', label = T('doors_label'), icon = 'DoorOpen', content = { title = T('doors_label'), blocks = {} } } },
    onAction = onAction,
})

---@param options? { closestFirst?: boolean, create?: boolean }
local function open(options)
    options = options or {}
    local result, err = DoorlockClient.trigger('qbdoorlock:server:managementSnapshotRequested')
    if not result then
        toast(err or T('admin_required'))
        return
    end

    setData(result)
    if options.closestFirst ~= nil then closestFirst = options.closestFirst end

    if options.create then
        local new = askNewDoor(T('new_door_title'), '', false)
        if not new then return end
        pendingTool = { kind = 'create', name = new.name, double = new.double }
    end

    while true do
        if pendingTool then
            local tool = pendingTool
            pendingTool = nil
            runTool(tool)
        end

        Kora.nui.updateApp(APP_ID, { navigation = buildNavigation() })
        Kora.nui.openApp(APP_ID, { viewId = currentView })
        if not pendingTool then break end
    end
end

Kora.events.onPush('qbdoorlock:client:managementOpened', function(closest)
    CreateThread(function() open({ closestFirst = closest == true }) end)
end)

Kora.events.onPush('qbdoorlock:client:targetedCreationRequested', function()
    CreateThread(function() open({ create = true }) end)
end)
