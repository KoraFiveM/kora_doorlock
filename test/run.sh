#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$dir/.."
for test in "$dir"/*.lua "$dir"/smoke/*.lua; do
    [ "$(basename "$test")" = harness.lua ] && continue
    echo "== $test"
    "${LUA:-lua}" "$test"
done
