local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local resourceDir = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path
local harness = require('harness')

local any
any = setmetatable({}, {
    __index = function() return any end,
    __call = function() return any end,
})
local pushes, provided, commands = {}, {}, {}
local position = { x = 0.0, y = 0.0, z = 0.0 }
setmetatable(position, { __sub = function(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end })
local vecMeta = { __sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, getmetatable(a)) end,
    __len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end }
local function vec(x, y, z) return setmetatable({ x = x, y = y, z = z }, vecMeta) end
position = vec(0, 0, 0)

local zones = {}
_G.Kora = setmetatable({
    events = { onPush = function(name, fn) pushes[name] = fn end },
    callback = { register = function() end, trigger = function() return nil end },
    compat = { provideExport = function(_, name, fn) provided[name] = fn end, isCallable = function() return true end },
    zones = { point = function(options) options.remove = function() end; zones[#zones + 1] = options; return options end },
    lang = function(key) return key end,
}, { __index = function() return any end })
_G.vec3 = vec
_G.vector3 = vec
_G.Config = { InteractionDistance = 1.8, compat = { qbDoorlockExports = true } }
local threads = {}
_G.CreateThread = function(fn) threads[#threads + 1] = fn end
_G.Wait = function() error('stop', 0) end
_G.joaat = function() return 1 end
_G.GetEntityCoords = function() return position end
_G.PlayerPedId = function() return 1 end
_G.AddEventHandler = function() end
_G.RegisterNetEvent = function() end
_G.exports = function() end
setmetatable(_G, { __index = function(_, key) if type(key) == 'string' and key:match('^%u') then return any end end })

dofile(resourceDir .. 'shared/schema.lua')
dofile(resourceDir .. 'client/main.lua')

local function define(id, x, label, locked)
    pushes['qbdoorlock:client:doorDefinitionUpdated'](id, {
        label = label, model = 1, coords = { x = x, y = 0.0, z = 0.0 }, heading = 0.0, distance = 2.0,
    }, locked)
end

harness.test('the four stock exports are provided under qb-doorlock', function()
    for _, name in ipairs({ 'GetDoorStates', 'GetClosestDoor', 'GetNearbyDoors', 'GetDoorList' }) do
        harness.assertTrue(type(provided[name]) == 'function', name)
    end
end)

harness.test('GetDoorStates and GetDoorList use the stock id keyed shapes', function()
    define('front', 1.0, 'Front door', true)
    define('back', 50.0, 'Back door', false)
    local states = provided.GetDoorStates()
    harness.assertEqual(states.front, true)
    harness.assertEqual(states.back, false)
    local list = provided.GetDoorList()
    harness.assertEqual(list.front.doorLabel, 'Front door')
    harness.assertEqual(list.front.locked, true)
    harness.assertEqual(list.front.textCoords.x, 1.0)
    harness.assertEqual(list.front.entities, nil)
end)

harness.test('GetNearbyDoors and GetClosestDoor follow the interaction zones', function()
    harness.assertEqual(next(provided.GetNearbyDoors()), nil)
    harness.assertEqual(next(provided.GetClosestDoor()), nil)
    zones[1].onEnter()
    harness.assertEqual(provided.GetNearbyDoors().front, true)
    harness.assertEqual(provided.GetNearbyDoors().back, nil)
    position = vec(1.5, 0, 0)
    for _, thread in ipairs(threads) do pcall(thread) end
    local closest = provided.GetClosestDoor()
    harness.assertEqual(closest.id, 'front')
    harness.assertEqual(closest.data.doorLabel, 'Front door')
    harness.assertTrue(math.abs(closest.distance - 0.5) < 0.001)
end)

harness.test('removed doors disappear from the compat views', function()
    pushes['qbdoorlock:client:doorDefinitionRemoved']('back')
    harness.assertEqual(provided.GetDoorStates().back, nil)
    harness.assertEqual(provided.GetDoorList().back, nil)
end)

harness.report('doorlock compat')
