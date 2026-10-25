#!/usr/bin/env python3
"""Builds the documentation site's sources (TODO E.2): the repository's guides
copied into site_src/ (their folders kept, so their links work), a home page,
the templates page (each template's README), and the Lua API reference
generated from engine/definitions/engine_api.lua (and the editor plugin API).
Then MkDocs builds the site:

    python3 scripts/docs/build_site.py            # -> build/docs_src/ (+ mkdocs.yml)
    mkdocs build -f build/docs_src/mkdocs.yml     # -> build/docs_site/

CI (.github/workflows/docs.yml) publishes it to GitHub Pages on every push
to main. Links to files that aren't pages (source files, images outside the
docs) point at the repository on GitHub.
"""
import os
import re
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "build", "docs_src")
DOCS = os.path.join(OUT, "docs")
REPO = "https://github.com/bcrowe306/rayzr"
SITE = "https://bcrowe306.github.io/rayzr/"

# The pages (repository paths), in the site's navigation.
GUIDES = [
    ("Editor", [
        ("The editor", "editor/README.md"),
        ("Code tab", "editor/CODE_EDITOR.md"),
        ("Plugins: design", "editor/docs/plugins.md"),
        ("Plugins: guide", "editor/docs/plugin_guide.md"),
    ]),
    ("Engine guides", None),  # every engine/docs/*.md (from its README's table)
    ("Scripting", [
        ("Scripting guide", "engine/SCRIPTING.md"),
    ]),
    ("Formats", [
        ("Level editor (LDtk)", "engine/LDTK.md"),
        ("The .rayzr package", "engine/RAYZR_FORMAT.md"),
    ]),
    ("Contributing", [
        ("Releases and dev builds", "RELEASING.md"),
        ("Editor test drives", "editor/TEST_DRIVE.md"),
    ]),
]


def rewrite_links(text, rel_path, pages):
    """Links to pages stay relative; links to other files go to GitHub."""
    base = os.path.dirname(rel_path)

    def fix(m):
        label, target = m.group(1), m.group(2)
        if re.match(r"^[a-z]+://|^#|^mailto:", target):
            return m.group(0)
        if target.startswith("file://"):  # (absolute local links in some files)
            p = target.split("rayzr/", 1)[-1]
            return f"[{label}]({REPO}/blob/main/{p})"
        path, _, anchor = target.partition("#")
        resolved = os.path.normpath(os.path.join(base, path)) if path else rel_path
        if resolved in pages:
            return m.group(0)
        kind = "tree" if os.path.isdir(os.path.join(ROOT, resolved)) else "blob"
        return f"[{label}]({REPO}/{kind}/main/{resolved}{'#' + anchor if anchor else ''})"

    # (Not inside code blocks.)
    out, inside = [], False
    for line in text.split("\n"):
        if line.lstrip().startswith("```"):
            inside = not inside
        out.append(line if inside else re.sub(r"\[([^\]]*)\]\(([^)\s]+)\)", fix, line))
    return "\n".join(out)


def copy_page(rel, pages):
    with open(os.path.join(ROOT, rel)) as f:
        text = f.read()
    dst = os.path.join(DOCS, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "w") as f:
        f.write(rewrite_links(text, rel, pages))


# --- the Lua API reference ----------------------------------------------------------

