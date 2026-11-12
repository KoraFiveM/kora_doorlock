---
title: Database
sidebar_position: 11
---

# Database

Tables are created and checked automatically at start with `kora_sql`. There is nothing to import.

| Table | Columns | Purpose |
| --- | --- | --- |
| `kora_doorlock_doors` | `id` varchar(64) primary, `definition` longtext JSON, `created_at` | In-game doors, overrides of configured doors, and tombstones. |
| `kora_doorlock_links` | `door_id` varchar(64) primary, `linked_door_id` varchar(64) | Linked pairs, stored as two rows (one per direction). A link is only used if both directions exist and both doors exist. |
| `kora_doorlock_categories` | `id` varchar(48) primary, `label` varchar(96), `defaults` longtext JSON, `created_at` | Creator categories and their default settings. |

- A stored door with the same ID as a configured door overrides it.
- Deleting a configured door stores the definition `{"deleted":true}` so it stays removed after a restart. Deleting a door that exists only in the database deletes the row.
- Stored passcodes are kept in the definition JSON in plain text.
- Lock and unlock state is not stored.
- Malformed rows are skipped with a console warning.
- The `ox_doorlock` table is only read by the import command.
