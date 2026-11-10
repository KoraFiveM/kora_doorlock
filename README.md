# kora_doorlock

A server-authoritative, kora_lib-native door lock resource with the feature set of
`ox_doorlock`. It supports single and double doors, persistent in-game editing,
passcodes, jobs and gangs, character IDs, metadata-aware key items, consumable
keys, lockpicking, per-door ACEs, automatic doors, movement rates, hold-open,
hidden indicators, sounds, and auto-locking.

kora_lib owns the resource's commands, permissions, protected events, callbacks,
minigames, targeting facade, keybinds, zones, raycasts, streaming, sounds, UI,
notifications, timers, configuration, and SQL. kora_core is used only for player,
job, gang, and inventory data, which are framework domains kora_lib intentionally
does not own.

## Property policies

Server resources can call `RegisterDoorPolicy(id, callback)` to attach an
authoritative policy to an existing stable door ID. It returns `true` or
`false, error`; the callback receives `(source, id, context)` with `lockpick`,
`authorised`, and `door` fields and must return `true`. For protected doors the
policy has the final decision, including legacy hook grants. Linked protected
doors also require approval. Unprotected doors retain the existing grant-only
hook behavior.

The invoking resource owns the persisted policy marker. Stopping the provider
locks affected doors, and restored doors remain locked until re-registration.
`ClearDoorPolicy(id)` removes the callback while retaining this closed boundary.
`ReleaseDoorPolicy(id)` explicitly and durably unlinks the owner's policy,
restoring the door's legacy permissions without deleting the door. Both return
`true` or `false, error` and reject other providers. Confirmed state changes
continue to emit `kora_doorlock:stateChanged(source, id, locked, usedItem)`.

## Install

The test server already starts `kora_doorlock` after `kora_lib`, `kora_sql`, and
`kora_core`. The database tables (`kora_doorlock_doors`, `kora_doorlock_links`, `kora_doorlock_categories`) are created automatically at startup by kora_sql; there is no SQL to import.

`kora_target` is optional. If it starts, lockpickable door objects receive a
kora_lib interaction option. The `pickClosestDoor` client export remains available
without a target resource.

## Door creator

Players with the permission selected by `Config.AdminPermission` and
`Config.AdminPermissionPrefix` (`kora_core.admin` by default) can use:

- `/doorlocks` (or `/doorlocks closest`) to open the creator. It works like the
  kora_crafting creator: a grid of doors you can search, a *Create new door* button
  and one page per door.
- `/adddoor` to jump straight to *Create new door*.
- `/newdoor` and `/doordebug` are aliases of `/adddoor` for stock qb-doorlock habits.
- `/importoxdoors` to import an existing `ox_doorlock` database table. Imported
  IDs use the stable `ox-<number>` form; existing IDs are skipped.

**Doors**: a grid of every door with its state, access, distance, auto-lock, link
and lockpick setting, a *Closest to me* sort and a *Refresh* button. Pick a door
to edit it.

**Creating a door**: press *Create new door*, type a name and say whether it is a
double door. The creator closes: aim at the door (it is outlined, found with `Kora.raycast`) and press **E** to confirm (for a double
door, then aim at the second leaf and press **E** again). **Backspace** cancels. The door
ID is made from the name (`Back Office` becomes `back-office`), and the new door's
page opens when you are done.

**A door's page** has its own forms and cards:

- Lock or unlock it, and teleport to it
- Details: name, interaction distance, auto-lock seconds, movement rate, automatic,
  hold open, hide indicator
- Access: a passcode, and cards for jobs and gangs (name and minimum grade),
  characters (by ID) and key items (name, optional metadata type, used up or kept)
  with *Add*, *Edit* and *Remove*
- Lockpicking (on or off, pins, tolerance, speed) and the four sounds
- Where it is, with *Aim at a different single or double door* to move it
- Linking it with another door so they lock and unlock together
- *Duplicate door* (copies the settings, then you aim at the new door) and *Delete door*

Passcodes are never shown after they are set. The creator only shows whether one
is set: leave the field empty to keep it, type a new code to replace it, or use
*Remove passcode* to clear it. This also applies to category defaults.

