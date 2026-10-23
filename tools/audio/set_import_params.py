#!/usr/bin/env python3
"""Pins the Godot import parameters of the generated audio (run after a first `godot --import`, then import
again so Godot picks the changes up):

  sfx/*.wav        compress/mode=0 (16-bit PCM, no lossy QOA), no trim/normalize, no loop
  music/title.ogg  loop=true, bpm=125, beat_count=64, bar_beats=4

Usage: python3 set_import_params.py <game_dir>
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

WAV_PARAMS = {
	"force/8_bit": "false",
	"force/mono": "false",
	"force/max_rate": "false",
	"edit/trim": "false",
	"edit/normalize": "false",
	"edit/loop_mode": "0",
	"compress/mode": "0",
}
OGG_PARAMS = {"loop": "true", "loop_offset": "0", "bpm": "125", "beat_count": "64", "bar_beats": "4"}


def patch(path: Path, params: dict[str, str]) -> bool:
	text = path.read_text()
	if "[params]" not in text:
		text = text.rstrip("\n") + "\n\n[params]\n"
	head, body = text.split("[params]", 1)
	changed = False
	for key, val in params.items():
		pat = re.compile(rf"^{re.escape(key)}=.*$", re.M)
		line = f"{key}={val}"
		if pat.search(body):
			new_body = pat.sub(line, body)
		else:
			new_body = body.rstrip("\n") + "\n" + line + "\n"
		changed |= new_body != body
		body = new_body
	if changed:
		path.write_text(head + "[params]" + body)
	return changed


def main() -> None:
	game = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "game"
	audio = game / "assets" / "audio"
	n = 0
	for imp in sorted((audio / "sfx").glob("*.wav.import")):
		n += patch(imp, WAV_PARAMS)
	title = audio / "music" / "title.ogg.import"
	if title.exists():
		n += patch(title, OGG_PARAMS)
	print(f"import params patched in {n} file(s)")


if __name__ == "__main__":
	main()
