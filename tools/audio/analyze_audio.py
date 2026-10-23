#!/usr/bin/env python3
"""Analyses the generated audio files (numpy only): peak, RMS, loudness, octave-band balance, loop seam.

Usage:
  python3 analyze_audio.py                    # analyse everything under game/assets/audio
  python3 analyze_audio.py --bands <file.wav> # octave band balance of one file
  python3 analyze_audio.py --png <dir>        # also write spectrogram previews into <dir>
Exit code 1 if a hard limit is violated (clipping, peak > -1 dBFS for music, broken loop seam ...).
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dsp  # noqa: E402
from dsp import SR  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
AUDIO = ROOT / "game" / "assets" / "audio"


def decode_ogg(path: Path) -> np.ndarray:
	"""Decodes an OGG with ffmpeg into float32 stereo."""
	with tempfile.TemporaryDirectory() as td:
		raw = Path(td) / "out.f32"
		subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(path), "-f", "f32le", "-ac", "2", "-ar", str(SR), str(raw)],
					   check=True)
		return np.frombuffer(raw.read_bytes(), dtype="<f4").astype(float).reshape(-1, 2)


def octave_bands(x: np.ndarray) -> list[tuple[int, float]]:
	mono = x if x.ndim == 1 else x.mean(axis=1)
	spec = np.abs(np.fft.rfft(mono)) ** 2
	f = np.fft.rfftfreq(len(mono), 1 / SR)
	total = spec.sum()
	out = []
	for c in (31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000):
		m = (f >= c / np.sqrt(2)) & (f < c * np.sqrt(2))
		out.append((c, 10 * np.log10(spec[m].sum() / total + 1e-15)))
	return out


def seam_click(x: np.ndarray, period: int, n_ctx: int = 2048) -> tuple[float, float]:
	"""High-passed peak right at the loop seam vs. the same musical position one period (8 bars) later.
	Both positions carry the same downbeat (kick + crash), so a click at the seam would stand out."""
	mono = x if x.ndim == 1 else x.mean(axis=1)

	def hp_peak(center: int) -> float:
		ctx = np.take(mono, np.arange(center - n_ctx, center + n_ctx), mode="wrap")
		hp = dsp.butter(ctx, "highpass", 6000, 4)
		return float(np.max(np.abs(hp[n_ctx - 256:n_ctx + 256])))

	return hp_peak(0), hp_peak(period)


def codec_edge_error(x: np.ndarray, ref: np.ndarray, win: int = 2048) -> tuple[float, float]:
	"""Encoder error (decoded - source) at the file edges vs. the median error elsewhere."""
	e = (x - ref).mean(axis=1)
	edge = max(np.sqrt(np.mean(e[:win] ** 2)), np.sqrt(np.mean(e[-win:] ** 2)))
	mids = [np.sqrt(np.mean(e[i:i + win] ** 2)) for i in range(win, len(e) - 2 * win, win * 7)]
	return float(edge), float(np.median(mids))


def jump_stats(x: np.ndarray) -> tuple[float, float]:
	"""Sample-to-sample step at the seam vs. the 99.9th percentile step inside the file."""
	d = np.abs(np.diff(x, axis=0)).max(axis=1) if x.ndim == 2 else np.abs(np.diff(x))
	seam = float(np.max(np.abs(x[0] - x[-1])))
	return seam, float(np.percentile(d, 99.9))


def main() -> int:
	args = sys.argv[1:]
	png_dir = Path(args[args.index("--png") + 1]) if "--png" in args else None
	if "--bands" in args:
		p = Path(args[args.index("--bands") + 1])
		x = dsp.read_wav16(p) if p.suffix == ".wav" else decode_ogg(p)
		for c, v in octave_bands(x):
			print(f"  {c:6d} Hz {v:6.1f} dB " + "#" * int(max(0, 40 + v)))
		return 0
	ok = True
	report: dict = {}

	# ---- title music ----
	title = AUDIO / "music" / "title.ogg"
	if title.exists():
		x = decode_ogg(title)
		pk = dsp.peak_db(x)
		lu = dsp.loudness(x)
		seam_hp, ref_hp = seam_click(x, len(x) // 2)
		jump, p999 = jump_stats(x)
		print(f"title.ogg: {len(x)} samples = {len(x) / SR:.3f} s, peak {pk:.2f} dBFS, loudness {lu:.1f} LUFS, "
			  f"rms {dsp.rms_db(x):.1f} dB")
		print(f"  seam: hp-peak at loop point {seam_hp:.4f} vs same downbeat at bar 9 {ref_hp:.4f}; "
			  f"step across seam {jump:.4f} vs p99.9 step {p999:.4f}")
		src_wav = Path(args[args.index("--title-wav") + 1]) if "--title-wav" in args else None
		if src_wav and src_wav.exists():
			ref = dsp.stereo(dsp.read_wav16(src_wav))
			if len(ref) == len(x):
				edge, mid = codec_edge_error(x, ref)
				print(f"  codec error at file edges {dsp.to_db(edge):.1f} dB vs typical {dsp.to_db(mid):.1f} dB")
				if edge > 4.0 * mid:
					print("  !! encoder error concentrated at the loop edges")
					ok = False
			else:
				print("  !! decoded length differs from the source")
				ok = False
		print("  octave bands (rel. dB):", " ".join(f"{c}:{v:.0f}" for c, v in octave_bands(x)))
		report["title"] = {"samples": len(x), "peak_db": pk, "lufs": lu}
		if pk > -1.0:
			print("  !! peak above -1 dBFS")
			ok = False
		if seam_hp > 1.5 * ref_hp + 1e-3 or jump > 2.0 * p999:
			print("  !! loop seam looks discontinuous")
			ok = False
		if png_dir:
			dsp.spectrogram_png(png_dir / "title.png", x, 1400, 380)

	# ---- game music samples ----
	gdir = AUDIO / "music" / "game"
	meta_p = gdir / "meta.json"
	if meta_p.exists():
		meta = json.loads(meta_p.read_text())
		print(f"game music: {meta}")
		for name, info in meta["samples"].items():
			data = np.frombuffer((gdir / info["file"]).read_bytes(), dtype="<f4").astype(float)
			ch = int(info.get("channels", 1))
			data = data.reshape(-1, ch) if ch > 1 else data
			print(f"  {name:10s} {len(data) / SR:6.3f} s ch={ch} peak {dsp.peak_db(data):6.1f} dB rms {dsp.rms_db(data):6.1f} dB")
			if np.max(np.abs(data)) > 1.0:
				ok = False
				print("  !! sample exceeds full scale")
		bass = np.frombuffer((gdir / meta["samples"]["bass"]["file"]).read_bytes(), dtype="<f4").astype(float)
		nf = int(meta["bass_note_frames"])
		notes = bass.reshape(-1, nf)
		levels = [dsp.loudness(np.concatenate([n_] * 4)) for n_ in notes]
		print("  bass note loudness (LUFS, every 5th semitone): "
			  + " ".join(f"{i}:{levels[i]:.1f}" for i in range(0, len(levels), 5)))
		# check pitch of each note (fundamental via autocorrelation on the sustained part)
		errs = []
		for s, n_ in enumerate(notes):
			f_exp = 41.203 * 2 ** (s / 12)
			seg = n_[int(0.03 * SR):int(0.25 * SR)]
			ac = np.correlate(seg, seg, "full")[len(seg) - 1:]
			lo = int(SR / (f_exp * 1.5))
			hi = int(SR / (f_exp / 1.5))
			lag = lo + int(np.argmax(ac[lo:hi]))
			errs.append(1200 * np.log2((SR / lag) / f_exp))
		print(f"  bass pitch error: max {np.max(np.abs(errs)):.1f} cents (autocorrelation, integer lag)")
		if png_dir:
			dsp.spectrogram_png(png_dir / "game_bass_notes.png", bass, 1400, 380)

	# ---- sfx ----
	sdir = AUDIO / "sfx"
	if sdir.exists():
		print("sfx:")
		for p in sorted(sdir.glob("*.wav")):
			x = dsp.read_wav16(p)
			pk = dsp.peak_db(x)
			clip = int(np.sum(np.abs(x) >= 32766 / 32768))
			print(f"  {p.stem:15s} {len(x) / SR:5.2f} s ch={1 if x.ndim == 1 else 2} peak {pk:6.1f} dBFS "
				  f"rms {dsp.rms_db(x):6.1f} dB loud {dsp.loudness(x):6.1f} LUFS{'  !! CLIPPED' if clip else ''}")
			if clip or pk > -0.5:
				ok = False
			if png_dir:
				dsp.spectrogram_png(png_dir / f"sfx_{p.stem}.png", x, 700, 240)
	print("RESULT:", "OK" if ok else "PROBLEMS FOUND")
	return 0 if ok else 1


if __name__ == "__main__":
	sys.exit(main())
