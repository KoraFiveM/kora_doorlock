local doors, activeDoors, streamedDoors, entityDoors = {}, {}, {}, {}
local targetModels, pendingTargetModels = {}, {}
local nearbyDoor, prompt, pickingLock, lockpickTarget
local toggleBinding, activeSelection
local SELECT_CONTROLS = { 38, 177 } -- E confirms, Backspace cancels, like QB.raycast.getCoords
local spriteDicts = {}

local function translate(key, replacements)
    return QB.lang(key, replacements)
end

local function notify(message, notificationType)
    QB.notify.send({ title = translate('title'), message = message, type = notificationType or 'info' })
end

local function doorLeaves(door)
    return door.doors or { { model = door.model, coords = door.coords, heading = door.heading } }
end

local function doorHash(id, index)
    return joaat(('qbdoorlock:%s:%s'):format(id, index))
end

local function doorDistance(door, position)
    local closest = math.huge
    for _, leaf in ipairs(doorLeaves(door)) do closest = math.min(closest, #(position - leaf.coords)) end
    return closest
end

local function stateText(door)
    return door.locked and 'unlock_door' or 'lock_door'
end

local function hidePrompt()
    if prompt then QB.textui.hide(prompt); prompt = nil end
end

local function updatePrompt()
    local door = nearbyDoor and doors[nearbyDoor]
    if not door or door.hideUi or not Config.DrawTextUI then return hidePrompt() end
    local options = { key = 'E', icon = door.locked and 'Lock' or 'Unlock', position = 'right-center' }
    if prompt then QB.textui.update(prompt, stateText(door), options)
    else prompt = QB.textui.show(stateText(door), options) end
end

local function clearDoorEntities(door)
    if not door or not door.entities then return end
    for _, entity in pairs(door.entities) do
        entityDoors[entity] = nil
        if DoesEntityExist(entity) then
            pcall(function()
                Entity(entity).state:set('qbdoorlock:id', false, false)
                Entity(entity).state:set('doorId', false, false)
            end)
        end
    end
    door.entities = {}
end

local function removeDoor(id)
    local door = doors[id]
    if not door then return end
    if door.interactionZone then door.interactionZone.remove() end
    if door.streamZone then door.streamZone.remove() end
    clearDoorEntities(door)
    for index = 1, #doorLeaves(door) do RemoveDoorFromSystem(doorHash(id, index)) end
    activeDoors[id], streamedDoors[id], doors[id] = nil, nil, nil
    if nearbyDoor == id then nearbyDoor = nil; hidePrompt() end
end

local function playDoorSound(door, locked)
    local fallback = Config.DefaultSounds and Config.DefaultSounds[locked and 'locked' or 'unlocked'] or nil
    local name = locked and door.lockSound or door.unlockSound
    local set = locked and door.lockSoundSet or door.unlockSoundSet
    name, set = name or (fallback and fallback.name), set or (fallback and fallback.set)
    if name and set then QB.sound.playFromCoords(door.coords, name, set, { range = 20.0, releaseAfter = 3000 }) end
end

local function applyState(id, locked, source, silent)
    local door = doors[id]
    if not door then return end
    local changed = door.locked ~= (locked == true)
    door.locked = locked == true
    door.state = door.locked and 1 or 0
    for index in ipairs(doorLeaves(door)) do
        local hash = doorHash(id, index)
        DoorSystemSetDoorState(hash, door.locked and 1 or 0, false, false)
        if door.holdOpen then DoorSystemSetHoldOpen(hash, not door.locked) end
    end
    if changed and not silent and QB.distance.player(door.coords, 20.0) then playDoorSound(door, door.locked) end
    if nearbyDoor == id then updatePrompt() end

    if door.locked then
        CreateThread(function()
            local deadline = GetGameTimer() + 5000
            while GetGameTimer() < deadline do
                local closed = true
                for index in ipairs(doorLeaves(door)) do if not IsDoorClosed(doorHash(id, index)) then closed = false; break end end
                if closed then return end
                Wait(0)
            end
        end)
    end
end

local function getDoorIdFromEntity(entity)
    if type(entity) ~= 'number' or entity == 0 then return nil end
    if entityDoors[entity] then return entityDoors[entity] end
    local ok, state = pcall(function() return Entity(entity).state end)
    local id = ok and state and (state['qbdoorlock:id'] or state.doorId) or nil
    return type(id) == 'string' and id or nil
end

local function canTargetLockpick(entity)
    local id = getDoorIdFromEntity(entity)
    local door = id and doors[id]
    if not door or pickingLock or not door.lockpick or (not Config.CanPickUnlockedDoors and not door.locked) then return false end
    lockpickTarget = id
    return true
end

local function pickDoor(id)
    if pickingLock then return false end
    local door = id and doors[id]
    if not door or not door.lockpick or (not Config.CanPickUnlockedDoors and not door.locked) then return false end
    pickingLock = true
    CreateThread(function()
        local authorization, err = QB.callback.trigger('qbdoorlock:server:lockpickStarted', id)
        if not authorization then pickingLock = false; return notify(err or translate('cannot_pick'), 'error') end
        local playerPed = QB.cache.ped()
        TaskTurnPedToFaceCoord(playerPed, door.coords.x, door.coords.y, door.coords.z, 1000)
        Wait(400)
        local animation = QB.anim.play(playerPed, 'mp_common_heist', 'pick_door', {
            blendInSpeed = 3.0, blendOutSpeed = 1.0, flag = 49,
        })
        local result = QB.minigames.play('lockpick', nil, authorization)
        if animation then QB.anim.stopHandle(animation, 0) end
        QB.events.trigger('qbdoorlock:server:lockpickFinished', id, authorization, result and result.proof or nil)
        if not result or not result.success then notify(translate('lock_resisted'), 'error') end
        pickingLock = false
    end)
    return true
end

local function registerTargetModel(model)
    if targetModels[model] or GetResourceState('qbtarget') ~= 'started' then pendingTargetModels[model] = true; return end
    local ok, targetId = pcall(QB.interact.addModel, model, {
        {
            label = translate('pick_lock'), icon = 'LockKeyhole', distance = 1.5,
            canInteract = function(entity) return canTargetLockpick(entity) end,
            action = function() if lockpickTarget then pickDoor(lockpickTarget) end end,
        },
    }, 1.5)
    if ok then targetModels[model], pendingTargetModels[model] = targetId, nil
    else pendingTargetModels[model] = true end
end

local function registerPendingTargets()
    for model in pairs(pendingTargetModels) do registerTargetModel(model) end
end

local function setupDoor(id, raw, locked)
    local door, err = DoorlockSchema.normalize(raw, Config.InteractionDistance)
    if not door then return print(('^3[qbdoorlock]^7 rejected client door %s: %s'):format(tostring(id), err)) end
    removeDoor(id)
    door.id, door.locked, door.state, door.maxDistance, door.entities = id, locked == true, locked and 1 or 0, door.distance, {}
    doors[id] = door
    for index, leaf in ipairs(doorLeaves(door)) do
        local hash = doorHash(id, index)
        AddDoorToSystem(hash, leaf.model, leaf.coords.x, leaf.coords.y, leaf.coords.z, false, false, false)
        DoorSystemSetDoorState(hash, 4, false, false)
        DoorSystemSetDoorState(hash, door.locked and 1 or 0, false, false)
        if door.doorRate or not door.automatic then DoorSystemSetAutomaticRate(hash, door.doorRate or 10.0, false, false) end
        if door.holdOpen then DoorSystemSetHoldOpen(hash, not door.locked) end
        pendingTargetModels[leaf.model] = true
    end
    door.interactionZone = QB.zones.point({
        coords = door.coords, radius = door.distance, debug = Config.Debug,
        onEnter = function() activeDoors[id] = true end,
        onExit = function() activeDoors[id] = nil; if nearbyDoor == id then nearbyDoor = nil; hidePrompt() end end,
    })
    door.streamZone = QB.zones.point({
        coords = door.coords, radius = 80.0, debug = false,
        onEnter = function() streamedDoors[id] = true end,
        onExit = function() streamedDoors[id] = nil; clearDoorEntities(door) end,
    })
    registerPendingTargets()
end

local function targetedLeaf()
    local hit, _, entity = QB.raycast.fromCamera(6.0)
    if not hit or not entity or entity == 0 or GetEntityType(entity) ~= 3 then return nil end
    if getDoorIdFromEntity(entity) then return nil end
    local coords = GetEntityCoords(entity)
    return { entity = entity, model = GetEntityModel(entity), coords = { x = coords.x, y = coords.y, z = coords.z }, heading = GetEntityHeading(entity) }
end

local function releaseSelection(state)
    if state.released then return end
    state.released = true
    if activeSelection == state then activeSelection = nil end
    if state.highlighted and DoesEntityExist(state.highlighted) then SetEntityDrawOutline(state.highlighted, false) end
    state.highlighted = nil
    if state.hint then pcall(QB.textui.hide, state.hint) end
    toggleBinding.disable(false)
end

-- Blocks until the player confirms the map door under the crosshair with E, or
-- cancels with Backspace (returns nil). The door is found with QB.raycast and
-- outlined while aimed at. `first` is a leaf already chosen, so a double door
-- cannot pick the same leaf twice. `hintText` replaces the default prompt text.
local function selectLeaf(first, promptKey, hintText)
    if activeSelection then return nil end
    local state = {}
    activeSelection = state
    toggleBinding.disable(true)
    state.hint = QB.textui.show(('%s  ·  **E:** confirm  ·  **Backspace:** cancel'):format(hintText or translate(promptKey or 'select_second')),
        { icon = 'DoorOpen' })

    local ok, result = pcall(function()
        while activeSelection == state do
            local leaf = targetedLeaf()
            if leaf and first and leaf.entity == first.entity then leaf = nil end

            if leaf and state.highlighted ~= leaf.entity then
                if state.highlighted and DoesEntityExist(state.highlighted) then SetEntityDrawOutline(state.highlighted, false) end
                state.highlighted = leaf.entity
                SetEntityDrawOutlineColor(255, 255, 255, 255)
                SetEntityDrawOutline(leaf.entity, true)
            elseif not leaf and state.highlighted then
                if DoesEntityExist(state.highlighted) then SetEntityDrawOutline(state.highlighted, false) end
                state.highlighted = nil
            end

            for _, control in ipairs(SELECT_CONTROLS) do DisableControlAction(0, control, true) end
            if IsDisabledControlJustReleased(0, 177) then return nil end
            if leaf and IsDisabledControlJustReleased(0, 38) then return leaf end
            Wait(0)
        end
        return nil
    end)
    releaseSelection(state)
    if not ok then error(result, 0) end
    return result
end

-- The creator (client/creator.lua) is a separate script, so it reaches the door
-- runtime through this one table instead of sharing locals.
DoorlockClient = {
    notify = notify,
    translate = translate,
    targetedLeaf = targetedLeaf,
    selectLeaf = selectLeaf,
    distanceTo = function(id, position)
        local door = doors[id]
        return door and doorDistance(door, position) or math.huge
    end,
}

QB.callback.register('qbdoorlock:client:passcodeRequested', function(label)
    local result = QB.nui.openInputDialog({ { id = 'passcode', label = 'Passcode', type = 'password', required = true, maxLength = 128 } }, label or 'Door lock')
    return result and not result.cancelled and result.values and result.values.passcode or nil
end)

QB.events.onPush('qbdoorlock:client:doorStateChanged', function(id, locked, source) applyState(id, locked, source, false) end)
QB.events.onPush('qbdoorlock:client:doorDefinitionUpdated', function(id, definition, locked) setupDoor(id, definition, locked) end)
QB.events.onPush('qbdoorlock:client:doorDefinitionRemoved', removeDoor)
QB.events.onPush('qbdoorlock:client:teleported', function(coords) QB.teleport.player(coords) end)

toggleBinding = QB.keybind.add({
    name = 'qbdoorlock_toggle', description = 'Lock or unlock the nearby door', defaultKey = 'E', defaultMapper = 'keyboard',
    onPressed = function() if nearbyDoor then QB.events.trigger('qbdoorlock:server:doorToggled', nearbyDoor) end end,
})

CreateThread(function()
    local spriteConfig = Config.DrawSprite
    if spriteConfig then
        for _, sprite in pairs(spriteConfig) do
            if sprite.dict and QB.stream.loadTextureDict(sprite.dict) then spriteDicts[sprite.dict] = true end
        end
    end
    local definitions, serverStates = QB.callback.trigger('qbdoorlock:server:doorsRequested')
    if type(definitions) ~= 'table' then return notify(translate('definitions_failed'), 'error') end
    for id, definition in pairs(definitions) do setupDoor(id, definition, type(serverStates) == 'table' and serverStates[id] == true) end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if activeSelection then releaseSelection(activeSelection) end
    for dictionary in pairs(spriteDicts) do SetStreamedTextureDictAsNoLongerNeeded(dictionary) end
end)

CreateThread(function()
    while true do
        local position = GetEntityCoords(PlayerPedId())
        local closestId, closestDistance
        for id in pairs(activeDoors) do
            local door = doors[id]
            if door then
                local distance = doorDistance(door, position)
                if distance <= door.distance and (not closestDistance or distance < closestDistance) then closestId, closestDistance = id, distance end
                if not door.hideUi and Config.DrawSprite then
                    local sprite = Config.DrawSprite[door.locked and 'locked' or 'unlocked']
                    if sprite then
                        local color = sprite.color or { 255, 255, 255, 100 }
                        SetDrawOrigin(door.coords.x, door.coords.y, door.coords.z, 0)
                        DrawSprite(sprite.dict, sprite.name, 0.0, 0.0, sprite.width or 0.018, (sprite.height or 0.018) * GetAspectRatio(true), 0.0, color[1], color[2], color[3], color[4])
                        ClearDrawOrigin()
                    end
                end
            end
        end
        if nearbyDoor ~= closestId then nearbyDoor = closestId; updatePrompt() end
        Wait(next(activeDoors) and 0 or 200)
    end
end)

CreateThread(function()
    while true do
        for id in pairs(streamedDoors) do
            local door = doors[id]
            if door then
                for index, leaf in ipairs(doorLeaves(door)) do
                    local entity = door.entities[index]
                    if not entity or not DoesEntityExist(entity) then
                        if entity then entityDoors[entity] = nil end
                        entity = QB.world.getClosestEntity('object', leaf.coords, {
                            radius = 1.0, models = { leaf.model }, includeInvisible = true,
                        })
                        if entity then
                            door.entities[index], entityDoors[entity] = entity, id
                            pcall(function()
                                Entity(entity).state:set('qbdoorlock:id', id, false)
                                Entity(entity).state:set('doorId', id, false)
                            end)
                        end
                    end
                end
            end
        end
        Wait(next(streamedDoors) and 500 or 1000)
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName) if resourceName == 'qbtarget' then registerPendingTargets() end end)

---@param id string
---@return boolean? locked
exports('getDoorState', function(id)
    local door = doors[id]
    if not door then return nil end
    return door.locked
end)

---@return string? id
exports('getClosestDoorId', function() return nearbyDoor end)

---@return QBDoorlockDefinition? door
exports('getClosestDoor', function() return nearbyDoor and doors[nearbyDoor] or nil end)

---@param entity integer
---@return string? id
exports('getDoorIdFromEntity', getDoorIdFromEntity)

---@return boolean used
exports('useClosestDoor', function()
    if not nearbyDoor then return false end
    QB.events.trigger('qbdoorlock:server:doorToggled', nearbyDoor)
    return true
end)

---@return boolean started
exports('pickClosestDoor', function() return pickDoor(nearbyDoor) end)
