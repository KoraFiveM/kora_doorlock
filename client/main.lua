local doors = {}
local nearbyDoor
local prompt
local APP_ID = 'qbdoorlock:management'
local managementSnapshotData
local managementClosestFirst = false

local function notify(message, type)
    QB.notify.send({ title = 'Door lock', message = message, type = type or 'info' })
end

local function targetedDoor()
    local hit, _, entity = QB.raycast.fromCamera(6.0)
    if not hit or not entity or entity == 0 or GetEntityType(entity) ~= 3 then return nil end
    local coords = GetEntityCoords(entity)
    return { model = GetEntityModel(entity), coords = { x = coords.x, y = coords.y, z = coords.z } }
end

local function createTargetedDoor()
    local target = targetedDoor()
    if not target then return notify('Look directly at a map door within 6 metres, then try again.', 'error') end
    local result = QB.nui.openInputDialog({
        { id = 'id', label = 'Door ID', type = 'text', required = true, placeholder = 'e.g. city-hall-office', maxLength = 64 },
        { id = 'label', label = 'Door name', type = 'text', required = true, placeholder = 'e.g. City Hall Office', maxLength = 64 },
        { id = 'locked', label = 'Starts locked', type = 'checkbox', default = true },
        { id = 'group', label = 'Allowed job or gang (optional)', type = 'text', placeholder = 'e.g. police' },
        { id = 'grade', label = 'Minimum grade', type = 'number', min = 0, default = 0, dependsOn = 'group' },
        { id = 'autoLock', label = 'Auto-lock after seconds (optional; 0 disables)', type = 'number', min = 0, max = 3600 },
    }, 'Create door lock', 'The selected map door will be saved immediately and synchronized to every player.')
    if not result or result.cancelled or type(result.values) ~= 'table' then return end

    local data = result.values
    data.model, data.coords = target.model, target.coords
    CreateThread(function()
        local ok, snapshot, err = pcall(QB.callback.trigger, 'qbdoorlock:managementCreateDoor', data)
        if not ok then return notify(('Door creation failed: %s'):format(tostring(snapshot)), 'error') end
        if not snapshot then return notify(err or 'Could not create the door.', 'error') end
        managementSnapshotData = snapshot
        notify('Door created and saved.', 'success')
    end)
end

local function doorLeaves(door)
    if door.doors then return door.doors end
    return { { model = door.model, coords = door.coords } }
end

local function asVector3(coords)
    if type(coords) ~= 'table' then return coords end
    return vector3(coords.x, coords.y, coords.z)
end

local function normaliseDefinition(definition)
    if definition.coords then definition.coords = asVector3(definition.coords) end
    if definition.doors then
        for _, leaf in ipairs(definition.doors) do leaf.coords = asVector3(leaf.coords) end
    end
    return definition
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

    definition = normaliseDefinition(definition)
    if doors[id] then return end
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

RegisterNetEvent('qbdoorlock:client:addDoor', function(id, definition, locked)
    if type(id) ~= 'string' or type(definition) ~= 'table' then return end
    definition.locked = locked == true
    setupDoor(id, definition)
end)

RegisterNetEvent('qbdoorlock:client:definitions', function(definitions, serverStates)
    if type(definitions) ~= 'table' then return end
    for id, definition in pairs(definitions) do
        if type(id) == 'string' and type(definition) == 'table' then
            definition.locked = type(serverStates) == 'table' and serverStates[id] == true or definition.locked
            setupDoor(id, definition)
        end
    end
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
    TriggerServerEvent('qbdoorlock:server:requestDefinitions')
end)

