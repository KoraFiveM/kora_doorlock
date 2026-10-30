local H = dofile('../kora_core/test/harness.lua')
local vectorMeta = {}
vectorMeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vectorMeta) end
vectorMeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function vec(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
vector3 = vec
dofile('shared/schema.lua')

-- Loads client/main.lua with a recording door system. Returns the chunk's setupDoor/iconCoords/doors.
local function setup(config)
    local f = { calls = {}, threads = {}, registered = {}, doorState = {}, closed = true, time = 0 }
    local env = {}; for key, value in pairs(_G) do env[key] = value end
    setmetatable(env, { __index = function() return function() end end })
    env.vector3 = vec
    env.DoorlockSchema = DoorlockSchema
    env.Config = config or { DrawSpriteCentered = true, InteractionDistance = 1.8 }
    env.exports = function() end
    env.joaat = function(text) return text end
    env.CreateThread = function(fn) f.threads[#f.threads + 1] = fn end
    env.GetGameTimer = function() return f.time end
    env.Wait = function() f.time = f.time + 100 end
    env.AddDoorToSystem = function(hash) f.registered[hash] = true; f.calls[#f.calls + 1] = 'add' end
    env.RemoveDoorFromSystem = function(hash) f.registered[hash] = nil; f.calls[#f.calls + 1] = 'remove' end
    env.IsDoorRegisteredWithSystem = function(hash) return f.registered[hash] == true end
    env.DoorSystemSetDoorState = function(hash, state) f.doorState[hash] = state end
    env.DoorSystemGetDoorState = function(hash) return f.doorState[hash] or 0 end
    env.IsDoorClosed = function() return f.closed end
    env.GetModelDimensions = function() return { x = 0.0, y = -0.05, z = -1.0 }, { x = 1.0, y = 0.05, z = 1.0 } end
    env.DoesEntityExist = function() return false end
    env.Kora = setmetatable({
        lang = function(key) return key end,
        callback = { register = function() end, trigger = function() end },
        events = { trigger = function() end, onPush = function() end },
        zones = { point = function() return { remove = function() end } end },
        keybind = { add = function() return { disable = function() end } end },
    }, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })
    env.QB = env.Kora -- the committed sources use the QB alias, the working tree uses Kora
    local file = assert(io.open('client/main.lua')); local source = file:read('a'); file:close()
    local chunk = assert(load(source .. '\nreturn setupDoor, iconCoords, doors', '@client/main.lua', 't', env))
    f.setupDoor, f.iconCoords, f.doors = chunk()
    f.threads = {} -- drop the resource's endless polling loops; only enforcement threads are run
    function f.runThreads()
        local pending = f.threads; f.threads = {}
        for _, fn in ipairs(pending) do fn() end
    end
    return f
end

local single = { label = 'Fleeca', model = 100, coords = { x = 10.0, y = 20.0, z = 30.0 }, heading = 0.0, autoLock = 3000 }

H.test('a re-sent definition for an unmoved door keeps its door-system entry', function()
    local f = setup()
    f.setupDoor('fleeca', single, true)
    H.assertEqual(table.concat(f.calls, ','), 'add')
    f.setupDoor('fleeca', single, true) -- saving Details with an auto-lock
    H.assertEqual(table.concat(f.calls, ','), 'add', 'no remove/re-add of the same hash')
    H.assertEqual(f.doorState['qbdoorlock:fleeca:1'], 1)
end)

H.test('a moved door is re-registered', function()
    local f = setup()
    f.setupDoor('fleeca', single, true)
    local moved = {}; for k, v in pairs(single) do moved[k] = v end
    moved.coords = { x = 50.0, y = 20.0, z = 30.0 }
    f.setupDoor('fleeca', moved, true)
    H.assertEqual(table.concat(f.calls, ','), 'add,remove,add')
end)

H.test('the lock state is re-asserted until the door system holds it', function()
    local f = setup()
    f.setupDoor('fleeca', single, true)
    f.doorState['qbdoorlock:fleeca:1'] = 0 -- the system dropped the lock
    f.runThreads()
    H.assertEqual(f.doorState['qbdoorlock:fleeca:1'], 1)
end)

H.test('a door the system lost is added back while enforcing', function()
    local f = setup()
    f.setupDoor('fleeca', single, true)
    f.registered['qbdoorlock:fleeca:1'] = nil
    f.runThreads()
    H.assertTrue(f.registered['qbdoorlock:fleeca:1'])
    H.assertEqual(f.doorState['qbdoorlock:fleeca:1'], 1)
end)

H.test('an older enforcement loop stops when a newer state arrives', function()
    local f = setup()
    f.setupDoor('fleeca', single, true)
    f.setupDoor('fleeca', single, false) -- unlocked afterwards
    f.runThreads()
    H.assertEqual(f.doorState['qbdoorlock:fleeca:1'], 0)
end)

H.test('the lock icon sits at the middle of a single door, not its hinge', function()
    local f = setup()
    f.setupDoor('fleeca', single, true)
    local at = f.iconCoords(f.doors.fleeca)
    H.assertEqual(at.x, 10.5); H.assertEqual(at.y, 20.0); H.assertEqual(at.z, 30.0)
end)

H.test('the icon centre follows the door heading', function()
    local f = setup()
    local turned = {}; for k, v in pairs(single) do turned[k] = v end
    turned.heading = 90.0
    f.setupDoor('fleeca', turned, true)
    local at = f.iconCoords(f.doors.fleeca)
    assert(math.abs(at.x - 10.0) < 1e-6 and math.abs(at.y - 20.5) < 1e-6, ('got %s,%s'):format(at.x, at.y))
end)

H.test('double doors stay halfway between the leaves and the offset is configurable', function()
    local f = setup({ DrawSpriteCentered = true, InteractionDistance = 1.8, DrawSpriteOffset = { x = 0.0, y = 0.0, z = 0.25 } })
    f.setupDoor('pair', { label = 'Pair', doors = {
        { model = 100, coords = { x = 0.0, y = 0.0, z = 0.0 } }, { model = 100, coords = { x = 2.0, y = 0.0, z = 0.0 } },
    } }, true)
    local at = f.iconCoords(f.doors.pair)
    H.assertEqual(at.x, 1.0); H.assertEqual(at.z, 0.25)
end)

H.test('centring can be turned off', function()
    local f = setup({ DrawSpriteCentered = false, InteractionDistance = 1.8 })
    f.setupDoor('fleeca', single, true)
    H.assertEqual(f.iconCoords(f.doors.fleeca).x, 10.0)
end)

H.report('kora_doorlock door state and icon')
