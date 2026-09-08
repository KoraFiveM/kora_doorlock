local Harness = dofile('test/harness.lua')

local function read(path)
    local file = assert(io.open(path, 'r'))
    local contents = file:read('*a')
    file:close()
    return contents
end

local client, server, manifest = read('client/main.lua'), read('server/main.lua'), read('fxmanifest.lua')

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

if Harness.failures > 0 then os.exit(1) end
print(('%d contract tests passed'):format(Harness.tests))
