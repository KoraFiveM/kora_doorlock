local doors = {}
local nearbyDoor
local prompt

local function notify(message, type)
    QB.notify.send({ title = 'Door lock', message = message, type = type or 'info' })
end

local function doorLeaves(door)
    if door.doors then return door.doors end
    return { { model = door.model, coords = door.coords } }
end

local function doorHash(id, index)
    return joaat(('qbdoorlock:%s:%s'):format(id, index))
end

local function applyDoor(id, locked)
    local door = doors[id]
    if not door then return end

    door.locked = locked == true
    for index, leaf in ipairs(doorLeaves(door)) do
        local hash = doorHash(id, index)
        AddDoorToSystem(hash, leaf.model, leaf.coords.x, leaf.coords.y, leaf.coords.z, false, false, false)
        DoorSystemSetDoorState(hash, door.locked and 1 or 0, false, true)
    end

    if nearbyDoor == id and prompt then
        QB.textui.update(prompt, door.locked and ('Unlock %s'):format(door.label) or ('Lock %s'):format(door.label), {
            key = 'E', icon = door.locked and 'Lock' or 'Unlock', position = 'right-center',
        })
    end
end

local function setupDoor(id, definition)
    assert(type(id) == 'string', 'qbdoorlock door IDs must be strings.')
    assert(type(definition) == 'table' and type(definition.label) == 'string', ('Door %s needs a label.'):format(id))
    assert((definition.model and definition.coords) or type(definition.doors) == 'table', ('Door %s needs model/coords or doors.'):format(id))

    definition.locked = definition.locked == true
    definition.distance = definition.distance or Config.InteractionDistance
    doors[id] = definition

    local coords = definition.coords or definition.doors[1].coords
    QB.zones.point({
        coords = coords,
        radius = definition.distance,
        debug = Config.Debug,
        onEnter = function()
            nearbyDoor = id
            prompt = QB.textui.show(definition.locked and ('Unlock %s'):format(definition.label) or ('Lock %s'):format(definition.label), {
                key = 'E', icon = definition.locked and 'Lock' or 'Unlock', position = 'right-center',
            })
        end,
        onExit = function()
            if nearbyDoor == id then nearbyDoor = nil end
            if prompt then QB.textui.hide(prompt); prompt = nil end
        end,
    })
    applyDoor(id, definition.locked)
end

RegisterNetEvent('qbdoorlock:client:sync', applyDoor)

RegisterNetEvent('qbdoorlock:client:states', function(serverStates)
    if type(serverStates) ~= 'table' then return end
    for id, locked in pairs(serverStates) do applyDoor(id, locked) end
end)

RegisterNetEvent('qbdoorlock:client:denied', function(reason)
    notify(reason or 'You do not have access to this door.', 'error')
end)

QB.keybind.add({
    name = 'qbdoorlock_toggle',
    description = 'Lock or unlock the nearby door',
    defaultKey = 'E',
    defaultMapper = 'keyboard',
    onPressed = function()
        if nearbyDoor then TriggerServerEvent('qbdoorlock:server:toggle', nearbyDoor) end
    end,
})

CreateThread(function()
    for id, definition in pairs(Config.Doors) do setupDoor(id, definition) end
    TriggerServerEvent('qbdoorlock:server:requestStates')
end)

exports('getDoorState', function(id)
    return doors[id] and doors[id].locked or nil
end)
