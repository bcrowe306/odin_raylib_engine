#!/usr/bin/env python3
"""Finds inputs that finish a platformer level (TODO E.2): holding right, it
adds a jump wherever the player stops making progress (a pit, spikes, an
enemy, a wall) - trying takeoffs before that point - until the player
reaches the door. The result goes into scripts/templates/tests/<id>.json as
a test that the level can be finished. Offline tool (a few minutes):

    python3 scripts/templates/find_route.py platformer scenes/level1.scene.json [--runner R]

Uses the runner's --input-script and --trace Player.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
from test_templates import ROOT, default_runner, find  # noqa: E402

TAP = 16
LIMIT = 2400


def run(runner, proj, scene, jumps, tmp, limit=LIMIT):
    inp = os.path.join(tmp, "in.txt")
    lines = ["5 RIGHT down"] + [f"{j} SPACE tap {TAP}" for j in sorted(jumps)]
    open(inp, "w").write("\n".join(lines) + "\n")
    out = subprocess.run([runner, proj, "--scene", scene, "--hidden", "--user-data", os.path.join(tmp, "ud"),
                          "--frames", str(limit), "--input-script", inp, "--trace", "Player",
                          "--dump-scene", os.path.join(tmp, "d.json")], capture_output=True, text=True, timeout=300)
    trace = []
    for line in out.stdout.splitlines():
        if line.startswith("@trace "):
            _, f, sc, x, y = line.split()
            trace.append((int(f), sc, float(x), float(y)))
    return trace, lines


def outcome(trace, start_scene, door_x):
    """(won, frame where progress stopped, furthest x)."""
    best, best_f, still = -1e9, 0, 0
    for i, (f, sc, x, y) in enumerate(trace):
        if sc != start_scene:
            return True, f, best
        if i > 0 and x < trace[i - 1][2] - 100:  # back at the start: died (or won and restarted)
            return abs(trace[i - 1][2] - door_x) < 24, f, best
        if x > best + 0.5:
            best, best_f, still = x, f, 0
        else:
            still += 1
            if still > 40:
                return abs(x - door_x) < 24, best_f, best
    return False, best_f, best


def main():
    args = sys.argv[1:]
    runner = default_runner()
    if "--runner" in args:
        i = args.index("--runner")
        runner = os.path.abspath(args[i + 1])
        del args[i:i + 2]
    tid, scene = args[0], args[1]
    proj_src = os.path.join(ROOT, "templates", tid)
    sc = json.load(open(os.path.join(proj_src, scene)))
    door_x = find(sc["root"], "Door")["position"][0]
    start_scene = sc["name"]
    jumps = []
    with tempfile.TemporaryDirectory() as tmp:
        proj = os.path.join(tmp, "p")
        shutil.copytree(proj_src, proj)
        horizon = 600  # frames played: the furthest point so far + some
        banned, last_best = set(), -1e9
        for step in range(60):
            trace, lines = run(runner, proj, scene, jumps, tmp, min(LIMIT, horizon))
            won, f, best = outcome(trace, start_scene, door_x)
            print(f"  jumps {sorted(jumps)} -> {'WON' if won else 'stuck'} at frame {f}, x {best:.0f}", flush=True)
            if won:
                print(json.dumps(lines))
                return 0
            # No further than before: the last jump led nowhere - take it back.
            if jumps and best <= last_best + 1:
                banned.add(jumps.pop())
                last_best = -1e9
                horizon = f + 400
                continue
            last_best = best
            # Try takeoffs before the point it stopped; keep the one that goes furthest.
            tries = []
            for k in range(4, 60, 4):
                j = f - k
                if j <= 6 or j in banned or any(abs(j - q) < TAP + 4 for q in jumps):
                    continue
                t2, _ = run(runner, proj, scene, jumps + [j], tmp, min(LIMIT, f + 240))
                w2, f2, b2 = outcome(t2, start_scene, door_x)
                tries.append((w2, b2, -k, j))
                if w2:
                    break
            if not tries:
                print("no takeoff helps")
                return 1
            tries.sort(reverse=True)
            jumps.append(tries[0][3])
            horizon = f + 400
    return 1


if __name__ == "__main__":
    sys.exit(main())