Every change is checked and saved by the server, and the creator shows what it
refused. Doors created or edited in-game are persistent. Editing a door authored in
`Config.Doors` creates a database override; deleting one creates a persistent
tombstone, so it does not reappear from config after a restart.

## Categories (optional)

A category is a name plus default settings for new doors, for quick and organised creation. Think of a building:
"Police" with the police job on it. Doors never need a category, and *Create new door* works as before.

1. **Categories** page, *Create new category*, type a name (`Police`). The category ID is made from it (`police`).
2. On the category's page set its **default settings** (details, passcode, jobs and gangs, characters, key items,
   lockpicking, sounds). They are copied to every door placed from then on.
3. Press **Place doors**. The creator closes and runs two stages:
   - **Single doors**: aim at a door and press **E**. It is saved at once as `police-1`, named *Police 1*, with
     the defaults, and you can aim at the next one. **Backspace** ends the stage.
   - A prompt asks about **double doors**. If you accept, aim at the first door, **E**, aim at the second, **E**.
     **Backspace** at the first door ends the stage. **Backspace** at the second only drops that pair, so a wrong
     first door can be redone.
4. The creator opens on the category with the list of its doors, numbered in order.

Every door keeps its own copy of the settings. To change one door only (the chief's office needs grade 4 instead
of 0) open it from the list and edit it like any other door. Changing the category's defaults later only affects
doors placed afterwards. The door ID stays `police-N` whatever the door is renamed to.

- The next number is one above the highest `category-N` that exists, so deleting a door never renumbers the others.
- A door that is already placed is refused if you aim at it again.
- A door can be moved into or out of a category from its own page (*Category*). This only organises the creator:
  it never changes who can open a door.
- Deleting a category keeps its doors; they just stop being in a category.
- Categories are stored in the `kora_doorlock_categories` table (created automatically at start). A door's category is saved in the door itself.

## Configuration

The canonical kora_doorlock shape is:

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
    autoLock = 10000, -- milliseconds
    automatic = false,
    doorRate = 1.0,
    holdOpen = false,
    hideUi = false,
    lockpick = true,
    lockpickDifficulty = {
        pinCount = 5,
        tolerance = 0.14,
        speed = 1.0,
        timeLimit = 15000,
        attempts = 1,
    },
    lockSound = 'Remote_Control_Close',
    lockSoundSet = 'PI_Menu_Sounds',
    unlockSound = 'Remote_Control_Open',
    unlockSoundSet = 'PI_Menu_Sounds',
}
```

A true double door uses exactly two leaves:

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

Access methods are alternatives. A matching per-door ACE, character ID,
job/gang grade, key item, or passcode permits the action. A door without any
access rule is public. The server always rechecks access and distance.

For parity when importing definitions, these ox-style aliases are accepted:

- `name` → `label`
- `state = 0|1` → `locked = false|true`
- `maxDistance` → `distance`
- `autolock` in seconds → `autoLock` in milliseconds
- `auto` → `automatic`
- `citizenIds` → `characters`
- item `metadata = 'type'` → `metadata = { type = 'type' }`

ox-style difficulty arrays (`easy`, `medium`, `hard`, or custom
`areaSize`/`speedMultiplier` entries) are also accepted and translated onto
kora_lib's server-validated lockpick game. New definitions should use the native
kora_lib options shown above.

## Doors with no requirements

```lua
Config.UnrestrictedDoorsOpenToAll = false -- default
```

`false` (the default): doors with no job/item/citizen requirements (no `groups`, `items`, `characters` or
`passcode`) can only be used by players with a door ACE (and admins, if `Config.AdminsBypassDoorAccess` is on). Set it to `true` to let everyone use them.
The server enforces this on every toggle; if the option is missing or `nil` it behaves as `false`. It can also
be changed from the kora_lib config panel and applies the next time someone uses a door.

## Server authority

Every toggle is decided on the server; the client only sends the request. A refused toggle shows the access-denied
notification and re-sends the door's real state to that player.

```lua
Config.DoorAceExactOnly = true     -- door ACEs are only doorlock.<id> / doorlock.<label>
```

```lua
Config.AdminsBypassDoorAccess = false -- default
```

`false` (the default): the admin permission (`Config.AdminPermission`, which `group.admin` holds by default)
only grants the `/doorlocks` menu. At the door an admin needs the door's job/gang grade, character, key item,
passcode or door ACE like any other player, and can still lock or unlock any door from the menu. Set it to `true`
to let admins use every door with **E**, as older versions did. With `Config.Debug = true` the server prints which
check granted or refused each toggle.

Set `DoorAceExactOnly = false` to also accept `group.<id>` / `command.<id>` objects as older versions did.
Note that a `doorAuthorization` hook returning `true` still grants access, so only register hooks you trust.

## ACE access

Grant one door by its stable ID (recommended) or its ox-compatible display
name:

```cfg
add_ace identifier.license:abc123 "doorlock.city-hall-office" allow
# Existing ox-style grants such as "doorlock.City Hall Office" also work.
```

When `Config.PlayerAceAuthorised` is enabled, the permission configured by
`Config.PlayerAcePermission` (default `command.doorlock`) can use every door.
Administrative editing remains restricted to the separately configured
administrative permission (`kora_core.admin` by default).

## APIs

Client exports:

```lua
exports.kora_doorlock:useClosestDoor()
exports.kora_doorlock:pickClosestDoor()
local door = exports.kora_doorlock:getClosestDoor()
local id = exports.kora_doorlock:getClosestDoorId()
local id = exports.kora_doorlock:getDoorIdFromEntity(entity)
local locked = exports.kora_doorlock:getDoorState('city-hall-office')
```

Server exports:

```lua
local door = exports.kora_doorlock:getDoor('city-hall-office')
local door = exports.kora_doorlock:getDoorFromName('City Hall Office')
local allDoors = exports.kora_doorlock:getAllDoors()

