#!/usr/bin/env python3
"""In-game music samples for the runtime sequencer in AudioManager (200 BPM, bar = 1.2 s = 52920 frames).

Writes raw little-endian float32 PCM (Godot reads them with FileAccess + PackedByteArray.to_float32_array();
*.raw is in the export include filter) plus meta.json into game/assets/audio/music/game/:

  kick.raw    mono one-shot (every quarter)
  snare.raw   stereo one-shot (beat 3; clap + snare body + small room)
  hat.raw     mono one-shot (8ths, velocity groove applied by the sequencer)
  bass.raw    mono, 41 consecutive notes of exactly one quarter (13230 frames) each:
              note s = E1 (41.203 Hz) * 2^(s/12), s = 0..40. Filtered saw + square + sub, saturated,
              loudness-matched so the climb is clearly audible but not jumpy.
  atmos.raw   stereo, 4-bar seamless loop (211680 frames): non-tonal dark air (no pitch, so it never
              clashes with the chromatically rising bass), gently pumped on the quarters.

Usage: python3 make_game_music.py <out_dir> [--preview <wav>]
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dsp  # noqa: E402
from dsp import SR, ns  # noqa: E402

BPM = 200.0
QUARTER = 13230            # 0.3 s
BAR = 4 * QUARTER          # 1.2 s
EIGHTH = QUARTER // 2
BASS_BASE_HZ = 41.203
BASS_NOTES = 41            # semitones 0..40
ATMOS_BARS = 4
# Sequencer pattern (must match audio_manager.gd): hat velocities per 8th, 4-bar cycle
HAT_VEL = [
	[0.55, 1.0, 0.62, 0.92, 0.55, 1.0, 0.66, 0.9],
	[0.55, 0.96, 0.6, 0.92, 0.58, 1.0, 0.62, 0.95],
	[0.55, 1.0, 0.62, 0.92, 0.55, 1.0, 0.66, 0.9],
	[0.58, 0.96, 0.6, 0.94, 0.55, 1.0, 0.7, 1.0],
]
GAIN = {"kick": 0.42, "snare": 0.36, "hat": 0.3, "bass": 0.33, "atmos": 0.2}  # also in audio_manager.gd


def kick() -> np.ndarray:
	n = QUARTER - ns(0.01)
	t = dsp.time_axis(n)
	f = 54.0 + 115.0 * np.exp(-t / 0.024) + 320.0 * np.exp(-t / 0.004)
	body = np.sin(dsp.TAU * dsp.phase(f, n))
	amp = dsp.env_points(n, [(0, 0), (0.001, 1), (0.03, 0.95)]) * np.exp(-np.maximum(t - 0.03, 0) / 0.085)
	click = dsp.butter(dsp.noise(n, 3), "bandpass", [2000, 10000], 2) * dsp.exp_decay(n, 0.003) * 0.45
	click += np.sin(dsp.TAU * 2200 * t) * dsp.exp_decay(n, 0.002) * 0.3
	y = dsp.saturate(body * amp * 1.2 + click, 2.0)
	y = dsp.eq(y, "peak", 120, 1.2, 2.0)
	y = dsp.fade(y, 0, 0.04)
	return dsp.normalize_peak(y, -3.0)


def snare() -> np.ndarray:
	n = ns(0.7)
	t = dsp.time_axis(n)
	f = 195.0 + 70.0 * np.exp(-t / 0.008)
	body = (np.sin(dsp.TAU * dsp.phase(f, n)) + 0.35 * np.sin(dsp.TAU * dsp.phase(f * 1.8, n))) * dsp.exp_decay(n, 0.05)
	nz = dsp.butter(dsp.noise(n, 8), "bandpass", [1500, 12000], 2)
	env = np.zeros(n)
	for i, d in enumerate([0.0, 0.009, 0.018]):
		k = ns(d)
		env[k:] += dsp.exp_decay(n - k, 0.006, 0.0003) * 0.8
	env += dsp.exp_decay(n, 0.11, 0.0006)
	y = body * 0.75 + nz * env * 0.7
	y = dsp.saturate(y, 1.6)
	y = dsp.eq(y, "peak", 2500, 0.9, 2.5)
	room = dsp.reverb_ir(rt60=0.7, predelay=0.006, damping=0.4, seed=12)
	wet = dsp.convolve(dsp.butter(y, "highpass", 400, 2), room)[:n]
	out = dsp.stereo(y) + wet * 0.22
	out = dsp.fade(out, 0, 0.15)
	return dsp.normalize_peak(out, -3.0)


def hat() -> np.ndarray:
	n = ns(0.12)
	ratios = np.array([205.3, 304.4, 369.6, 522.7, 540.0, 800.0]) * 1.7
	metal = sum(dsp.square(r, n, phase0=0.13 * i) for i, r in enumerate(ratios))
	metal = dsp.butter(metal, "bandpass", [7000, 14000], 3)
	nz = dsp.butter(dsp.noise(n, 31), "highpass", 8500, 3)
	y = (metal * 0.55 + nz * 0.55) * dsp.exp_decay(n, 0.022, 0.0002)
	y = dsp.fade(y, 0, 0.02)
	return dsp.normalize_peak(y, -3.0)


def bass_note(semitone: int) -> np.ndarray:
	"""One bass hit, exactly one quarter long, ending in silence."""
	n = QUARTER
	t = dsp.time_axis(n)
	f0 = BASS_BASE_HZ * 2 ** (semitone / 12.0)
	fc = 560.0 + 2.6 * f0 + 3000.0 * np.exp(-t / 0.05)
	a = dsp.additive(f0 * 2 ** (-7 / 1200), n, fc, q=1.4)
	b = dsp.additive(f0 * 2 ** (7 / 1200), n, fc, q=1.4, phase0=0.37)
	sq = dsp.additive(f0, n, fc * 0.8, q=1.0, shape="square", phase0=0.11)
	sub = np.sin(dsp.TAU * f0 * t)
	# sub swells in over ~25 ms so the kick transient keeps its room
	sub_env = np.clip(t / 0.025, 0, 1)
	y = (a + b) * 0.45 + sq * 0.35 + sub * sub_env * 0.38
	amp = dsp.env_points(n, [(0, 0), (0.0015, 1.0), (0.11, 0.62), (0.235, 0.55), (0.292, 0.0), (0.3, 0.0)], curve=2.0)
	y = dsp.saturate(y * amp * 1.5, 3.0)
	# presence: harmonics 4..20 of the low notes carry the pitch on small speakers
	y = dsp.eq(y, "peak", 650, 0.7, 4.5)
	y = dsp.eq(y, "lowshelf", 70, 0.7, -2.0)
	y[-ns(0.008):] = 0.0
	return y


def atmos() -> np.ndarray:
	"""Non-tonal dark air, seamless 4-bar loop, stereo."""
	n = ATMOS_BARS * BAR
	t = np.arange(n) / n  # 0..1 over the loop
	out = np.zeros((n, 2))
	for c in range(2):
		src = dsp.pink(n, 40 + c)
		# moving band (one slow sweep per loop) + a faster shimmer band
		fc = 420.0 * 2 ** (1.2 * np.sin(dsp.TAU * (t + 0.15 * c)))
		wind = dsp.process_looped(lambda x: dsp.tv_filter(x, "bp", np.tile(fc, 3), q=2.2, block=256), src)
		air = dsp.process_looped(lambda x: dsp.butter(x, "bandpass", [5500, 11000], 2), dsp.noise(n, 50 + c))
		air *= 0.5 + 0.5 * np.sin(dsp.TAU * (8 * t + 0.25 * c)) ** 2
		out[:, c] = wind * 0.9 + air * 0.12
	# swell into every second bar line (reverse-envelope noise), circular
	sw_n = ns(1.0)
	sw = dsp.butter(np.stack([dsp.noise(sw_n, 61), dsp.noise(sw_n, 62)], axis=1), "bandpass", [900, 6000], 2)
	sw *= (np.linspace(0, 1, sw_n) ** 3)[:, None]
	for b in (2, 4):
		dsp.mix_into(out, sw, b * BAR - sw_n, 0.35, wrap=True)
	# pump on the quarters (kick)
	q = (np.arange(n) % QUARTER) / SR
	pump = 1.0 - 0.55 * np.where(q < 0.008, q / 0.008, np.exp(-(q - 0.008) / 0.09))
	out *= pump[:, None]
	return dsp.normalize_peak(out, -6.0)


def render_preview(samples: dict, bars: int, semitone_of_quarter) -> np.ndarray:
	"""Python mirror of the GDScript sequencer (for analysis / docs)."""
	n = bars * BAR
	out = np.zeros((n + SR, 2))
	for bar in range(bars):
		b0 = bar * BAR
		for q in range(4):
			dsp.mix_into(out, dsp.stereo(samples["kick"]), b0 + q * QUARTER, GAIN["kick"])
			s = semitone_of_quarter(bar * 4 + q)
			dsp.mix_into(out, dsp.stereo(samples["bass"][s]), b0 + q * QUARTER, GAIN["bass"])
		dsp.mix_into(out, samples["snare"], b0 + 2 * QUARTER, GAIN["snare"])
		for e in range(8):
			v = HAT_VEL[bar % 4][e]
			dsp.mix_into(out, dsp.pan(samples["hat"], 0.15 if e % 2 else -0.1), b0 + e * EIGHTH, GAIN["hat"] * v)
	at = samples["atmos"]
	for s in range(0, n, len(at)):
		dsp.mix_into(out, at, s, GAIN["atmos"])
	return out[:n]


def main() -> None:
	out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
	out_dir.mkdir(parents=True, exist_ok=True)
	samples = {"kick": kick(), "snare": snare(), "hat": hat(), "atmos": atmos()}
	notes = [bass_note(s) for s in range(BASS_NOTES)]
	# loudness match: K-weighted loudness of each note (repeated 4x like in the sequencer) -> equal, then
	# a gentle tilt (+1.5 dB towards the top) so the rising tension is felt
	ref = None
	for s, x in enumerate(notes):
		lu = dsp.loudness(np.concatenate([x] * 4))
		if ref is None:
			ref = lu
		target = ref + 1.5 * s / (BASS_NOTES - 1)
		notes[s] = x * dsp.db(target - lu)
	peak = max(np.max(np.abs(x)) for x in notes)
	notes = [x * (dsp.db(-3.0) / peak) for x in notes]
	samples["bass"] = notes

	meta = {
		"rate": SR, "bpm": BPM, "frames_per_quarter": QUARTER, "frames_per_bar": BAR,
		"bass_base_hz": BASS_BASE_HZ, "bass_notes": BASS_NOTES, "bass_note_frames": QUARTER,
		"samples": {},
	}
	for name in ("kick", "snare", "hat", "atmos"):
		x = samples[name].astype(np.float32)
		dsp.write_raw_f32(out_dir / f"{name}.raw", x)
		meta["samples"][name] = {"file": f"{name}.raw", "channels": 1 if x.ndim == 1 else 2, "frames": len(x)}
	bass = np.concatenate(notes).astype(np.float32)
	dsp.write_raw_f32(out_dir / "bass.raw", bass)
	meta["samples"]["bass"] = {"file": "bass.raw", "channels": 1, "frames": len(bass)}
	(out_dir / "meta.json").write_text(json.dumps(meta, indent="\t") + "\n")
	print(f"game music samples -> {out_dir}")
	for k, v in meta["samples"].items():
		print(f"  {k:6s} {v['frames']:7d} frames ch={v['channels']}")

	if "--preview" in sys.argv:
		p = Path(sys.argv[sys.argv.index("--preview") + 1])
		# 16 bars: bass climbs one semitone every 3 quarters (like steady kills), then wraps (level-17 rule)
		pv = render_preview(samples, 16, lambda q: min(q // 3, 40))
		print(f"  preview: peak {dsp.peak_db(pv):.1f} dBFS, loudness {dsp.loudness(pv):.1f} LUFS")
		dsp.write_wav16(p, pv)


if __name__ == "__main__":
	main()