-- Door controls are rendered by qblib's shared AppShell. The client only
-- presents the snapshot; the server re-checks staff permission for every
-- refresh and mutation.
local function managementDefinition(snapshot, closestFirst, asUpdate)
    local rows, linkedLabels, lockedCount = {}, {}, 0
    for _, door in ipairs(snapshot) do linkedLabels[door.id] = door.label end
    local playerCoords = GetEntityCoords(PlayerPedId())
    for _, door in ipairs(snapshot) do
        if door.locked then lockedCount = lockedCount + 1 end
        local definition = doors[door.id]
        local doorCoords = definition and (definition.coords or (definition.doors and definition.doors[1] and definition.doors[1].coords))
        local distance = doorCoords and #(playerCoords - doorCoords) or math.huge
        rows[#rows + 1] = {
            id = door.id,
            label = door.label,
            description = ('%s · %s · %s'):format(
                door.locked and 'Locked' or 'Unlocked',
                door.leaves > 1 and ('%d leaves'):format(door.leaves) or 'Single door',
                door.autoLock and ('Auto-lock: %d sec'):format(math.floor(door.autoLock / 1000)) or 'Auto-lock: off'
            ),
            icon = door.leaves > 1 and 'DoorOpen' or 'DoorClosed',
            tone = door.locked and 'warning' or 'success',
            metadata = {
                { label = 'Distance', value = distance < math.huge and ('%.1f m'):format(distance) or 'Unknown' },
                { label = 'Linked door', value = door.linkedTo and (linkedLabels[door.linkedTo] or door.linkedTo) or 'None' },
            },
            distance = distance,
            data = { linkedTo = door.linkedTo },
        }
    end
    if closestFirst then
        table.sort(rows, function(a, b) return a.distance < b.distance end)
    end
    for _, row in ipairs(rows) do
        row.actions = {
            { id = 'doorlock:toggle', label = row.tone == 'warning' and 'Unlock' or 'Lock', icon = row.tone == 'warning' and 'Unlock' or 'Lock', variant = 'secondary' },
        }
        if row.data.linkedTo then
            row.actions[#row.actions + 1] = {
                id = 'doorlock:unlink', label = 'Unlink double door', icon = 'Unlink', variant = 'outline',
                confirm = 'The two doors will no longer change state together.',
            }
        else
            local options = {}
            for _, candidate in ipairs(snapshot) do
                if candidate.id ~= row.id and not candidate.linkedTo then
                    options[#options + 1] = { value = candidate.id, label = candidate.label }
                end
            end
            row.actions[#row.actions + 1] = {
                id = 'doorlock:link', label = 'Link double door', icon = 'Link', variant = 'primary', disabled = #options == 0,
                fields = { { id = 'linkedDoorId', label = 'Link with', type = 'select', required = true, options = options } },
                confirm = 'Both doors will lock and unlock together.',
            }
        end
    end

    local app = {
        title = 'Door Lock Control',
        description = 'Live server-authoritative door status',
        icon = 'LockKeyhole',
        -- Deliberately omit an app-specific accent so the management shell
        -- retains the effective qbtheme colour selected by this player.
        defaultView = 'doors',
        footer = 'All changes are synchronized to every player.',
        navigation = {
            {
                id = 'doors', label = 'Doors', icon = 'DoorOpen',
                content = {
                    title = 'Configured doors',
                    description = 'Manage the current lock state. Door access rules still apply to normal player interaction.',
                    actions = {
                        { id = 'doorlock:create', label = 'Create targeted door', icon = 'Plus', variant = 'primary' },
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
                            id = 'door-list', type = 'list', title = 'Door states', searchable = true,
                            searchPlaceholder = 'Search doors…', pageSize = 12, layout = 'cards',
                            items = rows,
                            empty = 'No doors configured. Use /adddoor while looking at a map door.',
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
            elseif actionId == 'doorlock:create' then
                QB.nui.closeApp(APP_ID)
                createTargetedDoor()
                return { notice = { tone = 'success', message = 'Use /adddoor while looking at the door you want to add.' } }
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
            elseif actionId == 'doorlock:link' and context and type(context.itemId) == 'string' and type(context.value) == 'table' then
                updated, err = QB.callback.trigger('qbdoorlock:managementLinkDoors', context.itemId, context.value.linkedDoorId)
            elseif actionId == 'doorlock:unlink' and context and type(context.itemId) == 'string' then
                updated, err = QB.callback.trigger('qbdoorlock:managementUnlinkDoors', context.itemId)
            else
                error('That door action is no longer available.')
            end
            if not updated then error(err or 'The door lock service did not answer.') end
            managementSnapshotData = updated
            return { update = managementDefinition(updated, managementClosestFirst, true), notice = { tone = 'success', message = 'Door lock updated.' } }
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
RegisterCommand(Config.CreateCommand or 'adddoor', createTargetedDoor, false)

exports('getDoorState', function(id)
    return doors[id] and doors[id].locked or nil
end)
