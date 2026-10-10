-- Drives client/creator.lua against stubbed qblib calls: it checks the pages the
-- creator builds and the exact definitions it sends to the server.
local Harness = dofile('test/harness.lua')

Config = { InteractionDistance = 1.8 }

local app, pushHandlers, calls, dialogs, alerts, notifications = nil, {}, {}, {}, {}, {}
local snapshot, nextCallback = {}, {}
local selections = {}

local function door(id, label, definition, extra)
    definition.label = label
    local result = { id = id, label = label, locked = definition.locked ~= false, leaves = definition.doors and 2 or 1, definition = definition }
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

snapshot = {
    door('lobby', 'Lobby', {
        model = 1, coords = { x = 1, y = 2, z = 3 }, heading = 90, locked = true, distance = 2, autoLock = 5000,
        groups = { police = 2 }, characters = { 'ABC123' },
        items = { { name = 'keycard', metadata = { type = 'staff' }, remove = true } },
        lockpick = true, lockpickDifficulty = { pinCount = 6, tolerance = 0.2, speed = 1.5, attempts = 2, timeLimit = 20000 },
    }, { autoLock = 5000 }),
    door('vault', 'Vault', { model = 2, coords = { x = 9, y = 9, z = 9 }, locked = false }),
    door('front', 'Front', {
        doors = { { model = 3, coords = { x = 0, y = 0, z = 0 }, heading = 0 }, { model = 3, coords = { x = 2, y = 0, z = 0 }, heading = 180 } },
        locked = true,
    }),
}

