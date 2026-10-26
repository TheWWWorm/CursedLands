from pathlib import Path
import gzip,hashlib,json,re,shutil,subprocess
from release_config import WORK as W, REPO as R, VERSION, VALIDATION_DIR as D, VALIDATION_FILE as F
read=lambda p:json.loads(Path(p).read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,obj):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(obj,indent=2)+'\n')
def copy(src,dst):dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
def compress(src,dst):dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(gzip.compress(src.read_bytes(),mtime=0))
build=read(W/'build.json');game_tree=subprocess.check_output(['git','rev-parse','HEAD:game'],cwd=R,text=True).strip()
assert build['game_tree']==game_tree
assert not subprocess.check_output(['git','status','--porcelain','--','game'],cwd=R,text=True).strip()
D.mkdir(parents=True,exist_ok=True)
linux=[];failed_initial=[]
for suite in ['checks-headless','checks-rendered','checks-water-fixed']:
    result=read(W/suite/'results.json');copy(W/suite/'results.json',D/(suite+'.json'))
    for case in result['cases']:
        log=W/suite/case['log'];compress(log,D/'logs'/(suite+'-'+case['id']+'.log.gz'))
        if not case['passed']:
            assert suite=='checks-rendered' and case['id']=='path_trace_water',case
            failed_initial.append({'case':case['id'],'errors':case['errors'],'record':suite+'.json'})
        else:linux.append({'case':case['id'],'checks':case['result']['checks'],'result':suite+'.json','log':'logs/'+suite+'-'+case['id']+'.log.gz'})
assert len(linux)==12,len(linux)
assert len(failed_initial)==1
windows=[]
for name in ['path_trace_rr_live','path_trace_rtxdi_live','path_trace_transmission_live']:
    p=W/'evidence'/('windows-'+name);result=read(p/'result.json')
    assert result['exit']==0 and not result['errors'],result['errors']
    checks=int(re.search(r'(\d+) checks 0 failures',result['summary'][0])[1])
    assert checks>=dict(path_trace_rr_live=32,path_trace_rtxdi_live=38,path_trace_transmission_live=25)[name]
    compress(p/'result.json',D/'logs'/('windows-'+name+'-result.json.gz'))
    compress(p/'run.log',D/'logs'/('windows-'+name+'.log.gz'))
    windows.append({'case':name,'checks':checks,'result':'logs/windows-'+name+'-result.json.gz','log':'logs/windows-'+name+'.log.gz','adapter':result['adapter']})
    for f in p.glob('*.json'):
        if f.name!='result.json':copy(f,D/'windows'/name/f.name)
assert read(W/'android-audit.json')['all_five_platforms_identical']
assert read(W/'browser-fresh.json')['passed'] and read(W/'browser-validation.json')['cache_upgrade']['passed']
for name in ['android-audit.json','android-build.json','branding-audit.json','browser-fresh.json','browser-fresh-logs.json','browser-validation.json','browser-upgrade-logs.json','previous-browser-input.json','windows-engine-template.json']:
    copy(W/name,D/name)
for name in ['cpu-release-tests.log','runner-tests.log','translations.log','rtxdi-shader-audit.log','sharc-shader-audit.log','nrd-shader-audit.log','path-shader-audit.log','water-registration-negative.log','windows-policy-prearchive.log']:
    copy(W/name,D/name)
assert 'Ran 9 tests' in (W/'cpu-release-tests.log').read_text() and '\nOK' in (W/'cpu-release-tests.log').read_text()
assert 'Ran 11 tests' in (W/'runner-tests.log').read_text() and '\nOK' in (W/'runner-tests.log').read_text()
assert 'FAILED (failures=2)' in (W/'water-registration-negative.log').read_text()
for p in ['browser-fresh-start.png','browser-update-waiting.png','browser-upgrade-passed.png']:
    copy(W/p,D/'visuals'/p)
