from pathlib import Path
import gzip, hashlib, json, re, shutil, subprocess
from release_config import VERSION, PREVIOUS_VERSION
w = Path(__file__).resolve().parent
r = w.parent / 'repo'
out = r / 'docs/validation' / ('release-' + VERSION)
out.mkdir(exist_ok=True)
read = lambda p: json.loads(p.read_text())
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
superseded = {
    'cpu-raytrace_source_cache': 'rendered-raytrace_source_cache',
    'cpu-ground_mark_animation': 'rendered-ground_mark_animation',
    'autochess-arena_portrait_feedback_ui': 'fps30-arena_portrait_feedback_ui',
    'autochess-arena_portrait_polish_ui': 'fps30-arena_portrait_polish_ui',
    'autochess-arena_astral_ui': 'astral-ui-clean-teardown',
    'windows-route-path_trace_traversal_stalls': 'windows-route-waypoint-path_trace_traversal_stalls',
}
required = [x['tag'] for group in ['cpu', 'tutorials', 'autochess', 'vulkan']
            for x in read(w / (group + '-merged.json'))]
required = [superseded.get(x, x) for x in required]
required += ['windows-framegen-rtx_frame_generation', 'windows-route-waypoint-path_trace_traversal_stalls',
             'windows-dlss-rtx_super_resolution', 'windows-dlss-fsr_screen',
             'windows-fsr-fsr_render', 'windows-fsr-path_trace_upload_staging',
             'windows-fsr-path_trace_history_handoff',
             'issue-regression-creature_alerts', 'issue-regression-authored_wolf_corpse',
             'issue-regression-dialogue_clock_coop', 'issue108-held-space-rendered']
rows = []
logs = out / 'logs'
logs.mkdir(exist_ok=True)
for tag in required:
    p = w / 'checks' / tag
    d = read(p / 'result.json')
    assert d['exit'] == 0 and not d['errors'], (tag, d['exit'], d['errors'])
    count, summary = None, []
    for line in d['summary']:
        match = re.search(r'"checks"\s*:\s*(\d+)|checks[= ](\d+)|(\d+) checks|ARENA_COMMANDER_UI (\d+)', line)
        if match:
            count = int(next(x for x in match.groups() if x))
            summary = [line] if len(line) < 300 else [line.split(' {')[0] + ': passed']
    row = {k: d[k] for k in ['suite', 'platform', 'renderer', 'seconds', 'fixture_sha256'] if k in d}
    row.update(tag=tag, checks=count, passed=True, summary=summary,
               run_log_sha256=sha(p / 'run.log'),
               allowed_diagnostics=d.get('allowed_diagnostics', []))
    rows.append(row)
    with gzip.open(logs / (tag + '.txt.gz'), 'wb') as f:
        f.write((p / 'run.log').read_bytes())
    for f in p.glob('*.json'):
        if f.name in ['result.json', 'route-inventory.json', 'wine-adapter-mapping.json']:
            continue
        data = read(f)
        if isinstance(data, dict):
            assert not data.get('failures'), (tag, f.name)
        if f.stat().st_size < 1_000_000:
            shutil.copy2(f, out / (tag + '-' + f.name))
build = read(w / 'build.json')
assert build['game_tree'] == subprocess.check_output(['git', 'rev-parse', 'HEAD:game'], cwd=r, text=True).strip()
cross = read(w / 'android-audit.json')
assert cross['all_five_platforms_identical'] and cross['compiled_scripts'] == 435
assert read(w / 'browser-fresh.json')['passed']
assert read(w / 'browser-validation.json')['cache_upgrade']['passed']
wiki = read(w / 'wiki-actual-results/result.json')
assert len(wiki['checks']) == 36 and not wiki['errors']
peers = read(w / 'peer-tests/result.json')
assert all(x['passed'] and x['results_match'] for x in peers)
for name in ['branding-audit.json', 'android-audit.json', 'browser-fresh.json',
             'browser-validation.json', 'previous-browser-input.json', 'wiki-package.json',
             'windows-engine-template.json', 'legacy-dialogue-fixture-comparison.json']:
    shutil.copy2(w / name, out / name)
shutil.copy2(w / 'peer-tests/result.json', out / 'autochess-peers.json')
shutil.copy2(w / 'wiki-actual-results/result.json', out / 'wiki-browser.json')
recipes = out / 'recipes'
recipes.mkdir(exist_ok=True)
for name in ['release_config.py', 'build.py', 'android.py', 'audit-android.py',
             'run_packaged.py', 'test_merged.py', 'test_windows.py', 'pt_harness.py',
             'run_peers.py', 'update_guide.py', 'guide_export.gd', 'prepare-host.py',
             'sync-host.py', 'record-integrated.py', 'archive-platforms.py',
             'tools_bundle.py', 'archive-rtx30.py', 'verify_live.py', 'wiki_actual.mjs']:
    if (w / name).exists(): shutil.copy2(w / name, recipes / name)
