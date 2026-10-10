#!/usr/bin/env sh
set -eu

LUA_BIN="${LUA:-lua5.4}"
"$LUA_BIN" test/schema.lua
"$LUA_BIN" test/server.lua
"$LUA_BIN" test/database.lua
"$LUA_BIN" test/contract.lua
"$LUA_BIN" test/creator.lua
