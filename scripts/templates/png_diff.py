#!/usr/bin/env python3
"""Golden-image comparison without dependencies (CI has no Pillow): decodes
8-bit RGB / RGBA PNGs (what raylib writes) and compares two images.

    python3 scripts/templates/png_diff.py a.png b.png      # prints the stats

diff(a, b, threshold) -> (fraction of pixels whose largest channel
difference exceeds `threshold` (0-255), mean absolute channel difference);
different sizes: (1.0, 255). Used by test_templates.py's "golden" tests.
"""
import struct
import sys
import zlib


def read_png(path):
    """(width, height, rows): rows of RGBA bytes."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    pos, idat, w = 8, [], 0
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or ctype not in (2, 6) or interlace:
                raise ValueError(f"{path}: only 8-bit RGB / RGBA, not interlaced (got depth {depth}, type {ctype})")
            bpp = 4 if ctype == 6 else 3
        elif kind == b"IDAT":
            idat.append(chunk)
        elif kind == b"IEND":
            break
    raw = zlib.decompress(b"".join(idat))
    stride = w * bpp
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        ftype = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if ftype == 1:
                line[x] = (line[x] + a) & 255
            elif ftype == 2:
                line[x] = (line[x] + b) & 255
            elif ftype == 3:
                line[x] = (line[x] + ((a + b) >> 1)) & 255
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        if bpp == 3:
            rgba = bytearray()
            for x in range(w):
                rgba += line[x * 3:x * 3 + 3] + b"\xff"
            rows.append(rgba)
        else:
            rows.append(line)
    return w, h, rows


def diff(a_path, b_path, threshold=48):
    aw, ah, a = read_png(a_path)
    bw, bh, b = read_png(b_path)
    if (aw, ah) != (bw, bh):
        return 1.0, 255.0
    bad = total = 0
    for ra, rb in zip(a, b):
        for x in range(0, len(ra), 4):
            d = max(abs(ra[x] - rb[x]), abs(ra[x + 1] - rb[x + 1]), abs(ra[x + 2] - rb[x + 2]))
            total += d
            if d > threshold:
                bad += 1
    n = aw * ah
    return bad / n, total / (n * 1.0)


if __name__ == "__main__":
    frac, mean = diff(sys.argv[1], sys.argv[2])
    print(f"differing pixels {frac:.4%}, mean difference {mean:.2f}")