exports.kora_doorlock:setDoorState('city-hall-office', false) -- also accepts 0/1
exports.kora_doorlock:editDoor('city-hall-office', { autoLock = 30000 })
local id = exports.kora_doorlock:createDoor(definition)
exports.kora_doorlock:removeDoor(id)
local imported, skipped = exports.kora_doorlock:importOxDoors()
```

The local server event form is also available:

```lua
TriggerEvent('kora_doorlock:setState', 'city-hall-office', 0)
```

Listen for successful changes:

```lua
AddEventHandler('kora_doorlock:stateChanged', function(source, doorId, locked, usedItem)
    -- source is nil for server/auto-lock changes.
end)

AddEventHandler('kora_doorlock:loaded', function()
    -- Persistent definitions and links are ready.
end)
```

Authorization hooks can grant access for custom systems:

```lua
local hookId = exports.kora_doorlock:registerHook('doorAuthorization', function(payload)
    if payload.door.label == 'VIP Room' and isVip(payload.source) then return true end
end, { nameFilter = '^VIP' })

exports.kora_doorlock:removeHook(hookId)
```

## Tests

Run the plain-Lua suite from this resource directory (it needs a sibling `kora_core` resource for its test harness):

```sh
test/run.sh
```

## Interaction prompt text

```lua
Config.ShowDoorNameInPrompt = false -- default
```

`false` (the default): the prompt shown to players is the generic "Lock Door" / "Unlock Door" (translated through
the `lock_door_generic` / `unlock_door_generic` locale keys), so internal door names such as `MRPD-F1-ChiefOffice`
are not exposed. Set it to `true` to show the door label in the prompt (`lock_door` / `unlock_door` keys). The
admin/creator menu always shows the internal door name.

## qb-doorlock compatibility

The resource provides `qb-doorlock`. Client exports `GetDoorStates` (`{[id]=locked}`), `GetDoorList` (`{[id]=door}` with `doorLabel`/`textCoords` added), `GetNearbyDoors` (`{[id]=true}`) and `GetClosestDoor` (`{id, distance, data}`, `{}` when none) mirror the stock shapes. Door ids are Kora's string ids, not stock numeric indexes. `qb-doorlock:server:updateState` and `lockpicks:UseLockpick` are not handled here.
