from pathlib import Path
import gzip,hashlib,json,shutil,subprocess,zipfile
from release_config import WORK as W, REPO as R, VERSION, VALIDATION_DIR as D, VALIDATION_FILE as F
read=lambda p:json.loads(p.read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
old=W.parents[1]/'release-1.31.0-20261026/release'
build=read(W/'build.json');assert subprocess.check_output(['git','rev-parse','HEAD:game'],cwd=R,text=True).strip()==build['game_tree']
assert read(W/'android-audit.json')['all_five_platforms_identical']
assert read(W/'compiled-scripts.json')==read(old/'compiled-scripts.json')
assert read(W/'browser-fresh.json')['passed'] and read(W/'browser-validation.json')['cache_upgrade']['passed']
assert read(W/'web-wiki-prearchive.json')['wiki_files']==13819
assert read(W/'payload-parity.json')['all_payloads_except_version_and_scene_ids_identical']
assert read(W/'smoke/results.json')['passed']
D.mkdir(parents=True,exist_ok=True)
def copy(src,dst):dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
for name in ['android-audit.json','android-build.json','branding-audit.json','browser-fresh.json','browser-fresh-logs.json','browser-validation.json','browser-upgrade-logs.json','previous-browser-input.json','windows-engine-template.json','browser-upgrade-fixture-version-failure.json','web-wiki-prearchive.json','payload-parity.json']:
 copy(W/name,D/name)
for name in ['web-wiki-negative.log','web-release-unit.log']:
 (D/(name+'.gz')).write_bytes(gzip.compress((W/name).read_bytes(),mtime=0))
copy(W/'smoke/results.json',D/'smoke.json')
for p in (W/'smoke').glob('*/run.log'):(D/(p.parent.name+'.log.gz')).write_bytes(gzip.compress(p.read_bytes(),mtime=0))
for name in ['browser-fresh-start.png','browser-update-waiting.png','browser-upgrade-passed.png']:copy(W/name,D/'visuals'/name)
for name in ['release_config.py','build.py','android.py','audit-android.py','audit_branding.py','archive_release.py','tools_bundle.py','pack_audit.py','export_mobile_template.py','web-export-presets.cfg','prepare_web_host.py','sync-host.py','prepare-browser-input.py','browser-common.cjs','browser-fresh.cjs','browser-run.cjs','browser-server.py','browser-check.html','verify_live.py','verify_publication.py','record_patch.py','payload_parity.py','release-container.json']:
 copy(W/name,D/'recipes'/name)
previous=read(R/'docs/validation/release-1.31.0-2026-10-26.json')
platforms=previous['platform_runtime']
for name,row in platforms.items():row['coverage_origin']='Inherited from 1.31.0 after exact game payload/native-code comparison; source changes are version metadata and packaging validation only.'
platforms['web']={'target_os_tested':True,'scope':'Fresh engine startup and published 1.31.0 cache upgrade, preserving IndexedDB; complete 13,819-file offline wiki compared byte for byte in archive.'}
platforms['android']['scope']='ARM64 export, version code 66, unchanged signing certificate and production Java/native libraries, identical compiled game scripts; device runtime not exercised.'
report={'version':VERSION,'release_type':'stable','date':'2026-10-26','source_commit':build['source_commit'],'game_tree':build['game_tree'],'acceptance_passed':True,'platform_runtime':platforms,'change':'Restore the complete offline wiki in the standalone browser archive. Hosted wiki and gameplay are unchanged.','original_comparison':'Original-game Wine comparison is inapplicable to distribution of the remake public wiki. The previous 1.30.0 archive and committed hosted wiki provide direct references.','regression':{'browser_fixture_retry':'Initial copied browser fixture still expected 1.30.0 and rejected the verified 1.31.0 baseline before update. Corrected baseline version; unchanged cache-hash and IndexedDB assertions pass.', 'negative_control':'Published 1.31.0 standalone web ZIP fails: 13,819 wiki files missing. Original immutable artifact retained.','fixed_prearchive':read(W/'web-wiki-prearchive.json'),'unit_test':'test_web_release: omitted, partial and changed wiki bundles fail; complete bundle passes.','final_archive_check':'archive_release.py executes tools/check_web_release.py before the withdrawal-policy checks and publication.'},'five_platform_script_parity':read(W/'android-audit.json'),'game_payload_comparison':read(W/'payload-parity.json'),'inherited_runtime_validation':'release-1.31.0-2026-10-26.json','inherited_assertions':628,'additional_packaged_smoke':read(W/'smoke/results.json')['cases'],'browser':{'fresh':True,'previous_version':'1.31.0','cache_upgrade':True,'profile_preserved':True},'known_open_reports':previous['known_open_reports'],'limits':previous['limits'],'evidence_directory':'release-1.31.1','engine_build':read(W/'windows-engine-template.json')}
F.write_text(json.dumps(report,indent=2)+'\n')
(D/'README.md').write_text('# Release 1.31.1 validation\n\nThis packaging patch restores the offline wiki omitted from the 1.31.0 standalone browser archive. The hosted wiki remained intact. The published 1.31.0 archive is the retained failing control; the new archive must contain all 13,819 committed wiki files with identical contents. The new validator is unit tested for omission, partial bundles and changed content.\n\nAll 446 compiled game scripts are unchanged across platforms and compared with 1.31.0. Pack resources and Windows engine code are compared separately; only version metadata and Godot-generated root-node IDs differ. The 628 final-package assertions from 1.31.0 remain applicable, with a fresh packaged startup/knife check, fresh browser start and real service-worker upgrade for 1.31.1. Native Windows OS, macOS and Android device runtime limitations remain unchanged.\n')
print('Patch acceptance passed; 13,819 wiki files, five-platform script parity and unchanged game payload confirmed')
