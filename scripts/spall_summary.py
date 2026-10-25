#!/usr/bin/env python3
"""Summarizes a spall trace written by a profiling build (engine/profiling.odin):
time per zone (total and self, i.e. without its child zones), per frame.

  scripts/spall_summary.py trace.spall [--frame-zone frame] [--top 30]

A frame is one "frame" zone (the runner's) or "editor.frame" (the editor's);
--frame-zone names another. Open the trace itself in https://gravitymoth.com/spall/.
"""
import argparse, struct, sys
from collections import defaultdict

ap = argparse.ArgumentParser()
ap.add_argument("trace")
ap.add_argument("--frame-zone", default=None)
ap.add_argument("--top", type=int, default=30)
args = ap.parse_args()

data = open(args.trace, "rb").read()
magic, version, scale, _ = struct.unpack_from("<QQdQ", data, 0)
if magic != 0x0BADF00D:
    sys.exit("not a spall trace")
pos = 32
total = defaultdict(float)
self_ = defaultdict(float)
count = defaultdict(int)
stack = []  # [name, start, child time]
while pos + 20 <= len(data):
    size, tid, pid, first_ts = struct.unpack_from("<IIIQ", data, pos)
    pos += 20
    end = pos + size
    while pos < end:
        t = data[pos]
        if t == 3:  # begin
            ts, nl, al = struct.unpack_from("<QBB", data, pos + 1)
            name = data[pos + 11:pos + 11 + nl].decode("utf-8", "replace")
            pos += 11 + nl + al
            stack.append([name, ts, 0.0])
        elif t == 4:  # end
            (ts,) = struct.unpack_from("<Q", data, pos + 1)
            pos += 9
            if not stack:
                continue
            name, start, child = stack.pop()
            d = (ts - start) * scale / 1e6  # ms
            total[name] += d
            self_[name] += d - child
            count[name] += 1
            if stack:
                stack[-1][2] += d
        elif t == 7:  # pad skip
            (n,) = struct.unpack_from("<I", data, pos + 1)
            pos += 5 + n
        elif t in (8, 9):  # names
            pos += 2 + data[pos + 1]
        else:
            break
    pos = end

total.pop("Spall Trace Buffer Flush", None)
fz = args.frame_zone or ("frame" if "frame" in count else "editor.frame")
frames = count.get(fz, 0) or 1
print(f"{frames} frames ({fz}): {total.get(fz, 0) / frames:.3f} ms per frame")
print(f"{'zone':32} {'total ms/frame':>14} {'self ms/frame':>14} {'calls/frame':>12}")
for name in sorted(total, key=lambda n: -self_[n])[:args.top]:
    print(f"{name:32} {total[name] / frames:14.3f} {self_[name] / frames:14.3f} {count[name] / frames:12.1f}")
