#!/usr/bin/env python3
"""Colourises the channel-packed enemy strips exactly like the game shader (docs/SPEC.md §16.2) and writes
contact sheets to docs/previews/enemies/.

    col = base*(0.18 + 1.0*R) + G*mix(1, base, 0.35)*0.9 + B*eye_color
    base = vertical level gradient from content_top (t=0) to content_bottom (t=1)

Usage: python3 tools/preview_enemies.py [planet ...] [--variants l1,l12,l17,black] [--gif l1] [--out DIR]
Writes per planet and variant <planet>_<variant>.png (all 16 frames, full sprite resolution + in-game size),
<planet>_channels.png (raw R/G/B/A) and overview_<variant>.png (all planets side by side).
"""
import argparse
import json
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SPRITES = os.path.join(ROOT, "game", "assets", "sprites", "enemies")
PLANETS = ["neptune", "uranus", "saturn", "jupiter", "mars", "earth"]
EYE_DEFAULT = (1.0, 0.95, 0.70)
EYE_BLACK = (1.0, 0.28, 0.08)
# gradient stops copied from game/scripts/data/level_data.gd
VARIANTS = {
	"l1": ("level 1: blue -> light cyan", [(0.08, 0.22, 0.95), (0.55, 1.0, 1.0)], EYE_DEFAULT),
	"l12": ("level 12: orange -> almost black", [(1.0, 0.55, 0.05), (0.06, 0.03, 0.01)], EYE_DEFAULT),
	"l17": ("level 17: rainbow", [(0.56, 0.18, 0.95), (0.22, 0.30, 1.0), (0.10, 0.72, 0.95), (0.15, 0.85, 0.28),
		(1.0, 0.92, 0.10)], EYE_DEFAULT),
	"black": ("levels 19/20: black", [(0.035, 0.035, 0.045), (0.02, 0.02, 0.03)], EYE_BLACK),
	"l14": ("level 14: violet -> almost black", [(0.66, 0.28, 1.0), (0.06, 0.02, 0.09)], EYE_DEFAULT),
	"l5": ("level 5: light grey -> almost black", [(0.86, 0.87, 0.90), (0.06, 0.06, 0.07)], EYE_DEFAULT),
}
BG = np.array([0.025, 0.025, 0.055])


def load(planet, sprites=SPRITES):
	img = np.asarray(Image.open(os.path.join(sprites, planet + ".png")).convert("RGBA")).astype(np.float32) / 255.0
	with open(os.path.join(sprites, planet + ".json")) as f:
		meta = json.load(f)
	return img, meta


def gradient(stops, t):
	stops = np.asarray(stops, dtype=np.float32)
	n = len(stops) - 1
	x = np.clip(t, 0.0, 1.0) * n
	i = np.minimum(np.floor(x).astype(int), n - 1)
	f = (x - i)[..., None]
	return stops[i] * (1.0 - f) + stops[i + 1] * f


def colourise(frame, meta, stops, eye, bg=BG):
	h, w, _ = frame.shape
	top = float(meta["content_top"])
	bottom = float(meta["content_bottom"])
	t = (np.arange(h, dtype=np.float32) + 0.5 - top) / max(1.0, bottom - top)
	base = np.broadcast_to(gradient(stops, t)[:, None, :], (h, w, 3))
	R = frame[..., 0:1]
	Gc = frame[..., 1:2]
	B = frame[..., 2:3]
	A = frame[..., 3:4]
	col = base * (0.18 + 1.0 * R) + Gc * (1.0 * 0.65 + base * 0.35) * 0.9 + B * np.asarray(eye, np.float32)
	col = np.clip(col, 0.0, 1.0)
	return bg * (1.0 - A) + col * A


def to_img(arr):
	return Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8))


def frames_of(img, meta):
	fw = meta["frame_w"]
	return [img[:, i * fw:(i + 1) * fw] for i in range(meta["frames"])]