# Retain full final-package UI evidence outside the checkout; published proof uses one native 4K view and each icon.
ui=W/'checks-rendered/high_resolution_ui/data/godot/app_userdata/Cursed Lands'
visual_root=Path('/home/llm2x/Documents/EI/Evidence/releases/1.31.0')
visual_root.mkdir(parents=True,exist_ok=True)
for p in ui.glob('*.png'):copy(p,visual_root/'ui'/p.name)
copy(ui/'high-resolution-ui.json',D/'high-resolution-ui.json')
for lang in ['en','ru','de']:copy(ui/f'book-{lang}-3840x2160.png',D/'visuals'/f'book-{lang}-3840x2160.png')
copy(ui/'water-hint-ru-4k.png',D/'visuals/water-hint-ru-4k.png')
copy(W/'evidence/windows-path_trace_rr_live/rr-4k-performance.png',D/'visuals/rr-4k-performance.png')
for p in (W/'evidence').glob('*/*.png'):copy(p,visual_root/'windows'/p.parent.name/p.name)
# Retain compact fixtures/results generated inside the isolated Linux profiles.
for suite in ['checks-rendered','checks-water-fixed']:
    for case in read(W/suite/'results.json')['cases']:
        userdata=W/suite/case['id']/'data/godot/app_userdata/Cursed Lands'
        for p in userdata.rglob('*.json'):
            if 'shader_cache' not in p.parts:copy(p,D/'linux'/case['id']/p.relative_to(userdata))
