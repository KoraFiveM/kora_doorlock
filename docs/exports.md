---
title: Exports
sidebar_position: 8
---

# Exports

## Server

```lua
local door = exports.kora_doorlock:getDoor('city-hall-office')       -- table or false; accepts an ID or a table with id
local door = exports.kora_doorlock:getDoorFromName('City Hall Office') -- by label, or nil
local all = exports.kora_doorlock:getAllDoors()                       -- sorted by id
local locked = exports.kora_doorlock:getDoorState('city-hall-office') -- true, false or nil

exports.kora_doorlock:setDoorState('city-hall-office', false)         -- true/false/0/1, returns boolean
exports.kora_doorlock:editDoor('city-hall-office', { autoLock = 30000 })
local id = exports.kora_doorlock:createDoor(definition)               -- id or false
local removed, err = exports.kora_doorlock:removeDoor(id)
local imported, skipped = exports.kora_doorlock:importOxDoors()
```

| Export | Notes |
| --- | --- |
| `getDoor`, `getDoorFromName`, `getAllDoors` | Return `id`, `name`, `label`, `state`, `locked`, `coords`, `characters`, `citizenIds`, `groups`, `items`, `maxDistance`, `distance` and `definition` (without the passcode; `hasPasscode` is given instead). |
| `setDoorState` | Changes state and its linked door; fires `kora_doorlock:stateChanged` with no source. |
| `editDoor` | Patch is merged into the door, validated and saved. Accepts ox-style keys (`state`, `name`, `maxDistance`, `autolock` in seconds, `auto`). An empty string clears a field. Returns false if invalid or the database is not ready. |
| `createDoor` | Validated and saved. Uses `definition.id` if valid, otherwise an ID made from the label. Fails if the ID exists. |
| `removeDoor` | Deletes a door (tombstone for configured ones). |
| `importOxDoors` | Returns the imported and skipped counts, or `nil` and an error. |
| `registerHook`, `removeHook` | See [Access and permissions](./permissions.md). `removeHook` only works for the resource that registered it. |
| `RegisterDoorPolicy(id, callback)`, `ClearDoorPolicy(id)`, `ReleaseDoorPolicy(id)` | Door policies. Return `true`, or `false` and an error. |

`createDoor`, `editDoor` and `removeDoor` fail until the database is ready, see [Installation](./installation.md).

## Client

```lua
exports.kora_doorlock:useClosestDoor()      -- request a toggle of the closest door; returns boolean
exports.kora_doorlock:pickClosestDoor()     -- start lockpicking; returns boolean started
local door = exports.kora_doorlock:getClosestDoor()
local id = exports.kora_doorlock:getClosestDoorId()
local id = exports.kora_doorlock:getDoorIdFromEntity(entity)
local locked = exports.kora_doorlock:getDoorState('city-hall-office')
```

Door objects that this resource has found also carry the state bag keys `kora_doorlock:id` and `doorId`.

The `qb-doorlock` compatibility exports are listed in [Compatibility](./compatibility.md).