def sheet(planet, variant, img, meta, out_dir):
	title, stops, eye = VARIANTS[variant]
	fr = frames_of(img, meta)
	fw, fh = meta["frame_w"], meta["frame_h"]
	cols = 4
	rows = (len(fr) + cols - 1) // cols
	small_h = fh // 2
	child_scale = 0.45
	cw, ch = int(round(fw / 2 * child_scale)), int(round(fh / 2 * child_scale))
	W = cols * fw
	H = 24 + rows * fh + 20 + small_h * 2 + 8 + 20 + ch + 8
	canvas = np.zeros((H, W, 3), np.float32) + BG
	for i, f in enumerate(fr):
		x = (i % cols) * fw
		y = 24 + (i // cols) * fh
		canvas[y:y + fh, x:x + fw] = colourise(f, meta, stops, eye)
	# in-game size (1 sprite px = 0.5 game px): two rows of 8 frames
	y0 = 24 + rows * fh + 20
	for i, f in enumerate(fr):
		c = colourise(f, meta, stops, eye)
		small = np.asarray(to_img(c).resize((fw // 2, fh // 2), Image.LANCZOS)).astype(np.float32) / 255.0
		x = (i % 8) * (fw // 2)
		y = y0 + (i // 8) * small_h
		canvas[y:y + small_h, x:x + fw // 2] = small
	# children (scale 0.45): the GPU samples the mipmapped channels and colourises afterwards, so the channels are
	# box-filtered first (like the mip chain) and coloured at the small size
	y1 = y0 + small_h * 2 + 8 + 20
	for i, f in enumerate(fr):
		raw = Image.fromarray((np.clip(f, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
		small = np.asarray(raw.resize((cw, ch), Image.BOX)).astype(np.float32) / 255.0
		meta_s = dict(meta, content_top=meta["content_top"] * ch / fh, content_bottom=meta["content_bottom"] * ch / fh)
		canvas[y1:y1 + ch, i * (cw + 4):i * (cw + 4) + cw] = colourise(small, meta_s, stops, eye)
	im = to_img(canvas)
	d = ImageDraw.Draw(im)
	d.text((6, y1 - 16), "children (scale %.2f, mipmapped)" % child_scale, fill=(160, 160, 170))
	d.text((6, 6), "%s  -  %s   (content rows %d..%d)" % (planet, title, meta["content_top"], meta["content_bottom"]),
		fill=(220, 220, 230))
	for i in range(len(fr)):
		d.text(((i % cols) * fw + 4, 24 + (i // cols) * fh + 2), str(i), fill=(120, 120, 140))
	# content_top / bottom marks on the first frame
	for yy in (meta["content_top"], meta["content_bottom"]):
		d.line([(0, 24 + yy), (6, 24 + yy)], fill=(255, 60, 60))
	d.text((6, y0 - 16), "in-game size (128 x 80 game px per frame)", fill=(160, 160, 170))
	path = os.path.join(out_dir, "%s_%s.png" % (planet, variant))
	im.save(path)
	return path


def channels(planet, img, meta, out_dir):
	fr = frames_of(img, meta)
	fw, fh = meta["frame_w"], meta["frame_h"]
	pick = [0, 4, 8, 12]
	canvas = np.zeros((20 + 4 * fh, len(pick) * fw, 3), np.float32)
	for j, k in enumerate(pick):
		f = fr[k]
		for c in range(4):
			ch = f[..., c]
			canvas[20 + c * fh:20 + (c + 1) * fh, j * fw:(j + 1) * fw] = ch[..., None]
	im = to_img(canvas)
	d = ImageDraw.Draw(im)
	d.text((6, 4), "%s raw channels: rows R / G / B / A, frames %s" % (planet, pick), fill=(255, 200, 80))
	path = os.path.join(out_dir, "%s_channels.png" % planet)
	im.save(path)
	return path


def overview(planets, variant, out_dir, sprites=SPRITES):
	title, stops, eye = VARIANTS[variant]
	data = [(p,) + load(p, sprites) for p in planets if os.path.exists(os.path.join(sprites, p + ".png"))]
	if not data:
		return None
	fw, fh = 256, 160
	picks = [0, 4, 8, 12]
	W = len(picks) * fw + 2 * (fw // 2)
	H = 20 + len(data) * fh
	canvas = np.zeros((H, W, 3), np.float32) + BG
	for r, (p, img, meta) in enumerate(data):
		fr = frames_of(img, meta)
		for j, k in enumerate(picks):
			canvas[20 + r * fh:20 + (r + 1) * fh, j * fw:(j + 1) * fw] = colourise(fr[k], meta, stops, eye)
		for j, k in enumerate((0, 8)):
			c = colourise(fr[k], meta, stops, eye)
			small = np.asarray(to_img(c).resize((fw // 2, fh // 2), Image.LANCZOS)).astype(np.float32) / 255.0
			x = len(picks) * fw + j * (fw // 2)
			y = 20 + r * fh + fh // 4
			canvas[y:y + fh // 2, x:x + fw // 2] = small
	im = to_img(canvas)
	d = ImageDraw.Draw(im)
	d.text((6, 4), "overview - %s (frames 0/4/8/12 + in-game size)" % title, fill=(220, 220, 230))
	for r, (p, _img, _m) in enumerate(data):
		d.text((4, 22 + r * fh), p, fill=(150, 150, 170))
	path = os.path.join(out_dir, "overview_%s.png" % variant)
	im.save(path)
	return path


def gif(planet, variant, img, meta, out_dir, scale=1.0, fps=40.0):
	"""Animated preview of the flap cycle (2.5 cycles/s like in the game -> 40 frames/s), looped."""
	_title, stops, eye = VARIANTS[variant]
	fw, fh = meta["frame_w"], meta["frame_h"]
	frames = []
	for f in frames_of(img, meta):
		im = to_img(colourise(f, meta, stops, eye))
		if scale != 1.0:
			im = im.resize((int(fw * scale), int(fh * scale)), Image.LANCZOS)
		frames.append(im.convert("P", palette=Image.ADAPTIVE, colors=255))
	path = os.path.join(out_dir, "%s_%s.gif" % (planet, variant))
	frames[0].save(path, save_all=True, append_images=frames[1:], duration=int(1000 / fps), loop=0, disposal=2)
	return path


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("planets", nargs="*", default=PLANETS)
	ap.add_argument("--variants", default="l1,l12,l17,black")
	ap.add_argument("--sprites", default=SPRITES)
	ap.add_argument("--out", default=os.path.join(ROOT, "docs", "previews", "enemies"))
	ap.add_argument("--no-overview", action="store_true")
	ap.add_argument("--gif", default="", help="also write animated GIFs for these variants (comma list)")
	args = ap.parse_args()
	os.makedirs(args.out, exist_ok=True)
	variants = [v for v in args.variants.split(",") if v]
	for p in args.planets:
		if not os.path.exists(os.path.join(args.sprites, p + ".png")):
			print("missing", p)
			continue
		img, meta = load(p, args.sprites)
		for v in variants:
			print(sheet(p, v, img, meta, args.out))
		print(channels(p, img, meta, args.out))
		for v in [v for v in args.gif.split(",") if v]:
			print(gif(p, v, img, meta, args.out))
	if not args.no_overview:
		for v in variants:
			path = overview(PLANETS, v, args.out, args.sprites)
			if path:
				print(path)


if __name__ == "__main__":
	main()
