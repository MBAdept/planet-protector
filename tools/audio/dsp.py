"""Small offline DSP toolkit (numpy/scipy only) for the Planet Protector audio.

Everything in this project is synthesised from scratch with these helpers - no external samples.
Conventions: sample rate SR = 44100, float64 signals in [-1, 1], mono = shape (n,), stereo = shape (n, 2).
"""
from __future__ import annotations

import struct
import wave
import zlib
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
TAU = 2.0 * np.pi


# ------------------------------------------------------------------------------------------------
# basics
# ------------------------------------------------------------------------------------------------
def ns(seconds: float) -> int:
	"""Seconds -> samples."""
	return int(round(seconds * SR))


def db(x: float) -> float:
	"""dB -> linear gain."""
	return float(10.0 ** (x / 20.0))


def to_db(x: float) -> float:
	return float(20.0 * np.log10(max(float(x), 1e-12)))


def midi_hz(m: float) -> float:
	return float(440.0 * 2.0 ** ((m - 69.0) / 12.0))


def time_axis(n: int) -> np.ndarray:
	return np.arange(n) / SR


def stereo(x: np.ndarray) -> np.ndarray:
	if x.ndim == 2:
		return x
	return np.stack([x, x], axis=1)


def pan(x: np.ndarray, p: float) -> np.ndarray:
	"""Constant-power pan of a mono signal, p in [-1 (left), 1 (right)]."""
	a = (p + 1.0) * 0.25 * np.pi
	return np.stack([x * np.cos(a), x * np.sin(a)], axis=1) * np.sqrt(2.0)


def mix_into(dst: np.ndarray, src: np.ndarray, start: int, gain: float = 1.0, wrap: bool = False) -> None:
	"""Adds src into dst at sample offset start. With wrap=True the part that runs past the end is
	added to the beginning (seamless loops)."""
	n = len(dst)
	if src.ndim == 1 and dst.ndim == 2:
		src = stereo(src)
	if wrap:
		start %= n
		pos = 0
		while pos < len(src):
			s = (start + pos) % n
			chunk = min(len(src) - pos, n - s)
			dst[s:s + chunk] += src[pos:pos + chunk] * gain
			pos += chunk
		return
	if start >= n:
		return
	if start < 0:
		src = src[-start:]
		start = 0
	m = min(len(src), n - start)
	if m > 0:
		dst[start:start + m] += src[:m] * gain


def fade(x: np.ndarray, fade_in: float = 0.0, fade_out: float = 0.0) -> np.ndarray:
	y = x.copy()
	a = ns(fade_in)
	b = ns(fade_out)
	if a > 0:
		ramp = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
		y[:a] *= ramp if y.ndim == 1 else ramp[:, None]
	if b > 0:
		ramp = np.cos(np.linspace(0, np.pi / 2, b)) ** 2
		y[-b:] *= ramp if y.ndim == 1 else ramp[:, None]
	return y


# ------------------------------------------------------------------------------------------------
# envelopes
# ------------------------------------------------------------------------------------------------
def env_points(n: int, points: list[tuple[float, float]], curve: float = 0.0) -> np.ndarray:
	"""Breakpoint envelope: points = [(time_s, value), ...]. curve > 0 makes segments exponential-ish."""
	t = time_axis(n)
	ts = np.array([p[0] for p in points], float)
	vs = np.array([p[1] for p in points], float)
	if curve == 0.0:
		return np.interp(t, ts, vs)
	out = np.empty(n)
	out[:] = vs[-1]
	out[t < ts[0]] = vs[0]
	for i in range(len(ts) - 1):
		m = (t >= ts[i]) & (t < ts[i + 1])
		u = (t[m] - ts[i]) / max(ts[i + 1] - ts[i], 1e-9)
		u = (1.0 - np.exp(-curve * u)) / (1.0 - np.exp(-curve))
		out[m] = vs[i] + (vs[i + 1] - vs[i]) * u
	return out


