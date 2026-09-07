# qbdoorlock

A small qblib-native replacement for the core behaviour of `ox_doorlock`:
single or double GTA doors, synchronized locked state, proximity prompts, jobs,
gangs, character IDs, key items, and optional auto-locking.

## Install

`qbdoorlock` is already added after `qbcore` in `server.cfg`.

## In-game creation

Players with the `qbcore.admin` permission can create a persistent single-door
lock without editing files:

1. Stand within six metres and look directly at the map door.
2. Run `/adddoor` (or the configured `Config.CreateCommand`).
3. Give it a permanent ID, a name, starting state, and optional job/gang access.

The door is saved in the database, immediately synchronized to every player,
and restored after resource or server restarts. `/doorlocks` also includes a
**Create targeted door** shortcut; it closes the dashboard so you can aim at the
door, then use `/adddoor`.

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
unlocking a door. Use **Link double door** on a card to select any other
unlinked door; the pair then locks and unlocks together, and can be unlinked
from either card. Links persist across restarts. Every request and change is
checked server-side and requires the `qbcore.admin` permission. Change the
command name with `Config.AdminCommand`.
