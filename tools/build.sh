#!/usr/bin/env bash
# Builds the single-file Linux executable build/PlanetProtector.x86_64 (PCK embedded).
# Requires Godot 4.7.2 ("godot" on PATH) with the 4.7.2 export templates installed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
godot --headless --path "$ROOT/game" --import
godot --headless --path "$ROOT/game" --export-release "Linux" "$ROOT/build/PlanetProtector.x86_64"
chmod +x "$ROOT/build/PlanetProtector.x86_64"
ls -la "$ROOT/build/PlanetProtector.x86_64"