def parse_lua_api(path):
    """LuaCATS definitions -> classes: {name: {doc, fields, functions, parents}}."""
    classes, order, table_of = {}, [], {}
    doc, params, returns = [], [], []
    current = None
    with open(path) as f:
        lines = f.read().split("\n")
    for line in lines:
        s = line.strip()
        m = re.match(r"^---@class\s+([\w.]+)\s*(?::\s*(.+))?", s)
        if m:
            name = m.group(1)
            if name not in classes:
                classes[name] = {"doc": [], "fields": [], "functions": [], "parents": (m.group(2) or "").strip()}
                order.append(name)
            current = name
            classes[name]["doc"] += doc
            doc, params, returns = [], [], []
            continue
        m = re.match(r"^---@field\s+(\S+)\s+(\S+)\s*(.*)", s)
        if m and current:
            classes[current]["fields"].append((m.group(1), m.group(2), m.group(3)))
            continue
        m = re.match(r"^---@param\s+(\S+)\s+(\S+)\s*(.*)", s)
        if m:
            params.append((m.group(1), m.group(2), m.group(3)))
            continue
        m = re.match(r"^---@return\s+(\S+)\s*(.*)", s)
        if m:
            returns.append((m.group(1), m.group(2)))
            continue
        if s.startswith("---@"):
            continue
        if s.startswith("---"):
            doc.append(s[3:].rstrip())
            continue
        m = re.match(r"^local\s+(\w+)\s*=\s*\{\}", s)
        if m and current:
            table_of[m.group(1)] = current
            if doc and not classes[current]["doc"]:
                classes[current]["doc"] = doc
            doc = []
            continue
        m = re.match(r"^function\s+(\w+)([.:])(\w+)\s*\(([^)]*)\)", s)
        if m:
            owner = table_of.get(m.group(1), m.group(1))
            if owner not in classes:
                classes[owner] = {"doc": [], "fields": [], "functions": [], "parents": ""}
                order.append(owner)
            classes[owner]["functions"].append({
                "name": m.group(3), "sep": m.group(2), "args": m.group(4), "doc": doc,
                "params": params, "returns": returns})
            doc, params, returns = [], [], []
            continue
        if s == "" or not s.startswith("--"):
            doc, params, returns = [], [], []
    globals_ = {}
    for line in lines:
        m = re.match(r"^(\w+)\s*=\s*(\w+)\s*$", line.strip())
        if m and m.group(2) in classes:
            globals_[m.group(2)] = m.group(1)
    return classes, order, globals_


def md_escape(s):
    return s.replace("|", "\\|")


def render_class(name, c, global_name=None):
    title = global_name or name
    out = [f"## {title}", ""]
    if c["parents"]:
        out += [f"*Inherits {c['parents']}*", ""]
    text = "\n".join(c["doc"]).strip()
    if text:
        out += [text, ""]
    if c["fields"]:
        out += ["| Field | Type | |", "|---|---|---|"]
        for f, t, d in c["fields"]:
            out.append(f"| `{f}` | `{md_escape(t)}` | {md_escape(d)} |")
        out.append("")
    for fn in c["functions"]:
        call = f"{title}{fn['sep']}{fn['name']}({fn['args']})"
        out += [f"### {call}", ""]
        body = "\n".join(fn["doc"]).strip()
        if body:
            out += [body, ""]
        if fn["params"]:
            for p, t, d in fn["params"]:
                out.append(f"- `{p}` `{t}` {d}".rstrip())
            out.append("")
        if fn["returns"]:
            out.append("Returns " + ", ".join(f"`{t}`" + (f" {d}" if d else "") for t, d in fn["returns"]))
            out.append("")
    return out


