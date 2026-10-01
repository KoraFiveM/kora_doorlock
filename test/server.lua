local Harness = dofile('test/harness.lua')

function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, {
        __sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end,
    })
end

Config = {
    InteractionDistance = 2,
    DefaultAutoLock = nil,
    PlayerAceAuthorised = false,
    LockpickItems = { 'lockpick' },
    LockpickDifficulty = { 'easy' },
    Doors = {
        public = { label = 'Public', model = 1, coords = vector3(0, 0, 0), locked = true },
        police = { label = 'Police', model = 2, coords = vector3(0, 0, 0), locked = true, groups = { police = 2 } },
        coded = { label = 'Coded', model = 3, coords = vector3(0, 0, 0), locked = true, passcode = '1234' },
        keyed = { label = 'Keyed', model = 4, coords = vector3(0, 0, 0), locked = true, items = { { name = 'keycard', metadata = 'police', remove = true } } },
        pickable = { label = 'Pickable', model = 5, coords = vector3(0, 0, 0), locked = true, lockpick = true },
        ace = { label = 'ACE Door', model = 6, coords = vector3(0, 0, 0), locked = true, groups = { staff = 0 } },
    },
}
dofile('shared/schema.lua')

local eventHandlers, callbackHandlers, exported, pushed, localEvents, removedItems = {}, {}, {}, {}, {}, {}
local player = { citizenid = 'CID', job = { name = 'police', grade = { level = 2 } }, gang = { name = 'none', grade = 0 } }
local items = {
    keycard = { { name = 'keycard', amount = 1, slot = 7, info = { type = 'police' } } },
    lockpick = { { name = 'lockpick', amount = 1, slot = 8, info = {} } },
}

QB = {
    lang = function(key) return key end,
    permissions = { hasPermission = function(source, permission, prefix)
        return source == 2 and permission == 'ACE Door' and prefix == 'doorlock'
    end },
    compat = { isCallable = function(value) return type(value) == 'function' end },
    resources = { serverRegistry = function(cleanup)
        return { track = function() end, untrack = function() end, cleanup = cleanup }
    end },
    events = {
        register = function(name, handler) eventHandlers[name] = handler end,
        push = function(target, name, ...) pushed[#pushed + 1] = { target = target, name = name, args = { ... } } end,
    },
    callback = {
        register = function(name, handler) callbackHandlers[name] = handler end,
        trigger = function(_, name) if name == 'qbdoorlock:client:passcodeRequested' then return '1234' end end,
    },
    timers = { setTimeout = function() return 1 end, clearTimeout = function() end },
    notify = { send = function() end },
    distance = { player = function() return true end },
    minigames = { authorizeProof = function() return 'authorization' end, consumeProof = function() return true end },
    commands = { add = function() end },
    sql = { ready = function() return false end },
}

local exportProvider = {
    getPlayer = function(_, source) return source == 1 and player or nil end,
    getItemsByName = function(_, source, name) return source == 1 and (items[name] or {}) or {} end,
    removeItem = function(_, source, name, amount, slot)
        removedItems[#removedItems + 1] = { source = source, name = name, amount = amount, slot = slot }
        return true
    end,
}
exports = setmetatable({ qbcore = exportProvider }, { __call = function(_, name, callback) exported[name] = callback end })

function GetCurrentResourceName() return 'qbdoorlock' end
function GetInvokingResource() return nil end
function GetPlayerPed() return 1 end
function GetEntityCoords() return vector3(0, 0, 0) end
function SetEntityCoords() end
function AddEventHandler(name, handler) localEvents[name] = handler end
function TriggerEvent(name, ...) localEvents[#localEvents + 1] = { name = name, args = { ... } } end
function CreateThread(callback) callback() end
function Wait() end

dofile(arg[1] or 'server/main.lua')

Harness.test('public doors toggle through the authenticated qblib handler', function()
    Harness.equal(exported.getDoorState('public'), true)
    eventHandlers['qbdoorlock:server:doorToggled'](1, 'public')
    Harness.equal(exported.getDoorState('public'), false)
    Harness.equal(pushed[#pushed].name, 'qbdoorlock:client:doorStateChanged')
end)

Harness.test('group, passcode, and metadata item access all authorize', function()
    eventHandlers['qbdoorlock:server:doorToggled'](1, 'police')
    Harness.equal(exported.getDoorState('police'), false)
    eventHandlers['qbdoorlock:server:doorToggled'](1, 'coded')
    Harness.equal(exported.getDoorState('coded'), false)
    eventHandlers['qbdoorlock:server:doorToggled'](1, 'keyed')
    Harness.equal(exported.getDoorState('keyed'), false)
    Harness.equal(removedItems[1].name, 'keycard')
    Harness.equal(removedItems[1].slot, 7)
end)

Harness.test('server exports expose numeric and boolean state compatibility', function()
    Harness.equal(exported.setDoorState('public', 1), true)
    Harness.equal(exported.getDoor('public').state, 1)
    Harness.equal(exported.setDoorState('public', 2), false)
    Harness.equal(#exported.getAllDoors(), 6)
    Harness.equal(exported.getDoorFromName('Police').id, 'police')
end)

Harness.test('ox-style door-name ACE grants remain compatible', function()
    eventHandlers['qbdoorlock:server:doorToggled'](2, 'ace')
    Harness.equal(exported.getDoorState('ace'), false)
end)

Harness.test('lockpicking requires and consumes a qblib proof', function()
    local authorization = callbackHandlers['qbdoorlock:server:lockpickStarted'](1, 'pickable')
    Harness.equal(authorization, 'authorization')
    eventHandlers['qbdoorlock:server:lockpickFinished'](1, 'pickable', authorization, 'proof')
    Harness.equal(exported.getDoorState('pickable'), false)
end)

Harness.test('passcode completion requires the player to remain near the door', function()
    exported.setDoorState('coded', true)
    local near, notifications = true, {}
    QB.distance.player = function() return near end
    QB.notify.send = function(_, options) notifications[#notifications + 1] = options end
    QB.callback.trigger = function(_, name)
        Harness.equal(name, 'qbdoorlock:client:passcodeRequested')
        return coroutine.yield('passcode prompt')
    end

    local function request()
        local pending = coroutine.create(function() return eventHandlers['qbdoorlock:server:doorToggled'](1, 'coded') end)
        local ok, phase = coroutine.resume(pending)
        Harness.equal(ok, true)
        Harness.equal(phase, 'passcode prompt')
        return pending
    end

    local pending, pushCount = request(), #pushed
    near = false
    Harness.equal(coroutine.resume(pending, '1234'), true)
    Harness.equal(coroutine.status(pending), 'dead')
    Harness.equal(exported.getDoorState('coded'), true)
    Harness.equal(#pushed, pushCount)
    Harness.equal(#notifications, 0)

    near = true
    pending = request()
    Harness.equal(coroutine.resume(pending), true)
    Harness.equal(exported.getDoorState('coded'), true)
    Harness.equal(#notifications, 1)
    Harness.equal(notifications[1].message, 'access_denied')

    pending = request()
    local result = table.pack(coroutine.resume(pending, '1234'))
    Harness.equal(result[1], true)
    Harness.equal(result.n, 1)
    Harness.equal(coroutine.status(pending), 'dead')
    Harness.equal(exported.getDoorState('coded'), false)
    Harness.equal(#pushed, pushCount + 1)
end)

if Harness.failures > 0 then os.exit(1) end
print(('%d server tests passed'):format(Harness.tests))
