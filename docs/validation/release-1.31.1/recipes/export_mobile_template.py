#!/usr/bin/env python3
"""Export engine-only Android or offline-capable Web builds with Godot 4.7."""
import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile


LICENSE_SCRIPT = '''extends SceneTree
func _initialize():
 var file = FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
 file.store_string(Engine.get_license_text())
 var components = Engine.get_copyright_info()
 for component in components:
  file.store_string("\\n\\n" + JSON.stringify(component, "\\t") + "\\n")
 var info = Engine.get_license_info()
 for name in info:
  file.store_string("\\n\\n" + name + "\\n" + str(info[name]) + "\\n")
 file.close()
 print("LICENSE_NOTICES components=", components.size(), " licenses=", info.size())
 quit()
'''


def android_notices(stage, notices, godot, env):
    """Embed distribution notices without changing the application's runtime."""
    target = stage / 'src/release_licenses'
    target.mkdir()
    names = ['LICENSE.md', 'THIRD_PARTY_NOTICES.md', 'licenses/LGPL-2.1.txt']
    for name in names:
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(notices / name, destination)
    third_party = target / 'THIRD_PARTY_NOTICES.md'
    third_party.write_text(third_party.read_text().replace('game/fonts/LICENSE.txt', 'FONT_LICENSE.txt'))
    shutil.copyfile(stage / 'fonts/LICENSE.txt', target / 'FONT_LICENSE.txt')
    script = stage.parent / 'release_licenses.gd'
    script.write_text(LICENSE_SCRIPT)
    run_checked([godot, '--headless', '--script', str(script), '--',
                 str(target / 'GODOT_LICENSES.txt')], env=env)
    names += ['FONT_LICENSE.txt', 'GODOT_LICENSES.txt']
    presets = stage / 'export_presets.cfg'
    text = presets.read_text()
    blocks = re.split(r'(?=\[preset\.\d+\]\n)', text)
    matches = 0
    for index, block in enumerate(blocks):
        if re.search(r'^name="Android"$', block, re.M):
            existing = re.search(r'^include_filter="([^"]*)"$', block, re.M)
            assert existing, 'Android include_filter missing'
            filters = [value.strip() for value in existing[1].split(',') if value.strip()]
            filters += ['src/release_licenses/' + name for name in names]
            blocks[index] = block[:existing.start()] + 'include_filter=' + json.dumps(','.join(dict.fromkeys(filters))) + block[existing.end():]
            matches += 1
    assert matches == 1, 'Expected one Android preset'
    presets.write_text(''.join(blocks))


def run_checked(command, **kwargs):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, **kwargs)
    if result.returncode == 0 and '--import' in command and 'no resource loaders' in result.stdout:
        (pathlib.Path(__file__).parent / 'web-import-bootstrap.log').write_text(result.stdout)
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, **kwargs)
    print(result.stdout, end='', flush=True)
    result.check_returncode()
    # Godot may return success despite a GDScript compilation failure.
    if re.search(r'(?m)^(?:SCRIPT )?ERROR:', result.stdout):
        raise RuntimeError('Godot reported an error; see the output above.')


def web_assets(project, output):
    for name in ('storage.js', 'files.js', 'data-worker.js', 'installer-worker.js'):
        shutil.copyfile(project / 'web' / name, output / name)
    # Preserve the approved transparent raster master and its exact web derivatives.
    for name in ('icon-192.png','icon-512.png','index.icon.png','index.apple-touch-icon.png'):
        shutil.copyfile(pathlib.Path(__file__).parent.parent/'repo/public'/name,output/name)
    shutil.copyfile(project/'assets/branding/splash.png',output/'index.png')
    return None


