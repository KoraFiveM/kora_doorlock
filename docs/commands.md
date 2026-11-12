---
title: Commands
sidebar_position: 7
---

# Commands

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
