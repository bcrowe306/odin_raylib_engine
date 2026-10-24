#!/usr/bin/env python3
"""Pastes the engine_api.lua blocks an engine test run printed on drift
("---- paste into engine_api.lua ---- ... ---- end ----") over the matching
"-- <name> begin" ... "-- <name> end" sections.
  scripts/paste_lua_definitions.py /tmp/test.log"""
import re, sys
log = open(sys.argv[1]).read()
api_path = 'engine/definitions/engine_api.lua'
api = open(api_path).read()
blocks = re.findall(r'---- paste into engine_api.lua ----\n(.*?)---- end ----', log, re.S)
for b in blocks:
    m = re.match(r'-- (.+?) begin', b)
    if not m:
        continue
    name = m.group(1)
    i = api.find('-- %s begin' % name)
    end = '-- %s end\n' % name
    j = api.find(end)
    if i < 0 or j < 0:
        print('no section', name); continue
    api = api[:i] + b + api[j + len(end):]
    print('pasted', name)
open(api_path, 'w').write(api)
