#!/usr/bin/env python3
"""Prepares the web runner's source tree (scripts/build_web_runner.sh).

Copies engine/ (without tests), runner/web/ and ui/ into OUT, then patches
the copies so they build for js_wasm32 + emscripten - the originals are not
touched:

  * ui/: `import "core:os"` -> the engine's osx package; the shell-command
    native dialogs (posix popen) become "no dialog" (a web page can't run
    commands).
  * Box2D: a copy of Odin's vendor:box2d bindings that links the Box2D we
    build with emcc (the vendor wasm path pulls in Odin's libc shim, which
    collides with emscripten's libc).

usage: web_prepare.py REPO OUT ODIN_ROOT
"""
import os
import re
import shutil
import sys


def copy_tree(src, dst, skip_tests=False):
    for root, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("docs", "examples", "tests", "screenshots")]
        rel = os.path.relpath(root, src)
        out = os.path.join(dst, rel)
        os.makedirs(out, exist_ok=True)
        for f in files:
            if skip_tests and f.endswith("_test.odin"):
                continue
            if f.endswith((".odin", ".lua", ".ttf", ".png", ".fs", ".vs", ".txt", ".xml")):
                shutil.copy2(os.path.join(root, f), os.path.join(out, f))


def patch_file(path, fn):
    with open(path) as f:
        text = f.read()
    new = fn(text)
    if new != text:
        with open(path, "w") as f:
            f.write(new)


def main():
    repo, out, odin_root = sys.argv[1], sys.argv[2], sys.argv[3]
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    copy_tree(os.path.join(repo, "engine"), os.path.join(out, "engine"), skip_tests=True)
    copy_tree(os.path.join(repo, "runner", "web"), os.path.join(out, "runner", "web"))
    copy_tree(os.path.join(repo, "ui"), os.path.join(out, "ui"), skip_tests=True)

    # ui/: core:os -> osx (relative to each file's depth).
    ui = os.path.join(out, "ui")
    for root, _, files in os.walk(ui):
        depth = os.path.relpath(root, out).count(os.sep) + 1
        osx = "../" * depth + "engine/osx"
        for f in files:
            if f.endswith(".odin"):
                patch_file(os.path.join(root, f), lambda t: t.replace('import "core:os"', 'import os "%s"' % osx))

    # core:path/filepath imports core:os: the copies use engine/pathx.
    for top in ("engine", "ui", "runner"):
        for root, _, files in os.walk(os.path.join(out, top)):
            depth = os.path.relpath(root, out).count(os.sep) + 1
            px = "../" * depth + "engine/pathx"
            for f in files:
                if f.endswith(".odin") and "pathx" not in root and "osx" not in root:
                    patch_file(os.path.join(root, f), lambda t, px=px: t.replace('import "core:path/filepath"', 'import filepath "%s"' % px))

    # ui/native_dialog.odin: no shell commands on the web.
    nd = os.path.join(ui, "native_dialog.odin")
    if os.path.exists(nd):
        def stub(t):
            m = re.search(r"exec_dialog_cmd :: proc\(cmd: string\) -> \(output: string, ok: bool\) \{\n.*?\n\}\n", t, re.S)
            if m:
                t = t[:m.start()] + "exec_dialog_cmd :: proc(cmd: string) -> (output: string, ok: bool) {\n\treturn \"\", false // (web: no dialogs)\n}\n" + t[m.end():]
            if "posix." not in t:
                t = t.replace('import "core:sys/posix"\n', "")
            if "libc." not in t:
                t = t.replace('import "core:c/libc"\n', "")
            return t
        patch_file(nd, stub)

    # Box2D bindings that link our emcc-built Box2D (symbols from "env").
    b2src = os.path.join(odin_root, "vendor", "box2d")
    b2 = os.path.join(out, "engine", "box2d_web")
    os.makedirs(b2)
    for f in os.listdir(b2src):
        if f.endswith(".odin") and f != "box2d_wasm.odin":
            shutil.copy2(os.path.join(b2src, f), os.path.join(b2, f))
    patch_file(os.path.join(b2, "box2d.odin"), lambda t: re.sub(r'@\(private\) LIB_PATH :: "lib/box2d_wasm" \+ VECTOR_EXT \+ "\.o"', '@(private) LIB_PATH :: "env.o"', t))
    open(os.path.join(b2, "env.o"), "w").close()
    for f in os.listdir(os.path.join(out, "engine")):
        if f.endswith(".odin"):
            patch_file(os.path.join(out, "engine", f), lambda t: t.replace('import b2 "vendor:box2d"', 'import b2 "box2d_web"'))
    # No virtual memory on the web: growing arenas over malloc (engine/vmemx).
    for f in os.listdir(os.path.join(out, "engine")):
        if f.endswith(".odin"):
            patch_file(os.path.join(out, "engine", f), lambda t: t.replace('import vmem "core:mem/virtual"', 'import vmem "vmemx"'))

    # zlib bindings for emscripten's zlib port (-sUSE_ZLIB): module "env".
    zsrc = os.path.join(odin_root, "vendor", "zlib")
    zdst = os.path.join(out, "engine", "zlib_web")
    os.makedirs(zdst)
    for f in os.listdir(zsrc):
        if f.endswith(".odin"):
            shutil.copy2(os.path.join(zsrc, f), os.path.join(zdst, f))
    for f in os.listdir(zdst):
        patch_file(os.path.join(zdst, f), lambda t: t.replace('foreign import zlib "system:z"', 'foreign import zlib "env.o"'))
    for f in os.listdir(os.path.join(out, "engine")):
        if f.endswith(".odin"):
            patch_file(os.path.join(out, "engine", f), lambda t: t.replace('import zlib "vendor:zlib"', 'import zlib "zlib_web"'))
    for name in ("env.o",):
        open(os.path.join(out, "engine", "lua54", name), "w").close()
    print("prepared", out)


if __name__ == "__main__":
    main()
