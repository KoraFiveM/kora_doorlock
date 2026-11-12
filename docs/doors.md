---
title: Door definitions
sidebar_position: 7
---

# Door definitions

A door is a table keyed by a permanent ID in `Config.Doors`. IDs created in game use letters, digits, `-` and `_` (1-64 characters, starting with a letter or digit). All definitions, whether from config, the database, exports or the creator, go through the same validation on the server; invalid ones are refused or skipped with a console message.

## Single door

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
    autoLock = 10000,
    lockpick = true,
    lockpickDifficulty = { pinCount = 5, tolerance = 0.14, speed = 1.0, timeLimit = 15000, attempts = 1 },
}
```

## Double door

A double door uses exactly two leaves. Its centre is the midpoint of the two leaves.

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

## Fields

| Field | Description |
| --- | --- |
| `label` | Required, 1-96 characters. Also accepted as `name`. |
| `model`, `coords`, `heading` | Single door model hash, position and heading. Model must be non-zero. |
| `doors` | Two leaves, each with `model`, `coords`, `heading`. Replaces the single-door fields. |
| `locked` | Starting state, default `true`. Also `state = 0` or `1`. Lock state is not persisted; doors start in this state after a restart. |
| `distance` | Interaction distance, 0.5 to 20 metres. Falls back to `Config.InteractionDistance`. Also `maxDistance`. |
| `groups` | Job or gang name to minimum grade (up to 32, names lowercased). |
| `characters` | Up to 64 character IDs, 1-96 characters each. Also `citizenIds`. |
| `items` | Up to 32 key items. Each is a name, or a table with `name`, optional `metadata` and `remove`. `metadata` may be a string (shorthand for `{ type = value }`) or a table of up to 16 scalar values. With `remove = true` one item is consumed on use. |
| `passcode` | Up to 128 characters. Players enter it in a dialog. Never sent to clients. |
| `autoLock` | Milliseconds, 0 to 24 hours. Also `autolock` in seconds. |
| `automatic`, `auto` | Let the game open and close the door by itself. |
| `doorRate` | Movement rate, 0 to 10. |
| `holdOpen` | Keep the door open while unlocked. |
| `hideUi` | Hide the prompt and the lock icon. |
| `lockpick` | Allow lockpicking. |
| `lockpickDifficulty` | Native table (`pinCount` 1-12, `tolerance` 0.03-0.35, `speed` 0.3-4, `timeLimit` 2000-60000, `attempts` 1-10), or a list of `easy`, `medium`, `hard` or `areaSize`/`speedMultiplier` entries (up to 12). |
| `lockSound`, `lockSoundSet`, `unlockSound`, `unlockSoundSet` | Custom sounds, see `Config.IgnoreVehicleDoorSounds`. |
| `category` | Creator category ID. Organisation only, never affects access. |
| `policyOwner` | Set by `RegisterDoorPolicy`, see [Access and permissions](./permissions.md). |

## Aliases accepted for ox_doorlock imports

`name` for `label`, `state` for `locked`, `maxDistance` for `distance`, `autolock` (seconds) for `autoLock`, `auto` for `automatic`, `citizenIds` for `characters`, and item `metadata = 'type'`. ox-style difficulty lists are translated onto the `kora_lib` lockpick game.

## Persistence

A door edited in game is saved to the database and overrides the config entry. Deleting a configured door stores a tombstone so it does not return. See [Database](./database.md).
