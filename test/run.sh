#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$dir")"
cd "$root"
for test in "$dir"/*.lua "$dir"/smoke/*.lua; do "${LUA:-lua}" "$test"; done
if command -v luac5.4 >/dev/null 2>&1; then
    find "$root" -name '*.lua' -not -path '*/.git/*' -print0 | xargs -0 -n1 luac5.4 -p
fi
