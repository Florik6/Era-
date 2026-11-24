#!/bin/bash
# Parse/compile check of every script (autoloads included). Prints errors with file:line.
cd "$(dirname "$0")/.."
timeout 200 godot --headless --import >/dev/null 2>&1
timeout 120 godot --headless --path . tests/load_all.tscn 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error|at: |FAILED|LOAD_ALL_DONE|ERROR" | grep -v "^\s*$" | head -${1:-60}
