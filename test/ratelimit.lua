local H = dofile('../kora_core/test/harness.lua')

-- Loads client/main.lua with stubbed natives. The chunk is extended to return its
-- local pickDoor/doors so the test can drive them without the game loop.
local function setup(trigger)
    local f = { notifications = {}, threads = {} }
    local env = {}; for key, value in pairs(_G) do env[key] = value end
    setmetatable(env, { __index = function() return function() end end })
    env.Config = {}
    env.exports = function() end
    env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
    env.CreateThread = function(fn) f.threads[#f.threads + 1] = fn end
    env.GetCurrentResourceName = function() return 'kora_doorlock' end
    env.QB = setmetatable({
        lang = function(key, values) return values and values.seconds and (key .. ':' .. values.seconds) or key end,
        notify = { send = function(data) f.notifications[#f.notifications + 1] = data end },
        callback = { register = function() end, trigger = trigger },
        cache = { ped = function() return 1 end },
        anim = { play = function() end, stopHandle = function() end },
        minigames = { play = function() return { success = true } end },
        events = { trigger = function() end, onPush = function() end },
    }, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })
    local file = assert(io.open('client/main.lua')); local source = file:read('a'); file:close()
    local chunk = assert(load(source .. '\nreturn pickDoor, doors', '@client/main.lua', 't', env))
    f.pickDoor, f.doors = chunk()
    f.doors.bank = { coords = { x = 1, y = 2, z = 3 }, lockpick = true, locked = true }
    function f.pick() f.pickDoor('bank'); f.threads[#f.threads]() end
    return f
end

H.test('a rate-limited lockpick start does not raise and the door can be picked again', function()
    local limited = true
    local f = setup(function()
        if limited then error('Callback rate limit exceeded; retry in 7144ms') end
        return nil, 'denied'
    end)
    assert(f.pickDoor('bank') == true)
    H.assertEqual(f.pickDoor('bank'), false) -- still in progress
    f.threads[#f.threads]()                  -- must not raise
    H.assertEqual(#f.notifications, 1)
    H.assertEqual(f.notifications[1].message, 'slow_down:8')
    H.assertEqual(f.notifications[1].type, 'error')
    limited = false
    assert(f.pickDoor('bank') == true) -- pickingLock was reset
end)

H.report('qbdoorlock lockpick rate limit')
