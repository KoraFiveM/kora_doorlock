local H = dofile('../kora_core/test/harness.lua')
vector3 = function(x, y, z) return { x = x, y = y, z = z } end
dofile('shared/access.lua')
dofile('shared/schema.lua')

local A = DoorlockAccess

-- ---------------------------------------------------------------------------
-- Pure rules
-- ---------------------------------------------------------------------------

H.test('an unrestricted door is closed to ordinary players by default', function()
    H.assertFalse(A.decide({ restricted = A.isRestricted({}) }, false))
    H.assertFalse(A.decide({ restricted = false }, nil))
end)

H.test('unrestricted doors open to everyone only when the config says so', function()
    H.assertTrue(A.decide({ restricted = false }, true))
    H.assertFalse(A.decide({ restricted = true }, true), 'a restricted door never opens to everyone')
end)

H.test('admins and door ACEs always pass', function()
    H.assertTrue(A.decide({ admin = true, restricted = true }, false))
    H.assertTrue(A.decide({ ace = true, restricted = true }, false))
end)

H.test('matching character, group or item passes; otherwise a restricted door fails', function()
    H.assertTrue(A.decide({ character = true, restricted = true }, false))
    H.assertTrue(A.decide({ group = true, restricted = true }, false))
    H.assertTrue(A.decide({ item = true, restricted = true }, false))
    H.assertFalse(A.decide({ restricted = true }, false))
end)

H.test('isRestricted sees every access requirement', function()
    H.assertFalse(A.isRestricted({}))
    H.assertTrue(A.isRestricted({ passcode = '1234' }))
    H.assertTrue(A.isRestricted({ characters = { 'ABC' } }))
    H.assertTrue(A.isRestricted({ groups = { police = 0 } }))
    H.assertTrue(A.isRestricted({ items = { { name = 'key' } } }))
end)

H.test('group and character matching', function()
    local cop = { citizenid = 'ABC1', job = { name = 'police', grade = { level = 2 } }, gang = { name = 'none', grade = 0 } }
    H.assertTrue(A.matchesGroup(cop, { police = 2 }))
    H.assertFalse(A.matchesGroup(cop, { police = 3 }))
    H.assertFalse(A.matchesGroup(cop, { ambulance = 0 }))
    H.assertTrue(A.matchesGroup({ job = { name = 'x', grade = 4 } }, { x = 4 }))
    H.assertFalse(A.matchesGroup(nil, { police = 0 }))
    H.assertTrue(A.matchesCharacter(cop, { 'ZZZ', 'ABC1' }))
    H.assertFalse(A.matchesCharacter(cop, { 'ZZZ' }))
    H.assertFalse(A.matchesCharacter({}, { '' }), 'a player with no character id never matches')
    H.assertFalse(A.matchesCharacter(cop, nil))
end)

-- ---------------------------------------------------------------------------
-- The real server toggle handler, with the framework stubbed
-- ---------------------------------------------------------------------------

