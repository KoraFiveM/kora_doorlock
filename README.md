# qbdoorlock

A server-authoritative, qblib-native door lock resource with the feature set of
`ox_doorlock`. It supports single and double doors, persistent in-game editing,
passcodes, jobs and gangs, character IDs, metadata-aware key items, consumable
keys, lockpicking, per-door ACEs, automatic doors, movement rates, hold-open,
hidden indicators, sounds, and auto-locking.

qblib owns the resource's commands, permissions, protected events, callbacks,
minigames, targeting facade, keybinds, zones, raycasts, streaming, sounds, UI,
notifications, timers, configuration, and SQL. qbcore is used only for player,
job, gang, and inventory data, which are framework domains qblib intentionally
does not own.

## Install

The test server already starts `qbdoorlock` after `qblib`, `qbsql`, and
`qbcore`. The database tables are created through qbsql migrations at startup.

`qbtarget` is optional. If it starts, lockpickable door objects receive a
qblib interaction option. The `pickClosestDoor` client export remains available
without a target resource.

## Door management

Players with the permission selected by `Config.AdminPermission` and
`Config.AdminPermissionPrefix` (`qbcore.admin` by default) can use:

- `/doorlocks` (or `/doorlocks closest`) to search and sort doors, inspect state and access settings,
  lock/unlock, edit, retarget as a single or double door, duplicate, teleport,
  link states, unlink, or delete.
- `/adddoor` to capture the map door under the crosshair and configure every
  supported setting. For a double door, press E on the second leaf or X to
  cancel after completing the form.
- `/importoxdoors` to import an existing `ox_doorlock` database table. Imported
  IDs use the stable `ox-<number>` form; existing IDs are skipped.

Doors created or edited in-game are persistent. Editing a door authored in
`Config.Doors` creates a database override; deleting one creates a persistent
tombstone, so it does not reappear from config after a restart.

## Configuration

The canonical qbdoorlock shape is:

```lua
Config.Doors['city-hall-office'] = {
    label = 'City Hall Office',
    model = `v_ilev_fib_door1`,
    coords = vector3(105.76, -742.03, 45.03),
    heading = 90.0,
    locked = true,
    distance = 1.8,
    groups = { government = 2, police = 0 },
    characters = { 'ABC12345' },
    items = {
        { name = 'office_keycard', metadata = { type = 'city-hall' } },
        { name = 'single_use_key', remove = true },
    },
    passcode = 'open sesame',
    autoLock = 10000, -- milliseconds
    automatic = false,
    doorRate = 1.0,
    holdOpen = false,
    hideUi = false,
    lockpick = true,
    lockpickDifficulty = {
        pinCount = 5,
        tolerance = 0.14,
        speed = 1.0,
        timeLimit = 15000,
        attempts = 1,
    },
    lockSound = 'Remote_Control_Close',
    lockSoundSet = 'PI_Menu_Sounds',
    unlockSound = 'Remote_Control_Open',
    unlockSoundSet = 'PI_Menu_Sounds',
}
```

A true double door uses exactly two leaves:

```lua
Config.Doors['city-hall-front'] = {
    label = 'City Hall Front',
    doors = {
        { model = `v_ilev_ph_door01`, coords = vector3(434.7, -983.2, 30.8), heading = 90.0 },
        { model = `v_ilev_ph_door01`, coords = vector3(434.7, -985.0, 30.8), heading = 270.0 },
    },
    locked = false,
    groups = { police = 0 },
}
```

Access methods are alternatives. A matching per-door ACE, character ID,
job/gang grade, key item, or passcode permits the action. A door without any
access rule is public. The server always rechecks access and distance.

For parity when importing definitions, these ox-style aliases are accepted:

- `name` → `label`
- `state = 0|1` → `locked = false|true`
- `maxDistance` → `distance`
- `autolock` in seconds → `autoLock` in milliseconds
- `auto` → `automatic`
- `citizenIds` → `characters`
- item `metadata = 'type'` → `metadata = { type = 'type' }`

ox-style difficulty arrays (`easy`, `medium`, `hard`, or custom
`areaSize`/`speedMultiplier` entries) are also accepted and translated onto
qblib's server-validated lockpick game. New definitions should use the native
qblib options shown above.

## ACE access

Grant one door by its stable ID (recommended) or its ox-compatible display
name:

```cfg
add_ace identifier.license:abc123 "doorlock.city-hall-office" allow
# Existing ox-style grants such as "doorlock.City Hall Office" also work.
```

When `Config.PlayerAceAuthorised` is enabled, the permission configured by
`Config.PlayerAcePermission` (default `command.doorlock`) can use every door.
Administrative editing remains restricted to the separately configured
administrative permission (`qbcore.admin` by default).

## APIs

Client exports:

```lua
exports.qbdoorlock:useClosestDoor()
exports.qbdoorlock:pickClosestDoor()
local door = exports.qbdoorlock:getClosestDoor()
local id = exports.qbdoorlock:getClosestDoorId()
local id = exports.qbdoorlock:getDoorIdFromEntity(entity)
local locked = exports.qbdoorlock:getDoorState('city-hall-office')
```

Server exports:

```lua
local door = exports.qbdoorlock:getDoor('city-hall-office')
local door = exports.qbdoorlock:getDoorFromName('City Hall Office')
local allDoors = exports.qbdoorlock:getAllDoors()

exports.qbdoorlock:setDoorState('city-hall-office', false) -- also accepts 0/1
exports.qbdoorlock:editDoor('city-hall-office', { autoLock = 30000 })
local id = exports.qbdoorlock:createDoor(definition)
exports.qbdoorlock:removeDoor(id)
local imported, skipped = exports.qbdoorlock:importOxDoors()
```

The local server event form is also available:

```lua
TriggerEvent('qbdoorlock:setState', 'city-hall-office', 0)
```

Listen for successful changes:

```lua
AddEventHandler('qbdoorlock:stateChanged', function(source, doorId, locked, usedItem)
    -- source is nil for server/auto-lock changes.
end)

AddEventHandler('qbdoorlock:loaded', function()
    -- Persistent definitions and links are ready.
end)
```

Authorization hooks can grant access for custom systems:

```lua
local hookId = exports.qbdoorlock:registerHook('doorAuthorization', function(payload)
    if payload.door.label == 'VIP Room' and isVip(payload.source) then return true end
end, { nameFilter = '^VIP' })

exports.qbdoorlock:removeHook(hookId)
```

## Tests

Run the plain-Lua suite from this resource directory:

```sh
test/run.sh
```
