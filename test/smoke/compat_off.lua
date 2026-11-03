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
_G.Config = { InteractionDistance = 1.8, compat = { qbDoorlockExports = false } }
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


harness.test('no qb-doorlock exports are provided when Config.compat.qbDoorlockExports is false', function()
    harness.assertEqual(next(provided), nil)
end)

harness.report('doorlock compat off')
