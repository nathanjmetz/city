"""Builds the haul roads into the county's sand and gravel pits.

Run (offline): python3 tools/terrain/build_haul.py
Reads terrain/grant_in/cover.bin (bare ground) and county.bin (the miles of
county road) and writes terrain/grant_in/haul.bin: 64 x 64 lossless WebP,
one texel per mile square of the survey grid (square floor(x / 1608),
floor(z / 1608) in region metres, wrapped to 64; the real map is 23 squares
across, so nothing on it shares a texel). Alpha 255 where the square has a
haul road; red = the side its county road is on (0 west, 1 east, 2 north,
3 south, times 64); green = where across the square the lane runs (256ths
of a mile); blue = how far it runs in from the road (256ths of a mile).

Real reference: every working pit in Grant County (the Mississinewa and
Salamonie outwash pits, Sweetser, Marion) has one gravel haul road in from
the nearest county road, straight and about 8 m wide, which the trucks
keep pale with dust. One lane a square, to its biggest pit that a lane can reach, from whichever
side with a road is shortest and keeps out of the water and the woods.
"""
import os
import numpy as np
from PIL import Image

DIR = os.path.join(os.path.dirname(__file__), "..", "..", "terrain", "grant_in")
MILE = 1608.0
CELL = 18.0
X0, Z0 = -10392.0, -13608.0


def main():
	cov = np.asarray(Image.open(os.path.join(DIR, "cover.bin")).convert("RGBA")).astype(np.float32) / 255.0
	miles = np.asarray(Image.open(os.path.join(DIR, "county.bin")).convert("RGB"))
	n = cov.shape[0]
	bare = cov[..., 3] >= 0.5
	seen = np.zeros_like(bare)
	pits = []
	for j0, i0 in zip(*np.nonzero(bare)):
		if seen[j0, i0]:
			continue
		seen[j0, i0] = True
		todo, cells = [(j0, i0)], []
		while todo:
			j, i = todo.pop()
			cells.append((j, i))
			for dj in (-1, 0, 1):
				for di in (-1, 0, 1):
					jj, ii = j + dj, i + di
					if 0 <= jj < n and 0 <= ii < n and bare[jj, ii] and not seen[jj, ii]:
						seen[jj, ii] = True
						todo.append((jj, ii))
		if len(cells) >= 3:
			c = np.array(cells, dtype=np.float64)
			pits.append((len(cells), X0 + (c[:, 1].mean() + 0.5) * CELL, Z0 + (c[:, 0].mean() + 0.5) * CELL))

	def at(x, z):
		i = int((x - X0) / CELL)
		j = int((z - Z0) / CELL)
		if 0 <= i < n and 0 <= j < n:
			return cov[j, i]
		return None

	out = np.zeros((64, 64, 4), dtype=np.uint8)
	made = 0
	done = set()
	for size, x, z in sorted(pits, reverse=True):
		sx, sz = int(np.floor(x / MILE)), int(np.floor(z / MILE))
		if (sx, sz) in done:
			continue
		fx, fz = x / MILE - sx, z / MILE - sz
		options = []
		# (side, line, mile, channel, length m, step direction from the road)
		for side, line, seg, ch, length, d in (
				(0, sx, sz, 0, fx * MILE, (1, 0)), (1, sx + 1, sz, 0, (1 - fx) * MILE, (-1, 0)),
				(2, sz, sx, 1, fz * MILE, (0, 1)), (3, sz + 1, sx, 1, (1 - fz) * MILE, (0, -1))):
			if miles[seg & 63, line & 63, ch] <= 127 or length > 700.0:
				continue
			start = (line * MILE, z) if ch == 0 else (x, line * MILE)
			wet, woods, ok = 0.0, 0.0, True
			k = 0
			for s in np.arange(10.0, max(length - 20.0, 11.0), 9.0):
				c = at(start[0] + d[0] * s, start[1] + d[1] * s)
				if c is None:
					ok = False
					break
				wet = max(wet, c[1])
				woods += c[0]
				k += 1
			if not ok or wet > 0.1:
				continue
			options.append((length + 900.0 * woods / max(k, 1), side, length, fz if ch == 0 else fx))
		if not options:
			continue
		_, side, length, across = min(options)
		done.add((sx, sz))
		out[sz & 63, sx & 63] = (side * 64, int(round(across * 255)), min(255, int(round((length + 12.0) / MILE * 256))), 255)
		made += 1
	Image.fromarray(out, "RGBA").save(os.path.join(DIR, "haul.bin"), "WEBP", lossless=True)
	print("pits", len(pits), "haul roads", made)


if __name__ == "__main__":
	main()