def adsr(n: int, a: float, d: float, s: float, r: float, gate: float | None = None) -> np.ndarray:
	"""Linear-attack / exponential decay+release ADSR. gate = note length in seconds (default: n - r)."""
	t = time_axis(n)
	if gate is None:
		gate = max(n / SR - r, a)
	env = np.where(t < a, t / max(a, 1e-6), s + (1.0 - s) * np.exp(-(t - a) / max(d, 1e-6)))
	g_val = (s + (1.0 - s) * np.exp(-(gate - a) / max(d, 1e-6))) if gate > a else gate / max(a, 1e-6)
	rel = g_val * np.exp(-(t - gate) / max(r / 4.0, 1e-6))
	env = np.where(t < gate, env, rel)
	return env


def exp_decay(n: int, tau: float, attack: float = 0.0005) -> np.ndarray:
	t = time_axis(n)
	att = np.clip(t / max(attack, 1e-6), 0.0, 1.0)
	return att * np.exp(-t / tau)


# ------------------------------------------------------------------------------------------------
# oscillators
# ------------------------------------------------------------------------------------------------
def _as_array(v: float | np.ndarray, n: int) -> np.ndarray:
	return np.broadcast_to(np.asarray(v, float), (n,)).astype(float)


def phase(freq: float | np.ndarray, n: int, phase0: float = 0.0) -> np.ndarray:
	"""Unwrapped phase in cycles; phase[i] = phase0 + sum_{j<i} f[j]/SR."""
	f = _as_array(freq, n)
	ph = np.empty(n)
	ph[0] = 0.0
	np.cumsum(f[:-1] / SR, out=ph[1:])
	return ph + phase0


def _blep(ph: np.ndarray, dt: np.ndarray) -> np.ndarray:
	out = np.zeros_like(ph)
	m = ph < dt
	x = ph[m] / dt[m]
	out[m] = x + x - x * x - 1.0
	m = ph > 1.0 - dt
	x = (ph[m] - 1.0) / dt[m]
	out[m] = x * x + x + x + 1.0
	return out


def saw(freq: float | np.ndarray, n: int, phase0: float = 0.0) -> np.ndarray:
	"""PolyBLEP band-limited sawtooth (rising)."""
	f = _as_array(freq, n)
	dt = np.clip(f / SR, 1e-7, 0.5)
	ph = phase(f, n, phase0) % 1.0
	return 2.0 * ph - 1.0 - _blep(ph, dt)


def square(freq: float | np.ndarray, n: int, phase0: float = 0.0, pw: float = 0.5) -> np.ndarray:
	"""Band-limited pulse made from two PolyBLEP saws."""
	f = _as_array(freq, n)
	dt = np.clip(f / SR, 1e-7, 0.5)
	ph = phase(f, n, phase0)
	p1 = ph % 1.0
	p2 = (ph + pw) % 1.0
	s1 = 2.0 * p1 - 1.0 - _blep(p1, dt)
	s2 = 2.0 * p2 - 1.0 - _blep(p2, dt)
	return 0.5 * (s1 - s2)


def sine(freq: float | np.ndarray, n: int, phase0: float = 0.0) -> np.ndarray:
	return np.sin(TAU * phase(freq, n, phase0))


def lp_mag(ratio: np.ndarray, q: float = 0.707, poles: int = 4) -> np.ndarray:
	"""Magnitude response of a (resonant) analog low-pass at frequency ratio f/fc."""
	r2 = ratio * ratio
	h = 1.0 / np.sqrt((1.0 - r2) ** 2 + r2 / (q * q))
	if poles >= 4:
		h = h / np.sqrt((1.0 - r2) ** 2 + 2.0 * r2)  # second (Butterworth) stage
	return h


def additive(freq: float | np.ndarray, n: int, cutoff: float | np.ndarray, q: float = 0.707, poles: int = 4,
			 shape: str = "saw", phase0: float = 0.0, max_freq: float = 19000.0) -> np.ndarray:
	"""Alias-free saw/square through a (time-varying) analog-style low-pass, by additive synthesis.
	freq and cutoff may be arrays (glides, filter envelopes)."""
	f = _as_array(freq, n)
	fc = np.maximum(_as_array(cutoff, n), 1.0)
	ph = phase(f, n, phase0)
	fmin = max(float(f.min()), 1.0)
	kmax = int(min(max_freq, float(fc.max()) * 12.0) / fmin) + 1
	out = np.zeros(n)
	step = 2 if shape == "square" else 1
	for k in range(1, kmax + 1, step):
		fk = k * f
		amp = lp_mag(fk / fc, q, poles) / k
		# fade harmonics out smoothly towards max_freq (no aliasing, no clicks on glides)
		amp = amp * np.clip((max_freq - fk) / 1500.0, 0.0, 1.0)
		if amp.max() < 1e-5:
			if fk.min() > max_freq or k * fmin > 2.5 * float(fc.max()):
				break
			continue
		out += amp * np.sin(TAU * k * ph)
	return out * (2.0 / np.pi)


