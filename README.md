# qbdoorlock

A small qblib-native replacement for the core behaviour of `ox_doorlock`:
single or double GTA doors, synchronized locked state, proximity prompts, jobs,
gangs, character IDs, key items, and optional auto-locking.

## Install

`qbdoorlock` is already added after `qbcore` in `server.cfg`. Add doors in
`config.lua`, then restart the resource (or the server).

## Door configuration

Every door needs a stable string ID, a label, an initial `locked` state, and
either one `model`/`coords` pair or a `doors` array for double doors.

```lua
['city-hall-office'] = {
    label = 'City Hall Office',
    model = `v_ilev_fib_door1`,
    coords = vector3(105.76, -742.03, 45.03),
    locked = true,
    groups = { government = 2, police = 0 },
    citizenIds = { ['ABC12345'] = true },
    items = { 'office_keycard' },
    autoLock = 10000,
}
```

Access methods are alternatives: any matching job/gang grade, character ID, or
one of the configured item checks is enough. A door with no access rules is
publicly togglable. The server checks both access and player distance; the
client prompt alone grants nothing.

`autoLock` is in milliseconds and starts when an authorized player unlocks the
door. `Config.DefaultAutoLock` applies to any door without its own value.

## Integration

Other server resources can use the server-only exports:

```lua
exports.qbdoorlock:setDoorState('city-hall-office', false)
local locked = exports.qbdoorlock:getDoorState('city-hall-office')
```

The player presses the rebindable **E** interaction while standing at the door.

## Staff dashboard

`/doorlocks` opens a qblib AppShell dashboard with the current state of every
configured door. It shows each door's current distance, and supports searching,
sorting by closest to the player, refreshing live state, and locking or
unlocking a door. Every request and change is checked server-side and requires
the `qbcore.admin` permission. Change the command name with
`Config.AdminCommand`.