QB = {
    nui = {
        registerApp = function(definition) app = definition end,
        updateApp = function() end,
        openApp = function() return true end,
        openInputDialog = function(fields, title)
            local queued = table.remove(dialogs, 1)
            Harness.ok(queued, 'unexpected dialog: ' .. tostring(title))
            return queued(fields, title)
        end,
        openAlert = function() return table.remove(alerts, 1) end,
    },
    callback = {
        trigger = function(name, ...)
            calls[#calls + 1] = { name = name, args = { ... } }
            local handler = table.remove(nextCallback, 1)
            if handler then return handler(...) end
            if name == 'qbdoorlock:server:managementDoorCreated' then return { doors = snapshot, id = snapshot[1].id } end
            return snapshot
        end,
    },
    events = {
        onPush = function(name, handler) pushHandlers[name] = handler end,
        trigger = function(name, ...) calls[#calls + 1] = { name = name, args = { ... } } end,
    },
    notify = { send = function(options) notifications[#notifications + 1] = options end },
    cache = { coords = function() return { x = 0, y = 0, z = 0 } end },
}

DoorlockClient = {
    notify = function(message, kind) notifications[#notifications + 1] = { message = message, type = kind } end,
    translate = function(key) return key end,
    distanceTo = function(id) return ({ lobby = 30, vault = 5, front = 12 })[id] or math.huge end,
    selectLeaf = function() return table.remove(selections, 1) end,
}
function CreateThread(callback) callback() end

dofile('client/creator.lua')

local function reply(values) return function() return { values = values } end end
local function lastCall() return calls[#calls] end

local function action(id, value)
    return app.onAction(id, { value = value })
end

local function navigation(result) return result.update.navigation end

local function findBlock(view, id)
    for _, block in ipairs(view.content.blocks) do
        if block.id == id then return block end
    end
end

local function findField(form, id)
    for _, field in ipairs(form.fields) do
        if field.id == id then return field end
    end
end

local function formFor(view, prefix)
    for _, block in ipairs(view.content.blocks) do
        if block.type == 'form' and block.id:find(prefix, 1, true) == 1 then return block end
    end
end

Harness.test('registers one app and the open handlers', function()
    Harness.equal(app.id, 'qbdoorlock:creator')
    Harness.ok(pushHandlers['qbdoorlock:client:managementOpened'])
    Harness.ok(pushHandlers['qbdoorlock:client:targetedCreationRequested'])
end)

Harness.test('the doors page lists every door as a card and can sort by distance', function()
    local result = action('door:refresh')
    local view = navigation(result)[1]
    Harness.equal(view.id, 'doors')
    local list = findBlock(view, 'door-list')
    Harness.equal(#list.items, 3)
    Harness.equal(list.items[1].action, 'door:select:lobby')
    Harness.equal(list.items[3].description, 'Locked · Double door · Public')

    result = action('door:closest')
    list = findBlock(navigation(result)[1], 'door-list')
    Harness.equal(list.items[1].id, 'vault')
    Harness.equal(list.items[2].id, 'front')
    action('door:closest')
end)

Harness.test('selecting a door adds its own page with forms and cards', function()
    local result = action('door:select:lobby')
    local nav = navigation(result)
    Harness.equal(#nav, 2)
    local view = nav[2]
    Harness.equal(view.id, 'door')
    Harness.equal(view.label, 'Lobby')

    local details = formFor(view, 'door-details')
    Harness.equal(findField(details, 'autoLock').default, 5)
    Harness.equal(findField(details, 'distance').default, 2)
    Harness.equal(findField(formFor(view, 'door-lockpick'), 'pinCount').default, 6)
    Harness.equal(findBlock(view, 'door-groups').items[1].label, 'police')
    Harness.equal(findBlock(view, 'door-characters').items[1].label, 'ABC123')
    Harness.equal(findBlock(view, 'door-items').items[1].metadata[1].value, 'type=staff')
    Harness.equal(#findBlock(view, 'door-geometry').items, 1)
    local link = formFor(view, 'door-link')
    Harness.equal(#findField(link, 'linkedDoorId').options, 2)
end)

Harness.test('saving details sends only that part changed', function()
    calls = {}
    local result = action('door:details', {
        label = ' Main Lobby ', distance = '3', autoLock = '0', doorRate = '', automatic = true, holdOpen = false, hideUi = true,
    })
    Harness.equal(result.notice.message, 'Saved.')
    local call = lastCall()
    Harness.equal(call.name, 'qbdoorlock:server:managementDoorSaved')
    Harness.equal(call.args[1], 'lobby')
    Harness.equal(call.args[3], false)
    local definition = call.args[2]
    Harness.equal(definition.label, 'Main Lobby')
    Harness.equal(definition.distance, 3)
    Harness.equal(definition.autoLock, nil)
    Harness.equal(definition.automatic, true)
    Harness.equal(definition.hideUi, true)
    Harness.equal(definition.groups.police, 2, 'untouched settings stay')
    Harness.equal(definition.model, 1)
    Harness.equal(snapshot[1].definition.label, 'Lobby', 'the snapshot itself is not mutated')
end)

Harness.test('a server refusal is shown instead of lost', function()
    nextCallback = { function() return nil, 'Door auto-lock must be between 0 and 24 hours.' end }
    local result = action('door:details', { label = 'Lobby', distance = '2', autoLock = '99999999' })
    Harness.equal(result.notice.tone, 'destructive')
    Harness.equal(result.notice.message, 'Door auto-lock must be between 0 and 24 hours.')
end)

Harness.test('groups, characters and key items are added, edited and removed through dialogs', function()
    calls = {}
    dialogs = { reply({ name = ' Ambulance ', grade = '3' }) }
    action('door:group:add')
    Harness.equal(lastCall().args[2].groups.ambulance, 3)
    Harness.equal(lastCall().args[2].groups.police, 2)

    dialogs = { reply({ grade = '0' }) }
    action('door:group:edit:police')
    Harness.equal(lastCall().args[2].groups.police, 0)

    action('door:group:remove:police')
    Harness.equal(lastCall().args[2].groups, nil)

    dialogs = { reply({ character = 'XYZ789' }) }
    action('door:character:add')
    Harness.equal(lastCall().args[2].characters[2], 'XYZ789')
    action('door:character:remove:ABC123')
    Harness.equal(lastCall().args[2].characters, nil)

    dialogs = { reply({ name = 'Master Key', type = '', remove = 'keep' }) }
    action('door:item:add')
    local items = lastCall().args[2].items
    Harness.equal(#items, 2)
    Harness.equal(items[2].name, 'master key')
    Harness.equal(items[2].metadata, nil)
    Harness.equal(items[2].remove, nil)

    dialogs = { reply({ name = 'keycard', type = 'vip', remove = 'use' }) }
    action('door:item:edit:1')
    items = lastCall().args[2].items
    Harness.equal(items[1].metadata.type, 'vip')
    Harness.equal(items[1].remove, true)

    action('door:item:remove:1')
    Harness.equal(lastCall().args[2].items, nil)

    local before = #calls
    dialogs = { function() return { cancelled = true } end }
    action('door:group:add')
    Harness.equal(#calls, before, 'a cancelled dialog saves nothing')
end)

Harness.test('lockpick and passcode forms keep the other difficulty settings', function()
    calls = {}
    action('door:lockpick', { lockpick = false, pinCount = '8', tolerance = '0.1', speed = '2' })
    local definition = lastCall().args[2]
    Harness.equal(definition.lockpick, false)
    Harness.equal(definition.lockpickDifficulty.pinCount, 8)
    Harness.equal(definition.lockpickDifficulty.attempts, 2)
    Harness.equal(definition.lockpickDifficulty.timeLimit, 20000)

    action('door:passcode', { passcode = '  ' })
    Harness.equal(lastCall().args[2].passcode, nil)
    action('door:passcode', { passcode = 'open sesame' })
    Harness.equal(lastCall().args[2].passcode, 'open sesame')

    action('door:sounds', { lockSound = 'Click', lockSoundSet = 'Set', unlockSound = '', unlockSoundSet = '' })
    Harness.equal(lastCall().args[2].lockSound, 'Click')
    Harness.equal(lastCall().args[2].unlockSound, nil)
end)

Harness.test('lock, link, unlink and delete use the management callbacks', function()
    calls = {}
    action('door:toggle')
    Harness.equal(lastCall().name, 'qbdoorlock:server:managementStateSet')
    Harness.equal(lastCall().args[2], false)

    action('door:link', { linkedDoorId = 'vault' })
    Harness.equal(lastCall().name, 'qbdoorlock:server:managementDoorsLinked')
    Harness.equal(lastCall().args[2], 'vault')
    local refused = action('door:link', {})
    Harness.equal(refused.notice.tone, 'destructive')

    action('door:unlink')
    Harness.equal(lastCall().name, 'qbdoorlock:server:managementDoorsUnlinked')

    alerts = { { confirmed = false } }
    local before = #calls
    action('door:delete')
    Harness.equal(#calls, before, 'declining the alert deletes nothing')

    alerts = { { confirmed = true } }
    nextCallback = { function() return { snapshot[2], snapshot[3] } end }
    local result = action('door:delete')
    Harness.equal(lastCall().name, 'qbdoorlock:server:managementDoorDeleted')
    Harness.equal(#navigation(result), 1, 'the deleted door page is gone')
    action('door:refresh') -- the stub snapshot still has all three doors
end)

Harness.test('a linked door shows its partner and an unlink card', function()
    snapshot[1].linkedTo = 'vault'
    action('door:select:lobby')
    local view = navigation(action('door:refresh'))[2]
    local cards = findBlock(view, 'door-link').items
    Harness.equal(cards[1].label, 'Vault')
    Harness.equal(#cards[1].actions, 2)
    Harness.equal(cards[1].actions[2].id, 'door:unlink')
    snapshot[1].linkedTo = nil
end)

Harness.test('creating a door asks for a name, closes, then saves what was aimed at', function()
    calls = {}
    dialogs = { reply({ name = 'Side Door', double = false }) }
    local result = action('door:new')
    Harness.equal(result.close, true)

    selections = { { model = 77, coords = { x = 5, y = 6, z = 7 }, heading = 45, entity = 1 } }
    local created = door('side-door', 'Side Door', { model = 77, coords = { x = 5, y = 6, z = 7 }, locked = true })
    nextCallback = { function(_, definition)
        return { doors = { snapshot[1], created }, id = 'side-door', saw = definition }
    end }
    pushHandlers['qbdoorlock:client:managementOpened'](false)

    local call
    for _, entry in ipairs(calls) do
        if entry.name == 'qbdoorlock:server:managementDoorCreated' then call = entry end
    end
    Harness.ok(call, 'the door was sent to the server')
    local definition = call.args[1]
    Harness.equal(definition.label, 'Side Door')
    Harness.equal(definition.model, 77)
    Harness.equal(definition.coords.x, 5)
    Harness.equal(definition.locked, true)
    Harness.equal(definition.distance, 1.8)
end)

Harness.test('a double door needs two aimed leaves and a cancel creates nothing', function()
    calls = {}
    dialogs = { reply({ name = 'Gate', double = true }) }
    action('door:new')
    selections = { { model = 5, coords = { x = 0, y = 0, z = 0 }, heading = 0, entity = 1 }, false }
    pushHandlers['qbdoorlock:client:managementOpened'](false)
    for _, entry in ipairs(calls) do
        Harness.ok(entry.name ~= 'qbdoorlock:server:managementDoorCreated', 'cancelled second leaf must not save')
    end

    calls = {}
    dialogs = { reply({ name = 'Gate', double = true }) }
    action('door:new')
    selections = {
        { model = 5, coords = { x = 0, y = 0, z = 0 }, heading = 0, entity = 1 },
        { model = 5, coords = { x = 2, y = 0, z = 0 }, heading = 180, entity = 2 },
    }
    pushHandlers['qbdoorlock:client:managementOpened'](false)
    local sent
    for _, entry in ipairs(calls) do
        if entry.name == 'qbdoorlock:server:managementDoorCreated' then sent = entry.args[1] end
    end
    Harness.ok(sent)
    Harness.equal(#sent.doors, 2)
    Harness.equal(sent.model, nil)
end)

Harness.test('duplicating carries the settings over to the newly aimed door', function()
    calls = {}
    action('door:select:lobby')
    dialogs = { function(fields)
        Harness.equal(findField({ fields = fields }, 'name').default, 'Lobby copy')
        return { values = { name = 'Lobby annex', double = false } }
    end }
    Harness.equal(action('door:duplicate').close, true)
    selections = { { model = 99, coords = { x = 8, y = 8, z = 8 }, heading = 10, entity = 3 } }
    pushHandlers['qbdoorlock:client:managementOpened'](false)
    local sent
    for _, entry in ipairs(calls) do
        if entry.name == 'qbdoorlock:server:managementDoorCreated' then sent = entry.args[1] end
    end
    Harness.ok(sent)
    Harness.equal(sent.label, 'Lobby annex')
    Harness.equal(sent.model, 99)
    Harness.equal(sent.groups.police, 2)
end)

Harness.test('retargeting replaces only the geometry', function()
    calls = {}
    action('door:select:lobby')
    Harness.equal(action('door:retarget:double').close, true)
    selections = {
        { model = 41, coords = { x = 1, y = 1, z = 1 }, heading = 0, entity = 4 },
        { model = 42, coords = { x = 3, y = 1, z = 1 }, heading = 180, entity = 5 },
    }
    pushHandlers['qbdoorlock:client:managementOpened'](false)
    local saved
    for _, entry in ipairs(calls) do
        if entry.name == 'qbdoorlock:server:managementDoorSaved' then saved = entry end
    end
    Harness.ok(saved)
    Harness.equal(saved.args[1], 'lobby')
    Harness.equal(saved.args[3], false)
    Harness.equal(#saved.args[2].doors, 2)
    Harness.equal(saved.args[2].model, nil)
    Harness.equal(saved.args[2].groups.police, 2)
end)

Harness.test('the creator does not use resource-owned network events', function()
    local file = assert(io.open('client/creator.lua', 'r'))
    local source = file:read('*a')
    file:close()
    Harness.ok(not source:find('RegisterNetEvent', 1, true) and not source:find('TriggerServerEvent', 1, true))
end)

if Harness.failures > 0 then os.exit(1) end
print(('%d creator tests passed'):format(Harness.tests))