recipes=['release_config.py','build.py','android.py','audit-android.py','audit_branding.py','archive_release.py','tools_bundle.py','pack_audit.py','export_mobile_template.py','web-export-presets.cfg','prepare_web_host.py','sync-host.py','prepare-browser-input.py','browser-common.cjs','browser-fresh.cjs','browser-run.cjs','browser-server.py','browser-check.html','run_windows.py','verify_live.py','verify_publication.py','record_release.py','release-container.json']
for name in recipes:copy(W/name,D/'recipes'/name)
source={'source_commit':build['source_commit'],'game_tree':game_tree,'compiled_scripts':len(read(W/'compiled-scripts.json')),'files':{f:sha(R/f) for f in subprocess.check_output(['git','ls-files','game','engine_patches','tools/regressions.json','tools/tests/test_regression_runner.py'],cwd=R,text=True).splitlines() if (R/f).is_file()}}
dump(D/'source-snapshot.json',source)
platforms={
'linux-x86_64':{'target_os_tested':True,'scope':'Final executable and PCK: 12 focused cases, Vulkan Forward+ and OpenGL, including 108 high-resolution UI assertions, spell lights in both campaigns and PT loading, water, emission and lightning.'},
'windows-x86_64':{'target_os_tested':False,'proton_tested':True,'dlss_fg_tested':False,'scope':'Final EXE/PCK and standard signed RR runtime under GE-Proton11-11/VKD3D: real RR, RTXDI with RR and refraction with RR; native 4K output, motion, resize, streaming and fallback.'},
'macos-universal':{'target_os_tested':False,'scope':'Unsigned Intel/Apple-silicon package, embedded branding, version metadata, archive integrity and compiled-script parity audited; macOS runtime unavailable.'},
'android':{'target_os_tested':False,'scope':'ARM64 APK, increasing version code 65, unchanged signing certificate/application identity, native hashes, production Java and compiled-script parity audited; device runtime unavailable.'},
'web':{'target_os_tested':True,'scope':'Fresh Chromium engine startup and an upgrade from the published 1.30.0 service-worker cache preserve IndexedDB. No original campaign imported in this browser check.'}}
report={'version':VERSION,'release_type':'stable','date':'2026-10-26','source_commit':build['source_commit'],'game_tree':game_tree,'accepted_fixes_commit':'562f5e78edd7201795ca589c48d5453e5dc68ec0','acceptance_passed':True,
'qualification_scope':'Final exported package checks plus retained integrated-source regressions. Approval covers publication of these verified changes, not resolution of every original report.',
'platform_runtime':platforms,'final_package_regressions':{'linux':linux,'windows_proton_dx12':windows,'total_assertions':sum(c['checks'] for c in linux+windows),'cases':len(linux+windows),'failures':0},
'cpu_tests':{'count':20,'passed':True,'coverage':['release asset exclusion','DLSS camera contract','regression runner including PT water renderer selection']},
'five_platform_script_parity':read(W/'android-audit.json'),'branding':read(W/'branding-audit.json'),'browser':{'fresh':True,'previous_version':'1.30.0','cache_upgrade':True,'local_storage_preserved':True},
'prior_evidence':['e2-2026-10-26/README.md','e2-2026-10-26/runs/main-integration/summary.json','pt-transport-2026-10-26/rr-validation.md','pt-transport-2026-10-26/water-validation.md','pt-transport-2026-10-26/rtxdi-validation.md','pt-transport-2026-10-26/transmission-validation.md'],
'prior_evidence_note':'E2 aggregate 2390 assertions and combined integration 369 assertions overlap other renderer evidence; they are not summed into the final-package count. Game code is unchanged since the accepted fix commit; only release metadata differs.',
'failures_investigated':[{'failure':'PT water registered without Forward+, so the standard runner launched OpenGL and failed its capability assertion.','initial_records':failed_initial,'fix':'Register path_trace_water and path_trace_water_live with rendering_method forward_plus. No game behavior changed.','negative_control':'New runner unit test fails both cases before the registration fix.','final_control':'Both real GPU water suites pass with the corrected registry; all runner unit tests pass.','original_comparison':'Inapplicable: this is the remake test-launch renderer configuration, not original gameplay.'}],
'known_open_reports':['LiA mountain flashes remain unresolved.','The exact recorded PT delay and two stutters are not fully attributed. The fixed loading race and verified shader-preparation stalls do not prove those exact recording events are resolved.'],
'limits':['Native Windows OS, macOS runtime and Android device runtime not exercised here.','Standard RTX 30 RR was exercised; standard NVIDIA FG is not supported on these test GPUs. No RR plus FG qualification or performance claim.','Path tracing and its new optional modes remain experimental.'],
'recording':'../../../Evidence/e2/fixes-20261026/ui/ui-4k-recording.mp4 (local workstation evidence, 3840x2160; original E2 validation)',
'evidence_directory':'release-1.31.0','public_browser_build_sha256':sha(R/'public/BUILD-INFO.json'),'engine_build':read(W/'windows-engine-template.json')}
dump(F,report)
(D/'README.md').write_text('''# Release 1.31.0 validation

The release record in the parent directory contains the acceptance scope and platform limits. The final package regressions exercise the exact exported executable and PCK, with 446 compiled scripts verified byte-identical across all five platforms. Existing E2 and integrated-source results remain linked separately and are not double-counted.

The first registered PT water run failed because its manifest selected OpenGL. A negative-control unit test fails both affected registrations; the corrected Forward+ registrations and both actual GPU water cases pass. No assertion was weakened and no game code changed for this runner correction. The initial failed result is retained alongside the final results.

Full final-package UI captures in EN/RU/DE at 1080p, 1440p and 4K are retained under the workstation Evidence/releases/1.31.0/ui directory. The earlier native 4K E2 recording is retained in Evidence/e2/fixes-20261026/ui. Representative native-resolution screenshots, logs, source hashes and the exact release recipes are retained here. GPU Lab assigned devices automatically; Wine tests used one locked writable prefix, with reference seeds and toolchains unchanged.

The LiA mountain flashes and attribution of the exact recorded loading delay and stutters remain open. This publication does not claim those reports completely resolved. See the E2 investigation for the verified fixes and remaining uncertainty.
''')
print(json.dumps({'assertions':report['final_package_regressions']['total_assertions'],'cases':len(linux+windows),'cpu_tests':20,'evidence':str(D),'game_tree':game_tree},indent=2))