def noise(n: int, seed: int = 0) -> np.ndarray:
	return np.random.default_rng(seed).standard_normal(n)


def pink(n: int, seed: int = 0) -> np.ndarray:
	"""Pink-ish noise via FFT shaping."""
	w = np.random.default_rng(seed).standard_normal(n)
	spec = np.fft.rfft(w)
	f = np.fft.rfftfreq(n, 1.0 / SR)
	spec[1:] /= np.sqrt(f[1:] / 20.0).clip(1.0, None)
	spec[0] = 0
	y = np.fft.irfft(spec, n)
	return y / (np.std(y) + 1e-12)


# ------------------------------------------------------------------------------------------------
# filters
# ------------------------------------------------------------------------------------------------
def butter(x: np.ndarray, kind: str, freq: float | list[float], order: int = 2) -> np.ndarray:
	sos = signal.butter(order, freq, btype=kind, fs=SR, output="sos")
	return signal.sosfilt(sos, x, axis=0)


def butter_zp(x: np.ndarray, kind: str, freq: float | list[float], order: int = 2) -> np.ndarray:
	"""Zero-phase version (for offline shaping where phase does not matter)."""
	sos = signal.butter(order, freq, btype=kind, fs=SR, output="sos")
	return signal.sosfiltfilt(sos, x, axis=0)


def rbj(kind: str, f0: float, q: float = 0.707, gain_db: float = 0.0) -> tuple[np.ndarray, np.ndarray]:
	"""RBJ audio-EQ-cookbook biquad coefficients (b, a), a[0] = 1."""
	f0 = float(np.clip(f0, 10.0, SR * 0.49))
	w0 = TAU * f0 / SR
	cw, sw = np.cos(w0), np.sin(w0)
	alpha = sw / (2.0 * q)
	A = 10.0 ** (gain_db / 40.0)
	if kind == "lp":
		b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
		a = [1 + alpha, -2 * cw, 1 - alpha]
	elif kind == "hp":
		b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
		a = [1 + alpha, -2 * cw, 1 - alpha]
	elif kind == "bp":
		b = [alpha, 0.0, -alpha]
		a = [1 + alpha, -2 * cw, 1 - alpha]
	elif kind == "peak":
		b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
		a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
	elif kind == "lowshelf":
		sa = 2 * np.sqrt(A) * alpha
		b = [A * ((A + 1) - (A - 1) * cw + sa), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - sa)]
		a = [(A + 1) + (A - 1) * cw + sa, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sa]
	elif kind == "highshelf":
		sa = 2 * np.sqrt(A) * alpha
		b = [A * ((A + 1) + (A - 1) * cw + sa), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sa)]
		a = [(A + 1) - (A - 1) * cw + sa, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sa]
	else:
		raise ValueError(kind)
	b = np.array(b) / a[0]
	a = np.array(a) / a[0]
	return b, a


def eq(x: np.ndarray, kind: str, f0: float, q: float = 0.707, gain_db: float = 0.0) -> np.ndarray:
	b, a = rbj(kind, f0, q, gain_db)
	return signal.lfilter(b, a, x, axis=0)


