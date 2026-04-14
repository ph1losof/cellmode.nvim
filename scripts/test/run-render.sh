#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

nvim --headless -u NONE -n -l "$ROOT/scripts/test/render_integration.lua"