local function setup(options)
    local f = { notifications = {}, handlers = {}, states = {}, pushes = {} }
    local env = {}; for key, value in pairs(_G) do env[key] = value end
    setmetatable(env, { __index = function() return function() end end })
    env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
    env.DoorlockSchema = DoorlockSchema
    env.DoorlockAccess = DoorlockAccess
    env.GetCurrentResourceName = function() return 'kora_doorlock' end
    env.CreateThread = function() end
    env.AddEventHandler = function() end
    env.TriggerEvent = function() end
    env.Config = {
        Doors = { bank = { label = 'Bank', model = 1, coords = { x = 1, y = 2, z = 3 }, locked = true,
            groups = options.groups, characters = options.characters, passcode = options.passcode } },
        InteractionDistance = 1.8, UnrestrictedDoorsOpenToAll = options.open, AdminPermission = 'admin',
        lockpickRateLimit = { max = 4, window = 10000 },
    }
    env.exports = setmetatable({}, {
        __call = function() end,
        __index = function() return { getPlayer = function() return options.player end, getItemsByName = function() return {} end } end,
    })
    env.Kora = setmetatable({
        lang = function(key) return key end,
        notify = { send = function(_, data) f.notifications[#f.notifications + 1] = data end },
        permissions = { hasPermission = function(_, name) return options.admin == true and name == 'admin' end },
        distance = { player = function() return options.near ~= false end },
        events = {
            register = function(name, handler) f.handlers[name] = handler end,
            push = function(_, name, id, state) f.pushes[#f.pushes + 1] = { name = name, id = id, state = state } end,
        },
        callback = { register = function() end, trigger = function() return options.supplied end },
        sql = { ready = function() return false end },
        timers = { setTimeout = function() return 1 end, clearTimeout = function() end },
        resources = { serverRegistry = function() return { track = function() end, untrack = function() end } end },
        compat = { isCallable = function() return true end },
    }, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })
    env.QB = env.Kora -- the committed sources use the QB alias, the working tree uses Kora
    local file = assert(io.open('server/main.lua')); local source = file:read('a'); file:close()
    local chunk = assert(load(source .. '\nreturn states', '@server/main.lua', 't', env))
    f.states = chunk()
    function f.toggle() f.handlers['qbdoorlock:server:doorToggled'](7, 'bank') end
    return f
end

local civilian = { citizenid = 'CIV1', job = { name = 'unemployed', grade = { level = 0 } }, gang = { name = 'none', grade = 0 } }

H.test('server: a stranger cannot unlock a door with no authorisation list', function()
    local f = setup({ player = civilian })
    f.toggle()
    H.assertEqual(f.states.bank, true)
    H.assertEqual(#f.notifications, 1)
    H.assertEqual(f.notifications[1].type, 'error')
    H.assertEqual(f.notifications[1].message, 'access_denied')
end)

H.test('server: the same door toggles for everyone when the config opts in', function()
    local f = setup({ player = civilian, open = true })
    f.toggle()
    H.assertEqual(f.states.bank, false)
end)

H.test('server: an admin can toggle an unrestricted door', function()
    local f = setup({ player = civilian, admin = true })
    f.toggle()
    H.assertEqual(f.states.bank, false)
end)

H.test('server: a matching job grade can toggle, a wrong job or a low grade cannot', function()
    local cop = { citizenid = 'COP1', job = { name = 'police', grade = { level = 2 } } }
    local f = setup({ player = cop, groups = { police = 2 } })
    f.toggle(); H.assertEqual(f.states.bank, false)
    local rookie = { citizenid = 'COP2', job = { name = 'police', grade = { level = 1 } } }
    f = setup({ player = rookie, groups = { police = 2 } })
    f.toggle(); H.assertEqual(f.states.bank, true)
    f = setup({ player = civilian, groups = { police = 0 }, open = true })
    f.toggle(); H.assertEqual(f.states.bank, true, 'open-to-all must not apply to a restricted door')
end)

H.test('server: a listed character can toggle and an unlisted one cannot', function()
    local f = setup({ player = civilian, characters = { 'CIV1' } })
    f.toggle(); H.assertEqual(f.states.bank, false)
    f = setup({ player = civilian, characters = { 'OTHER' } })
    f.toggle(); H.assertEqual(f.states.bank, true)
end)

H.test('server: a missing player record is never authorised by default', function()
    local f = setup({ player = nil })
    f.toggle()
    H.assertEqual(f.states.bank, true)
end)

H.test('server: a toggle from out of range is ignored', function()
    local f = setup({ player = civilian, admin = true, near = false })
    f.toggle()
    H.assertEqual(f.states.bank, true)
    H.assertEqual(#f.notifications, 0)
end)

H.test('server: a wrong passcode does not unlock', function()
    local f = setup({ player = civilian, passcode = '1234', supplied = 'nope' })
    f.toggle(); H.assertEqual(f.states.bank, true)
    f = setup({ player = civilian, passcode = '1234', supplied = '1234' })
    f.toggle(); H.assertEqual(f.states.bank, false)
end)

H.report('kora_doorlock authorisation')
