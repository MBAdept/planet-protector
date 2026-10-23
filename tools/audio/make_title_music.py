#!/usr/bin/env python3
"""Title music: dark synthwave / cinematic electronic, E minor, 125 BPM, 16 bars, seamless loop.

Everything is rendered into a circular buffer (every note, reverb and delay tail that runs past the end
is wrapped to the beginning; stateful master processing runs on three copies and keeps the middle), so
the loop point is mathematically continuous.

Arrangement (bars 1-16, chords two bars each: Em | C | Am | B, twice):
  1-8   kick 4/4, clap 2+4, hats, rolling 16th bass + sub, pumping supersaw pads, 16th arpeggio whose
        filter slowly opens; low cinematic "braam" + crash on bar 1; tom fill on bar 8.
  9-16  + lead hook (3-3-2 rhythm), 16th hats, brighter pads, crash + braam on bar 9.
  16    beats 3-4: kick/bass drop out, snare roll + noise riser + reverse cymbal into the loop start.

Usage: python3 make_title_music.py <out.wav> [--stems <dir>]
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dsp  # noqa: E402
from dsp import SR, ns  # noqa: E402

BPM = 125.0
S16 = 5292                 # samples per 16th note at 125 BPM (exact)
BEAT = 4 * S16
BAR = 16 * S16
BARS = 16
L = BARS * BAR             # 1 354 752 samples = 30.72 s
CEILING_DB = -2.0          # Vorbis decoding overshoots by ~0.6 dB; the decoded file must stay <= -1 dBFS

# Chord progression, 2 bars per chord.  pad = voicing, arp = arpeggio tones, bass = rolling bass root.
PROG = [
	{"name": "Em", "pad": [52, 55, 59, 64, 71], "arp": [64, 67, 71, 76], "bass": 40},
	{"name": "C", "pad": [48, 55, 60, 64, 67], "arp": [64, 67, 72, 76], "bass": 36},
	{"name": "Am", "pad": [45, 52, 57, 60, 64], "arp": [64, 69, 72, 76], "bass": 33},
	{"name": "B", "pad": [47, 54, 59, 63, 66], "arp": [63, 66, 71, 75], "bass": 35},
]

# Lead hook (bars 9-16): (start in beats from bar 9, length in beats, midi, velocity)
HOOK = [
	(0.0, .75, 71, 1.0), (.75, .75, 76, .85), (1.5, 1.0, 79, .95), (2.5, .5, 78, .8), (3.0, 1.0, 76, .9),
	(4.0, .75, 74, 1.0), (4.75, .75, 76, .85), (5.5, 2.5, 71, .9),
	(8.0, .75, 72, 1.0), (8.75, .75, 76, .85), (9.5, 1.0, 79, .95), (10.5, .5, 81, .85), (11.0, 1.0, 79, .9),
	(12.0, .75, 76, 1.0), (12.75, .75, 79, .85), (13.5, 2.5, 76, .9),
	(16.0, .75, 69, 1.0), (16.75, .75, 72, .85), (17.5, 1.0, 76, .95), (18.5, .5, 79, .85), (19.0, 1.0, 76, .9),
	(20.0, .75, 72, 1.0), (20.75, .75, 74, .85), (21.5, 2.5, 76, .9),
	(24.0, .75, 75, 1.0), (24.75, .75, 78, .85), (25.5, 1.0, 83, 1.0), (26.5, .5, 81, .85), (27.0, 1.0, 78, .9),
	(28.0, .75, 75, 1.0), (28.75, .75, 78, .9), (29.5, 2.5, 83, 1.0),
]


def at(bar: int, beat: float = 0.0) -> int:
	return int(round(bar * BAR + beat * BEAT))


def chord(bar: int) -> dict:
	return PROG[(bar // 2) % 4]


# ================================================================================================
# drums
# ================================================================================================
def kick() -> np.ndarray:
	n = ns(0.55)
	t = dsp.time_axis(n)
	f = 49.0 + 90.0 * np.exp(-t / 0.032) + 260.0 * np.exp(-t / 0.005)
	body = np.sin(dsp.TAU * dsp.phase(f, n))
	amp = dsp.env_points(n, [(0, 0), (0.0015, 1), (0.04, 0.92), (0.55, 0)], curve=0.0)
	amp *= np.exp(-np.maximum(t - 0.04, 0) / 0.13)
	click = dsp.butter(dsp.noise(n, 11), "bandpass", [1500, 9000], 2) * dsp.exp_decay(n, 0.004) * 0.5
	click += np.sin(dsp.TAU * 1800 * t) * dsp.exp_decay(n, 0.0025) * 0.35
	y = dsp.saturate(body * amp * 1.15 + click, 1.8)
	y = dsp.eq(y, "peak", 3500, 1.0, 2.0)
	return dsp.fade(y, 0, 0.03) * 0.95


def snare(seed: int = 3, tone: float = 1.0, length: float = 0.35) -> np.ndarray:
	n = ns(length)
	t = dsp.time_axis(n)
	f = 185.0 + 60.0 * np.exp(-t / 0.01)
	body = (np.sin(dsp.TAU * dsp.phase(f, n)) + 0.4 * np.sin(dsp.TAU * dsp.phase(f * 1.72, n))) * dsp.exp_decay(n, 0.055)
	nz = dsp.butter(dsp.noise(n, seed), "bandpass", [1800, 11000], 2) * dsp.exp_decay(n, 0.09, 0.0008)
	y = dsp.saturate(body * 0.7 * tone + nz * 0.8, 1.4)
	return dsp.fade(y, 0, 0.02)


def clap(seed: int = 5) -> np.ndarray:
	n = ns(0.5)
	t = dsp.time_axis(n)
	src = dsp.butter(dsp.noise(n, seed), "bandpass", [900, 6500], 2)
	env = np.zeros(n)
	for i, d in enumerate([0.0, 0.0105, 0.0215, 0.031]):
		k = ns(d)
		e = dsp.exp_decay(n - k, 0.0065 if i < 3 else 0.12, 0.0004)
		env[k:] += e * (0.85 if i < 3 else 1.0)
	y = src * env
	y += snare(seed + 1, tone=0.8, length=0.5) * 0.45
	y = dsp.eq(y, "peak", 1200, 0.8, 3.0)
	y = dsp.saturate(y * 0.9, 1.3)
	return dsp.fade(y, 0, 0.05)


def hat(decay: float = 0.035, seed: int = 21, length: float = 0.25) -> np.ndarray:
	n = ns(length)
	ratios = np.array([205.3, 304.4, 369.6, 522.7, 540.0, 800.0]) * 1.6
	metal = sum(dsp.square(r, n, phase0=np.random.default_rng(seed + i).random()) for i, r in enumerate(ratios))
	metal = dsp.butter(metal, "bandpass", [6500, 13000], 3)
	nz = dsp.butter(dsp.noise(n, seed), "highpass", 8000, 3)
	y = (metal * 0.6 + nz * 0.5) * dsp.exp_decay(n, decay, 0.0003)
	y = dsp.eq(y, "highshelf", 11000, 0.7, 3.0)
	return dsp.fade(y / (np.max(np.abs(y)) + 1e-9), 0, 0.01)


def crash(seed: int = 31, length: float = 2.8) -> np.ndarray:
	n = ns(length)
	out = np.zeros((n, 2))
	for c in range(2):
		ratios = np.array([205.3, 304.4, 369.6, 522.7, 540.0, 800.0, 1043.0, 1243.0]) * (1.3 + 0.05 * c)
		metal = sum(dsp.square(r, n, phase0=np.random.default_rng(seed + i + 10 * c).random()) for i, r in enumerate(ratios))
		metal = dsp.butter(metal, "bandpass", [3500, 14000], 2)
		nz = dsp.butter(dsp.noise(n, seed + c), "highpass", 4500, 2)
		env = dsp.exp_decay(n, 0.75, 0.001) * 0.7 + dsp.exp_decay(n, 0.09, 0.0005) * 0.5
		out[:, c] = (metal * 0.35 + nz * 0.65) * env
	out = dsp.eq(out, "peak", 9000, 0.7, 2.0)
	return dsp.fade(out / np.max(np.abs(out)), 0, 0.4)


def tom(f0: float, seed: int = 41) -> np.ndarray:
	n = ns(0.6)
	t = dsp.time_axis(n)
	f = f0 * (1.0 + 0.6 * np.exp(-t / 0.03))
	y = np.sin(dsp.TAU * dsp.phase(f, n)) * dsp.exp_decay(n, 0.18, 0.001)
	y += dsp.butter(dsp.noise(n, seed), "bandpass", [300, 3000], 2) * dsp.exp_decay(n, 0.02) * 0.25
	return dsp.fade(dsp.saturate(y, 1.6), 0, 0.05)


def impact() -> np.ndarray:
	"""Cinematic low boom for the loop start."""
	n = ns(2.6)
	t = dsp.time_axis(n)
	f = 34.0 + 46.0 * np.exp(-t / 0.25)
	y = np.sin(dsp.TAU * dsp.phase(f, n)) * dsp.exp_decay(n, 0.9, 0.002)
	y += dsp.butter(dsp.noise(n, 51), "lowpass", 400, 2) * dsp.exp_decay(n, 0.25, 0.001) * 0.6
	return dsp.fade(dsp.saturate(y, 1.5), 0, 0.5)


def riser(length: float, seed: int = 61) -> np.ndarray:
	n = ns(length)
	t = dsp.time_axis(n) / length
	src = np.stack([dsp.noise(n, seed), dsp.noise(n, seed + 1)], axis=1)
	fc = 250.0 * (9000.0 / 250.0) ** (t ** 1.6)
	y = dsp.tv_filter(src, "bp", fc, q=1.6, block=128)
	y += dsp.tv_filter(src, "hp", fc * 0.8, q=0.7, block=128) * 0.35
	amp = t ** 2.2
	return y * amp[:, None] / (np.max(np.abs(y)) + 1e-9)


def downlifter(length: float, seed: int = 71) -> np.ndarray:
	n = ns(length)
	t = dsp.time_axis(n) / length
	src = np.stack([dsp.noise(n, seed), dsp.noise(n, seed + 1)], axis=1)
	fc = 7000.0 * (300.0 / 7000.0) ** (t ** 0.7)
	y = dsp.tv_filter(src, "bp", fc, q=1.2, block=128)
	amp = (1.0 - t) ** 2 * np.clip(t / 0.01, 0, 1)
	return y * amp[:, None] / (np.max(np.abs(y)) + 1e-9)


# ================================================================================================
# tonal instruments
# ================================================================================================
def supersaw_note(midi: float, length: float, seed: int, voices: int = 7, spread_cents: float = 22.0) -> np.ndarray:
	"""Unfiltered stereo supersaw for one pad note (attack/release applied, filter later on the bus)."""
	n = ns(length)
	rng = np.random.default_rng(seed)
	out = np.zeros((n, 2))
	f0 = dsp.midi_hz(midi)
	det = np.linspace(-1.0, 1.0, voices)
	for i, d in enumerate(det):
		cents = d * spread_cents * (0.85 + 0.3 * rng.random())
		f = f0 * 2 ** (cents / 1200.0)
		drift = 1.0 + 0.0008 * np.sin(dsp.TAU * (0.13 + 0.1 * rng.random()) * dsp.time_axis(n) + rng.random() * 6)
		v = dsp.saw(f * drift, n, phase0=rng.random())
		out += dsp.pan(v, d * 0.85) * (1.0 if i == voices // 2 else 0.8)
	return out / voices


def pluck(midi: float, bright: float, seed: int) -> np.ndarray:
	"""Arp pluck: saw+square additive with a snappy filter envelope; stereo (two detuned layers)."""
	n = ns(0.24)
	t = dsp.time_axis(n)
	f0 = dsp.midi_hz(midi)
	fc = 350.0 + (900.0 + 4200.0 * bright) * np.exp(-t / (0.045 + 0.03 * bright))
	amp = dsp.env_points(n, [(0, 0), (0.002, 1), (0.11, 0.5), (0.24, 0)], curve=2.5)
	a = dsp.additive(f0 * 2 ** (-6 / 1200), n, fc, q=1.4) * 0.6 + dsp.additive(f0 * 2 ** (-6 / 1200), n, fc, q=1.4, shape="square") * 0.5
	b = dsp.additive(f0 * 2 ** (6 / 1200), n, fc, q=1.4, phase0=0.3) * 0.6 + dsp.additive(f0 * 2 ** (6 / 1200), n, fc, q=1.4, shape="square", phase0=0.5) * 0.5
	return np.stack([a * amp, b * amp], axis=1)


_bass_cache: dict[int, np.ndarray] = {}


def bass_note(midi: int) -> np.ndarray:
	"""Short rolling-bass note: alias-free saw through a resonant LP with envelope + sine sub, saturated."""
	if midi in _bass_cache:
		return _bass_cache[midi]
	n = ns(0.15)
	t = dsp.time_axis(n)
	f0 = dsp.midi_hz(midi)
	fc = 160.0 + f0 * 2.0 + 1700.0 * np.exp(-t / 0.035)
	saw = dsp.additive(f0, n, fc, q=1.3)
	sub = np.sin(dsp.TAU * f0 * t)
	amp = dsp.env_points(n, [(0, 0), (0.002, 1), (0.06, 0.75), (0.115, 0.6), (0.15, 0)], curve=2.0)
	y = dsp.saturate((saw * 0.8 + sub * 0.6) * amp, 1.7)
	_bass_cache[midi] = y
	return y


def braam(midis: list[int], length: float = 3.2, seed: int = 81) -> np.ndarray:
	"""Low distorted cinematic brass-like hit with slowly opening filter."""
	n = ns(length)
	t = dsp.time_axis(n)
	out = np.zeros((n, 2))
	rng = np.random.default_rng(seed)
	for m in midis:
		f0 = dsp.midi_hz(m)
		for d in (-1, 1):
			out += dsp.pan(dsp.saw(f0 * 2 ** (d * 9 / 1200), n, rng.random()), d * 0.6)
	fc = 120.0 + 1500.0 * (1 - np.exp(-t / 0.35)) * np.exp(-t / 1.4)
	out = dsp.tv_filter(out, "lp", fc, q=1.1, block=128, stages=2)
	amp = dsp.env_points(n, [(0, 0), (0.04, 1), (length * 0.5, 0.45), (length, 0)], curve=1.5)
	out = dsp.saturate(out * amp[:, None] * 2.5, 2.2)
	return out / np.max(np.abs(out))


def lead_line(notes: list[tuple[int, int, int, float]], n: int) -> np.ndarray:
	"""Monophonic legato lead. notes = [(start_sample, end_sample, midi, vel)] sorted, within [0, n).
	Glide between connected notes, delayed vibrato, 3 detuned saws + sub square, filter follows the notes."""
	t = dsp.time_axis(n)
	pitch = np.full(n, float(notes[0][2]))
	amp = np.zeros(n)
	note_t = np.zeros(n)        # time since note start (for vibrato / filter env)
	vel_arr = np.zeros(n)
	for i, (s, e, m, v) in enumerate(notes):
		pitch[s:] = m
		note_t[s:] = t[s:] - t[s]
		vel_arr[s:] = v
		legato = i > 0 and notes[i - 1][1] >= s - 10
		att = 0.012 if not legato else 0.006
		rel_end = min(e + ns(0.22), n)
		seg = np.arange(s, rel_end)
		local = (seg - s) / SR
		gate = (e - s) / SR
		env = np.where(local < att, (0.75 if legato else 0.0) + (1 - (0.75 if legato else 0.0)) * local / att,
					   0.82 + 0.18 * np.exp(-(local - att) / 0.15))
		rel = np.where(local > gate, np.exp(-(local - gate) / 0.06), 1.0)
		amp[seg] = np.maximum(amp[seg], env * rel * v)
	# glide: smooth pitch in the log domain (only where notes connect it audibly matters)
	pitch_s = dsp.one_pole_lp(pitch, 1.0 / (dsp.TAU * 0.022))
	vib = 0.16 * np.clip((note_t - 0.28) / 0.35, 0, 1) * np.sin(dsp.TAU * 5.4 * t)
	freq = 440.0 * 2 ** ((pitch_s + vib - 69.0) / 12.0)
	out = np.zeros((n, 2))
	for d, p, ph in ((-9, -0.55, 0.1), (0, 0.0, 0.4), (9, 0.55, 0.7)):
		out += dsp.pan(dsp.saw(freq * 2 ** (d / 1200), n, ph), p) * 0.5
	out += dsp.stereo(dsp.square(freq * 0.5, n, 0.2, pw=0.42)) * 0.28
	fc = 900.0 + 2600.0 * vel_arr + 3800.0 * np.exp(-note_t / 0.12)
	out = dsp.tv_filter(out, "lp", fc, q=1.05, block=64, stages=2)
	out = out * amp[:, None]
	out = dsp.saturate(out * 1.4, 1.6)
	return out


# ================================================================================================
# arrangement
# ================================================================================================
def pump_curve(kick_pos: list[int], depth: float, release_beats: float = 0.55) -> np.ndarray:
	"""Sidechain gain curve from kick positions (circular)."""
	ks = np.array(sorted(p % L for p in kick_pos))
	idx = np.arange(L)
	j = np.searchsorted(ks, idx, side="right") - 1
	last = np.where(j >= 0, ks[j], ks[-1] - L)
	tau = (idx - last) / SR
	rel = release_beats * BEAT / SR
	att = 0.010
	f = np.where(tau < att, 0.5 - 0.5 * np.cos(np.pi * tau / att),
				 0.5 * (1 + np.cos(np.pi * np.clip((tau - att) / rel, 0, 1))))
	return 1.0 - depth * f


def loop(fn, x: np.ndarray) -> np.ndarray:
	"""Apply a stateful (filter) function to a loop buffer without a seam."""
	return dsp.process_looped(fn, x)


def render(stems_dir: Path | None = None) -> np.ndarray:
	buses = {k: np.zeros((L, 2)) for k in ("kick", "snare", "hats", "fx", "bass", "pads", "arp", "lead", "braam")}
	send_rev = np.zeros((L, 2))       # big hall
	send_room = np.zeros((L, 2))      # drum room
	send_delay = np.zeros((L, 2))     # dotted-8th ping-pong

	# ---------------- drums ----------------
	k = kick()
	kick_pos = []
	for bar in range(BARS):
		for beat in range(4):
			if bar == BARS - 1 and beat >= 2:
				continue  # drop before the loop point
			kick_pos.append(at(bar, beat))
			dsp.mix_into(buses["kick"], k, at(bar, beat), 1.0, wrap=True)
	cl = clap()
	for bar in range(BARS):
		for beat in (1, 3):
			if bar == BARS - 1 and beat == 3:
				continue
			v = 0.82 if bar < 8 else 0.88
			dsp.mix_into(buses["snare"], dsp.pan(cl, 0.0), at(bar, beat), v, wrap=True)
			dsp.mix_into(send_room, dsp.stereo(cl), at(bar, beat), v * 0.5, wrap=True)
			dsp.mix_into(send_rev, dsp.stereo(cl), at(bar, beat), v * 0.18, wrap=True)
	# bar 8 (index 7) beat 4: tom fill, bar 16 beats 3-4: snare roll crescendo
	toms = [(3.0, 150.0), (3.25, 120.0), (3.5, 96.0), (3.75, 78.0)]
	for b, f in toms:
		dsp.mix_into(buses["snare"], dsp.pan(tom(f), -0.3 + 0.2 * toms.index((b, f))), at(7, b), 0.42, wrap=True)
		dsp.mix_into(send_rev, dsp.stereo(tom(f)), at(7, b), 0.15, wrap=True)
	for i in range(8):
		v = 0.2 + 0.3 * i / 7
		dsp.mix_into(buses["snare"], dsp.stereo(snare(100 + i, 0.8, 0.25)), at(15, 2.0 + i * 0.25), v, wrap=True)
		dsp.mix_into(send_rev, dsp.stereo(snare(100 + i, 0.8, 0.25)), at(15, 2.0 + i * 0.25), v * 0.25, wrap=True)
	for i in range(4):
		dsp.mix_into(buses["snare"], dsp.stereo(snare(120 + i, 0.6, 0.2)), at(15, 3.5 + i * 0.125), 0.5 + 0.05 * i, wrap=True)
	# hats
	h_closed = [hat(0.03, 21 + i) for i in range(4)]
	h_open = hat(0.2, 29, 0.6)
	for bar in range(BARS):
		for step in range(16):
			if bar == BARS - 1 and step >= 8:
				continue
			on8 = step % 2 == 0
			if not on8 and bar < 4:
				continue
			if not on8 and bar < 8 and step % 4 != 3:
				continue
			if step % 4 == 2:
				v = 0.75
			elif step % 4 == 0:
				v = 0.42
			else:
				v = 0.26 + 0.06 * ((bar * 7 + step * 3) % 3)
			hs = h_closed[(bar + step) % 4]
			p = 0.18 if step % 4 == 2 else -0.12
			dsp.mix_into(buses["hats"], dsp.pan(hs, p), at(bar, step / 4.0), v, wrap=True)
		if bar >= 8 and bar % 2 == 1 and bar != BARS - 1:
			dsp.mix_into(buses["hats"], dsp.pan(h_open, 0.25), at(bar, 3.5), 0.35, wrap=True)
	# fx: crash + impact at bar 1 and 9, riser into the loop point, downlifter after bar 9
	cr = crash()
	imp = impact()
	for bar in (0, 8):
		dsp.mix_into(buses["fx"], cr, at(bar), 0.55, wrap=True)
		dsp.mix_into(send_rev, cr, at(bar), 0.12, wrap=True)
		dsp.mix_into(buses["fx"], dsp.stereo(imp), at(bar), 0.7 if bar == 0 else 0.5, wrap=True)
	rs = riser(2 * BAR / SR)
	dsp.mix_into(buses["fx"], rs, at(14), 0.30, wrap=True)
	dsp.mix_into(send_rev, rs, at(14), 0.12, wrap=True)
	rev_cym = crash(37, 1.2)[::-1]
	dsp.mix_into(buses["fx"], dsp.fade(rev_cym, 0.3, 0.0), L - len(rev_cym), 0.45, wrap=True)
	rev_cym2 = crash(39, 0.96)[::-1]
	dsp.mix_into(buses["fx"], dsp.fade(rev_cym2, 0.3, 0.0), at(8) - len(rev_cym2), 0.3, wrap=True)
	dl = downlifter(BAR / SR)
	dsp.mix_into(buses["fx"], dl, at(8), 0.18, wrap=True)
	dsp.mix_into(send_rev, dl, at(8), 0.08, wrap=True)

	# ---------------- braam ----------------
	br = braam([28, 40, 47])
	for bar in (0, 8):
		dsp.mix_into(buses["braam"], br, at(bar), 1.0, wrap=True)
		dsp.mix_into(send_rev, br, at(bar), 0.3, wrap=True)

	# ---------------- rolling bass ----------------
	for bar in range(BARS):
		ch = chord(bar)
		for beat in range(4):
			if bar == BARS - 1 and beat >= 2:
				continue
			for s16 in (1, 2, 3):
				m = ch["bass"]
				if bar % 2 == 1 and beat == 3 and s16 >= 2:
					m += 12
				v = (0.8, 0.68, 0.95)[s16 - 1]
				dsp.mix_into(buses["bass"], dsp.stereo(bass_note(m)), at(bar, beat + s16 / 4.0), v, wrap=True)
	# long sub under the fill (bar 16, beats 3-4): falling sine for tension
	n_fill = 2 * BEAT
	tf = dsp.time_axis(n_fill)
	sub_fill = np.sin(dsp.TAU * dsp.phase(dsp.midi_hz(35) * 2 ** (-tf * 0.6), n_fill)) * dsp.env_points(n_fill, [(0, 0), (0.02, 0.6), (n_fill / SR - 0.05, 0.4), (n_fill / SR, 0)])
	dsp.mix_into(buses["bass"], dsp.stereo(sub_fill), at(15, 2), 1.0, wrap=True)

	# ---------------- pads ----------------
	pad_dry = np.zeros((L, 2))
	for ci in range(8):
		bar = ci * 2
		ch = chord(bar)
		length = 2 * BAR / SR + 0.6
		for j, m in enumerate(ch["pad"]):
			note = supersaw_note(m, length, seed=1000 + ci * 10 + j)
			env = dsp.env_points(len(note), [(0, 0), (0.09, 1.0), (length - 0.6, 0.85), (length, 0.0)], curve=1.5)
			dsp.mix_into(pad_dry, note * env[:, None], at(bar), 0.55 if j else 0.7, wrap=True)
	tt = np.arange(L) / L
	pad_fc = np.where(np.arange(L) < 8 * BAR, 1300.0 + 2000.0 * (np.arange(L) / (8 * BAR)) ** 1.5, 3800.0)
	pad_fc = pad_fc * (1.0 + 0.12 * np.sin(dsp.TAU * 4 * tt))
	pad = loop(lambda x: dsp.butter(dsp.tv_filter(x, "lp", np.tile(pad_fc, 3), q=0.9, block=128, stages=2),
									"highpass", 140, 2), pad_dry)
	pump = pump_curve(kick_pos, 0.72)
	buses["pads"] = pad * pump[:, None]
	send_rev += buses["pads"] * 0.35

	# ---------------- arpeggio ----------------
	pattern = [0, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 2, 1, 2, 3]
	accents = {0, 3, 6, 8, 11, 14}
	cache: dict[tuple[int, int], np.ndarray] = {}
	for bar in range(BARS):
		ch = chord(bar)
		for step in range(16):
			if bar == BARS - 1 and step >= 12:
				continue
			m = ch["arp"][pattern[step]]
			if bar >= 8 and step in (7, 15):
				m += 12
			bright = min(1.0, 0.25 + 0.75 * (bar / 7.0)) if bar < 8 else 0.9
			bq = int(round(bright * 8))
			key = (m, bq)
			if key not in cache:
				cache[key] = pluck(m, bq / 8.0, seed=m)
			v = 1.0 if step in accents else 0.62
			if bar >= 8:
				v *= 0.8
			dsp.mix_into(buses["arp"], cache[key], at(bar, step / 4.0), v, wrap=True)
	buses["arp"] = loop(lambda x: dsp.butter(x, "highpass", 220, 2), buses["arp"]) * (0.35 + 0.65 * pump)[:, None]
	send_delay += buses["arp"] * 0.5
	send_rev += buses["arp"] * 0.25

	# ---------------- lead ----------------
	notes = []
	for (b0, length, m, v) in HOOK:
		s = at(8) + int(round(b0 * BEAT))
		e = s + int(round(length * BEAT)) - ns(0.01)
		notes.append((s - at(8), e - at(8), m, v))
	seg_len = 8 * BAR + ns(1.0)
	lead = lead_line(notes, seg_len)
	lead = dsp.butter(lead, "highpass", 180, 2)
	lead = dsp.eq(lead, "peak", 2500, 0.8, 2.0)
	lead = dsp.chorus(lead, 2.5, 0.4, 10.0, 0.35)
	dsp.mix_into(buses["lead"], lead, at(8), 1.0, wrap=True)
	send_delay += buses["lead"] * 0.45
	send_rev += buses["lead"] * 0.4

	# ---------------- returns ----------------
	hall = dsp.reverb_ir(rt60=2.8, predelay=0.025, damping=0.65, seed=3)
	room = dsp.reverb_ir(rt60=0.9, predelay=0.008, damping=0.4, seed=5)
	rev_ret = dsp.convolve(loop(lambda x: dsp.butter(x, "highpass", 250, 2), send_rev), hall, circular=True)
	rev_ret = loop(lambda x: dsp.butter(x, "lowpass", 9000, 2), rev_ret)
	room_ret = dsp.convolve(loop(lambda x: dsp.butter(x, "highpass", 300, 2), send_room), room, circular=True)
	dly_ret = dsp.delay(send_delay, 3 * S16 / SR, feedback=0.42, repeats=7, lp_hz=3500, hp_hz=300, circular=True)
	returns = rev_ret * 0.5 * pump[:, None] ** 0.5 + room_ret * 0.35 + dly_ret * 0.42

	gains = {"kick": 0.53, "snare": 0.62, "hats": 0.75, "fx": 0.6, "bass": 0.36, "pads": 0.85, "arp": 0.52,
			 "lead": 0.48, "braam": 0.27}
	mix = returns.copy()
	for k2, g in gains.items():
		mix += buses[k2] * g
	if stems_dir:
		stems_dir.mkdir(parents=True, exist_ok=True)
		for k2, g in gains.items():
			dsp.write_wav16(stems_dir / f"{k2}.wav", np.clip(buses[k2] * g * 0.5, -1, 1))
			print(f"  stem {k2:6s} rms {dsp.rms_db(buses[k2] * g):6.1f} dB  peak {dsp.peak_db(buses[k2] * g):6.1f} dB")
		print(f"  stem return rms {dsp.rms_db(returns):6.1f} dB")
		print(f"  premaster peak {dsp.peak_db(mix):.1f} dB rms {dsp.rms_db(mix):.1f} dB")
	return master(mix)


def master(mix: np.ndarray) -> np.ndarray:
	y = loop(lambda x: dsp.eq(dsp.eq(dsp.butter(x, "highpass", 28, 2), "highshelf", 9000, 0.7, 1.5),
							  "peak", 320, 0.8, -1.5), mix)
	y = dsp.process_looped(lambda x: dsp.compressor(x, thresh_db=-16.0, ratio=2.2, attack=0.012, release=0.16,
													 knee_db=8.0), y)
	# gain into the limiter so that the result sits around -11.5 LUFS (punchy, ~3 dB max. limiting)
	target = -11.5
	for _ in range(3):
		probe = dsp.process_looped(lambda x: dsp.limiter(x, CEILING_DB, 0.004, 0.09), y)
		lu = dsp.loudness(probe)
		if abs(lu - target) < 0.3:
			break
		y = y * dsp.db(target - lu)
	print(f"  limiter input peak {dsp.peak_db(y):+.1f} dBFS (ceiling {CEILING_DB}) -> max gain reduction {dsp.peak_db(y) - CEILING_DB:.1f} dB")
	y = dsp.process_looped(lambda x: dsp.limiter(x, CEILING_DB, 0.004, 0.09), y)
	return y


def main() -> None:
	out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("title.wav")
	stems = None
	if "--stems" in sys.argv:
		stems = Path(sys.argv[sys.argv.index("--stems") + 1])
	y = render(stems)
	print(f"title: {len(y)} samples ({len(y) / SR:.2f} s) peak {dsp.peak_db(y):.2f} dBFS, "
		  f"loudness {dsp.loudness(y):.1f} LUFS")
	dsp.write_wav16(out, y)


if __name__ == "__main__":
	main()
