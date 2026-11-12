---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Doorlock is a config-driven, server-authoritative door-lock system with an in-game creator and management UI. It answers to the legacy `kora_doorlock` and `qb-doorlock` export names. Every access decision — ACE, admin, job/gang, character, key item, passcode, hook or another resource’s policy — is made on the server; the client only shows state and prompts.

## Install Kora Doorlock

1. **Add the folder** — Place the `kora_doorlock` folder in your resources directory. It declares `dependencies { 'kora_lib', 'kora_core', 'kora_sql' }`, so all three must be started first.

2. **Load order** — Shared scripts load `@kora_lib/init.lua` first, then `types.lua`, `config.lua`, `shared/schema.lua` and `shared/access.lua`. Server scripts load `@kora_sql/init.lua` before `server/tables.lua` and `server/main.lua`.

   ```lua title="fxmanifest.lua" {9,10,11,12,20,24,25,26}
   fx_version 'cerulean'
   game 'gta5'
   lua54 'yes'

   name 'kora_doorlock'
   provide 'qb-doorlock'

   dependencies {
       'kora_lib',
       'kora_core',
       'kora_sql',
   }

   shared_scripts {
       '@kora_lib/init.lua',
       'types.lua',
       'config.lua',
       'shared/schema.lua',
       'shared/access.lua',
   }

   client_scripts {
       'client/main.lua',
       'client/creator.lua',
   }

   server_scripts {
       '@kora_sql/init.lua',
       'server/tables.lua',
       'server/main.lua',
   }
   ```

3. **Define doors (optional)** — `Config.Doors` in `config.lua` is a table keyed by a permanent, stable door ID. A single door needs `model` and `coords`; a double door needs a `doors` array of exactly two leaves (each with its own `model`/`coords`). Doors can also be created entirely in-game with the creator — `Config.Doors` is only for doors you want authored ahead of time.

   ```lua title="config.lua"
   Config.Doors = {
       ['mission-row-armory'] = {
           label = 'Mission Row Armory',
           model = `v_ilev_arm_secdoor`,
           coords = vector3(452.6, -982.7, 30.7),
           locked = true,
           groups = { police = 0 }, -- job/gang name = minimum grade
           autoLock = 5000, -- optional milliseconds; omit to disable
       },

       -- Double doors use 'doors'. Each leaf gets its own model and coordinates.
       ['mission-row-front'] = {
           label = 'Mission Row Front Doors',
           doors = {
               { model = `v_ilev_ph_door01`, coords = vector3(434.7, -983.2, 30.8) },
               { model = `v_ilev_ph_door01`, coords = vector3(434.7, -985.0, 30.8) },
           },
           locked = false,
           groups = { police = 0 },
       },
   }
   ```

4. **Give players door access** — A door with no `groups`, `characters`, `items` or `passcode` is "unrestricted". By default (`Config.UnrestrictedDoorsOpenToAll = false`) an unrestricted door can only be toggled by a player holding a door ACE — add one with `add_ace group.police doorlock.mission-row-armory allow` (or grant the general `Config.PlayerAcePermission`, default `doorlock`, via kora_lib permissions). See Access checks below for every other way a door can be opened.

5. **Start it** — Add `ensure kora_doorlock` after `kora_lib`, `kora_core` and `kora_sql` in `server.cfg`. On first boot it creates its own tables (`kora_doorlock_doors`, `kora_doorlock_links`, `kora_doorlock_categories`) through `Kora.sql.ensureTables`.

## Legacy compatibility

- The manifest does `provide 'qb-doorlock'`, so resources that declare `dependency 'qb-doorlock'` or call `exports['qb-doorlock']:*` keep working.
- Client-side, `Kora.compat.provideExport('qb-doorlock', ...)` answers `GetDoorStates`, `GetDoorList`, `GetNearbyDoors` and `GetClosestDoor` in the legacy shape (a `doorLabel`/`textCoords` pair alongside the normal fields).
- The admin command `importoxdoors` (configurable via `Config.ImportCommand`) migrates an existing `ox_doorlock` table: it checks `information_schema` for the table, reads every row, decodes its `data` as a door definition, and imports it under the id `ox-<id>`. Already-imported or malformed rows are skipped and counted separately.

## Configuration reference

The most relevant fields in `config.lua`. Boolean switches default to the secure/off option unless noted.

