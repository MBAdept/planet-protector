#!/usr/bin/env bash
# Regenerates ALL game audio from scratch (pure numpy/scipy synthesis, no samples) and re-imports it.
#   tools/audio/build_audio.sh            # everything (~1 min)
#   tools/audio/build_audio.sh sfx        # only the sound effects
#   tools/audio/build_audio.sh game       # only the in-game sequencer samples
#   tools/audio/build_audio.sh title      # only the title music
# Requires: python3 + numpy + scipy, ffmpeg with libvorbis, godot 4.7 on PATH (for the import step).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GAME="$ROOT/game"
AUDIO="$GAME/assets/audio"
WHAT="${1:-all}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$AUDIO/music/game" "$AUDIO/sfx"

if [[ "$WHAT" == all || "$WHAT" == title ]]; then
	echo "== title music"
	python3 "$HERE/make_title_music.py" "$TMP/title.wav"
	ffmpeg -v error -y -i "$TMP/title.wav" -c:a libvorbis -q:a 6 "$AUDIO/music/title.ogg"
	cp "$TMP/title.wav" "$TMP/title_src.wav"
fi
if [[ "$WHAT" == all || "$WHAT" == game ]]; then
	echo "== in-game sequencer samples"
	python3 "$HERE/make_game_music.py" "$AUDIO/music/game"
fi
if [[ "$WHAT" == all || "$WHAT" == sfx ]]; then
	echo "== sound effects"
	python3 "$HERE/make_sfx.py" "$AUDIO/sfx"
fi

if command -v godot >/dev/null 2>&1; then
	echo "== godot import"
	godot --headless --path "$GAME" --import >/dev/null 2>&1 || true
	python3 "$HERE/set_import_params.py" "$GAME"
	godot --headless --path "$GAME" --import >/dev/null 2>&1 || true
fi

echo "== analysis"
if [[ -f "$TMP/title_src.wav" ]]; then
	python3 "$HERE/analyze_audio.py" --title-wav "$TMP/title_src.wav"
else
	python3 "$HERE/analyze_audio.py"
fi
