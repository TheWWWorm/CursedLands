from pathlib import Path
import zipfile,json,hashlib,subprocess,sys,tempfile
r=Path(__file__).resolve().parent;repo=r.parent/'repo';assets=r/'assets';v=json.loads((r/'build.json').read_text())['version'];name='CursedLands-'+v+'-tools';dest=assets/(name+'.zip')
paths=['tools/convert_legacy_mod.py','tools/package_mod.py','tools/tests/test_legacy_mod_converter.py','game/src/ei/database.gd','game/src/game/mod_schema.gd','docs/mods.md','docs/versioning.md','docs/validation/hd-lands-1.5.0-2026-10-13.json','docs/validation/release-1.31.1-2026-10-26.json','docs/legacy-mod-converter.md','docs/legacy-mod-compatibility.md','docs/validation/legacy-mod-converter-2026-10-11.json','docs/validation/legacy-mod-real-mods-2026-10-11.json','LICENSE.md']
paths += ['docs/mod-formulas.md']
paths += [str(p.relative_to(repo)) for p in (repo/'examples/mods').rglob('*') if p.is_file()]
readme='''# Cursed Lands mod tools — 1.31.1

Requires Python 3.10 or newer. No additional Python packages are needed.
Extract the whole bundle and run commands from this directory:

    python3 tools/convert_legacy_mod.py --help
    python3 tools/package_mod.py examples/mods/quick-recovery quick-recovery.eimod
    python3 -B -m unittest discover -s tools/tests -p test_legacy_mod_converter.py -v

See docs/legacy-mod-converter.md for conversion instructions and limitations,
and docs/mods.md for importing packages through Main menu → Mods and rules.
The converter writes supported API 1 data changes or a report explaining
unsupported changes. Original native plugins and maps require a manual port. Package API 3 supports the documented bounded Lua formula API on Windows/Linux; see docs/mod-formulas.md and the translated examples.

The two files under game/src are source contract references used by the
asset-free tests. This bundle is not a game engine installation and contains
no original game or third-party mod assets.
'''
with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for path in sorted(paths):z.write(repo/path,name+'/'+path)
 z.writestr(name+'/README.md',readme)
with zipfile.ZipFile(dest) as z:
 assert z.testzip() is None
 assert set(z.namelist())=={name+'/'+p for p in paths}|{name+'/README.md'}
 for path in paths:assert z.read(name+'/'+path)==(repo/path).read_bytes()
 with tempfile.TemporaryDirectory(prefix='cl-stable-tools-',dir=r) as temp:
  z.extractall(temp);base=Path(temp)/name
  with (r/'tools-bundle-tests.log').open('w') as log:
   proc=subprocess.run([sys.executable,'-B','-m','unittest','discover','-s','tools/tests','-p','test_legacy_mod_converter.py','-v'],cwd=base,stdout=log,stderr=subprocess.STDOUT);assert proc.returncode==0
  subprocess.run([sys.executable,'-B','tools/package_mod.py','examples/mods/quick-recovery','quick-recovery.eimod'],cwd=base,check=True)
  expected=Path(json.loads((r/'build.json').read_text())['platforms']['linux-x86_64']['folder'])/'mods/quick-recovery-1.0.0.eimod'
  assert (base/'quick-recovery.eimod').read_bytes()==expected.read_bytes()
row={'name':dest.name,'bytes':dest.stat().st_size,'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}
manifest=json.loads((r/'assets.json').read_text()) if (r/'assets.json').exists() else [];manifest=[x for x in manifest if x['name']!=dest.name];manifest.append(row)
(r/'assets.json').write_text(json.dumps(manifest,indent=2)+'\n')
(r/'tools-bundle-audit.json').write_text(json.dumps({'files':paths,'exact_source_readback':True,'standalone_tests_passed':True,'standalone_test_log':'tools-bundle-tests.log','example_byte_identical':True,'artifact':row},indent=2)+'\n')
print(json.dumps(row))