def tv_filter(x: np.ndarray, kind: str, cutoff: float | np.ndarray, q: float = 0.707, block: int = 64,
			  stages: int = 1) -> np.ndarray:
	"""Time-varying biquad (block-wise coefficient updates, state carried over). Mono or stereo."""
	if x.ndim == 2:
		return np.stack([tv_filter(x[:, c], kind, cutoff, q, block, stages) for c in range(x.shape[1])], axis=1)
	n = len(x)
	fc = _as_array(cutoff, n)
	y = x.astype(float).copy()
	for _ in range(stages):
		out = np.empty(n)
		zi = np.zeros(2)
		for i in range(0, n, block):
			j = min(i + block, n)
			b, a = rbj(kind, float(fc[(i + j) // 2]), q)
			out[i:j], zi = signal.lfilter(b, a, y[i:j], zi=zi)
		y = out
	return y


def one_pole_lp(x: np.ndarray, hz: float) -> np.ndarray:
	k = np.exp(-TAU * hz / SR)
	return signal.lfilter([1.0 - k], [1.0, -k], x, axis=0)


# ------------------------------------------------------------------------------------------------
# non-linear
# ------------------------------------------------------------------------------------------------
def saturate(x: np.ndarray, drive: float = 2.0, oversample: int = 2, asym: float = 0.0) -> np.ndarray:
	"""tanh soft clip with oversampling. Output roughly level-matched for small signals."""
	if oversample > 1:
		up = signal.resample_poly(x, oversample, 1, axis=0)
	else:
		up = x
	y = np.tanh(drive * (up + asym)) - np.tanh(drive * asym)
	y /= np.tanh(drive)
	if oversample > 1:
		y = signal.resample_poly(y, 1, oversample, axis=0)
		y = y[: len(x)]
	return y


# ------------------------------------------------------------------------------------------------
# space: reverb (synthetic impulse responses), delay, chorus
# ------------------------------------------------------------------------------------------------
def reverb_ir(rt60: float = 2.0, length: float | None = None, predelay: float = 0.015, damping: float = 0.5,
			  seed: int = 7, early: bool = True, brightness: float = 1.0) -> np.ndarray:
	"""Stereo synthetic room IR: band-split noise with frequency dependent decay + early reflections.
	damping 0..1 shortens the high-frequency decay. Normalised to unit energy per channel."""
	length = length or rt60 * 1.15
	n = ns(length)
	t = time_axis(n)
	rng = np.random.default_rng(seed)
	bands = [(30, 220), (220, 900), (900, 3000), (3000, 7500), (7500, 16000)]
	rts = [1.15, 1.0, 1.0 - 0.25 * damping, 1.0 - 0.55 * damping, 1.0 - 0.75 * damping]
	gains = [1.0, 1.0, 0.95, 0.8 * brightness, 0.55 * brightness]
	ir = np.zeros((n, 2))
	for ch in range(2):
		w = rng.standard_normal(n)
		acc = np.zeros(n)
		for (lo, hi), rf, g in zip(bands, rts, gains):
			sos = signal.butter(3, [lo, hi], btype="band", fs=SR, output="sos")
			acc += g * signal.sosfilt(sos, w) * np.exp(-6.907755 * t / (rt60 * rf))
		ir[:, ch] = acc
	ir *= (1.0 - np.exp(-t / 0.012))[:, None]  # density build-up
	if early:
		ref = np.sqrt(np.mean(ir[ns(0.03):ns(0.08)] ** 2))
		for ch in range(2):
			for _ in range(10):
				d = rng.uniform(0.004, 0.06)
				k = ns(d)
				if k < n:
					ir[k, ch] += rng.choice([-1.0, 1.0]) * rng.uniform(2.0, 6.0) * ref * np.exp(-d / 0.05)
	pre = ns(predelay)
	ir = np.vstack([np.zeros((pre, 2)), ir])
	ir /= np.sqrt(np.sum(ir ** 2, axis=0, keepdims=True))
	return ir


def convolve(x: np.ndarray, ir: np.ndarray, circular: bool = False) -> np.ndarray:
	"""Stereo convolution (channel c of x with channel c of ir). circular=True: output length == len(x),
	the tail wraps around to the beginning (perfect for seamless loops; requires len(ir) < len(x))."""
	x = stereo(x)
	if circular:
		n = len(x)
		assert len(ir) < n
		X = np.fft.rfft(x, n, axis=0)
		H = np.fft.rfft(ir, n, axis=0)
		return np.fft.irfft(X * H, n, axis=0)
	return np.stack([signal.fftconvolve(x[:, c], ir[:, c]) for c in range(2)], axis=1)


def reverb(x: np.ndarray, ir: np.ndarray, wet: float, circular: bool = False, hp: float = 0.0,
		   keep_len: bool = True) -> np.ndarray:
	"""Returns the WET signal only (add it to the dry yourself). hp: high-pass the send (Hz)."""
	src = stereo(x)
	if hp > 0:
		src = butter(src, "highpass", hp, 2)
	y = convolve(src, ir, circular) * wet
	if keep_len and not circular:
		return y
	return y


def delay(x: np.ndarray, time_s: float, feedback: float = 0.4, repeats: int = 6, lp_hz: float = 4000.0,
		  hp_hz: float = 150.0, pingpong: bool = True, circular: bool = False, tail: float = 0.0) -> np.ndarray:
	"""Feedback delay built from filtered, shifted copies (wet only). Stereo out."""
	src = stereo(x)
	d = ns(time_s)
	n = len(src) if circular else len(src) + d * repeats + ns(tail)
	out = np.zeros((n, 2))
	cur = src.copy()
	g = 1.0
	def filt(v: np.ndarray) -> np.ndarray:
		v = one_pole_lp(v, lp_hz)
		return butter(v, "highpass", hp_hz, 1) if hp_hz > 0 else v

	for i in range(1, repeats + 1):
		cur = process_looped(filt, cur) if circular else filt(cur)
		g *= feedback
		tap = cur * g
		if pingpong:
			mono = tap.mean(axis=1)
			tap = np.stack([mono, np.zeros_like(mono)] if i % 2 == 1 else [np.zeros_like(mono), mono], axis=1) * 1.4
		mix_into(out, tap, i * d, 1.0, wrap=circular)
	return out


def chorus(x: np.ndarray, depth_ms: float = 3.0, rate: float = 0.6, base_ms: float = 12.0, mix: float = 0.5) -> np.ndarray:
	"""Simple stereo chorus (two modulated delay lines, linear interpolation)."""
	mono = x if x.ndim == 1 else x.mean(axis=1)
	n = len(mono)
	t = time_axis(n)
	out = np.zeros((n, 2))
	for c, ph in enumerate((0.0, 0.25)):
		dly = (base_ms + depth_ms * np.sin(TAU * (rate * t + ph))) * SR / 1000.0
		idx = np.arange(n) - dly
		i0 = np.floor(idx).astype(int)
		fr = idx - i0
		i0c = np.clip(i0, 0, n - 1)
		i1c = np.clip(i0 + 1, 0, n - 1)
		wet = mono[i0c] * (1 - fr) + mono[i1c] * fr
		wet[i0 < 0] = 0.0
		out[:, c] = wet
	return stereo(x) * (1.0 - mix) + out * mix


def widen(x: np.ndarray, width: float) -> np.ndarray:
	x = stereo(x)
	m = (x[:, 0] + x[:, 1]) * 0.5
	s = (x[:, 0] - x[:, 1]) * 0.5 * width
	return np.stack([m + s, m - s], axis=1)


# ------------------------------------------------------------------------------------------------
# dynamics
# ------------------------------------------------------------------------------------------------
def compressor(x: np.ndarray, thresh_db: float = -12.0, ratio: float = 2.0, attack: float = 0.01,
			   release: float = 0.12, knee_db: float = 6.0, makeup_db: float = 0.0, rms_ms: float = 8.0,
			   sidechain: np.ndarray | None = None, ctrl: int = 16) -> np.ndarray:
	"""Feed-forward compressor, RMS detector, soft knee, attack/release smoothing at control rate."""
	x2 = stereo(x)
	det = stereo(sidechain) if sidechain is not None else x2
	p = np.max(det ** 2, axis=1)
	p = one_pole_lp(p, 1.0 / (TAU * rms_ms / 1000.0))
	lvl = 10.0 * np.log10(np.maximum(p, 1e-12))
	over = lvl - thresh_db
	gr = np.where(over <= -knee_db / 2, 0.0,
				  np.where(over >= knee_db / 2, over * (1.0 - 1.0 / ratio),
						   (1.0 - 1.0 / ratio) * (over + knee_db / 2) ** 2 / (2.0 * knee_db)))
	gc = gr[::ctrl]
	ka = np.exp(-ctrl / (attack * SR))
	kr = np.exp(-ctrl / (release * SR))
	sm = np.empty_like(gc)
	s = 0.0
	for i, v in enumerate(gc.tolist()):
		s = (ka * s + (1 - ka) * v) if v > s else (kr * s + (1 - kr) * v)
		sm[i] = s
	g = np.interp(np.arange(len(p)), np.arange(len(gc)) * ctrl, sm)
	gain = 10.0 ** ((makeup_db - g) / 20.0)
	return x2 * gain[:, None] if x.ndim == 2 else x * gain


def limiter(x: np.ndarray, ceiling_db: float = -1.0, lookahead: float = 0.004, release: float = 0.08) -> np.ndarray:
	"""Look-ahead brick-wall peak limiter (sample peak). Output never exceeds the ceiling."""
	x2 = stereo(x)
	n = len(x2)
	c = db(ceiling_db)
	peak = np.max(np.abs(x2), axis=1)
	g_t = np.minimum(1.0, c / np.maximum(peak, 1e-12))
	w = max(1, ns(lookahead))
	# look-ahead minimum over [i, i+w-1] (centered min filter, shifted by w//2)
	from scipy.ndimage import minimum_filter1d
	cm = minimum_filter1d(np.concatenate([g_t, np.ones(w)]), size=w, mode="nearest")
	h = cm[w // 2:w // 2 + n]
	# moving average over the last w samples of h (ramps down before each peak)
	cs = np.concatenate([[0.0], np.cumsum(np.concatenate([np.full(w - 1, h[0]), h]))])
	s = (cs[w:] - cs[:-w]) / w
	s = np.minimum(s, h)
	# release: gain may only rise slowly
	kr = np.exp(-1.0 / (release * SR))
	out = np.empty(n)
	r = 1.0
	sl = s.tolist()
	for i in range(n):
		v = sl[i]
		r = v if v < r else kr * r + (1.0 - kr) * v
		out[i] = r
	y = x2 * out[:, None]
	y = np.clip(y, -c, c)  # numerical safety only, the gain curve already guarantees this
	return y if x.ndim == 2 else y[:, 0]


def process_looped(fn, x: np.ndarray) -> np.ndarray:
	"""Runs a stateful processor on a loop so that the result is seamless: process 3 copies, keep the middle."""
	n = len(x)
	y = fn(np.concatenate([x, x, x], axis=0))
	return y[n:2 * n]


def normalize_peak(x: np.ndarray, peak_db: float) -> np.ndarray:
	p = np.max(np.abs(x))
	return x * (db(peak_db) / p) if p > 0 else x


def rms_db(x: np.ndarray) -> float:
	return to_db(np.sqrt(np.mean(np.asarray(x, float) ** 2)))


def peak_db(x: np.ndarray) -> float:
	return to_db(np.max(np.abs(x)))


def k_weight(x: np.ndarray) -> np.ndarray:
	"""ITU-R BS.1770 K-weighting (pre-filter + RLB high-pass), designed for SR."""
	y = eq(x, "highshelf", 1681.974450955533, 0.7071752369554196, 3.999843853973347)
	b, a = rbj("hp", 38.13547087602444, 0.5003270373238773)
	return signal.lfilter(b, a, y, axis=0)


def loudness(x: np.ndarray) -> float:
	"""Approximate integrated loudness in LUFS (gated, BS.1770 style)."""
	x2 = stereo(x)
	y = k_weight(x2)
	blk = ns(0.4)
	hop = ns(0.1)
	if len(y) < blk:
		ms = np.mean(np.sum(y ** 2, axis=1))
		return float(-0.691 + 10 * np.log10(max(ms, 1e-12)))
	vals = []
	for i in range(0, len(y) - blk + 1, hop):
		vals.append(np.mean(np.sum(y[i:i + blk] ** 2, axis=1)))
	vals = np.array(vals)
	lk = -0.691 + 10 * np.log10(np.maximum(vals, 1e-12))
	g = vals[lk > -70]
	if len(g) == 0:
		return -70.0
	rel = -0.691 + 10 * np.log10(np.mean(g)) - 10
	g2 = vals[(lk > -70) & (lk > rel)]
	return float(-0.691 + 10 * np.log10(np.mean(g2)))


# ------------------------------------------------------------------------------------------------
# file output
# ------------------------------------------------------------------------------------------------
def write_wav16(path: str | Path, x: np.ndarray) -> None:
	path = Path(path)
	path.parent.mkdir(parents=True, exist_ok=True)
	ch = 1 if x.ndim == 1 else x.shape[1]
	pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
	with wave.open(str(path), "wb") as w:
		w.setnchannels(ch)
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes(pcm.tobytes())


def read_wav16(path: str | Path) -> np.ndarray:
	with wave.open(str(path), "rb") as w:
		ch = w.getnchannels()
		data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32768.0
	return data.reshape(-1, ch) if ch > 1 else data


def write_raw_f32(path: str | Path, x: np.ndarray) -> None:
	"""Little-endian float32, interleaved if stereo (read in Godot with PackedByteArray.to_float32_array())."""
	path = Path(path)
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_bytes(np.asarray(x, "<f4").tobytes())


# ------------------------------------------------------------------------------------------------
# previews: spectrogram / waveform PNG (no matplotlib on this machine)
# ------------------------------------------------------------------------------------------------
def _png(path: str | Path, rgb: np.ndarray) -> None:
	h, w, _ = rgb.shape
	raw = b"".join(b"\x00" + rgb[y].astype(np.uint8).tobytes() for y in range(h))

	def chunk(tag: bytes, data: bytes) -> bytes:
		return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

	Path(path).parent.mkdir(parents=True, exist_ok=True)
	Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
						   + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def _colormap(v: np.ndarray) -> np.ndarray:
	"""v in [0,1] -> 'inferno'-like RGB."""
	stops = np.array([[0, 0, 4], [40, 11, 84], [101, 21, 110], [159, 42, 99], [212, 72, 66], [245, 125, 21],
					  [250, 193, 39], [252, 255, 164]], float)
	pos = np.linspace(0, 1, len(stops))
	return np.stack([np.interp(v, pos, stops[:, c]) for c in range(3)], axis=-1)


def spectrogram_png(path: str | Path, x: np.ndarray, width: int = 1200, height: int = 360, fmax: float = 16000.0,
					floor_db: float = -90.0, wave_h: int = 90) -> None:
	"""Log-frequency spectrogram with a waveform strip on top."""
	_png(path, spectrogram_rgb(x, width, height, fmax, floor_db, wave_h))


def contact_sheet_png(path: str | Path, tiles: list[np.ndarray], cols: int = 4, gap: int = 6) -> None:
	h = max(t.shape[0] for t in tiles)
	w = max(t.shape[1] for t in tiles)
	rows = (len(tiles) + cols - 1) // cols
	img = np.full((rows * (h + gap), cols * (w + gap), 3), 40.0)
	for i, t in enumerate(tiles):
		r, c = divmod(i, cols)
		img[r * (h + gap):r * (h + gap) + t.shape[0], c * (w + gap):c * (w + gap) + t.shape[1]] = t
	_png(path, img)


def spectrogram_rgb(x: np.ndarray, width: int = 1200, height: int = 360, fmax: float = 16000.0,
					floor_db: float = -90.0, wave_h: int = 90) -> np.ndarray:
	mono = x if x.ndim == 1 else x.mean(axis=1)
	nfft = 4096
	hop = max(1, (len(mono) - nfft) // width) if len(mono) > nfft else 1
	frames = []
	win = np.hanning(nfft)
	padded = np.concatenate([mono, np.zeros(nfft)])
	for i in range(width):
		s = i * hop
		seg = padded[s:s + nfft] * win
		frames.append(np.abs(np.fft.rfft(seg)))
	S = 20 * np.log10(np.array(frames).T + 1e-9) - 20 * np.log10(nfft / 4)
	freqs = np.fft.rfftfreq(nfft, 1 / SR)
	ylog = np.geomspace(30.0, fmax, height)[::-1]
	img = np.empty((height, width))
	for i in range(width):
		img[:, i] = np.interp(ylog, freqs, S[:, i])
	v = np.clip((img - floor_db) / -floor_db, 0, 1)
	rgb = _colormap(v)
	# waveform strip
	wv = np.zeros((wave_h, width, 3)) + 12
	xs = x if x.ndim == 2 else x[:, None]
	step = max(1, len(mono) // width)
	for i in range(width):
		seg = xs[i * step:(i + 1) * step]
		if len(seg) == 0:
			continue
		lo, hi = seg.min(), seg.max()
		y0 = int((1 - (hi + 1) / 2) * (wave_h - 1))
		y1 = int((1 - (lo + 1) / 2) * (wave_h - 1))
		wv[y0:y1 + 1, i] = [90, 200, 255]
		if hi >= 0.999 or lo <= -0.999:
			wv[:4, i] = [255, 40, 40]
	wv[wave_h // 2, :] = [60, 60, 60]
	return np.concatenate([wv, rgb], axis=0)