def lua_reference():
    classes, order, globals_ = parse_lua_api(os.path.join(ROOT, "engine", "definitions", "engine_api.lua"))
    groups = {"Nodes": [], "Modules": [], "Types": []}
    for name in order:
        c = classes[name]
        if not c["functions"] and not c["fields"] and not c["doc"]:
            continue
        if name == "Node" or name.endswith("Node"):
            groups["Nodes"].append(name)
        elif name.endswith("Module") or name in globals_:
            groups["Modules"].append(name)
        else:
            groups["Types"].append(name)
    os.makedirs(os.path.join(DOCS, "api"), exist_ok=True)
    pages = []
    intro = {
        "Nodes": "Every node type's methods (on `self.node` or any node). Properties are fields too: `node.position = Vec2(10, 20)`.",
        "Modules": "The global modules scripts call: `Scene`, `Input`, `Save`, `Tween`, `Pool`, `Camera`...",
        "Types": "Values passed around: vectors, hits, events, options tables.",
    }
    for group, names in groups.items():
        lines = [f"# Lua API: {group}", "", intro[group], "",
                 "Generated from `engine/definitions/engine_api.lua` - the same definitions the Code tab and any "
                 "LuaLS editor use for completion and hover docs.", ""]
        for n in names:
            lines += render_class(n, classes[n], globals_.get(n))
        fn = f"api/{group.lower()}.md"
        with open(os.path.join(DOCS, fn), "w") as f:
            f.write("\n".join(lines) + "\n")
        pages.append((group, fn))
    # The editor plugin API.
    pclasses, porder, pglobals = parse_lua_api(os.path.join(ROOT, "editor", "definitions", "editor_api.lua"))
    lines = ["# Lua API: editor plugins", "",
             "The `Editor`, `ui` and overlay APIs plugins use (guide: [Plugins: guide](../editor/docs/plugin_guide.md)). "
             "Generated from `editor/definitions/editor_api.lua`.", ""]
    for n in porder:
        c = pclasses[n]
        if c["functions"] or c["fields"]:
            lines += render_class(n, c, {"EditorAPI": "Editor", "EditorUI": "ui"}.get(n))
    with open(os.path.join(DOCS, "api", "plugins.md"), "w") as f:
        f.write("\n".join(lines) + "\n")
    pages.append(("Editor plugins", "api/plugins.md"))
    return pages


# --- pages written here ---------------------------------------------------------------

HOME = """# Rayzr

![Rayzr](assets/rayzr.png){{ width="160" }}

A 2D game engine and editor: scenes and nodes, Lua scripting with live
reload, physics, tile maps and an integrated LDtk level editor, skeletal
animation, an audio mixer, and exports to macOS, Windows, Linux and the web -
from one editor, no compiler needed.

[Download the editor]({repo}/releases){{ .md-button .md-button--primary }}
[Getting started](getting_started.md){{ .md-button }}

| | |
|---|---|
| **Start fast** | [New Project templates](templates.md): a platformer, a top-down RPG, a shoot 'em up and a puzzle - complete small games to change |
| **Learn the editor** | [The editor](editor/README.md), [plugins](editor/docs/plugin_guide.md) |
| **Script it** | [Scripting guide](engine/SCRIPTING.md), the [Lua API](api/nodes.md) |
| **Go deeper** | [Engine guides](engine/docs/README.md): navigation, cameras, animation, audio, accessibility, crash reports... |

Dev builds: every change merged into the engine is published as a
pre-release ([Releases]({repo}/releases)); the editor tells you when a newer
one is out.
""".format(repo=REPO)

GETTING_STARTED = """# Getting started

1. **Install**: download the editor for your platform from
   [Releases]({repo}/releases) (`.dmg` on macOS, `.zip` on Windows,
   AppImage / `.deb` / `.tar.gz` on Linux) and run it. On macOS the first
   start may need right-click > Open (dev builds aren't notarized yet).
2. **Make a project**: the Welcome window (Help > Welcome) has New Project
   templates - pick **Platformer** (or another), a name and a folder, and
   **Create Project**.
3. **Play it**: press **F5**. Change something - a property in the
   Inspector, a line in a script (`scripts/player.lua`) - and play again;
   scripts reload while the game runs.
4. **Learn by changing**: each template has a README (in its folder) saying
   what's where and what to try first. The [templates page](templates.md)
   has them all.
5. **Export**: Project Settings > Export makes a standalone game for macOS,
   Windows, Linux or the web.

Next: [the editor](editor/README.md), [scripting](engine/SCRIPTING.md), the
[Lua API](api/nodes.md).
""".format(repo=REPO)


