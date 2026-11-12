---
title: "How to use"
sidebar_position: 3
---


# How to use

A door is identified everywhere by its permanent string ID. The server holds the one true lock state per ID; the client only renders it and asks the server to toggle it. Every access rule in this section is enforced server-side — the client cannot grant itself access.

## Access checks: every way a door can be opened

When a player interacts with a door (not lockpicking), the server builds a set of `facts` and applies `DoorlockAccess.decide` (`shared/access.lua`): admin or ACE always wins; otherwise a matching character, group or item grants access; otherwise an unrestricted door opens only if `Config.UnrestrictedDoorsOpenToAll` is on. A restricted door with none of those matching but a configured passcode falls through to a passcode prompt. These checks are distinct and are not interchangeable — do not conflate them:

- **ACE** (`hasDoorAce`) — with `Config.DoorAceExactOnly` on (default), only the ACE objects `doorlock.<doorId>` or `doorlock.<door label>` count, checked with `IsPlayerAceAllowed`. With it off, `Kora.permissions.hasPermission` is used instead, which can also match `group.<id>`/`command.<id>` objects. Independently, if `Config.PlayerAceAuthorised` is on, holding the general `Config.PlayerAcePermission` (default `doorlock`) authorises every door.
- **Admin bypass** (`facts.admin`) — only counted when `Config.AdminsBypassDoorAccess` is `true` and the player holds `Config.AdminPermission` (via `Kora.permissions.hasPermission`, prefix `Config.AdminPermissionPrefix`). Off by default: admins manage doors from `/doorlocks` instead of bypassing access with E.
- **Character** (`facts.character`, `DoorlockAccess.matchesCharacter`) — true when the player’s `citizenid` (or `charid`) is listed in the door’s `characters` array (or legacy `citizenIds`).
- **Group** (`facts.group`, `DoorlockAccess.matchesGroup`) — true when the player’s `job` or `gang` name matches a key in the door’s `groups` table and their grade/level is at or above the configured minimum.
- **Item** (`facts.item`) — only checked when none of ace/admin/character/group matched. The server looks up each entry in the door’s `items` list (name + optional `metadata` to match) via `exports.kora_core:getItemsByName`; a match with `amount > 0` and matching metadata grants access. If that item entry has `remove = true`, one unit is consumed with `exports.kora_core:removeItem` on success.
- **Passcode** — only consulted when nothing above authorised and the door has a `passcode` set. The server calls the client callback `kora_doorlock:client:passcodeRequested` (which opens an `Kora.nui` password input dialog) and compares the typed value verbatim. A non-empty, wrong answer is reported back as `wrongPasscode`, which the client shows as "Incorrect PIN" rather than a generic "Access denied".
- **Hooks** — any resource can register a `doorAuthorization` hook (see Functions & exports) that runs after the checks above and can force `authorised = true` (it cannot force a denial once something else already said yes; its `false`/`nil` result does not override a `true`).
- **Door policy** — if the door has a `policyOwner` (set via `RegisterDoorPolicy`), the owning resource’s callback gets the final say: it receives `{ lockpick, authorised, door }` and its return value (`true`/not-`true`) replaces the access decision entirely.
- **Linked doors** — two linked doors mirror each other’s state. If the door being toggled is linked to a door that itself has a `policyOwner`, that linked door’s own access check must also pass (checked with `skipLinked = true` to avoid recursing back).

## Lockpicking

Lockpicking is a separate path from the checks above: it never consults characters/groups/passcode/hooks for the pick itself, only whether the player is carrying a usable lockpick item.

1. **Eligibility** — The door must have `lockpick = true`. Unless `Config.CanPickUnlockedDoors` is on, an already-unlocked door cannot be picked.

2. **Start** — The client calls the callback `kora_doorlock:server:lockpickStarted(id)` (rate-limited per `Config.lockpickRateLimit`). The server confirms distance, confirms the player is carrying one of `Config.LockpickItems`, then calls `Kora.minigames.authorizeProof(source, 'lockpick', difficultyOptions(door))` to get a one-time server-issued authorization/proof token sized from the door’s (or config’s) `lockpickDifficulty`. Nothing is removed yet.

3. **Play** — The client plays the pick-door animation and the `lockpick` minigame using that authorization, then sends `kora_doorlock:server:lockpickFinished(id, authorization, proof)`.

4. **Resolve** — The server checks the pending record matches `id`/`authorization`, then calls `Kora.minigames.consumeProof(source, proof, 'lockpick', authorization)` — a minigame result cannot be forged or replayed; only a proof the minigame itself issued and the server itself consumes counts as a win. On success the door is toggled. Independently of success/failure, `Config.LockpickBreakChance` (`success`/`failure` percentages) may break and remove the lockpick item.

## The in-game creator and management UI

The `/doorlocks` command (or admin permission + `client/creator.lua`) opens a Kora UI app backed entirely by server callbacks — there is no separate permission check in the UI itself; every mutation re-checks `isAdmin` server-side. The UI lets staff browse/search doors, edit access (groups, characters, items, passcode), link/unlink pairs, delete doors, and manage "categories" (named default templates used when placing many similar doors, e.g. a police station’s cell block).

- `/adddoor` (configurable via `Config.CreateCommand`, aliases `newdoor`/`doordebug`) opens the raycast-based door creator: aim at a real map door, confirm with E, and the server assigns a slug ID derived from the label (e.g. "Mission Row Armory" → `mission-row-armory`, de-duplicated with a numeric suffix on collision).
- Placing a door inside a category (`kora_doorlock:server:managementCategoryDoorCreated`) reuses the category’s saved defaults and assigns the next free `<category>-N` id/label automatically.
- Deleting a door that was part of `Config.Doors` does not remove its database row outright: it is instead marked `{ deleted = true }` so a server restart does not re-create it from the static config; a door that was only ever created in-game is deleted outright.
