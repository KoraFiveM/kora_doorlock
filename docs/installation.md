---
title: Installation
sidebar_position: 2
---

# Installation

## Dependencies

Declared in `fxmanifest.lua`:

| Resource | Used for |
| --- | --- |
| `kora_lib` | Commands, permissions, callbacks, events, minigames, keybinds, zones, UI, notifications, timers, configuration |
| `kora_core` | Player, job, gang and inventory data (`getPlayer`, `getItemsByName`, `removeItem`) |
| `kora_sql` | Persistent doors, links and categories |

Optional, not declared: `kora_target`. When it is started, door objects that have `lockpick` enabled get a "Pick lock" interaction option. If it starts later, pending targets are registered when it starts.

## Steps

1. Place the resource in your resources folder.
2. Ensure it after its dependencies:

   ```cfg
   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_doorlock
   ```

3. No SQL import is needed. The tables are created at start by `kora_sql`, see [Database](./database.md).
4. Add doors to `Config.Doors` or create them in game with [the creator](./creator.md).
5. Grant staff the admin permission, see [Access and permissions](./permissions.md).

## Startup behaviour

Configured doors are loaded first. Then the resource waits up to 60 seconds for `kora_sql`, creates its tables, loads stored doors (overriding or removing configured ones), links and categories, and triggers `kora_doorlock:loaded`. If `kora_sql` is not ready or the schema fails, only the doors from `Config.Doors` work and in-game editing is disabled; an error is printed.

Clients request all door definitions and states from the server when they start.

The resource name is `kora_doorlock` and it provides `qb-doorlock`.
