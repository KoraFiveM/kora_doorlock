# kora_doorlock agent guide

`kora_doorlock` is a server-authoritative Kora door lock resource with an in-game creator, built on `kora_lib`. Layout: `fxmanifest.lua`, `config.lua`, `shared/schema.lua` (door validation) and `shared/access.lua` (pure access rules), `client/main.lua` (door system, prompt, keybind, lockpick) and `client/creator.lua` (creator UI), `server/main.lua` (authority, callbacks, commands, exports, persistence) and `server/tables.lua` (schema), `locales/`, `test/` (offline Lua tests) and `tests/` (kora_qa feature files).

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first for an overview of features, configuration, commands, exports, events and database usage.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.
