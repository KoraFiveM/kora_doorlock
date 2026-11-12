---
title: "Commands"
sidebar_position: 4
---


# Commands

All commands are server commands gated by the kora_lib permission system; a player needs the configured admin permission, and the server console is refused (`commandPermission` returns false for source 0).

## Built-in commands

### `/doorlocks [closest]`

Opens the door management UI (the creator/editor app).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | closest? — any value opens the UI with the door list sorted by distance (`closestFirst`). |
| Access | Config.AdminPermission (default 'admin'), prefix Config.AdminPermissionPrefix (default 'kora_core'). |

**Example**

```text
/doorlocks
/doorlocks closest
```

**Result**

The Kora UI management app opens for the player, with doors sorted by distance when `closest` is given.

### `/adddoor (aliases: newdoor, doordebug)`

Starts the raycast door creator: aim at a real map door and confirm with E to register it.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | Config.AdminPermission (default 'admin'), prefix Config.AdminPermissionPrefix (default 'kora_core'). |

**Example**

```text
/adddoor
```

**Result**

Client enters targeted-creation mode; aiming at a door and pressing E opens the new-door form.

### `/importoxdoors`

Imports every row from an existing `ox_doorlock` table (if present) as new kora_doorlock doors under id `ox-<row id>`.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | Config.AdminPermission (default 'admin'), prefix Config.AdminPermissionPrefix (default 'kora_core'). Command name configurable via Config.ImportCommand. |

**Example**

```text
/importoxdoors
```

**Result**

A toast reporting the number imported, or an error ("no ox_doorlock table found", a decode failure, etc.) if the table is missing or storage is not ready yet.

## Command summary

All commands require the admin permission (`Config.AdminPermission` with `Config.AdminPermissionPrefix`) and cannot be run from the server console.

| Command | Description |
| --- | --- |
| `/doorlocks` (`Config.AdminCommand`) | Open the creator. The argument `closest` sorts doors by distance. |
| `/adddoor` (`Config.CreateCommand`) | Start creating a door directly. |
| `/newdoor`, `/doordebug` | Aliases of `/adddoor`. |
| `/importoxdoors` (`Config.ImportCommand`) | Import the `ox_doorlock` table. Reports the number imported. |

The import reads `id`, `name` and `data` from the `ox_doorlock` table, creates doors with IDs `ox-NUMBER`, skips existing or invalid ones, and fails if the table does not exist.

## Keybind

`kora_doorlock_toggle` (default key `E`, rebindable in the game key settings) requests a lock or unlock of the closest door within its interaction distance.
