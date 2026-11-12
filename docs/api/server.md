---
title: "Server exports and hooks"
sidebar_position: 2
---


# Server exports and hooks

The server is the only place a door’s lock state and access rules live. It keeps every door definition in memory (seeded from `Config.Doors` then overlaid with database rows from `kora_doorlock_doors`), answers two net events (`doorToggled`, `lockpickFinished`) and a handful of `Kora.callback` RPCs used by the client UI, and exposes the exports and hook API below for other resources.

Namespace: `exports.kora_doorlock` · Source: `server/main.lua, shared/schema.lua, shared/access.lua`

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Door ID | A permanent, stable string key. Authored in `Config.Doors`, or auto-generated from the label when created in-game or via `createDoor`. |
| policyOwner | The resource name that currently has exclusive, final-say authorisation over a door via `RegisterDoorPolicy`. Persisted with the door; cleared only by `ReleaseDoorPolicy`. `ClearDoorPolicy` or the owning resource stopping drops the callback and locks the door, but `policyOwner` stays set, so the door stays closed until the policy is registered again. |
| Linked doors | Two door IDs set to mirror each other’s lock state via the management UI (`kora_doorlock:server:managementDoorsLinked`). Stored in `kora_doorlock_links`. |
| Category | A named set of default door settings (access, lockpick, sounds, etc.) used by the creator to stamp out many similar doors quickly; purely an authoring convenience, never consulted for access. |

## Functions

Read/write accessors for door state and definitions, plus the hook and door-policy APIs other resources use to extend or take over access control.

### `exports.kora_doorlock:getDoorState(id)`

Reads the current lock state of a door.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | Door ID. |

**Returns**

- **locked** — `true`/`false`, or `nil` if no such door exists.

**Example**

```lua
local locked = exports.kora_doorlock:getDoorState('mission-row-armory')
```

### `exports.kora_doorlock:getDoor(id)`

Reads one door’s public snapshot, including its full access definition.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string \| table | Door ID, or a table with an `id` field (for drop-in compatibility with callers that pass a door object). |

**Returns**

- **door** — table with `id`, `name`/`label`, `state` (0/1), `locked`, `coords`, `characters`/`citizenIds`, `groups`, `items`, `maxDistance`/`distance`, plus `definition` (the full normalised door). `false` if the door does not exist.

**Example**

```lua
local door = exports.kora_doorlock:getDoor('mission-row-armory')
if door then print(door.label, door.locked) end
```

### `exports.kora_doorlock:getAllDoors()`

Returns every configured door’s public snapshot, sorted by ID.

**Parameters**



**Returns**

- **doors** — array of the same table shape as `getDoor`.

**Example**

```lua
for _, door in ipairs(exports.kora_doorlock:getAllDoors()) do print(door.id, door.locked) end
```

### `exports.kora_doorlock:getDoorFromName(name)`

Finds the first door whose label matches `name` exactly.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Exact door label. |

**Returns**

- **door** — same shape as `getDoor`, or `nil` if no door has that label.

**Example**

```lua
local door = exports.kora_doorlock:getDoorFromName('Mission Row Armory')
```

**Representative console output**

```text
Labels are not guaranteed unique; this returns the first match found while iterating.
```

### `exports.kora_doorlock:setDoorState(id, state)`

Forces a door’s lock state from code, bypassing every access check (groups/items/passcode/hooks). Also triggers the normal state-change event, sound and auto-lock timer logic.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | Door ID. |
| `state` | boolean \| 0 \| 1 | New locked state. |

**Returns**

- **changed** — `true` if the door exists and the state was applied; `false` for an invalid `state` value or unknown door.

**Example**

```lua
exports.kora_doorlock:setDoorState('mission-row-armory', true)
```

### `exports.kora_doorlock:editDoor(id, patch)`

Patches an existing door’s stored definition and persists it. Accepts both the native field names and a few legacy aliases (`state`→locked, `name`→label, `maxDistance`→distance, `autolock`→autoLock in seconds, `auto`→automatic). Setting a field to `''` clears it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | Door ID. |
| `patch` | table | Partial door definition; unspecified fields keep their current value. |

**Returns**

- **edited** — `true` on success; `false` if the door does not exist, `patch` is not a table, storage is not ready, or the merged definition fails schema validation.

**Example**

```lua
exports.kora_doorlock:editDoor('mission-row-armory', { groups = { police = 2 } })
```

**Representative console output**

```text
A change to `locked`/`state` also applies the new lock state immediately; any other change re-applies the door without changing its current lock state.
```

### `exports.kora_doorlock:createDoor(raw)`

Creates and persists a new door from code.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `raw` | table | A door definition (see Config.Doors shape). `raw.id` is used verbatim (lower-cased) if present and free, otherwise an ID is derived from the label. |

**Returns**

- **id** — the new door’s ID string, or `false` if `raw` is invalid, storage is not ready, the ID is already taken, or the schema rejects it.

**Example**

```lua
local id = exports.kora_doorlock:createDoor({ label = 'Back Office', model = `prop_door...`, coords = vector3(0,0,0), groups = { realestate = 0 } })
```

### `exports.kora_doorlock:removeDoor(id)`

