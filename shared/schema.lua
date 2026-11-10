DoorlockSchema = DoorlockSchema or {}

local function finiteNumber(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function trimmed(value, maxLength)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('^%s*(.-)%s*$', '%1')
    if value == '' or #value > maxLength then return nil end
    return value
end

local function copyCoords(value)
    if type(value) ~= 'table' and type(value) ~= 'vector3' then return nil end
    local x, y, z = finiteNumber(value.x), finiteNumber(value.y), finiteNumber(value.z)
    if not x or not y or not z then return nil end
    return vector3(x, y, z)
end

local function denseValues(value, limit)
    if type(value) ~= 'table' then return nil end
    local count = 0
    for key in pairs(value) do
        count = count + 1
        if count > limit or type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return nil end
    end
    for index = 1, count do if rawget(value, index) == nil then return nil end end
    return count
end

local function normalizeLeaf(value)
    if type(value) ~= 'table' then return nil, 'Each door leaf must be a table.' end
    local model = finiteNumber(value.model)
    local coords = copyCoords(value.coords)
    if not model or model == 0 or not coords then return nil, 'Each door leaf needs a valid model and coordinates.' end
    local heading = finiteNumber(value.heading)
    return { model = math.floor(model), coords = coords, heading = heading }
end

local function normalizeGroups(value)
    if value == nil then return nil end
    if type(value) ~= 'table' then return nil, 'Door groups must be a name-to-grade table.' end
    local groups, count = {}, 0
    for name, grade in pairs(value) do
        count = count + 1
        if count > 32 then return nil, 'A door cannot have more than 32 groups.' end
        name = trimmed(name, 64)
        grade = finiteNumber(grade)
        if not name or not grade or grade < 0 then return nil, 'Door groups need valid names and non-negative grades.' end
        groups[name:lower()] = math.floor(grade)
    end
    return next(groups) and groups or nil
end

local function normalizeCharacters(value)
    if value == nil then return nil end
    if type(value) ~= 'table' then return nil, 'Door characters must be an array or set.' end
    local characters, seen, count = {}, {}, 0
    for key, entry in pairs(value) do
        local character = type(key) == 'string' and entry == true and key or entry
        if type(character) ~= 'string' and type(character) ~= 'number' then
            return nil, 'Character IDs must be text or numbers.'
        end
        character = tostring(character)
        if character == '' or #character > 96 then return nil, 'Character IDs must be 1-96 characters.' end
        if not seen[character] then
            count = count + 1
            if count > 64 then return nil, 'A door cannot have more than 64 character IDs.' end
            characters[count], seen[character] = character, true
        end
    end
    return #characters > 0 and characters or nil
end

local function normalizeMetadata(value)
    if value == nil then return nil end
    if type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean' then
        return { type = value }
    end
    if type(value) ~= 'table' then return nil end
    local result, count = {}, 0
    for key, entry in pairs(value) do
        count = count + 1
        if count > 16 or type(key) ~= 'string' or #key > 64 then return nil end
        local kind = type(entry)
        if kind ~= 'string' and kind ~= 'number' and kind ~= 'boolean' then return nil end
        if kind == 'string' and #entry > 128 then return nil end
        result[key] = entry
    end
    return result
end

local function normalizeItems(value)
    if value == nil then return nil end
    if type(value) == 'string' then value = { value } end
    local count = denseValues(value, 32)
    if not count then return nil, 'Door items must be a dense array with at most 32 entries.' end
    local items = {}
    for index = 1, count do
        local raw = value[index]
        local name = trimmed(type(raw) == 'table' and raw.name or raw, 64)
        if not name then return nil, 'Each door item needs a valid name.' end
        local metadata = type(raw) == 'table' and normalizeMetadata(raw.metadata or raw.type) or nil
        if type(raw) == 'table' and (raw.metadata ~= nil or raw.type ~= nil) and not metadata then
            return nil, ('Door item %s has invalid metadata.'):format(name)
        end
        items[index] = { name = name:lower(), metadata = metadata, remove = type(raw) == 'table' and raw.remove == true or nil }
    end
    return #items > 0 and items or nil
end

local function normalizeDifficulty(value)
    if value == nil then return nil end
    if type(value) == 'string' then value = { value } end
    if type(value) ~= 'table' then return nil, 'Lockpick difficulty must be a table or difficulty name.' end

    if value.pinCount or value.tolerance or value.speed or value.timeLimit or value.attempts then
        local result = {
            pinCount = finiteNumber(value.pinCount), tolerance = finiteNumber(value.tolerance),
            speed = finiteNumber(value.speed), timeLimit = finiteNumber(value.timeLimit), attempts = finiteNumber(value.attempts),
        }
        if result.pinCount then result.pinCount = math.floor(result.pinCount) end
        if result.attempts then result.attempts = math.floor(result.attempts) end
        if result.pinCount and (result.pinCount < 1 or result.pinCount > 12) then return nil, 'Lockpick pinCount must be between 1 and 12.' end
        if result.tolerance and (result.tolerance < 0.03 or result.tolerance > 0.35) then return nil, 'Lockpick tolerance must be between 0.03 and 0.35.' end
        if result.speed and (result.speed < 0.3 or result.speed > 4) then return nil, 'Lockpick speed must be between 0.3 and 4.' end
        if result.timeLimit and (result.timeLimit < 2000 or result.timeLimit > 60000) then return nil, 'Lockpick timeLimit must be between 2000 and 60000ms.' end
        if result.attempts and (result.attempts < 1 or result.attempts > 10) then return nil, 'Lockpick attempts must be between 1 and 10.' end
        return result
    end

    local count = denseValues(value, 12)
    if not count then return nil, 'Lockpick difficulty must contain at most 12 dense entries.' end
    local result = {}
    for index = 1, count do
        local entry = value[index]
        if type(entry) == 'string' then
            entry = entry:lower()
            if entry ~= 'easy' and entry ~= 'medium' and entry ~= 'hard' then return nil, 'Unknown lockpick difficulty.' end
            result[index] = entry
        elseif type(entry) == 'table' then
            local areaSize, speedMultiplier = finiteNumber(entry.areaSize), finiteNumber(entry.speedMultiplier)
            if not areaSize or not speedMultiplier then return nil, 'Custom lockpick difficulty needs areaSize and speedMultiplier.' end
            if areaSize <= 0 or speedMultiplier <= 0 then return nil, 'Custom lockpick difficulty values must be positive.' end
            result[index] = { areaSize = areaSize, speedMultiplier = speedMultiplier }
        else
            return nil, 'Invalid lockpick difficulty entry.'
        end
    end
    return #result > 0 and result or nil
end

---@param raw table
---@param fallbackDistance? number
---@return KoraDoorlockDefinition? definition
---@return string? error
function DoorlockSchema.normalize(raw, fallbackDistance)
    if type(raw) ~= 'table' then return nil, 'Door definition must be a table.' end
    local label = trimmed(raw.label or raw.name, 96)
    if not label then return nil, 'Door label must be 1-96 characters.' end

    local result = { label = label }
    if raw.doors ~= nil then
        local count = denseValues(raw.doors, 2)
        if count ~= 2 then return nil, 'Double doors need exactly two door leaves.' end
        result.doors = {}
        for index = 1, 2 do
            local leaf, err = normalizeLeaf(raw.doors[index])
            if not leaf then return nil, err end
            result.doors[index] = leaf
        end
        local a, b = result.doors[1].coords, result.doors[2].coords
        result.coords = vector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
    else
        local leaf, err = normalizeLeaf(raw)
        if not leaf then return nil, err end
        result.model, result.coords, result.heading = leaf.model, leaf.coords, leaf.heading
    end

    local groups, groupsErr = normalizeGroups(raw.groups)
    if groupsErr then return nil, groupsErr end
    local characters, charactersErr = normalizeCharacters(raw.characters or raw.citizenIds)
    if charactersErr then return nil, charactersErr end
    local items, itemsErr = normalizeItems(raw.items)
    if itemsErr then return nil, itemsErr end
    local difficulty, difficultyErr = normalizeDifficulty(raw.lockpickDifficulty)
    if difficultyErr then return nil, difficultyErr end

    local distance = finiteNumber(raw.distance or raw.maxDistance) or fallbackDistance or 1.8
    if distance < 0.5 or distance > 20 then return nil, 'Door interaction distance must be between 0.5 and 20 metres.' end
    local autoLock = finiteNumber(raw.autoLock)
    if not autoLock and raw.autolock ~= nil then
        local seconds = finiteNumber(raw.autolock)
        autoLock = seconds and seconds * 1000 or nil
    end
    if autoLock and (autoLock < 0 or autoLock > 86400000) then return nil, 'Door auto-lock must be between 0 and 24 hours.' end
    local doorRate = finiteNumber(raw.doorRate)
    if doorRate and (doorRate < 0 or doorRate > 10) then return nil, 'Door rate must be between 0 and 10.' end
    local passcode = raw.passcode == '' and nil or trimmed(raw.passcode, 128)
    if raw.passcode ~= nil and raw.passcode ~= '' and not passcode then return nil, 'Passcode must be at most 128 characters.' end

    if raw.locked ~= nil then
        result.locked = raw.locked == true or raw.locked == 1
    elseif raw.state ~= nil then
        result.locked = raw.state == true or raw.state == 1
    else
        result.locked = true
    end
    -- A category only organises doors in the creator: it never affects who can open one.
    local category = raw.category
    if category ~= nil then
        category = trimmed(category, 48)
        if not category or not category:match('^[a-z0-9][a-z0-9-]*$') then return nil, 'Door category is not a valid category ID.' end
    end
    result.category = category

    result.distance = distance
    result.groups, result.characters, result.items = groups, characters, items
    result.passcode, result.autoLock = passcode, autoLock and math.floor(autoLock) or nil
    result.automatic = raw.automatic == true or raw.auto == true
    result.doorRate = doorRate
    result.holdOpen, result.hideUi, result.lockpick = raw.holdOpen == true, raw.hideUi == true, raw.lockpick == true
    result.lockpickDifficulty = difficulty
    result.lockSound = trimmed(raw.lockSound, 96)
    result.unlockSound = trimmed(raw.unlockSound, 96)
    result.lockSoundSet = trimmed(raw.lockSoundSet, 96)
    result.unlockSoundSet = trimmed(raw.unlockSoundSet, 96)
    result.policyOwner = trimmed(raw.policyOwner, 64)
    return result
end

-- The settings a category gives every new door: a normal definition without a name, a place or a category.
-- It goes through the same checks as a door, by borrowing a throwaway leaf.
---@param raw table
---@param fallbackDistance? number
---@return table? defaults
---@return string? error
function DoorlockSchema.normalizeTemplate(raw, fallbackDistance)
    if type(raw) ~= 'table' then return nil, 'Category defaults must be a table.' end
    local probe = {}
    for key, value in pairs(raw) do probe[key] = value end
    probe.doors, probe.heading, probe.category = nil, nil, nil
    probe.label, probe.model, probe.coords = 'template', 1, { x = 0.0, y = 0.0, z = 0.0 }

    local defaults, err = DoorlockSchema.normalize(probe, fallbackDistance)
    if not defaults then return nil, err end
    defaults.label, defaults.model, defaults.coords, defaults.heading, defaults.doors, defaults.category = nil, nil, nil, nil, nil, nil
    return defaults
end

---A multi-leaf door's `doors` list, or a single-leaf door's own
---model/coords/heading wrapped as a one-entry list -- the shape every caller
---that walks a door's leaves actually needs.
function DoorlockSchema.leaves(door)
    return door.doors or { { model = door.model, coords = door.coords, heading = door.heading } }
end

---The numeric suffix of `id` if it matches `categoryId .. '-<number>'`
---exactly (e.g. "police-12" under category "police" -> 12), or nil otherwise.
function DoorlockSchema.categorySuffix(id, categoryId)
    local prefix = categoryId .. '-'
    if id:sub(1, #prefix) ~= prefix then return nil end
    local number = id:sub(#prefix + 1):match('^%d+$')
    return number and tonumber(number) or nil
end

---Highest DoorlockSchema.categorySuffix found across `ids` (a list of id
---strings) for `categoryId`, or 0 if none match.
function DoorlockSchema.highestCategorySuffix(ids, categoryId)
    local highest = 0
    for _, id in ipairs(ids) do
        local number = DoorlockSchema.categorySuffix(id, categoryId)
        if number and number > highest then highest = number end
    end
    return highest
end

function DoorlockSchema.copyCoords(coords)
    return { x = coords.x, y = coords.y, z = coords.z }
end

function DoorlockSchema.forNetwork(door)
    local result = {}
    for key, value in pairs(door) do result[key] = value end
    result.coords = DoorlockSchema.copyCoords(door.coords)
    if door.doors then
        result.doors = {}
        for index, leaf in ipairs(door.doors) do
            result.doors[index] = {
                model = leaf.model, coords = DoorlockSchema.copyCoords(leaf.coords), heading = leaf.heading,
            }
        end
        result.model, result.heading = nil, nil
    end
    return result
end
