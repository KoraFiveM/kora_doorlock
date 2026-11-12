---
title: kora_doorlock
sidebar_position: 1
---

# kora_doorlock

`kora_doorlock` is a server-authoritative door lock resource for Kora servers, with the feature set of `ox_doorlock`. Doors are defined in `Config.Doors` or created in game with a creator UI, and are saved in the database. Single and double doors support jobs and gangs, character IDs, key items (optionally consumed), passcodes, per-door ACEs, lockpicking, auto-lock, automatic doors, hold-open, hidden indicators and custom sounds. It provides `qb-doorlock` for basic client-side compatibility.

Current version: see `version` in `fxmanifest.lua`.

Every toggle is decided on the server. The client only sends a request and shows the result. Lock state is runtime state; door definitions persist.

## Pages

- [Installation](./installation.md) - dependencies, start order, database setup
- [Configuration](./configuration.md) - every `Config` option
- [Door definitions](./doors.md) - the fields of a door, limits and ox-style aliases
- [Access and permissions](./permissions.md) - how access is decided, ACEs, admin permission, hooks, policies
- [Door creator](./creator.md) - `/doorlocks`, creating, editing and categories
- [Commands](./commands.md) - chat commands and the keybind
- [Exports](./exports.md) - client and server exports
- [Events](./events.md) - local events, net events and callbacks
- [Database](./database.md) - tables and how overrides and deletions are stored
- [Compatibility](./compatibility.md) - `qb-doorlock` and `ox_doorlock` parity
- [Troubleshooting](./troubleshooting.md) - common problems

## Testing

- `test/run.sh` runs the plain Lua tests in `test/` and `test/smoke/` (it needs a sibling `kora_core` resource for the harness).
- `tests/checklist-housing-and-interiors.feature` holds manual QA scenarios for `kora_qa`, registered with `qa_feature` in `fxmanifest.lua`.