Deletes a door (or marks it deleted if it came from `Config.Doors`, so a restart does not re-create it) and any link it has.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | Door ID. |

**Returns**

- **removed** — `true` on success; `false` if storage is not ready or the door does not exist.
- **err** — present on failure, explains why.

**Example**

```lua
local ok, err = exports.kora_doorlock:removeDoor('mission-row-armory')
```

### `exports.kora_doorlock:importOxDoors()`

Runs the same import the `/importoxdoors` command runs, callable from code.

**Parameters**



**Returns**

- **imported** — number of rows imported, or `nil` on failure.
- **skippedOrError** — number skipped on success, or the error string on failure.

**Example**

```lua
local imported, skippedOrError = exports.kora_doorlock:importOxDoors()
```

### `exports.kora_doorlock:registerHook(event, callback, options?)`

Registers a callback consulted on every access decision. The only supported `event` is `'doorAuthorization'`. The callback receives `{ source, doorId, door, lockpick, authorised }` (the decision made so far) and may return `true` to force authorisation; any other return value does not change the outcome.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `event` | string | Must be `'doorAuthorization'`; anything else raises an assertion error. |
| `callback` | function | Called as `callback(payload)`. |
| `options?` | table | `{ nameFilter?: string, print?: boolean }` — `nameFilter` is a Lua pattern matched against the door’s label to scope the hook to specific doors; `print` logs every invocation to console. |

**Returns**

- **hookId** — integer handle for `removeHook`.

**Example**

```lua
local hookId = exports.kora_doorlock:registerHook('doorAuthorization', function(payload)
    if payload.door.label:find('Bank Vault') and payload.source == someTrustedId then return true end
end, { nameFilter = 'Bank Vault' })
```

**Representative console output**

```text
Hooks belonging to a resource are automatically removed when that resource stops (tracked via `Kora.resources.serverRegistry`).
```

### `exports.kora_doorlock:removeHook(hookId)`

Removes a previously registered hook. Only the resource that registered it may remove it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `hookId` | integer | Handle returned by `registerHook`. |

**Returns**

- **removed** — `true` on success; `false` if the hook does not exist or belongs to another resource.

**Example**

```lua
exports.kora_doorlock:removeHook(hookId)
```

### `exports.kora_doorlock:RegisterDoorPolicy(id, callback)`

Claims exclusive, final-say authorisation over one door for the calling resource. While claimed, the callback decides every access check on that door (and forces it locked immediately once claimed). Use this when another resource (e.g. a heist or minigame) needs to own a door completely rather than add a hook that only widens access.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | Door ID; must already exist. |
| `callback` | function | Called as `callback(source, id, { lockpick, authorised, door })`; its return value (`true`/not-`true`) is the final access decision. |

**Returns**

- **claimed** — `true` on success.
- **err** — present on failure: the door does not exist, `callback` is not callable, or the door’s policy already belongs to a different resource.

**Example**

```lua
exports.kora_doorlock:RegisterDoorPolicy('vault-door', function(source, id, ctx)
    return HasActiveHeistAccess(source)
end)
```

**Representative console output**

```text
Persisted on the door record as `policyOwner`, so it survives a kora_doorlock restart. If the owning resource stops (`onResourceStop`) the callback is dropped and the door is locked, but `policyOwner` is not cleared: the door stays closed to everyone until a policy is registered again or `ReleaseDoorPolicy` is called.
```

### `exports.kora_doorlock:ClearDoorPolicy(id)`

Drops the calling resource’s policy callback on a door without restoring its previous access rules (`policyOwner` stays set), and forces it locked. Used for an abrupt loss of ownership; see `ReleaseDoorPolicy` for a clean handback.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | Door ID. |

**Returns**

- **cleared** — `true` on success.
- **err** — present if the door does not exist or is not owned by the calling resource.

**Example**

```lua
exports.kora_doorlock:ClearDoorPolicy('vault-door')
```

### `exports.kora_doorlock:ReleaseDoorPolicy(id)`

Cleanly hands a claimed door back: clears `policyOwner` in the persisted definition (restoring its normal groups/characters/items/passcode rules) instead of leaving it force-locked.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | Door ID. |

**Returns**

- **released** — `true` on success.
- **err** — present if the door does not exist, is not owned by the calling resource, or the save failed.

**Example**

```lua
exports.kora_doorlock:ReleaseDoorPolicy('vault-door')
```

## Return fields and notes

| Export | Notes |
| --- | --- |
| `getDoor`, `getDoorFromName`, `getAllDoors` | Return `id`, `name`, `label`, `state`, `locked`, `coords`, `characters`, `citizenIds`, `groups`, `items`, `maxDistance`, `distance` and `definition` (without the passcode; `hasPasscode` is given instead). |
| `setDoorState` | Changes state and its linked door; fires `kora_doorlock:stateChanged` with no source. |
| `registerHook`, `removeHook` | See [Access and permissions](../permissions.md). |

Events fired by these exports are listed in [Events](../events.md); the `qb-doorlock` compatibility exports are in [Compatibility](../compatibility.md).

## Limits and related APIs

Server only. `editDoor`/`createDoor`/`removeDoor`/policy exports all require the database to be ready (`databaseReady`); called too early they fail quietly (`false`/`err`). Hooks only support the `doorAuthorization` event.
