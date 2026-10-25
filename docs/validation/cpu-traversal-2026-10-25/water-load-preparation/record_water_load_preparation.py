from pathlib import Path
import gzip, hashlib, json, shutil, re, subprocess

s = Path(__file__).resolve().parent
r = s / 'repo'
out = r / 'docs/validation/cpu-traversal-2026-10-25/water-load-preparation'
out.mkdir(exist_ok=True)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(name, value):
    (out / name).write_text(json.dumps(value, indent=2) + '\n')

def zipcopy(path, name):
    (out / (name + '.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))

checks = {}
for name in ['water-load-preparation-guarded-registered', 'water-load-preparation-guarded-related',
             'water-load-preparation-registered-before', 'water-load-preparation-registered']:
    folder = s / name
    receipt = json.loads((folder / 'results.json').read_text())
    expected = {'water-load-preparation-guarded-registered': 2,
                'water-load-preparation-guarded-related': 5,
                'water-load-preparation-registered-before': 1,
                'water-load-preparation-registered': 7}[name]
    assert len(receipt['cases']) == expected, (name, 'still running')
    if 'guarded' in name:
        assert receipt['passed'], name
    shutil.copy2(folder / 'results.json', out / (name + '.json'))
    for case in receipt['cases']:
        zipcopy(folder / case['log'], name + '-' + case['id'] + '.log')
        checks[name + '-' + case['id']] = {k: case[k] for k in ['passed', 'result', 'errors']}
        for p in (folder / case['id'] / 'data/godot/app_userdata/Cursed Lands').rglob('*.json'):
            if p.name in ['zone-traversal.json', 'water-load-preparation.json', 'cloud-load-preparation.json']:
                zipcopy(p, name + '-' + case['id'] + '-' + p.name)

names = ['water-load-preparation-before', 'water-load-preparation-before-fixture',
         'water-load-preparation-candidate', 'water-load-before-final-fixture',
         'dar-tactical-water-prepared', 'water-load-related-shader-water',
         'water-load-related-shader-water-staged', 'water-load-related-shader-water-before',
         'water-load-related-staged-fixture-before', 'water-load-related-staged-fixture-final']
for name in names:
    folder = s / 'runs' / name
    zipcopy(folder / 'run.log', name + '.log')
    shutil.copy2(folder / 'command.json', out / (name + '-command.json'))
    checks[name] = [line for line in (folder / 'run.log').read_text().splitlines()
                   if re.search(r'(checks=| checks |^FAIL |^SCRIPT ERROR|^DAR_.*PREPARATION)', line)]
    for p in (folder / 'data/godot/app_userdata/Cursed Lands').rglob('*.json'):
        if p.name in ['shader-compilation-water.json', 'water-load-preparation.json', 'zone-traversal.json']:
            zipcopy(p, name + '-' + p.name)

for label in ['final', 'guarded']:
    name = 'water-load-preparation-windows-' + label
    shutil.copy2(s / (name + '-checks.json'), out / (name + '-checks.json'))
    zipcopy(s / (name + '-water_load_preparation.log'), name + '.log')
    images = s / ('water-load-preparation-windows-' + ('guarded-' if label == 'guarded' else '') + 'images')
    shutil.copy2(images / 'water-load-preparation.json', out / (name + '.json'))
    if label == 'guarded':
        for p in images.glob('*.png'):
            shutil.copy2(p, out / ('windows-' + p.name))

for name in ['export_water_load_preparation_guarded.py', 'water_load_preparation_windows_guarded_check.py',
             'dar_tactical_diagnostics.gd', 'dar_tactical_metrics.gd', 'dar_tactical_route.gd',
             'dar_tactical_base.gd', 'shader_compilation_water_external.gd',
             'shader_compilation_water_staged_external.gd', 'record_water_load_preparation.py']:
    shutil.copy2(s / name, out / name)

snapshot = s / 'water-load-preparation-guarded-game'
runtime = [p for p in (r / 'game').rglob('*') if p.is_file()
           and '.godot' not in p.relative_to(r / 'game').parts
           and (p.suffix in {'.gd', '.gdshader', '.tscn', '.tres', '.gdextension'} or 'src/native/bin/' in str(p))]
differences = [str(p.relative_to(r / 'game')) for p in runtime
               if not (snapshot / p.relative_to(r / 'game')).exists()
               or sha(p) != sha(snapshot / p.relative_to(r / 'game'))]
assert not differences, differences
packs = {}
for name in ['mark-projection-final-linux', 'water-load-preparation-linux',
             'water-load-preparation-final-linux', 'water-load-preparation-guarded-linux',
             'water-load-preparation-guarded-windows']:
    paths = list((s / name).glob('runtime.*')) + list((s / name / 'src/native/bin').glob('libterrain_search*'))
    packs[name] = {str(p.relative_to(s / name)): sha(p) for p in paths}
source = ['game/src/game/fx/water_reflection.gd', 'game/src/game/shader_warmup.gd',
          'tools/tests/water_load_preparation.gd', 'tools/tests/shader_compilation_water.gd', 'tools/regressions.json']
write('provenance.json', {
    'base_commit': '4d172120', 'runtime_files_compared': len(runtime), 'differences': differences,
    'source_sha256': {name: sha(r / name) for name in source}, 'packs': packs,
    'snapshot': str(snapshot), 'native_libraries': 'Unchanged from accepted main; this change is GDScript only.',
    'original_comparison': 'The original-code comparison for shared gameplay remains in the parent report. This change prepares a Godot SubViewport and its shader/render-thread completion barrier, a remake-only Mirror implementation. The original executable has no corresponding Godot preparation entry point, so an identical original Wine regression or FPS comparison is inapplicable. Original map water heights, simulation and gameplay code remain unchanged. Windows/Wine evidence here executes the remake.',
    'intermediate_failures': [
        'The first fixture left its manually created viewport enabled and used exact transform equality. The maintained fixture disables it before observing draws and uses Transform3D.is_equal_approx for engine transform storage.',
        'The first related water invocation did not stage its res://tools/tests superclass for a packaged runtime. It was cancelled after the parse failure; the external staged copy retains the original test body.',
        'The older RT fixture failed three checks on both unchanged main and the candidate. It watched only the active device and returned while a replacement was still building. The correction observes pending and active devices and waits for replacement completion, retaining output, request identity and replacement assertions. Both versions then pass all 67 checks.',
        'The pre-guard candidate was tested against the expanded fixture and failed its canvas-only completion check plus dependent checks. Final Linux and Windows packs preserve the pending request when viewport.disable_3d is true and pass all 24 checks.'
    ]
})
route = json.loads((s / 'runs/dar-tactical-water-prepared/data/godot/app_userdata/Cursed Lands/zone-traversal/zone-traversal.json').read_text())
write('dar-controls.json', {'gpu_job': 'a9719b87ce414290', 'checks': route['checks'], 'failures': route['failures'],
    'frames': sum(row['frames'] for row in route['rows']),
    'controllable_frames': sum(row['controllable_frames'] for row in route['rows']),
    'phases': [{k: row[k] for k in ['phase', 'frames', 'controllable_frames', 'blocked']} for row in route['rows']],
    'baseline': '../dar-tactical-water-state.json', 'limits': 'Two-leg control regression, not an FPS comparison. This candidate precedes only the canvas-disabled loading guard; final registered standard and PT routes use the exact final runtime.'})
write('checks.json', checks)
print(json.dumps({'runtime_files': len(runtime), 'differences': differences, 'evidence_files': len(list(out.iterdir()))}))