- `Config.Doors` — authored doors, as above. Keys must be strings; invalid entries abort resource start (an `assert` fails with the schema error).
- `Config.InteractionDistance` (default `1.8`) — fallback interaction radius for a door with no explicit `distance`.
- `Config.DefaultAutoLock` (default `nil`) — default milliseconds an unlocked door waits before auto-relocking when the door itself sets no `autoLock`. Left unset, auto-lock is off by default.
- `Config.Debug` (default `false`) — prints an access-check breakdown (`ace`, `admin`, `character`, `group`, `item`, `restricted`) to the server console for every non-lockpick toggle.
- `Config.Notify` (default `false`) / `Config.DrawTextUI` (default `true`) — server-side lock/unlock toast, and the client interaction prompt.
- `Config.ShowDoorNameInPrompt` (default `false`) — includes the door label in the interaction prompt text (e.g. "Unlock MRPD-F1-ChiefOffice") instead of the generic "Lock/Unlock Door".
- `Config.DrawSprite` / `Config.DrawSpriteCentered` / `Config.DrawSpriteOffset` — the lock/unlock world sprite shown near a door, and how it is centred/nudged.
- `Config.PlayerAceAuthorised` (default `false`) + `Config.PlayerAcePermission` (default `'doorlock'`) — when the switch is on, any player holding this general kora_lib permission can open any door, independent of per-door ACEs.
- `Config.UnrestrictedDoorsOpenToAll` (default `false`, the secure default) — see Access checks.
- `Config.AdminsBypassDoorAccess` (default `false`, the secure default) — whether the admin permission alone lets a player use every door with E (otherwise admins use the `/doorlocks` menu instead).
- `Config.DoorAceExactOnly` (default `true`, the secure default) — restricts a door ACE to exactly `doorlock.<id>` / `doorlock.<label>`; `false` also accepts `group.<id>` and `command.<id>` objects (legacy behaviour, can match unrelated grants).
- `Config.LockpickItems` (default `{ 'lockpick' }`), `Config.CanPickUnlockedDoors` (default `false`), `Config.LockpickDifficulty`, `Config.LockpickBreakChance` (`{ success, failure }`, percent chance), `Config.lockpickRateLimit` (`{ max, window }` milliseconds) — lockpicking tuning.
- `Config.DefaultSounds`, `Config.IgnoreVehicleDoorSounds`, `Config.VehicleSoundSets`, `Config.VehicleSoundNames` — lock/unlock sound selection; the ignore list exists so a door whose stored sound happens to be a vehicle key-fob chirp or alarm falls back to the default instead of playing it.
- `Config.AdminPermission` (default `'admin'`) + `Config.AdminPermissionPrefix` (default `'kora_core'`) — the kora_lib permission that opens the `/doorlocks` management UI and runs the admin-only server callbacks.
- `Config.AdminCommand` (default `'doorlocks'`), `Config.CreateCommand` (default `'adddoor'`), `Config.ImportCommand` (default `'importoxdoors'`) — command names, see Commands.

## Dependencies

Declared in `fxmanifest.lua`:

| Resource | Used for |
| --- | --- |
| `kora_lib` | Commands, permissions, callbacks, events, minigames, keybinds, zones, UI, notifications, timers, configuration |
| `kora_core` | Player, job, gang and inventory data (`getPlayer`, `getItemsByName`, `removeItem`) |
| `kora_sql` | Persistent doors, links and categories |

Optional, not declared: `kora_target`. When it is started, door objects that have `lockpick` enabled get a "Pick lock" interaction option. If it starts later, pending targets are registered when it starts.

## Next steps

1. No SQL import is needed. The tables are created at start by `kora_sql`, see [Database](./database.md).
2. Add doors to `Config.Doors` or create them in game with [the creator](./creator.md).
3. Grant staff the admin permission, see [Access and permissions](./permissions.md).

Example start order:

```cfg
ensure kora_lib
ensure kora_sql
ensure kora_core
ensure kora_doorlock
```

## Startup behaviour

Configured doors are loaded first. Then the resource waits up to 60 seconds for `kora_sql`, creates its tables, loads stored doors (overriding or removing configured ones), links and categories, and triggers `kora_doorlock:loaded`. If `kora_sql` is not ready or the schema fails, only the doors from `Config.Doors` work and in-game editing is disabled; an error is printed.

Clients request all door definitions and states from the server when they start.

The resource name is `kora_doorlock` and it provides `qb-doorlock`.

See [Configuration](./configuration.md) for every `Config` option, including those listed above.
