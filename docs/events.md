---
title: Events
sidebar_position: 10
---

# Events

## Local server events (for other resources)

| Event | Arguments | Description |
| --- | --- | --- |
| `kora_doorlock:stateChanged` | `source, doorId, locked, usedItem` | Fired after every state change. `source` is nil for server, export or auto-lock changes. |
| `kora_doorlock:loaded` | none | Persistent doors, links and categories are ready. Not fired if the database failed to initialise. |
| `kora_doorlock:setState` | `doorId, state` | Handler: sets a state (true/false/0/1). |

```lua
TriggerEvent('kora_doorlock:setState', 'city-hall-office', 0)

AddEventHandler('kora_doorlock:stateChanged', function(source, doorId, locked, usedItem)
end)
```

## Client to server (protected `kora_lib` events)

| Event | Arguments | Description |
| --- | --- | --- |
| `kora_doorlock:server:doorToggled` | `doorId` | Request a toggle. Rate limit 10 per 5 seconds. |
| `kora_doorlock:server:lockpickFinished` | `doorId, authorization, proof` | Reports a lockpick result. |
| `kora_doorlock:server:teleportRequested` | `doorId` | Admin only. |

## Server to client pushes

`kora_doorlock:client:doorStateChanged`, `doorDefinitionUpdated`, `doorDefinitionRemoved`, `teleported`, `managementOpened` and `targetedCreationRequested`.

## Callbacks

| Callback | Direction | Description |
| --- | --- | --- |
| `kora_doorlock:server:doorsRequested` | client to server | All definitions and states. |
| `kora_doorlock:server:lockpickStarted` | client to server | Starts an authorised lockpick game. |
| `kora_doorlock:client:passcodeRequested` | server to client | Asks the player for the passcode. |
| `kora_doorlock:server:management...` | client to server | Admin-only creator operations: `SnapshotRequested`, `StateSet`, `DoorSaved`, `DoorCreated`, `DoorDeleted`, `DoorsLinked`, `DoorsUnlinked`, `CategoryCreated`, `CategoryRenamed`, `CategoryDefaultsSaved`, `CategoryDeleted`, `CategoryDoorCreated`. All check the admin permission and are rate limited. |

These internals are used by the creator and may change; use the [API reference](./api/index.md) from other resources.
