#!/usr/bin/env python3

import json
import subprocess

import sys

binary = sys.argv[1]

with open('comp_units.json') as f:
    comp_units = json.load(f)

all_syms = [
    v.split(' ')[-1]
    for v in subprocess.check_output(['nm',binary]).decode().strip().split('\n')
]

allowed = set([
    'main.main',
    'main.main_',
    'util.String.append_',
    'util.String.appendSlice_',
    'util.String.deinit_',
    'util.String.new_',
    'util.lock_',
    'util.rlock_',
    'util.unlock_',
    'util.runlock_',
    'util.free_u8_slice_',
])

symbols = [sym for sym in all_syms if next((
     comp for comp in comp_units if sym.startswith(comp)
    ), None
)]

cmd = ['strip']
for s in symbols:
    cmd += ['-N',s]

cmd += [binary,'-g']

#print(cmd)

subprocess.check_call(cmd)