def finish_web(project, output):
    manifest = {'id': './', 'name': 'Cursed Lands', 'short_name': 'Cursed Lands',
                'start_url': './', 'scope': './', 'display': 'standalone', 'orientation': 'landscape',
                'background_color': '#17130e', 'theme_color': '#17130e',
                'icons': [{'src': f'icon-{size}.png', 'sizes': f'{size}x{size}', 'type': 'image/png',
                           'purpose': 'any'} for size in (192, 512)]}
    (output / 'manifest.webmanifest').write_text(json.dumps(manifest, indent=2))
    files = sorted(p.name for p in output.iterdir() if p.is_file() and p.suffix in
                   {'.html', '.js', '.wasm', '.pck', '.png', '.webmanifest'} and p.name != 'service-worker.js')
    digest = hashlib.sha256()
    hashes = {}
    for name in files:
        digest.update((output / name).read_bytes())
        hashes[name] = hashlib.sha256((output / name).read_bytes()).hexdigest()
    worker = (project / 'web/service-worker.js').read_text()
    # The worker reuses an unchanged file (same SHA-256) from the previous cache
    # instead of downloading it again.
    worker = worker.replace('@BUILD@', digest.hexdigest()[:20]).replace('@FILES@', json.dumps(hashes, indent=0))
    (output / 'service-worker.js').write_text(worker)
    (output / '_headers').write_text('''/*.wasm
  Content-Type: application/wasm
/service-worker.js
  Cache-Control: no-cache
/index.html
  Cache-Control: no-cache
/*
  X-Content-Type-Options: nosniff
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
''')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=['web', 'android'])
    parser.add_argument('--output', type=pathlib.Path, required=True)
    source_root = pathlib.Path(__file__).resolve().parents[1]
    parser.add_argument('--project', type=pathlib.Path, default=source_root / 'game' if (source_root / 'game/project.godot').exists() else source_root)
    parser.add_argument('--godot', default=shutil.which('godot-4') or shutil.which('godot'))
    parser.add_argument('--sdk', type=pathlib.Path, default=os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT'))
    parser.add_argument('--java', type=pathlib.Path, default=os.environ.get('JAVA_HOME'))
    parser.add_argument('--release', action='store_true', help='Android release uses configured Godot release signing credentials.')
    default_notices = source_root if (source_root / 'THIRD_PARTY_NOTICES.md').is_file() else source_root.parent / 'publish'
    parser.add_argument('--notices', type=pathlib.Path, default=default_notices,
                        help='Repository directory containing the distribution license notices.')
    args = parser.parse_args()
    project, output = args.project.resolve(), args.output.resolve()
    if output.is_relative_to(project):
        parser.error('Keep builds outside the engine source directory.')
    if not args.godot:
        parser.error('Install Godot 4.7 and matching export templates.')
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cursed-export-',dir=pathlib.Path(__file__).resolve().parent) as temp:
        stage = pathlib.Path(temp) / 'project'
        stage.mkdir()
        for name in ['src', 'scenes', 'fonts', 'art', 'web', 'icons', 'assets']:
            if name == 'art' and not (project / name).is_dir():
                continue
            shutil.copytree(project / name, stage / name)
        for name in ['project.godot', 'export_presets.cfg', 'icon.png']:
            shutil.copyfile(project / name, stage / name)
        config = (stage / 'project.godot').read_text().replace('Evil Islands Remake (PoC)', 'Cursed Lands')
        (stage / 'project.godot').write_text(config)
        env = os.environ.copy()
        if args.platform == 'android' and (args.sdk or args.java):
            cfg = pathlib.Path(temp) / 'config/godot'
            cfg.mkdir(parents=True)
            # Copy editor preferences into an isolated location, preserving the
            # user's signing setup without changing their SDK paths globally.
            existing = pathlib.Path(os.environ.get('XDG_CONFIG_HOME', pathlib.Path.home() / '.config')) / 'godot/editor_settings-4.7.tres'
            settings = existing.read_text() if existing.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
            for key, value in [('android_sdk_path', args.sdk), ('java_sdk_path', args.java)]:
                if not value:
                    continue
                line = 'export/android/' + key + ' = ' + json.dumps(str(value.resolve()))
                pattern = '^export/android/' + key + ' = .*?$'
                settings = re.sub(pattern, line, settings, flags=re.M) if re.search(pattern, settings, flags=re.M) else settings + '\n' + line + '\n'
            (cfg / 'editor_settings-4.7.tres').write_text(settings)
            env['XDG_CONFIG_HOME'] = str(cfg.parent)
        if args.platform == 'android' and args.release:
            required = ['LICENSE.md', 'THIRD_PARTY_NOTICES.md', 'licenses/LGPL-2.1.txt']
            if not all((args.notices / name).is_file() for name in required):
                parser.error('Android releases need the repository notices directory (--notices).')
            android_notices(stage, args.notices.resolve(), args.godot, env)
        run_checked([args.godot, '--headless', '--path', str(stage), '--editor', '--import', '--quit'], env=env)
        credentials = project / '.godot/export_credentials.cfg'
        if args.release and credentials.exists():
            shutil.copyfile(credentials, stage / '.godot/export_credentials.cfg')
        name = 'index.html' if args.platform == 'web' else 'cursed-lands.apk'
        run_checked([args.godot, '--headless', '--path', str(stage),
                        '--export-release' if args.release else '--export-debug',
                        'Web' if args.platform == 'web' else 'Android', str(output / name)], env=env)
        if args.platform == 'web':
            web_assets(project, output)
            finish_web(project, output)
        # Original files are not part of this source allowlist or the export.
        shutil.copyfile(project / 'fonts/LICENSE.txt', output / 'FONT_LICENSE.txt')
    print(output / name)


if __name__ == '__main__':
    main()
