---
title: Door creator
sidebar_position: 9
---

# Door creator

Admins (see [Access and permissions](./permissions.md)) manage doors in game. Every change is validated and saved by the server, and the creator shows what the server refused. Passcodes are never sent to the client: the creator only shows whether one is set. Leave the field empty to keep it, type a new code to replace it, or use "Remove passcode".

## Opening it

- `/doorlocks` opens the grid of doors; `/doorlocks closest` opens it sorted by distance.
- `/adddoor` (aliases `/newdoor`, `/doordebug`) starts creating a door.
- See [Commands](./commands.md).

## Doors

The grid lists each door with state, access, distance, auto-lock, link and lockpick setting, and can be searched. Selecting a door opens its page.

## Creating a door

Choose "Create new door", type a name and say whether it is a double door. The creator closes; aim at the door (it is outlined) and press **E** to confirm. For a double door, aim at the second leaf and press **E** again. **Backspace** cancels. The door ID is made from the name (`Back Office` becomes `back-office`, with a numeric suffix if taken). The creating admin must be within 12 metres of every leaf.

## A door's page

- Lock or unlock it, and teleport to it.
- Details: name, interaction distance, auto-lock seconds, movement rate, automatic, hold open, hide indicator.
- Access: passcode, jobs and gangs with minimum grade, characters by ID, key items (name, optional metadata type, used up or kept).
- Lockpicking (on or off, pins, tolerance, speed) and the four sounds.
- Move it by aiming at a different single or double door.
- Link it with another door so they lock and unlock together. A door can have one link; the other door must be unlinked first.
- Duplicate door (copies the settings, then you aim at the new door) and Delete door.

## Categories

A category is a name plus default settings for new doors. Doors never need one.

1. Open the Categories page, create one (`Police` becomes `police`, up to 64 characters, at most 100 categories), and set its default settings.
2. Press "Place doors". Single-door stage: aim at a door and press **E**; it is saved at once as `police-1` named "Police 1" with the defaults. **Backspace** ends the stage. Then a prompt offers double doors; at the second leaf **Backspace** only drops that pair.
3. Each door keeps its own copy of the defaults, so later changes to the category only affect doors placed afterwards.

The next number is one above the highest existing `category-N`. A door already covering an aimed leaf is refused. A door can be moved into or out of a category from its page; this only organises the creator. Deleting a category keeps its doors.

## Editing configured doors

Editing a door that came from `Config.Doors` saves a database override. Deleting it saves a tombstone. See [Database](./database.md).
