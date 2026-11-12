---
title: Troubleshooting
sidebar_position: 13
---

# Troubleshooting

**Nobody can use a door without requirements.** By default `Config.UnrestrictedDoorsOpenToAll` is false: such doors need a door ACE. Add a restriction or turn the option on.

**Admins cannot open doors with E.** `Config.AdminsBypassDoorAccess` is false by default. Admins can lock or unlock from `/doorlocks`.

**"Door definitions could not be loaded".** The client did not get a reply from the server. Check the server console and that `kora_lib` and `kora_core` started first.

**In-game editing does not work or the creator says storage is not ready.** `kora_sql` was not ready within 60 seconds or the schema failed. Check the console for `persistent door management is disabled`.

**A door resets to locked after a restart.** Lock state is not persisted; set `locked = false` on the door.

**A deleted configured door is back.** Tombstones live in `kora_doorlock_doors`; check the database is reachable.

**No "Pick lock" option.** It needs `kora_target` started, `lockpick = true` and a locked door (or `Config.CanPickUnlockedDoors`).

**Door sound differs from the configured one.** `Config.IgnoreVehicleDoorSounds` replaces vehicle key fob sounds with the default.

**Door ACE has no effect.** Use `doorlock.ID` or `doorlock.LABEL` exactly, or turn `Config.DoorAceExactOnly` off.

**Enable debug output.** Set `Config.Debug = true` to log each access decision.
