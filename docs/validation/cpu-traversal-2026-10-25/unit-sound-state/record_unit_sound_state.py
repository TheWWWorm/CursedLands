from pathlib import Path
import gzip, hashlib, json, re, shutil, subprocess

s = Path(__file__).resolve().parent
r = s / 'repo'
out = r / 'docs/validation/cpu-traversal-2026-10-25/unit-sound-state'
out.mkdir(exist_ok=True)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(name, value):
    (out / name).write_text(json.dumps(value, indent=2) + '\n')

def zipped(path, name):
    (out / (name + '.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))

checks = {}
for name in ['unit-sound-state-before', 'unit-sound-state-debug', 'unit-sound-state-before-corrected',
             'typed-sound-scan-probe', 'unit-sound-state-combat_inputs', 'unit-sound-state-audio_bus_routes',
             'dar-current-profile', 'dar-sound-state-micro']:
    folder = s / 'runs' / name
    zipped(folder / 'run.log', name + '.log')
    shutil.copy2(folder / 'command.json', out / (name + '-command.json'))
    checks[name] = [line for line in (folder / 'run.log').read_text().splitlines()
                   if re.search(r'(^FAIL |checks=| checks |^SOUND_STATE_|TYPED_UNIT_SOUND|AUDIO_BUS_ROUTES)', line)]

for directory, expected in [('unit-sound-state-registered', True),
                            ('unit-sound-state-registered-before', False),
                            ('unit-sound-state-rendered', True)]:
    report = json.loads((s / directory / 'results.json').read_text())
    assert report['passed'] == expected
    shutil.copy2(s / directory / 'results.json', out / (directory + '.json'))
    for row in report['cases']:
        zipped(s / directory / row['log'], directory + '-' + row['id'] + '.log')

windows = json.loads((s / 'unit-sound-state-windows-checks.json').read_text())
assert len(windows) == 4 and all(row['returncode'] == 0 for row in windows)
for path in s.glob('unit-sound-state-windows-*.log'):
    zipped(path, path.name)

for name in ['unit-sound-state-windows-checks.json', 'unit-sound-state-related.json',
             'unit_sound_state_windows_checks.py', 'export_unit_sound_state.py',
             'dar_sound_state_micro.gd', 'prepare_dar_current_profile.py',
             'dar-current-profile-methods.json', 'dar-current-profile-summary.json',
             'typed_sound_scan_probe.gd', 'typed_unit_sounds.gd', 'legacy_unit_sounds.gd', 'unit_sound_state_debug.gd',
             'record_unit_sound_state.py']:
    shutil.copy2(s / name, out / name)
path = out / 'legacy_unit_sounds.gd'
path.write_text(path.read_text().rstrip() + '\n')
shutil.copy2(s / 'dar-current-profile-game/cpu_scope.gd', out / 'cpu_scope.gd')

for name in ['dar-current-profile', 'dar-sound-state-micro']:
    folder = s / 'runs' / name / 'data/godot/app_userdata/Cursed Lands/zone-traversal'
    route = json.loads((folder / 'zone-traversal.json').read_text())
    assert route['failures'] == 0 and route['actor_count'] == 334
    for path in folder.glob('*.json'):
        zipped(path, name + '-' + path.name)

folder = s / 'runs/dar-sound-state-micro/data/godot/app_userdata/Cursed Lands/zone-traversal'
rows = json.loads((folder / 'sound-state-micro.json').read_text())
old = sum(row['usec'] for row in rows if not row['candidate']) / sum(row['calls'] for row in rows if not row['candidate'])
new = sum(row['usec'] for row in rows if row['candidate']) / sum(row['calls'] for row in rows if row['candidate'])
write('dar-micro.json', {
    'gpu_job': '56c771e90c114829', 'before_us': old, 'after_us': new,
    'saving_percent': 100 * (1 - new / old), 'rows': rows,
    'method': 'ABBA of the complete independent previous collector and new production collector over the same 334 live Dar actors, listener, normal mixer and player timelines. Initial observation is silent; repeated current-frame scans retain identical state and issue no duplicate sound requests. No own CPU builds or checks ran during this heavy GPU job.',
    'limits': 'Current-frame scan microbenchmark, not a complete moving-frame or whole-game FPS result. Separate state regressions exercise advancing clips, sound requests and RNG. The screening probe field named native actually selects the typed GDScript prototype; no native code changed.'})

baseline = subprocess.check_output(['git', 'show', 'e026666f:game/src/game/unit_sounds.gd'], cwd=r, text=True)
oracle = (r / 'tools/tests/unit_sound_state_reference.gd').read_text().split('\n', 1)[1]
assert oracle == baseline.replace('class_name UnitSounds\n', '', 1)
snapshot = s / 'unit-sound-state-game'
runtime = [p for p in (r / 'game').rglob('*') if p.is_file()
           and '.godot' not in p.relative_to(r / 'game').parts
           and (p.suffix in {'.gd', '.gdshader', '.tscn', '.tres', '.gdextension'} or 'src/native/bin/' in str(p))]
differences = [str(p.relative_to(r / 'game')) for p in runtime
               if not (snapshot / p.relative_to(r / 'game')).exists()
               or sha(p) != sha(snapshot / p.relative_to(r / 'game'))]
assert not differences
packs = {}
for name in ['unit-sound-state-linux', 'unit-sound-state-windows']:
    packs[name] = {str(p.relative_to(s / name)): sha(p) for p in
                   list((s / name).glob('runtime.*')) + list((s / name / 'src/native/bin').glob('libterrain_search*'))}
original = Path('/home/llm2x/Documents/EI/inspection/ghidra/decompiled/functions/00134')
write('provenance.json', {
    'base_commit': 'e026666f', 'runtime_files_compared': len(runtime), 'differences': differences,
    'snapshot': str(snapshot), 'packs': packs,
    'source_sha256': {name: sha(r / name) for name in ['game/src/game/unit_sounds.gd',
        'tools/tests/unit_sound_state.gd', 'tools/tests/unit_sound_state_reference.gd', 'tools/regressions.json']},
    'reference_exact_except_header_and_class_name': True,
    'original_sources': {str(p): sha(p) for p in [original / '534b60_FUN_00534b60.c', original / '534760_FUN_00534760.c']},
    'original_comparison': 'Original 0x534b60 retains clip/frame and idle/attack handles in fixed fields, resets previous time only on clip changes, uses prev < step <= current for steps, and suppresses silence/brief-zone attacks. 0x534760 uses prev <= voice_frame < current. The remake already implements those rules; this change preserves them while replacing its Dictionary state. An identical original Wine comparison of GDScript cache access is inapplicable. Windows/Wine checks execute the remake and make no original FPS claim.',
    'native_libraries': 'Unchanged; typed GDScript state only.',
    'diagnostic_profile': {'gpu_job': 'b761fa80b6d44fcc', 'base_commit': 'e026666f',
        'checks': 54, 'notes': 'Private timing wrappers only; inclusive scopes overlap. No extra FPS claim.'},
    'fixture_correction': 'The first before run reported four additional fixture failures because Godot String.contains("") is false. The request counter now explicitly accepts an empty suffix. On unchanged production, the corrected fixture passes every behavior comparison and fails only the intended typed-cache assertion. Raw initial failures are retained.'})
write('checks.json', checks)
print(json.dumps({'before_us': old, 'after_us': new, 'saving_percent': 100 * (1 - new / old), 'files': len(list(out.iterdir()))}))
