#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for test in "$dir"/smoke/*.lua; do "${LUA:-lua}" "$test"; done
