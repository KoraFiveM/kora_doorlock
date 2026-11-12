---
title: "Client exports"
sidebar_position: 3
---


# Client exports

Read-only accessors into the client’s locally cached door state, plus two convenience actions that reuse the same server round trip a player’s own keybind/target interaction would use. The client never decides access on its own — these calls still go through the server’s normal checks.

Namespace: `exports.kora_doorlock` · Source: `client/main.lua`

## Functions

Five client-only exports.

### `exports.kora_doorlock:getDoorState(id)`

Reads the client’s locally cached lock state for a door (kept in sync by the server via `doorStateChanged`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | Door ID. |

**Returns**

- **locked** — `true`/`false`, or `nil` if the client has no record of that door.

**Example**

```lua
local locked = exports.kora_doorlock:getDoorState('mission-row-armory')
```

### `exports.kora_doorlock:getClosestDoorId()`

Returns the ID of the door currently closest to the local player, within its interaction distance.

**Parameters**



**Returns**

- **id** — door ID, or `nil` if no door is in range.

**Example**

```lua
local id = exports.kora_doorlock:getClosestDoorId()
```

### `exports.kora_doorlock:getClosestDoor()`

Returns the full locally cached definition of the nearest in-range door.

**Parameters**



**Returns**

- **door** — the client’s normalised door table, or `nil`.

**Example**

```lua
local door = exports.kora_doorlock:getClosestDoor()
```

### `exports.kora_doorlock:getDoorIdFromEntity(entity)`

Resolves a streamed door object entity back to its door ID, using the entity state bag (`kora_doorlock:id`/`doorId`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | integer | A client entity handle. |

**Returns**

- **id** — door ID, or `nil` if the entity is not a tracked door (or does not exist).

**Example**

```lua
local id = exports.kora_doorlock:getDoorIdFromEntity(entity)
```

### `exports.kora_doorlock:useClosestDoor()`

Triggers the normal toggle flow (the same thing pressing E on the keybind does) on the nearest in-range door.

**Parameters**



**Returns**

- **used** — `true` if a nearby door was found and the toggle request was sent; `false` otherwise.

**Example**

```lua
exports.kora_doorlock:useClosestDoor()
```

### `exports.kora_doorlock:pickClosestDoor()`

Starts the lockpicking flow on the nearest in-range door, as if targeted.

**Parameters**



**Returns**

- **started** — `true` if picking began; `false` if already picking, no nearby door, or the door is not lockpickable/not eligible.

**Example**

```lua
exports.kora_doorlock:pickClosestDoor()
```

## State bag keys

Door objects that this resource has found also carry the state bag keys `kora_doorlock:id` and `doorId`.

## Limits and related APIs

Client only, and read-only with respect to door definitions: nothing here can change a door’s access rules (use the server exports for that).
