#!/usr/bin/env python3
"""Sound effects (16-bit PCM WAV, 44.1 kHz) for Planet Protector - modern, punchy, fully synthesised.

Each effect is normalised to a loudness target (approx. LUFS, BS.1770 K-weighting) and a peak cap, so the
mix is balanced: shots and frequent events sit low, explosions and stingers high, the player explosion is the
loudest/brightest/biggest sound of the game but is peak-limited to -1.5 dBFS (never clips).

Usage: python3 make_sfx.py <out_dir>
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dsp  # noqa: E402
from dsp import SR, ns  # noqa: E402

ROOM = None
HALL = None


def room() -> np.ndarray:
	global ROOM
	if ROOM is None:
		ROOM = dsp.reverb_ir(rt60=0.6, predelay=0.005, damping=0.5, seed=101)
	return ROOM


def hall() -> np.ndarray:
	global HALL
	if HALL is None:
		HALL = dsp.reverb_ir(rt60=1.8, predelay=0.02, damping=0.6, seed=102)
	return HALL


def with_reverb(x: np.ndarray, ir: np.ndarray, wet: float, hp: float = 250.0, length: float | None = None) -> np.ndarray:
	dry = dsp.stereo(x)
	# the dry part must have decayed completely when it ends (no truncation clicks)
	dry = dsp.fade(dry, 0.0, float(np.clip(len(dry) / SR * 0.2, 0.02, 0.3)))
	wet_sig = dsp.convolve(dsp.butter(dry, "highpass", hp, 2), ir)
	n = ns(length) if length else len(dry)
	out = np.zeros((n, 2))
	dsp.mix_into(out, dry, 0)
	dsp.mix_into(out, wet_sig, 0, wet)
	return dsp.fade(out, 0, min(0.12, n / SR * 0.3))


def to_mono(x: np.ndarray) -> np.ndarray:
	return x if x.ndim == 1 else x.mean(axis=1)


def crackle(n: int, seed: int, density: float, start: float, decay: float, hp: float = 2500.0) -> np.ndarray:
	"""Sparse random clicks (debris / sparks), stereo."""
	rng = np.random.default_rng(seed)
	out = np.zeros((n, 2))
	t = 0.0
	while True:
		t += rng.exponential(1.0 / density)
		if t + start >= n / SR:
			break
		k = ns(start + t)
		amp = np.exp(-t / decay) * rng.uniform(0.3, 1.0)
		ln = rng.integers(20, 160)
		click = rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln / 4))
		p = rng.uniform(-0.9, 0.9)
		dsp.mix_into(out, dsp.pan(click, p) * amp, k)
	return dsp.butter(out, "highpass", hp, 2)


# ================================================================================================
# player shots
# ================================================================================================
def shot_laser() -> np.ndarray:
	"""Blue laser: bright FM zap falling 1.9 kHz -> 380 Hz, tiny click and sub punch."""
	n = ns(0.24)
	t = dsp.time_axis(n)
	f = 380.0 + 1550.0 * np.exp(-t / 0.035)
	idx = 2.6 * np.exp(-t / 0.03) + 0.3
	ph = dsp.phase(f, n)
	mod = np.sin(dsp.TAU * 2.0 * ph)
	car = np.sin(dsp.TAU * ph + idx * mod)
	car2 = np.sin(dsp.TAU * dsp.phase(f * 1.006, n) + idx * 0.7 * mod)
	env = dsp.env_points(n, [(0, 0), (0.0015, 1), (0.05, 0.45), (0.24, 0)], curve=3.0)
	y = (car * 0.7 + car2 * 0.4) * env
	y += dsp.butter(dsp.noise(n, 1), "highpass", 4000, 2) * dsp.exp_decay(n, 0.004) * 0.35
	y += np.sin(dsp.TAU * dsp.phase(140 * np.exp(-t / 0.03) + 60, n)) * dsp.exp_decay(n, 0.025) * 0.5
	y = dsp.saturate(y, 1.3)
	return to_mono(with_reverb(y, room(), 0.12))


def shot_rocket() -> np.ndarray:
	"""Rocket launch: ignition pop, rising hiss whoosh, low thump, a few sparks."""
	n = ns(0.5)
	t = dsp.time_axis(n)
	src = dsp.noise(n, 5)
	fc = 700.0 + 2600.0 * (1 - np.exp(-t / 0.08))
	hiss = dsp.tv_filter(src, "bp", fc, q=1.3, block=64)
	hiss_env = dsp.env_points(n, [(0, 0), (0.008, 1), (0.08, 0.7), (0.5, 0)], curve=2.0)
	y = hiss * hiss_env * 0.9
	y += dsp.butter(src, "highpass", 6000, 2) * dsp.exp_decay(n, 0.05) * 0.25
	thump_f = 55.0 + 90.0 * np.exp(-t / 0.02)
	y += np.sin(dsp.TAU * dsp.phase(thump_f, n)) * dsp.exp_decay(n, 0.06, 0.001) * 0.9
	y += to_mono(crackle(n, 6, 60, 0.02, 0.1, 3000)) * 0.5
	whistle = np.sin(dsp.TAU * dsp.phase(900 + 500 * t / 0.5, n)) * dsp.env_points(n, [(0, 0), (0.05, 0.12), (0.5, 0)])
	y += whistle
	y = dsp.saturate(y, 1.5)
	return to_mono(with_reverb(y, room(), 0.15))


def shot_blaster() -> np.ndarray:
	"""Thick red laser: detuned band-limited saws diving 950 -> 140 Hz through a closing filter, sub punch."""
	n = ns(0.34)
	t = dsp.time_axis(n)
	f = 140.0 + 810.0 * np.exp(-t / 0.05)
	fc = 600.0 + 5000.0 * np.exp(-t / 0.06)
	a = dsp.additive(f * 2 ** (-12 / 1200), n, fc, q=2.0)
	b = dsp.additive(f * 2 ** (12 / 1200), n, fc, q=2.0, phase0=0.4)
	c = dsp.additive(f * 0.5, n, fc * 0.6, q=1.0, shape="square")
	env = dsp.env_points(n, [(0, 0), (0.002, 1), (0.09, 0.55), (0.34, 0)], curve=2.5)
	y = (a * 0.5 + b * 0.5 + c * 0.4) * env
	y += np.sin(dsp.TAU * dsp.phase(70 + 120 * np.exp(-t / 0.02), n)) * dsp.exp_decay(n, 0.05) * 0.8
	y += dsp.butter(dsp.noise(n, 9), "bandpass", [2000, 9000], 2) * dsp.exp_decay(n, 0.01) * 0.4
	y = dsp.saturate(y * 1.3, 2.2)
	return to_mono(with_reverb(y, room(), 0.14))


# ================================================================================================
# enemies
# ================================================================================================
def enemy_fire() -> np.ndarray:
	"""Fireball launch: dark 'fwoom' (noise falling through a band-pass) + soft low thoom."""
	n = ns(0.42)
	t = dsp.time_axis(n)
	src = dsp.pink(n, 13)
	fc = 1800.0 * np.exp(-t / 0.09) + 260.0
	whoosh = dsp.tv_filter(src, "bp", fc, q=1.6, block=64)
	env = dsp.env_points(n, [(0, 0), (0.015, 1), (0.12, 0.55), (0.42, 0)], curve=2.0)
	y = whoosh * env
	y += np.sin(dsp.TAU * dsp.phase(70 + 70 * np.exp(-t / 0.05), n)) * dsp.exp_decay(n, 0.09, 0.004) * 0.6
	y += to_mono(crackle(n, 14, 40, 0.01, 0.12, 1500)) * 0.25
	y = dsp.saturate(y * 1.2, 1.6)
	return to_mono(with_reverb(y, room(), 0.18))


def enemy_hit() -> np.ndarray:
	"""Small non-lethal hit: metallic tick + short noise burst + low knock."""
	n = ns(0.2)
	t = dsp.time_axis(n)
	y = np.zeros(n)
	for f, a, d in ((1250, 0.5, 0.05), (2980, 0.35, 0.035), (4420, 0.25, 0.025), (6100, 0.15, 0.02)):
		y += np.sin(dsp.TAU * f * t + f) * a * dsp.exp_decay(n, d, 0.0005)
	y += dsp.butter(dsp.noise(n, 17), "bandpass", [1500, 9000], 2) * dsp.exp_decay(n, 0.008) * 0.6
	y += np.sin(dsp.TAU * dsp.phase(110 + 200 * np.exp(-t / 0.01), n)) * dsp.exp_decay(n, 0.03) * 0.6
	y = dsp.saturate(y, 1.4)
	return to_mono(with_reverb(y, room(), 0.15))


def explosion(n_sec: float, seed: int, boom_hi: float, boom_lo: float, boom_tau: float, roar_tau: float,
			  bright: float, crackle_amt: float, width: float) -> np.ndarray:
	n = ns(n_sec)
	t = dsp.time_axis(n)
	out = np.zeros((n, 2))
	# crack (initial broadband transient)
	for c in range(2):
		crack = dsp.butter(dsp.noise(n, seed + c), "highpass", 1200, 2) * dsp.exp_decay(n, 0.012, 0.0003)
		out[:, c] += crack * 0.9 * bright
	# roar: decorrelated noise with a closing low-pass
	fc = 280.0 + (4500.0 * bright) * np.exp(-t / (roar_tau * 0.45))
	for c in range(2):
		src = dsp.pink(n, seed + 10 + c)
		roar = dsp.tv_filter(src, "lp", fc, q=0.8, block=64, stages=2)
		env = dsp.env_points(n, [(0, 0), (0.004, 1)]) * np.exp(-t / roar_tau)
		out[:, c] += roar * env * 0.9
	# boom: falling sine
	bf = boom_lo + (boom_hi - boom_lo) * np.exp(-t / 0.08)
	boom = np.sin(dsp.TAU * dsp.phase(bf, n)) * dsp.exp_decay(n, boom_tau, 0.002)
	out += dsp.stereo(boom) * 1.1
	# debris / sparks
	out += crackle(n, seed + 20, 70 * crackle_amt, 0.03, n_sec * 0.35, 2500) * 0.55 * crackle_amt
	out = dsp.widen(out, width)
	out = dsp.saturate(out * 1.2, 1.8)
	return out


def enemy_explode() -> np.ndarray:
	y = explosion(1.0, 200, boom_hi=150, boom_lo=45, boom_tau=0.22, roar_tau=0.22, bright=0.8, crackle_amt=0.8,
				  width=1.1)
	return with_reverb(y, hall(), 0.16, 300, 1.15)


def player_explode() -> np.ndarray:
	"""Bigger, deeper, brighter and longer than the enemy explosion; wide stereo; a second blast at 0.12 s."""
	y = explosion(1.9, 300, boom_hi=120, boom_lo=30, boom_tau=0.6, roar_tau=0.55, bright=1.25, crackle_amt=1.6,
				  width=1.45)
	second = explosion(1.6, 350, boom_hi=90, boom_lo=34, boom_tau=0.45, roar_tau=0.45, bright=1.0, crackle_amt=1.0,
					   width=1.3)
	dsp.mix_into(y, second, ns(0.12), 0.6)
	# bright metallic sizzle on top (ship debris)
	n = len(y)
	t = dsp.time_axis(n)
	sizzle = np.stack([dsp.butter(dsp.noise(n, 390 + c), "bandpass", [5000, 12000], 2) for c in range(2)], axis=1)
	sizzle *= (dsp.exp_decay(n, 0.35, 0.005) * (0.6 + 0.4 * np.sin(dsp.TAU * 23 * t) ** 2))[:, None]
	y += sizzle * 0.3
	return with_reverb(y, hall(), 0.22, 250, 2.2)


def locked_hit() -> np.ndarray:
	"""'Clink' on a locked enemy: inharmonic bell partials + a dull blocked knock."""
	n = ns(0.4)
	t = dsp.time_axis(n)
	f0 = 1520.0
	y = np.zeros(n)
	for r, a, d in ((1.0, 0.6, 0.16), (2.76, 0.4, 0.09), (5.40, 0.25, 0.05), (8.93, 0.15, 0.03), (1.5, 0.15, 0.1)):
		y += np.sin(dsp.TAU * f0 * r * t) * a * dsp.exp_decay(n, d, 0.0004)
	y += dsp.butter(dsp.noise(n, 23), "highpass", 5000, 2) * dsp.exp_decay(n, 0.003) * 0.5
	y += np.sin(dsp.TAU * dsp.phase(180 + 150 * np.exp(-t / 0.01), n)) * dsp.exp_decay(n, 0.025) * 0.45
	y = dsp.saturate(y, 1.2)
	return to_mono(with_reverb(y, room(), 0.2))


def materialize() -> np.ndarray:
	"""Spawn shimmer (0.45 s): rising tremolo glissando + rising filtered noise, stereo."""
	n = ns(0.6)
	t = dsp.time_axis(n)
	out = np.zeros((n, 2))
	env = dsp.env_points(n, [(0, 0), (0.25, 0.8), (0.42, 1.0), (0.6, 0)], curve=-1.5)
	trem = 0.55 + 0.45 * np.sin(dsp.TAU * 28 * t)
	for c, det in enumerate((0.997, 1.004)):
		f = (260.0 * 2 ** (t / 0.45 * 2.3)) * det
		tone = np.sin(dsp.TAU * dsp.phase(f, n)) + 0.3 * np.sin(dsp.TAU * dsp.phase(f * 2.01, n))
		nz = dsp.tv_filter(dsp.noise(n, 30 + c), "bp", 800 * 2 ** (t / 0.45 * 3), q=3.0, block=64)
		out[:, c] = (tone * 0.45 * trem + nz * 0.5) * env
	return with_reverb(out, room(), 0.25, 300, 0.75)


# ================================================================================================
# power-ups (SPEC §19.3)
# ================================================================================================
def powerup_on() -> np.ndarray:
	"""Power-up triggered: a resonant two-octave charge-up sweep (E3 -> E5) with a rising noise riser that lands on a
	bright E power-chord stab with a sub hit and a short shimmer; ping-pong echo, room. ~0.95 s, stereo."""
	n = ns(0.95)
	t = dsp.time_axis(n)
	out = np.zeros((n, 2))
	rise = 0.22
	# charge-up: detuned saws gliding up two octaves through an opening resonant low-pass
	k = np.clip(t / rise, 0.0, 1.0)
	f = dsp.midi_hz(52) * 2.0 ** (2.0 * k ** 1.6)
	fc = 500.0 + 6500.0 * k ** 1.3
	sweep_env = dsp.env_points(n, [(0, 0), (0.01, 0.7), (rise, 1.0), (rise + 0.06, 0.0)], curve=1.5)
	for d, p in ((-1, -0.5), (1, 0.5)):
		v = dsp.additive(f * 2 ** (d * 9 / 1200), n, fc, q=3.0, poles=2)
		out += dsp.pan(v * sweep_env * 0.5, p)
	riser = dsp.tv_filter(dsp.noise(n, 61), "bp", 900.0 + 7000.0 * k ** 2, q=2.0, block=64)
	out += dsp.stereo(riser * dsp.env_points(n, [(0, 0), (rise, 0.5), (rise + 0.03, 0.0)], curve=2.0) * 0.35)
	# landing: bright E5 power chord (E5, B5, E6) of detuned saws with a fast filter decay
	s0 = ns(rise)
	cn = n - s0
	ct = dsp.time_axis(cn)
	stab = np.zeros((cn, 2))
	rng = np.random.default_rng(62)
	fcs = 900.0 + 7000.0 * np.exp(-ct / 0.09)
	for m in (76, 83, 88):
		for d in (-1.0, 0.0, 1.0):
			stab += dsp.pan(dsp.saw(dsp.midi_hz(m) * 2 ** (d * 14 / 1200), cn, rng.random()), d * 0.7)
	stab = dsp.tv_filter(stab, "lp", fcs, q=1.1, block=64)
	stab *= dsp.env_points(cn, [(0, 0), (0.004, 1.0), (0.12, 0.45), (cn / SR, 0.0)], curve=2.0)[:, None]
	dsp.mix_into(out, stab, s0, 0.16)
	for i, m in enumerate((88, 95)):
		b = bell(m, cn - ns(0.04 * i), 0.35, 0.8)
		dsp.mix_into(out, dsp.pan(b, -0.3 + 0.6 * i), s0 + ns(0.04 * i), 0.22)
	sub = np.sin(dsp.TAU * dsp.phase(50.0 + 100.0 * np.exp(-ct / 0.025), cn)) * dsp.exp_decay(cn, 0.08, 0.001)
	dsp.mix_into(out, dsp.stereo(sub), s0, 0.45)
	shimmer = np.stack([dsp.butter(dsp.noise(cn, 63 + c), "bandpass", [6000, 13000], 2) for c in range(2)], axis=1)
	dsp.mix_into(out, shimmer * dsp.exp_decay(cn, 0.18, 0.003)[:, None], s0, 0.12)
	out = dsp.saturate(out, 1.3)
	echo = dsp.delay(out, 0.11, 0.3, 3, 5000, 400)
	dsp.mix_into(out, dsp.fade(echo[:n], 0.0, 0.2), 0, 0.3)
	return with_reverb(out, room(), 0.2, 300, 1.1)


def powerup_off() -> np.ndarray:
	"""Power-up over: a 'power-down' - a hollow square tone sliding down an octave and a half through a closing
	filter with a fading tremolo, over a soft falling whoosh. ~0.65 s, stereo."""
	n = ns(0.65)
	t = dsp.time_axis(n)
	out = np.zeros((n, 2))
	f = dsp.midi_hz(76) * 2.0 ** (-1.5 * (1.0 - np.exp(-t / 0.18)))
	fc = 3800.0 * np.exp(-t / 0.2) + 300.0
	env = dsp.env_points(n, [(0, 0), (0.008, 1.0), (0.25, 0.55), (0.6, 0.0)], curve=1.5)
	trem = 1.0 - 0.35 * (0.5 + 0.5 * np.sin(dsp.TAU * (14.0 - 8.0 * t / 0.65) * t)) * np.clip(t / 0.15, 0.0, 1.0)
	for d, p in ((-1, -0.4), (1, 0.4)):
		v = dsp.additive(f * 2 ** (d * 8 / 1200), n, fc, q=1.8, shape="square", poles=2)
		out += dsp.pan(v * env * trem * 0.55, p)
	whoosh = dsp.tv_filter(dsp.pink(n, 71), "bp", 2400.0 * np.exp(-t / 0.15) + 250.0, q=1.4, block=64)
	out += dsp.stereo(whoosh * dsp.env_points(n, [(0, 0), (0.02, 0.6), (0.5, 0.0)], curve=2.0) * 0.4)
	out = dsp.saturate(out, 1.4)
	return with_reverb(out, room(), 0.22, 300, 0.85)


def shield_hit() -> np.ndarray:
	"""A fireball dies on the shield: an electric zap (noise through a resonant band-pass diving 6 kHz -> 1.2 kHz,
	a buzzing 160 Hz pulse), a short metallic ring and a soft low 'thoomp'. ~0.3 s, mono."""
	n = ns(0.3)
	t = dsp.time_axis(n)
	zap = dsp.tv_filter(dsp.noise(n, 81), "bp", 1200.0 + 4800.0 * np.exp(-t / 0.025), q=4.0, block=32)
	y = zap * dsp.exp_decay(n, 0.045, 0.0005) * 1.4
	buzz = dsp.additive(160.0 + 60.0 * np.exp(-t / 0.02), n, 3000.0, q=1.2, shape="square", poles=2)
	y += buzz * dsp.exp_decay(n, 0.03, 0.0005) * 0.3
	for f, a, d in ((930.0, 0.45, 0.07), (2310.0, 0.35, 0.05), (3720.0, 0.25, 0.035)):
		y += np.sin(dsp.TAU * f * t + f) * a * dsp.exp_decay(n, d, 0.0008)
	y += np.sin(dsp.TAU * dsp.phase(90.0 + 120.0 * np.exp(-t / 0.012), n)) * dsp.exp_decay(n, 0.03) * 0.3
	y = dsp.saturate(y, 1.6)
	return to_mono(with_reverb(y, room(), 0.16))


# ================================================================================================
# stingers / ui
# ================================================================================================
def bell(midi: float, n: int, decay: float = 0.6, bright: float = 1.0) -> np.ndarray:
	"""FM bell / glassy pluck."""
	t = dsp.time_axis(n)
	f = dsp.midi_hz(midi)
	idx = (1.8 * bright) * np.exp(-t / (decay * 0.3)) + 0.2
	mod = np.sin(dsp.TAU * f * 3.5 * t)
	y = np.sin(dsp.TAU * f * t + idx * mod) * dsp.exp_decay(n, decay, 0.002)
	y += 0.3 * np.sin(dsp.TAU * f * 2 * t) * dsp.exp_decay(n, decay * 0.4, 0.002)
	return y


def extra_life() -> np.ndarray:
	"""Uplifting: fast E-major arpeggio of glassy bells over a soft supersaw swell, ping-pong delay."""
	n = ns(1.5)
	out = np.zeros((n, 2))
	notes = [76, 80, 83, 88, 92]
	for i, m in enumerate(notes):
		b = bell(m, n - ns(0.065 * i), 0.5 + 0.1 * i)
		dsp.mix_into(out, dsp.pan(b, -0.5 + 0.25 * i), ns(0.065 * i), 0.5)
	pad = np.zeros((n, 2))
	for m in (64, 68, 71, 76):
		for d in (-1, 1):
			pad += dsp.pan(dsp.additive(dsp.midi_hz(m) * 2 ** (d * 10 / 1200), n, 2500.0, q=0.9), d * 0.7)
	pad *= dsp.env_points(n, [(0, 0), (0.12, 0.25), (0.6, 0.2), (1.5, 0)], curve=1.5)[:, None]
	out += pad * 0.35
	echo = dsp.delay(out, 0.14, 0.35, 4, 6000, 300)
	dsp.mix_into(out, dsp.fade(echo[:n], 0.0, 0.3), 0, 0.4)
	return with_reverb(out, hall(), 0.25, 300, 1.8)


def level_complete() -> np.ndarray:
	"""Triumphant stinger: rising bell arp into a big, bright E-major supersaw chord with sub hit and shimmer."""
	n = ns(2.6)
	t = dsp.time_axis(n)
	out = np.zeros((n, 2))
	arp = [64, 68, 71, 76, 80, 83]
	for i, m in enumerate(arp):
		b = bell(m, n - ns(0.07 * i), 0.45)
		dsp.mix_into(out, dsp.pan(b, -0.6 + 0.24 * i), ns(0.07 * i), 0.38)
	c0 = ns(0.42)
	cn = n - c0
	ct = dsp.time_axis(cn)
	chord = np.zeros((cn, 2))
	rng = np.random.default_rng(5)
	for m in (52, 59, 64, 68, 71, 76):
		f0 = dsp.midi_hz(m)
		for d in np.linspace(-1, 1, 5):
			chord += dsp.pan(dsp.saw(f0 * 2 ** (d * 16 / 1200), cn, rng.random()), d * 0.8)
	fc = 600.0 + 5200.0 * (1 - np.exp(-ct / 0.12)) * np.exp(-ct / 1.6)
	chord = dsp.tv_filter(chord, "lp", fc, q=0.9, block=128, stages=2)
	chord *= dsp.env_points(cn, [(0, 0), (0.01, 1), (0.5, 0.65), (cn / SR, 0)], curve=1.5)[:, None]
	dsp.mix_into(out, chord, c0, 0.11)
	sub = np.sin(dsp.TAU * dsp.phase(41.2 + 60 * np.exp(-ct / 0.05), cn)) * dsp.exp_decay(cn, 0.35, 0.002)
	dsp.mix_into(out, dsp.stereo(sub), c0, 0.6)
	shimmer = np.stack([dsp.butter(dsp.noise(cn, 70 + c), "bandpass", [6000, 13000], 2) for c in range(2)], axis=1)
	dsp.mix_into(out, shimmer * dsp.exp_decay(cn, 0.6, 0.01)[:, None], c0, 0.12)
	out = dsp.saturate(out, 1.3)
	return with_reverb(out, hall(), 0.3, 250, 3.0)


def game_over() -> np.ndarray:
	"""Dark descending stinger: closing distorted low drone, falling minor bells, long tail."""
	n = ns(3.4)
	t = dsp.time_axis(n)
	out = np.zeros((n, 2))
	rng = np.random.default_rng(9)
	drone = np.zeros((n, 2))
	for m in (28, 40, 43, 47):
		f0 = dsp.midi_hz(m) * 2 ** (-t * 0.35 / 12)  # slowly sinking
		for d in (-1, 1):
			drone += dsp.pan(dsp.saw(f0 * 2 ** (d * 8 / 1200), n, rng.random()), d * 0.6)
	fc = 200.0 + 1600.0 * np.exp(-t / 0.7)
	drone = dsp.tv_filter(drone, "lp", fc, q=1.2, block=128, stages=2)
	drone *= dsp.env_points(n, [(0, 0), (0.03, 1), (1.2, 0.6), (3.4, 0)], curve=1.2)[:, None]
	out += dsp.saturate(drone * 0.5, 2.0) * 0.6
	for i, m in enumerate([71, 67, 64, 63]):
		s = ns(0.32 * i)
		b = bell(m, n - s, 0.9, 0.7)
		dsp.mix_into(out, dsp.pan(b, 0.4 - 0.25 * i), s, 0.3)
	boom = np.sin(dsp.TAU * dsp.phase(32 + 50 * np.exp(-t / 0.1), n)) * dsp.exp_decay(n, 0.8, 0.003)
	out += dsp.stereo(boom) * 0.6
	return with_reverb(out, hall(), 0.35, 250, 4.0)


def menu_move() -> np.ndarray:
	n = ns(0.08)
	t = dsp.time_axis(n)
	y = np.sin(dsp.TAU * 1320 * t) * dsp.exp_decay(n, 0.018, 0.001)
	y += 0.35 * np.sin(dsp.TAU * 2640 * t) * dsp.exp_decay(n, 0.008, 0.001)
	y += dsp.butter(dsp.noise(n, 41), "highpass", 6000, 2) * dsp.exp_decay(n, 0.002) * 0.25
	return to_mono(with_reverb(y, room(), 0.12, 400, 0.14))


def menu_confirm() -> np.ndarray:
	n = ns(0.45)
	out = np.zeros(n)
	for i, m in enumerate((76, 83)):
		s = ns(0.06 * i)
		b = bell(m, n - s, 0.18, 0.8)
		b += 0.4 * dsp.additive(dsp.midi_hz(m - 12), n - s, 3000.0) * dsp.exp_decay(n - s, 0.08, 0.002)
		dsp.mix_into(out, b, s, 0.6 if i == 0 else 0.75)
	out += dsp.butter(dsp.noise(n, 43), "highpass", 5000, 2) * dsp.exp_decay(n, 0.003) * 0.2
	return to_mono(with_reverb(out, room(), 0.2, 300, 0.55))


def menu_back() -> np.ndarray:
	n = ns(0.36)
	out = np.zeros(n)
	for i, m in enumerate((79, 72)):
		s = ns(0.055 * i)
		b = bell(m, n - s, 0.12, 0.5)
		b += 0.35 * dsp.additive(dsp.midi_hz(m - 12), n - s, 1800.0) * dsp.exp_decay(n - s, 0.07, 0.002)
		dsp.mix_into(out, b, s, 0.7)
	return to_mono(with_reverb(out, room(), 0.18, 300, 0.45))


def bonus_tick() -> np.ndarray:
	n = ns(0.05)
	t = dsp.time_axis(n)
	y = np.sin(dsp.TAU * 2350 * t) * dsp.exp_decay(n, 0.01, 0.0005)
	y += 0.5 * np.sin(dsp.TAU * 4700 * t + 1) * dsp.exp_decay(n, 0.005, 0.0005)
	y += 0.4 * np.sin(dsp.TAU * 3525 * t) * dsp.exp_decay(n, 0.007, 0.0005)
	return dsp.fade(y, 0, 0.01)


# name -> (generator, loudness target LUFS, peak cap dBFS)
SFX = {
	"shot_laser": (shot_laser, -21.0, -6.0),
	"shot_rocket": (shot_rocket, -21.0, -6.0),
	"shot_blaster": (shot_blaster, -19.5, -5.0),
	"enemy_fire": (enemy_fire, -22.0, -7.0),
	"enemy_hit": (enemy_hit, -20.0, -6.0),
	"enemy_explode": (enemy_explode, -15.5, -3.0),
	"locked_hit": (locked_hit, -19.0, -5.0),
	"player_explode": (player_explode, -11.0, -1.5),
	"extra_life": (extra_life, -16.0, -3.0),
	"level_complete": (level_complete, -14.5, -2.0),
	"materialize": (materialize, -24.0, -10.0),
	"menu_move": (menu_move, -21.0, -8.0),
	"menu_confirm": (menu_confirm, -18.0, -5.0),
	"menu_back": (menu_back, -19.5, -6.0),
	"bonus_tick": (bonus_tick, -21.0, -8.0),
	"game_over": (game_over, -14.0, -2.0),
	"powerup_on": (powerup_on, -16.0, -3.0),
	"powerup_off": (powerup_off, -19.5, -5.0),
	"shield_hit": (shield_hit, -20.5, -6.0),
}


def finish(x: np.ndarray, target_lufs: float, peak_cap: float) -> np.ndarray:
	"""Loudness-normalise, then peak-limit to the cap (brick-wall, look-ahead) - never clips."""
	x = dsp.butter(x, "highpass", 20.0, 2)  # DC blocker (saturated noise/booms leave a small offset)
	x = dsp.fade(x, 0.0, 0.004)
	for _ in range(4):
		lu = dsp.loudness(x)
		x = x * dsp.db(target_lufs - lu)
		if dsp.peak_db(x) > peak_cap:
			x = dsp.limiter(x, peak_cap, 0.002, 0.05)
		if abs(dsp.loudness(x) - target_lufs) < 0.2:
			break
	return x


def main() -> None:
	out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
	only = sys.argv[2:] if len(sys.argv) > 2 else None
	for name, (fn, target, cap) in SFX.items():
		if only and name not in only:
			continue
		x = finish(fn(), target, cap)
		dsp.write_wav16(out_dir / f"{name}.wav", x)
		print(f"  {name:15s} {len(x) / SR:5.2f} s ch={1 if x.ndim == 1 else 2} peak {dsp.peak_db(x):6.1f} dBFS "
			  f"loudness {dsp.loudness(x):6.1f} LUFS")


if __name__ == "__main__":
	main()