report = {
    'version': VERSION, 'previous_stable': 'v' + PREVIOUS_VERSION, 'date': '2026-10-24',
    'status': 'Integrated release packages validated; publication evidence is recorded separately.',
    'source_commit': build['source_commit'], 'game_tree': build['game_tree'],
    'campaign_protocol': 23, 'autochess_protocol': 4,
    'integrated_tips': {
        'path_tracing': 'bf10be5e059f2c38b89df8a314e1ceed7377ab52',
        'autochess': subprocess.check_output(['git', 'rev-parse', 'd9851b2e'], cwd=r, text=True).strip(),
        'contextual_tutorials': '870a06e1a3c7e88dd44558a53e2258d8c241d217',
        'github_issues_103_108': 'b06bc442fa55289a06d4b6e414f0720263a63b0f',
    },
    'platform_runtime': {
        'linux-x86_64': {'target_os_tested': True, 'status': 'passed', 'scope': 'Exported package: campaign, Autochess, EN/RU/DE UI and Vulkan NRD checks.'},
        'windows-x86_64': {'target_os_tested': False, 'status': 'Proton/VKD3D passed', 'scope': 'Exported DX12 executable: real DLSS/DLAA, FSR upscaling and generation, NRD, staged uploads, history handoff and full combat traversal. Optional dlssg_for_sm86 package separately tested.'},
        'android': {'target_os_tested': False, 'status': 'signed export verified', 'scope': 'Version code 62, unchanged app ID/certificate, non-debuggable, 435 production scripts identical; no device runtime test.'},
        'macos-universal': {'target_os_tested': False, 'status': 'archive verified', 'scope': 'Unsigned universal export, icon/version and production script parity checked; no macOS runtime test.'},
        'web': {'target_os_tested': True, 'status': 'passed', 'scope': 'Fresh engine start and upgrade from published 1.27.0 cache with IndexedDB preserved. Real localized guide articles exercised in both campaigns.'},
    },
    'packaged_checks': rows,
    'total_packaged_checks_reported': sum(x['checks'] or 0 for x in rows),
    'multiplayer': {'transports': ['enet', 'websocket'], 'checks': sum(p['checks'] for x in peers for p in x['peers']), 'results_match': True},
    'wiki_browser_checks': 36, 'compiled_scripts': 435,
    'validation_setup_corrections': [
        'The source-cache and ground-mark animation fixtures need rendering and were rerun under OpenGL after inappropriate headless invocations.',
        'Older portrait fixtures count frames; uncapped initial test profiles ran too quickly. Reruns with the required 30 FPS profile passed unchanged assertions.',
        'The Astral UI fixture now explicitly tears down its live match before quitting the root tree, allowing worker cleanup to finish. Its initial 164 assertions passed but shutdown emitted an add_child error.',
        'The traversal waypoint at (48,82) was obstructed after combat; the actor reached (48.5,82.5), outside the 0.6m assertion. The fixture now requests that reachable waypoint and retains the same arrival tolerance.',
        'The legacy dialogue_feedback fixture crashes in both the published 1.27.0 and integrated exported packages before zone setup. It is excluded; dialogue clock networking and a focused real-panel held-Space test are used for the changed behavior.',
        'The held-Space fixture allows asynchronous material textures to finish and renders the dialogue before exercising input; early fixture shutdown produced texture diagnostics after all six assertions passed.',
        'The isolated GPU Lab X11 worker emits a known null monitor-query diagnostic. Only that exact diagnostic and its stack are accepted; other errors fail validation.',
    ],
    'superseded_attempts': superseded,
    'limitations': [
        'Path tracing and frame generation remain experimental. Proton present counts do not qualify native Windows pacing, display cadence, latency or refresh-rate behavior.',
        'Native Windows, macOS and Android runtime execution was unavailable on this Linux workstation.',
        'The RTX 30-series optional modification does not constitute official NVIDIA hardware support.',
        'NVIDIA mark-placement approval is not verified by this release process; the pending status and source terms are retained in docs/branding/graphics-sdk-attribution.md.',
        'The exact player saves for some original issue reports were unavailable; authored fixtures and current regression cases were used.',
    ],
}
for tip in report['integrated_tips'].values():
    subprocess.run(['git', 'merge-base', '--is-ancestor', tip, 'HEAD'], cwd=r, check=True)
(r / 'docs/validation' / f'release-{VERSION}-2026-10-24.json').write_text(json.dumps(report, indent=2) + '\n')
(w / 'integrated-checks.json').write_text(json.dumps(rows, indent=2) + '\n')
print('Validated', len(rows), 'packaged suites,', report['total_packaged_checks_reported'], 'reported checks, 60 peer checks and 36 wiki checks')
