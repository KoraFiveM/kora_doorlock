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
-- The client script loads with the default (on); the saved config only arrives afterwards.
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

pushes['qbdoorlock:client:doorDefinitionUpdated']('front', {
    label = 'Front door', model = 1, coords = { x = 1.0, y = 0.0, z = 0.0 }, heading = 0.0, distance = 2.0,
}, true)
zones[1].onEnter()
position = vec(1.5, 0, 0)
for _, thread in ipairs(threads) do pcall(thread) end

harness.test('the exports are registered at load and return data while the flag is on', function()
    harness.assertEqual(provided.GetDoorStates().front, true)
    harness.assertEqual(provided.GetDoorList().front.doorLabel, 'Front door')
    harness.assertEqual(provided.GetNearbyDoors().front, true)
    harness.assertEqual(provided.GetClosestDoor().id, 'front')
end)

harness.test('flipping Config.compat.qbDoorlockExports off after load empties every export', function()
    Config.compat.qbDoorlockExports = false
    for _, name in ipairs({ 'GetDoorStates', 'GetDoorList', 'GetNearbyDoors', 'GetClosestDoor' }) do
        harness.assertTrue(type(provided[name]) == 'function', name)
        harness.assertEqual(next(provided[name]()), nil, name)
    end
    Config.compat.qbDoorlockExports = true
    harness.assertEqual(provided.GetDoorStates().front, true, 'turning it back on restores the data')
end)

harness.report('doorlock compat off')