def templates_page():
    root = os.path.join(ROOT, "templates")
    out = ["# Templates", "",
           "New Project templates are small, complete games: play one, then change it. "
           "Help > Welcome > New Project. The art is from [Kenney](https://kenney.nl) (CC0: use it for anything).", ""]
    import json
    entries = []
    for t in sorted(os.listdir(root)):
        meta = os.path.join(root, t, "template.json")
        if os.path.isfile(meta):
            entries.append((json.load(open(meta)).get("order", 0), t))
    os.makedirs(os.path.join(DOCS, "templates"), exist_ok=True)
    for _, t in sorted(entries):
        with open(os.path.join(root, t, "README.md")) as f:
            readme = f.read()
        pv = os.path.join(root, t, "preview.png")
        # (One level down: the template is a section of this page.)
        lines = ["#" + l if l.startswith("#") else l for l in readme.split("\n")]
        readme = "\n".join(lines)
        out.append(lines[0])
        if os.path.isfile(pv):
            shutil.copyfile(pv, os.path.join(DOCS, "templates", f"{t}.png"))
            out += ["", f"![{t}](templates/{t}.png)", ""]
        out += readme.split("\n")[1:]
        out.append("")
    return "\n".join(out)


def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(DOCS)
    # The logo (editor/assets/icon.png, made from branding/ by scripts/branding/make_icons.odin).
    os.makedirs(os.path.join(DOCS, "assets"))
    shutil.copy(os.path.join(ROOT, "editor", "assets", "icon.png"), os.path.join(DOCS, "assets", "rayzr.png"))
    nav_guides = []
    engine_docs = sorted(f for f in os.listdir(os.path.join(ROOT, "engine", "docs")) if f.endswith(".md"))
    pages = set()
    for section, items in GUIDES:
        if items is None:
            items = [("Overview", "engine/docs/README.md")] + [
                (open(os.path.join(ROOT, "engine", "docs", f)).readline().lstrip("# ").strip(), f"engine/docs/{f}")
                for f in engine_docs if f != "README.md"]
        nav_guides.append((section, items))
        pages.update(rel for _, rel in items)
    for _, items in nav_guides:
        for _, rel in items:
            copy_page(rel, pages)
    with open(os.path.join(DOCS, "index.md"), "w") as f:
        f.write(HOME)
    with open(os.path.join(DOCS, "getting_started.md"), "w") as f:
        f.write(GETTING_STARTED)
    with open(os.path.join(DOCS, "templates.md"), "w") as f:
        f.write(templates_page())
    api = lua_reference()

    def nav_yaml():
        y = ["nav:", "  - Home: index.md", "  - Getting started: getting_started.md", "  - Templates: templates.md"]
        for section, items in nav_guides:
            y.append(f"  - {section}:")
            for title, rel in items:
                y.append(f"    - {json_str(title)}: {rel}")
        y.append("  - Lua API:")
        for title, rel in api:
            y.append(f"    - {json_str(title)}: {rel}")
        return "\n".join(y)

    with open(os.path.join(OUT, "mkdocs.yml"), "w") as f:
        f.write(f"""site_name: Rayzr
site_description: A 2D game engine and editor
site_url: {SITE}
repo_url: {REPO}
edit_uri: ""
docs_dir: docs
site_dir: ../docs_site
theme:
  name: material
  logo: assets/rayzr.png
  favicon: assets/rayzr.png
  palette:
    - scheme: slate
      primary: black
      accent: amber
      toggle: {{icon: material/brightness-4, name: Light mode}}
    - scheme: default
      primary: black
      accent: amber
      toggle: {{icon: material/brightness-7, name: Dark mode}}
  features: [navigation.sections, navigation.top, search.highlight, content.code.copy]
markdown_extensions:
  - admonition
  - attr_list
  - tables
  - toc: {{permalink: true}}
  - pymdownx.highlight
  - pymdownx.superfences
  - pymdownx.details
validation:
  links:
    not_found: warn
    anchors: ignore
{nav_yaml()}
""")
    print(f"{OUT} ({sum(len(i) for _, i in nav_guides) + len(api) + 3} pages)")


def json_str(s):
    import json
    return json.dumps(s)


if __name__ == "__main__":
    sys.exit(main())
