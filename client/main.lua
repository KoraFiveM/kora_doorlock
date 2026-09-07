local doors = {}
local nearbyDoor
local prompt
local APP_ID = 'qbdoorlock:management'
local managementSnapshotData
local managementClosestFirst = false

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

-- Door controls are rendered by qblib's shared AppShell. The client only
-- presents the snapshot; the server re-checks staff permission for every
-- refresh and mutation.
local function managementDefinition(snapshot, closestFirst, asUpdate)
    local rows, lockedCount = {}, 0
    local playerCoords = GetEntityCoords(PlayerPedId())
    for _, door in ipairs(snapshot) do
        if door.locked then lockedCount = lockedCount + 1 end
        local definition = doors[door.id]
        local doorCoords = definition and (definition.coords or (definition.doors and definition.doors[1] and definition.doors[1].coords))
        local distance = doorCoords and #(playerCoords - doorCoords) or math.huge
        rows[#rows + 1] = {
            id = door.id,
            name = door.label,
            status = { label = door.locked and 'Locked' or 'Unlocked', badge = true, tone = door.locked and 'warning' or 'success' },
            type = door.leaves > 1 and ('%d doors'):format(door.leaves) or 'Single door',
            autoLock = door.autoLock and ('%d sec'):format(math.floor(door.autoLock / 1000)) or 'Off',
            distance = distance,
            distanceLabel = distance < math.huge and ('%.1f m'):format(distance) or 'Unknown',
        }
    end
    if closestFirst then
        table.sort(rows, function(a, b) return a.distance < b.distance end)
    end

    local app = {
        title = 'Door Lock Control',
        description = 'Live server-authoritative door status',
        icon = 'LockKeyhole',
        accent = '#d97706',
        defaultView = 'doors',
        footer = 'All changes are synchronized to every player.',
        navigation = {
            {
                id = 'doors', label = 'Doors', icon = 'DoorOpen',
                content = {
                    title = 'Configured doors',
                    description = 'Manage the current lock state. Door access rules still apply to normal player interaction.',
                    actions = {
                        { id = 'doorlock:closest', label = 'Closest to me', icon = 'MapPin', variant = closestFirst and 'primary' or 'secondary' },
                        { id = 'doorlock:refresh', label = 'Refresh', icon = 'RefreshCw', variant = 'secondary' },
                    },
                    blocks = {
                        { type = 'stats', items = {
                            { label = 'Configured', value = #snapshot, icon = 'DoorOpen' },
                            { label = 'Locked', value = lockedCount, icon = 'Lock', tone = 'warning' },
                            { label = 'Unlocked', value = #snapshot - lockedCount, icon = 'Unlock', tone = 'success' },
                        } },
                        {
                            id = 'door-list', type = 'table', title = 'Door states', searchable = true, action = 'doorlock:toggle', idKey = 'id',
                            searchPlaceholder = 'Search doors…', pageSize = 12,
                            columns = {
                                { key = 'name', label = 'Door' }, { key = 'status', label = 'Status' },
                                { key = 'distanceLabel', label = 'Distance' }, { key = 'type', label = 'Type' },
                                { key = 'autoLock', label = 'Auto-lock' },
                            },
                            rows = rows,
                            empty = 'No doors configured. Add a door to qbdoorlock/config.lua and restart this resource.',
                        },
                    },
                },
            },
        },
    }

    if not asUpdate then
        app.id = APP_ID
        app.onAction = function(actionId, context)
            local updated, err
            if actionId == 'doorlock:refresh' then
                updated, err = QB.callback.trigger('qbdoorlock:managementSnapshot')
            elseif actionId == 'doorlock:closest' then
                managementClosestFirst = true
                return { update = managementDefinition(managementSnapshotData or snapshot, true, true), notice = { tone = 'success', message = 'Doors sorted by your current distance.' } }
            elseif actionId == 'doorlock:toggle' and context and type(context.itemId) == 'string' then
                local selected
                for _, door in ipairs(managementSnapshotData or snapshot) do
                    if door.id == context.itemId then selected = door; break end
                end
                if not selected then error('That door is no longer configured.') end
                updated, err = QB.callback.trigger('qbdoorlock:managementSetState', context.itemId, not selected.locked)
            else
                error('That door action is no longer available.')
            end
            if not updated then error(err or 'The door lock service did not answer.') end
            managementSnapshotData = updated
            return { update = managementDefinition(updated, managementClosestFirst, true), notice = { tone = 'success', message = 'Door status updated.' } }
        end
    end
    return app
end

local function openManagement()
    CreateThread(function()
        local snapshot, err = QB.callback.trigger('qbdoorlock:managementSnapshot')
        if not snapshot then return notify(err or 'The door lock service did not answer.', 'error') end
        managementSnapshotData = snapshot
        managementClosestFirst = false
        QB.nui.registerApp(managementDefinition(snapshot, false))
        QB.nui.openApp(APP_ID)
    end)
end

RegisterCommand(Config.AdminCommand or 'doorlocks', openManagement, false)

exports('getDoorState', function(id)
    return doors[id] and doors[id].locked or nil
end)
