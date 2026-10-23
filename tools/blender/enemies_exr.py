"""Minimal OpenEXR reader (scanline images, single- or multi-part, NONE/ZIPS/ZIP compression).

Blender's bpy module ships without OpenImageIO, so the multilayer EXR written by Cycles is parsed here
with numpy only. read_exr() returns {channel_name: float32 array (H, W)}; in multi-part files the
channel names are used as stored (Blender writes full names like "ViewLayer.DiffDir.R").
"""
import struct
import zlib

import numpy as np

_PIXEL_DTYPES = {0: np.dtype("<u4"), 1: np.dtype("<f2"), 2: np.dtype("<f4")}
_LINES_PER_CHUNK = {0: 1, 2: 1, 3: 16}  # NONE, ZIPS, ZIP


def _read_cstr(buf, pos):
	end = buf.index(b"\0", pos)
	return buf[pos:end].decode("latin-1"), end + 1


def _undo_zip(data):
	raw = np.frombuffer(zlib.decompress(data), dtype=np.uint8).astype(np.int32)
	t = (np.cumsum(np.concatenate([[raw[0]], raw[1:] - 128])) & 0xFF).astype(np.uint8)
	half = (len(t) + 1) // 2
	out = np.empty_like(t)
	out[0::2] = t[:half]
	out[1::2] = t[half:]
	return out.tobytes()


def _read_header(buf, pos):
	header = {}
	while True:
		name, pos = _read_cstr(buf, pos)
		if name == "":
			return header, pos
		typ, pos = _read_cstr(buf, pos)
		size = struct.unpack_from("<i", buf, pos)[0]
		pos += 4
		header[name] = (typ, buf[pos:pos + size])
		pos += size


def _channels(header):
	chans = []
	cbuf = header["channels"][1]
	cpos = 0
	while True:
		cname, cpos = _read_cstr(cbuf, cpos)
		if cname == "":
			return chans
		ptype, _plin, xs, ys = struct.unpack_from("<iB3xii", cbuf, cpos)
		cpos += 16
		if xs != 1 or ys != 1:
			raise ValueError("subsampled channels unsupported")
		chans.append((cname, _PIXEL_DTYPES[ptype]))


def read_exr(path):
	with open(path, "rb") as f:
		buf = f.read()
	if buf[:4] != b"\x76\x2f\x31\x01":
		raise ValueError("not an EXR file: %s" % path)
	flags = struct.unpack_from("<I", buf, 4)[0]
	if flags & 0x200 or flags & 0x800:
		raise ValueError("unsupported EXR layout (tiled/deep) flags=%x" % flags)
	multipart = bool(flags & 0x1000)
	pos = 8
	headers = []
	if multipart:
		while True:
			h, pos = _read_header(buf, pos)
			if not h:
				break
			headers.append(h)
	else:
		h, pos = _read_header(buf, pos)
		headers.append(h)
	parts = []
	for h in headers:
		chans = _channels(h)
		xmin, ymin, xmax, ymax = struct.unpack("<iiii", h["dataWindow"][1])
		comp = h["compression"][1][0]
		if comp not in _LINES_PER_CHUNK:
			raise ValueError("unsupported EXR compression %d" % comp)
		lpc = _LINES_PER_CHUNK[comp]
		height = ymax - ymin + 1
		if "chunkCount" in h:
			nchunks = struct.unpack("<i", h["chunkCount"][1])[0]
		else:
			nchunks = (height + lpc - 1) // lpc
		offsets = struct.unpack_from("<%dQ" % nchunks, buf, pos)
		pos += 8 * nchunks
		parts.append((chans, xmin, ymin, xmax, ymax, comp, lpc, offsets))
	out = {}
	for chans, xmin, ymin, xmax, ymax, comp, lpc, offsets in parts:
		w = xmax - xmin + 1
		h = ymax - ymin + 1
		arrays = {c: np.zeros((h, w), dtype=np.float32) for c, _ in chans}
		for off in offsets:
			if multipart:
				off += 4  # part number
			y, size = struct.unpack_from("<ii", buf, off)
			data = buf[off + 8:off + 8 + size]
			nlines = min(lpc, ymax - y + 1)
			expected = sum(dt.itemsize for _, dt in chans) * w * nlines
			if len(data) != expected:
				if comp == 0:
					raise ValueError("bad chunk size")
				data = _undo_zip(data)
			p = 0
			for li in range(nlines):
				row = y - ymin + li
				for cname, dt in chans:
					arrays[cname][row] = np.frombuffer(data, dtype=dt, count=w, offset=p).astype(np.float32)
					p += w * dt.itemsize
		out.update(arrays)
	return out
