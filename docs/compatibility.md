---
title: Compatibility
sidebar_position: 12
---

# Compatibility

## qb-doorlock

The resource provides `qb-doorlock`. These client exports exist:

| Export | Returns |
| --- | --- |
| `GetDoorStates` | Table of door ID to locked state. |
| `GetDoorList` | Table of door ID to door, with `doorLabel` and `textCoords` added. |
| `GetNearbyDoors` | Table of door ID to `true`. |
| `GetClosestDoor` | `{ id, distance, data }`, or an empty table when none. |

Door IDs are Kora string IDs, not the numeric indexes of stock qb-doorlock. The events `qb-doorlock:server:updateState` and `lockpicks:UseLockpick` are not handled.

## ox_doorlock

Doors can be imported with `/importoxdoors`, and the aliases listed in [Door definitions](./doors.md) are accepted. The server exports `getDoor`, `getDoorFromName`, `getAllDoors`, `setDoorState`, `editDoor`, `createDoor`, `removeDoor` and `registerHook` follow the ox shape. See the [API reference](./api/index.md).
