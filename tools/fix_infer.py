#!/usr/bin/env python3
"""Iteratively fix 'Cannot infer the type' parse errors by replacing ':=' with '=' on the reported line."""
import re, subprocess, sys
for it in range(40):
    out = subprocess.run(["bash", "tools/check.sh", "400"], capture_output=True, text=True).stdout
    lines = out.splitlines()
    fixes = []
    for i, l in enumerate(lines):
        m = re.search(r'Cannot infer the type of "(\w+)" variable', l)
        if not m and 'inferred from a Variant value' in l:
            m = re.search(r'()', l)
        if m and i + 1 < len(lines):
            m2 = re.search(r'\(res://(.+?):(\d+)\)', lines[i + 1])
            if m2:
                fixes.append((m2.group(1), int(m2.group(2)), m.group(1)))
    if not fixes:
        print(out[-3000:])
        break
    for f, ln, var in fixes:
        src = open(f).read().split("\n")
        old = src[ln - 1]
        if var == '':
            new = old.replace(':=', '=', 1)
        else:
            new = re.sub(r'\b' + var + r'\s*:=', var + ' =', old, count=1)
        if new == old and var != '':
            new = re.sub(r'\b' + var + r'(\s*):=', var + r'\1=', old, count=1)
        src[ln - 1] = new
        open(f, "w").write("\n".join(src))
        print("fixed", f, ln, var)
