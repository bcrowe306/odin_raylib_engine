#!/bin/sh
# Every reference topic the level editor links to (level_tip / LevelRef_*
# / *_TOPIC constants / topic = "...") must exist in
# engine/docs/level_editor_reference.md (<!-- topic: a, b -->).
# Prints the missing ones; exits 1 when there are any.
cd "$(dirname "$0")/.." || exit 1
python3 - <<'PY'
import re, glob, sys
doc = open('engine/docs/level_editor_reference.md').read()
topics = set()
for m in re.finditer(r'<!-- topic: ([^>]*)-->', doc):
    topics.update(t.strip() for t in m.group(1).split(','))
used = {}
pats = [
    r'level_tip\(.*,\s*"([a-z][a-z0-9_.]*)"\)\s*$',
    r'(?:LevelRef_Open|LevelRef_Panel|LevelRef_Hover|level_help_button)\(\s*"([a-z][a-z0-9_.]*)"',
    r'_TOPIC\s*::\s*"([a-z][a-z0-9_.]*)"',
    r'topic\s*=\s*"([a-z][a-z0-9_.]*)"',
]
for f in glob.glob('editor/level_*.odin'):
    src = open(f).read()
    for p in pats:
        for m in re.finditer(p, src, re.M):
            used.setdefault(m.group(1), set()).add(f)
missing = sorted(t for t in used if t not in topics)
for t in missing:
    print('missing topic: %s (%s)' % (t, ', '.join(sorted(used[t]))))
print('%d topics linked, %d in the reference, %d missing' % (len(used), len(topics), len(missing)))
sys.exit(1 if missing else 0)
PY
