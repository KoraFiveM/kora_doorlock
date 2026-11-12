---
title: Access and permissions
sidebar_position: 8
---

# Access and permissions

## Who can use a door

On a toggle the server checks the player is near the door (distance plus one metre), then grants access if any of these is true:

1. The player has a door ACE (see below), or `Config.PlayerAceAuthorised` is on and they hold `Config.PlayerAcePermission`.
2. They hold the admin permission and `Config.AdminsBypassDoorAccess` is on.
3. Their character ID is in `characters`.
4. Their job or gang is in `groups` with a grade at or above the minimum.
5. They carry a matching item from `items` (metadata must match when given).
6. The door has no restrictions at all and `Config.UnrestrictedDoorsOpenToAll` is on.

If none applies and the door has a `passcode`, the player is asked for it. A wrong code shows "Incorrect PIN". Otherwise access is denied and the real door state is sent back to that player.

Registered hooks and policies can then grant or refuse, see below.

## Door ACEs

Grant one door by ID or by label:

```cfg
add_ace identifier.license:abc123 "doorlock.city-hall-office" allow
add_ace identifier.license:abc123 "doorlock.City Hall Office" allow
```

With `Config.DoorAceExactOnly = false`, `group.ID` and `command.ID` objects are also accepted.

## Admin permission

The creator, its callbacks and the commands require the `kora_lib` permission built from `Config.AdminPermissionPrefix` and `Config.AdminPermission` (`kora_core.admin` by default). Admins can lock or unlock any door from the menu, even without bypass. Teleporting to a door is also admin-only.

## Lockpicking

Needs a door with `lockpick = true`, the player near it, the door locked (unless `Config.CanPickUnlockedDoors`), and an item from `Config.LockpickItems`. The server starts a `kora_lib` lockpick minigame, verifies its proof on completion and toggles the door. The lockpick may break according to `Config.LockpickBreakChance`. Starts are rate limited by `Config.lockpickRateLimit`.

## Authorization hooks

Another resource can grant access with a hook. A hook returning `true` grants access, even for doors with restrictions.

```lua
local hookId = exports.kora_doorlock:registerHook('doorAuthorization', function(payload)
    if payload.door.label == 'VIP Room' and isVip(payload.source) then return true end
end, { nameFilter = '^VIP' })

exports.kora_doorlock:removeHook(hookId)
```

Only `doorAuthorization` is supported. The payload has `source`, `doorId`, `door`, `lockpick` and `authorised`. `nameFilter` is a Lua pattern matched against the door label; `print = true` logs each trigger. Hooks are removed when the registering resource stops. Only register hooks you trust.

## Door policies

A server resource can attach an authoritative policy to a door ID with `RegisterDoorPolicy(id, callback)`. The callback receives `(source, id, context)` with `lockpick`, `authorised` and `door`, and must return `true` to allow. For such doors the policy has the final say, including over hook grants. If the door is linked, the linked door's policy must also approve.

- The first registration marks the door as owned by the calling resource (stored in the door definition) and locks it.
- When the owner stops, or calls `ClearDoorPolicy`, the door is locked and stays closed to everyone until the policy is registered again.
- `ReleaseDoorPolicy` durably removes the ownership, restoring the door's normal permissions.
- Other resources cannot change a policy they do not own.

See the [API reference](./api/server.md) for the signatures.
