#!/usr/bin/env python3
"""Writes a large Lua file (default 10,000 lines) for code editor benchmarks.
Usage: gen_big_lua.py <out.lua> [lines]"""
import sys
out = sys.argv[1]
n = int(sys.argv[2]) if len(sys.argv) > 2 else 10000
lines = ["-- generated benchmark script", "local Big = {}", ""]
i = 0
while len(lines) < n - 2:
    lines += [
        f"--[[ block comment {i}",
        f"     spanning lines ]]",
        f"function Big:method_{i}(a, b)",
        f"    local s = \"string {i}\" .. tostring(a)  -- trailing comment",
        f"    if a > {i} and b ~= nil then return s, {i}.5 end",
        f"    for k, v in pairs(self.items or {{}}) do Log.info(k, v) end",
        f"    return nil",
        "end",
        "",
    ]
    i += 1
lines = lines[:n - 1] + ["return Big"]
open(out, "w").write("\n".join(lines) + "\n")
