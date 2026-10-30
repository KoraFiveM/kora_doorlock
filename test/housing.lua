local H = dofile('../kora_core/test/harness.lua')
local jsonTools = dofile('../kora_core/test/mocks.lua')
local json = { encode = jsonTools.stableEncode, decode = jsonTools.simpleDecode }

local function setup(stored, linked, rateLimit)
    local f = { exports = {}, callbacks = {}, callbackOptions = {}, actions = {}, events = {}, threads = {}, caller = 'housing' }
    local env = {}; for key, value in pairs(_G) do env[key] = value end
    env.json, env.DoorlockSchema = json, nil
    env.Config = { Doors = { test = { label = 'Test', model = 123, coords = { x = 1, y = 2, z = 3 }, locked = true } }, InteractionDistance = 2, lockpickRateLimit = rateLimit }
    if linked then env.Config.Doors.partner = { label = 'Partner', model = 124, coords = { x = 2, y = 2, z = 3 }, locked = true } end
    env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
    env.GetCurrentResourceName = function() return 'kora_doorlock' end
    env.GetInvokingResource = function() return f.caller end
    env.CreateThread = function(fn) f.threads[#f.threads + 1] = fn end
    env.AddEventHandler = function(name, fn) f.events[name] = fn end
    env.TriggerEvent = function() end
    env.exports = setmetatable({ kora_core = { getPlayer = function() return { citizenid = 'CID1' } end } }, {
        __call = function(_, name, fn) f.exports[name] = fn end,
    })
    env.QB = {
        lang = function(key) return key end,
        permissions = { hasPermission = function() return false end },
        compat = { isCallable = function(value) return type(value) == 'function' end },
        resources = { serverRegistry = function() return { track = function() end, untrack = function() end } end },
        callback = { register = function(name, fn, options) f.callbacks[name] = fn; f.callbackOptions[name] = options end },
        events = { register = function(name, fn) f.actions[name] = fn end, push = function() end },
        commands = { add = function() end }, distance = { player = function() return true end },
        notify = { send = function() end }, timers = { clearTimeout = function() end },
        sql = { ready = function() return true end, query = function(sql)
            if linked and sql:find('qbdoorlock_links', 1, true) then return { { door_id = 'test', linked_door_id = 'partner' }, { door_id = 'partner', linked_door_id = 'test' } } end
            if stored and sql:find('qbdoorlock_doors', 1, true) then return { { id = 'test', definition = stored } } end
            return {}
        end, execute = function(sql, params)
            if f.failSave then return nil, 'controlled SQL failure' end
            if sql:find('INSERT INTO `qbdoorlock_doors`', 1, true) then f.saved = params[2] end
            return { affectedRows = 1 }
        end },
    }
    assert(loadfile('shared/schema.lua', 't', env))()
    assert(loadfile('server/main.lua', 't', env))()
    f.threads[1]()
    function f.toggle() f.actions['qbdoorlock:server:doorToggled'](1, 'test') end
    return f
end

H.test('ordinary doors retain their grant-only hook behavior', function()
    local f = setup()
    f.exports.registerHook('doorAuthorization', function() return false end)
    f.toggle()
    H.assertEqual(f.exports.getDoorState('test'), false)
end)

H.test('property policy is authoritative and receives a stable door id', function()
    local f = setup()
    f.exports.registerHook('doorAuthorization', function() return true end)
    local permitted = false
    assert(f.exports.RegisterDoorPolicy('test', function(src, id, context)
        H.assertEqual(src, 1); H.assertEqual(id, 'test'); H.assertEqual(context.lockpick, false)
        return permitted
    end))
    f.toggle(); H.assertEqual(f.exports.getDoorState('test'), true)
    permitted = true
    f.toggle(); H.assertEqual(f.exports.getDoorState('test'), false)
    f.events.onResourceStop('housing')
    H.assertEqual(f.exports.getDoorState('test'), true)
    f.toggle(); H.assertEqual(f.exports.getDoorState('test'), true)
end)

H.test('restored policy doors remain locked until their provider rebinds', function()
    local f = setup()
    assert(f.exports.RegisterDoorPolicy('test', function() return true end))
    assert(f.exports.editDoor('test', { label = 'Edited', policyOwner = '' }))
    H.assertEqual(json.decode(f.saved).policyOwner, 'housing')
    local restarted = setup(f.saved)
    restarted.toggle(); H.assertEqual(restarted.exports.getDoorState('test'), true)
    assert(restarted.exports.RegisterDoorPolicy('test', function() return true end))
    restarted.toggle(); H.assertEqual(restarted.exports.getDoorState('test'), false)
end)

H.test('policy lookup errors and foreign registrations cannot open the door', function()
    local f = setup()
    assert(f.exports.RegisterDoorPolicy('test', function() error('controlled policy failure') end))
    f.toggle(); H.assertEqual(f.exports.getDoorState('test'), true)
    f.caller = 'other'
    H.assertEqual(f.exports.RegisterDoorPolicy('test', function() return true end), false)
    H.assertEqual(f.exports.ClearDoorPolicy('test'), false)
end)

H.test('failed policy persistence does not install an unconfirmed policy', function()
    local f = setup()
    f.failSave = true
    H.assertEqual(f.exports.RegisterDoorPolicy('test', function() return false end), false)
    f.toggle(); H.assertEqual(f.exports.getDoorState('test'), true)
end)

H.test('an unrestricted linked door cannot bypass its protected partner', function()
    local f = setup(nil, true)
    assert(f.exports.RegisterDoorPolicy('partner', function() return false end))
    f.toggle()
    H.assertEqual(f.exports.getDoorState('test'), true)
    H.assertEqual(f.exports.getDoorState('partner'), true)
    assert(f.exports.RegisterDoorPolicy('partner', function() return true end))
    f.toggle()
    H.assertEqual(f.exports.getDoorState('test'), false)
    H.assertEqual(f.exports.getDoorState('partner'), false)
end)

H.test('explicit owner unlink restores legacy access without deleting the door', function()
    local f = setup()
    assert(f.exports.RegisterDoorPolicy('test', function() return false end))
    f.caller = 'other'
    H.assertEqual(f.exports.ReleaseDoorPolicy('test'), false)
    f.caller, f.failSave = 'housing', true
    H.assertEqual(f.exports.ReleaseDoorPolicy('test'), false)
    f.toggle(); H.assertEqual(f.exports.getDoorState('test'), true)
    f.failSave = false
    assert(f.exports.ReleaseDoorPolicy('test'))
    H.assertEqual(json.decode(f.saved).policyOwner, nil)
    f.toggle(); H.assertEqual(f.exports.getDoorState('test'), false)
end)

H.test('lockpick callback uses Config.lockpickRateLimit and falls back to the original limit', function()
    local configured = setup(nil, nil, { max = 9, window = 3000 })
    local options = configured.callbackOptions['qbdoorlock:server:lockpickStarted']
    H.assertEqual(options.rateLimit.max, 9); H.assertEqual(options.rateLimit.window, 3000)
    local fallback = setup().callbackOptions['qbdoorlock:server:lockpickStarted']
    H.assertEqual(fallback.rateLimit.max, 4); H.assertEqual(fallback.rateLimit.window, 10000)
end)

H.report('qbdoorlock property policies')
