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
    AdminPermission = 'admin',
    AdminPermissionPrefix = 'qbcore',
    Doors = {},
}
dofile('shared/schema.lua')

local callbacks, exported, encoded, pushes = {}, {}, {}, {}
json = {
    encode = function(value)
        local key = ('encoded:%d'):format(#encoded + 1)
        encoded[key] = value
        return key
    end,
    decode = function(value)
        if value == 'ox-row' then
            return {
                state = 1, model = 20, coords = { x = 1, y = 1, z = 1 }, maxDistance = 3,
                autolock = 12, lockpick = true,
            }
        end
        return assert(encoded[value], 'unexpected encoded value')
    end,
}

QB = {
    lang = function(key) return key end,
    permissions = { hasPermission = function(_, permission, prefix) return permission == 'admin' and prefix == 'qbcore' end },
    compat = { isCallable = function(value) return type(value) == 'function' end },
    resources = { serverRegistry = function()
        return { track = function() end, untrack = function() end }
    end },
    events = {
        register = function() end,
        push = function(target, name, ...) pushes[#pushes + 1] = { target = target, name = name, args = { ... } } end,
    },
    callback = {
        register = function(name, handler) callbacks[name] = handler end,
        trigger = function() end,
    },
    timers = { setTimeout = function() return 1 end, clearTimeout = function() end },
    notify = { send = function() end },
    distance = { player = function() return true end },
    minigames = { authorizeProof = function() return 'authorization' end, consumeProof = function() return true end },
    commands = { add = function() end },
    sql = {
        ready = function() return true end,
        migrate = function() return true end,
        migrateFiles = function() return true end,
        scalar = function() return 1 end,
        query = function(statement)
            if statement:find('FROM `ox_doorlock`', 1, true) then return { { id = 42, name = 'Imported', data = 'ox-row' } } end
            return {}
        end,
        execute = function() return 1 end,
        update = function() return 1 end,
    },
}

exports = setmetatable({
    qbcore = {
        getPlayer = function() end,
        getItemsByName = function() return {} end,
        removeItem = function() return false end,
    },
}, { __call = function(_, name, callback) exported[name] = callback end })

function GetCurrentResourceName() return 'qbdoorlock' end
function GetInvokingResource() return nil end
function AddEventHandler() end
function TriggerEvent() end
function CreateThread(callback) callback() end
function Wait() end
function LoadResourceFile(_, path)
    local file = assert(io.open(path, 'r'))
    local value = file:read('*a')
    file:close()
    return value
end

dofile('server/main.lua')

Harness.test('persistent exports create, edit, and remove doors', function()
    local id = exported.createDoor({
        id = 'Lobby', name = 'Lobby', model = 10, coords = vector3(0, 0, 0), state = 0,
        maxDistance = 2.5, auto = true, autolock = 5,
    })
    Harness.equal(id, 'lobby')
    Harness.equal(exported.getDoor(id).locked, false)
    Harness.ok(exported.editDoor(id, { name = 'Reception', state = 1, auto = false, maxDistance = 4, autolock = 9 }))
    local edited = exported.getDoor(id)
    Harness.equal(edited.name, 'Reception')
    Harness.equal(edited.state, 1)
    Harness.equal(edited.maxDistance, 4)
    Harness.equal(edited.definition.automatic, false)
    Harness.equal(edited.definition.autoLock, 9000)
    Harness.ok(exported.removeDoor(id))
    Harness.equal(exported.getDoor(id), false)
end)

Harness.test('management persists double doors and validates their geometry', function()
    local snapshot, err = callbacks['qbdoorlock:server:managementDoorSaved'](1, 'front', {
        label = 'Front', locked = true,
        doors = {
            { model = 11, coords = vector3(0, 0, 0), heading = 90 },
            { model = 12, coords = vector3(2, 0, 0), heading = 270 },
        },
    }, true)
    Harness.ok(snapshot, err)
    Harness.equal(snapshot[1].leaves, 2)
end)

Harness.test('ox database import normalizes existing definitions', function()
    local imported, skipped = exported.importOxDoors()
    Harness.equal(imported, 1)
    Harness.equal(skipped, 0)
    local door = exported.getDoor('ox-42')
    Harness.equal(door.name, 'Imported')
    Harness.equal(door.state, 1)
    Harness.equal(door.maxDistance, 3)
    Harness.equal(door.definition.autoLock, 12000)
end)

if Harness.failures > 0 then os.exit(1) end
print(('%d database tests passed'):format(Harness.tests))
