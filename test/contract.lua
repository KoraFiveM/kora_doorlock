local Harness = dofile('test/harness.lua')

local function read(path)
    local file = assert(io.open(path, 'r'))
    local contents = file:read('*a')
    file:close()
    return contents
end

local client, server, manifest = read(arg[1] or 'client/main.lua'), read('server/main.lua'), read('fxmanifest.lua')

Harness.test('uses qblib gateways rather than resource-owned network events', function()
    Harness.ok(not client:find('RegisterNetEvent', 1, true) and not client:find('TriggerServerEvent', 1, true))
    Harness.ok(not server:find('RegisterNetEvent', 1, true) and not server:find('TriggerClientEvent', 1, true))
    for _, api in ipairs({ 'QB.events', 'QB.callback', 'QB.permissions', 'QB.minigames', 'QB.timers', 'QB.sql', 'QB.commands', 'QB.distance', 'QB.lang' }) do
        Harness.ok(server:find(api, 1, true), ('server should use %s'):format(api))
    end
    for _, api in ipairs({ 'QB.events', 'QB.callback', 'QB.sound', 'QB.stream', 'QB.anim', 'QB.interact', 'QB.keybind', 'QB.zones', 'QB.raycast', 'QB.nui', 'QB.textui', 'QB.notify', 'QB.teleport', 'QB.distance', 'QB.world', 'QB.cache', 'QB.lang' }) do
        Harness.ok(client:find(api, 1, true), ('client should use %s'):format(api))
    end
end)

Harness.test('publishes ox-doorlock-equivalent API operations', function()
    for _, exportName in ipairs({ 'getDoor', 'getAllDoors', 'getDoorFromName', 'setDoorState', 'editDoor', 'createDoor', 'removeDoor', 'importOxDoors' }) do
        Harness.ok(server:find("exports('" .. exportName .. "'", 1, true), ('missing server export %s'):format(exportName))
    end
    for _, exportName in ipairs({ 'useClosestDoor', 'pickClosestDoor', 'getClosestDoor', 'getClosestDoorId', 'getDoorIdFromEntity' }) do
        Harness.ok(client:find("exports('" .. exportName .. "'", 1, true), ('missing client export %s'):format(exportName))
    end
end)

Harness.test('loads schema before both realms', function()
    Harness.ok(manifest:find("'shared/schema.lua'", 1, true))
    Harness.ok(manifest:find("version '2.0.0'", 1, true))
end)

Harness.test('client getter preserves locked unlocked and missing values through actual sync handlers', function()
    local env = {}
    for key, value in pairs(_G) do env[key] = value end
    local exported, pushed, threads = {}, {}, {}
    local noop = function() end
    env.Config = { InteractionDistance = 1.8, DrawSprite = false, DrawTextUI = false }
    env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
    local definition = { label = 'Contract door', model = 1, coords = env.vector3(0, 0, 0), locked = true }
    env.QB = {
        callback = { register = noop, trigger = function(name)
            Harness.equal(name, 'qbdoorlock:server:doorsRequested')
            return { locked = definition, unlocked = definition }, { locked = true, unlocked = false }
        end },
        events = { onPush = function(name, handler) pushed[name] = handler end },
        keybind = { add = function() return { disable = noop } end },
        zones = { point = function() return { remove = noop } end },
        distance = { player = function() return false end },
    }
    env.exports = function(name, callback) exported[name] = callback end
    env.CreateThread = function(callback) threads[#threads + 1] = callback end
    env.AddEventHandler = noop
    env.GetResourceState = function() return 'missing' end
    env.joaat = function() return 1 end
    env.AddDoorToSystem, env.RemoveDoorFromSystem = noop, noop
    env.DoorSystemSetDoorState, env.DoorSystemSetAutomaticRate = noop, noop
    assert(loadfile('shared/schema.lua', 't', env))()
    assert(load(client, '@' .. (arg[1] or 'client/main.lua'), 't', env))()
    local function state(id, expected)
        local result = table.pack(exported.getDoorState(id))
        Harness.equal(result.n, 1, 'getter preserves one return value')
        Harness.equal(result[1], expected)
    end
    state('unloaded', nil)
    threads[1]() -- Run the existing hydrate once; leave unrelated native loops inert.
    state('locked', true)
    state('unlocked', false)
    state('absent', nil)
    state(nil, nil)
    state(false, nil)
    state(7, nil)
    state({}, nil)
    pushed['qbdoorlock:client:doorStateChanged']('locked', false, 1)
    state('locked', false)
    pushed['qbdoorlock:client:doorStateChanged']('unlocked', true, nil)
    state('unlocked', true)
    pushed['qbdoorlock:client:doorDefinitionUpdated']('replacement', definition, false)
    state('replacement', false)
    pushed['qbdoorlock:client:doorDefinitionUpdated']('replacement', definition, true)
    state('replacement', true)
    pushed['qbdoorlock:client:doorDefinitionRemoved']('replacement')
    state('replacement', nil)
end)

if Harness.failures > 0 then os.exit(1) end
print(('%d contract tests passed'):format(Harness.tests))
