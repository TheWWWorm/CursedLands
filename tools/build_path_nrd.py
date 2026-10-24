#!/usr/bin/env python3
"""Build NRD's CPU adapter and the exact REBLUR shader permutations it requests.

Dependencies are separate pinned SDK checkouts; no developer tool is shipped.
Use --check to verify the committed runtime without downloading or compiling.
"""
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'game/src/native/nrd'
SHADERS = ROOT / 'game/src/game/fx/shaders'
OUTPUT = SHADERS / 'nrd'
PINS = {
    'NRD': ('https://github.com/NVIDIA-RTX/NRD.git', 'e06852bd545973cb224eb28820b891205cfc1624'),
    'MathLib': ('https://github.com/NVIDIA-RTX/MathLib.git', 'aa432ad9a80691eb8c3ec4d576bbad5ac100fdc8'),
    'ShaderMake': ('https://github.com/NVIDIA-RTX/ShaderMake.git', '3f01623a76b092ac127d2debd79a672f55d77665'),
}
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def run(argv, **kwargs): return subprocess.run([str(v) for v in argv], check=True, **kwargs)
def layout(path):
    words = struct.unpack('<%dI' % (path.stat().st_size // 4), path.read_bytes())
    binding, sets = {}, {}; pos = 5
    while pos < len(words):
        length, op = words[pos] >> 16, words[pos] & 65535
        if op == 71 and length == 4:  # OpDecorate, literal Binding/DescriptorSet
            target, decoration, value = words[pos + 1:pos + 4]
            if decoration == 33: binding[target] = value
            if decoration == 34: sets[target] = value
        assert length > 0
        pos += length
    return {str(index): sorted(value for target, value in binding.items() if sets[target] == index)
            for index in sorted(set(sets.values()))}
def inputs():
    return {str(p.relative_to(ROOT)): sha(p) for p in sorted(SOURCE.iterdir()) if p.suffix in ('.cpp', '.hpp', '.json', '.hlsli', '.txt')} | {
        'tools/build_path_nrd.py': sha(Path(__file__)),
        'game/src/game/fx/shaders/path_trace_nrd.hlsl': sha(SHADERS / 'path_trace_nrd.hlsl')}
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--deps', type=Path)
    parser.add_argument('--build', type=Path)
    parser.add_argument('--dxc', type=Path)
    parser.add_argument('--godot-cpp', type=Path)
    parser.add_argument('--toolchain', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.check:
        manifest = json.loads((OUTPUT / 'build.json').read_text())
        assert manifest['pins'] == {key: value[1] for key, value in PINS.items()}
        assert manifest['sources'] == inputs(), 'NRD adapter source has changed; rebuild'
        for path, digest in manifest['files'].items(): assert sha(ROOT / path) == digest, path
        for platform in ('linux', 'windows'):
            native = manifest['native'][platform]
            assert native['sources'] == inputs(), platform + ' native adapter requires rebuilding'
            assert sha(ROOT / native['file']) == native['sha256'], native['file']
        print('Verified NRD sources, pinned SDK revisions and', len(manifest['files']), 'shader binaries')
        return
    if not all((args.deps, args.build, args.dxc, args.godot_cpp)):
        parser.error('--deps, --build, --dxc and --godot-cpp are required')
    args.deps.mkdir(parents=True, exist_ok=True)
    for name, (url, pin) in PINS.items():
        dep = args.deps / name
        if not dep.exists():
            run(['git', 'clone', url, dep]); run(['git', '-C', dep, 'checkout', '--detach', pin])
        assert subprocess.check_output(['git', '-C', dep, 'rev-parse', 'HEAD'], text=True).strip() == pin, name + ' revision mismatch'
    shared = [f'-DNRD_DIR={args.deps / "NRD"}', f'-DMATHLIB_DIR={args.deps / "MathLib"}',
              f'-DSHADERMAKE_DIR={args.deps / "ShaderMake"}', '-DCMAKE_BUILD_TYPE=Release']
    host = args.build / 'host'
    run(['cmake', '-S', SOURCE, '-B', host, '-DNRD_METADATA_ONLY=ON', *shared])
    run(['cmake', '--build', host, '-j', '6'])
    inventory = sorted(set(subprocess.check_output([host / 'nrd_shaders'], text=True).splitlines()))
    OUTPUT.mkdir(exist_ok=True)
    staging = args.build / 'shader-output'
    staging.mkdir(parents=True, exist_ok=True)
    wrappers = args.build / 'shader-sources'
    wrappers.mkdir(parents=True, exist_ok=True)
    common = [args.dxc, '-T', 'cs_6_0', '-E', 'main', '-HV', '2021', '-O3', '-WX', '-spirv',
              '-fspv-target-env=vulkan1.2', '-fvk-use-dx-layout', '-all_resources_bound',
              '-I', args.deps / 'NRD/Shaders', '-I', args.deps / 'MathLib']
    files = {}; layouts = {}
    for identifier in inventory:
        filename, *defines = identifier.split('|')
        name = hashlib.sha256(identifier.encode()).hexdigest() + '.spv'
        target = staging / name
        flags = ['-D', 'NRD_INTERNAL', '-fvk-s-shift', '0', '1', '-fvk-b-shift', '2', '1',
                 '-fvk-u-shift', '3', '0', '-fvk-t-shift', '20', '0']
        for define in defines: flags += ['-D', define]
        # Godot 4.7's Vulkan re-spirv optimizer corrupts REBLUR temporal
        # stabilization. Compute shaders with specialization constants keep
        # their original SPIR-V. This default-true guard preserves NRD's
        # behavior and avoids a global engine/debug setting. Upstream sources
        # stay untouched; only generated build wrappers contain the guard.
        source = (args.deps / 'NRD/Shaders' / filename).read_text()
        source, count = re.subn(r'(NRD_EXPORT void NRD_CS_MAIN\([^)]*\)\s*\{)',
            r'\1\n    if (!ei_nrd_dispatch) return;', source, count=1)
        assert count == 1, filename
        wrapper = wrappers / filename
        wrapper.write_text('[[vk::constant_id(0)]] const bool ei_nrd_dispatch = true;\n' + source)
        run([*common, *flags, wrapper, '-Fo', target])
        files[str((OUTPUT / name).relative_to(ROOT))] = sha(target)
        layouts[target.stem] = layout(target)
    for mode in ('pack', 'resolve'):
        target = staging / (mode + '.spv')
        run([*common, '-D', 'NRD_' + mode.upper(), SHADERS / 'path_trace_nrd.hlsl', '-Fo', target])
        files[str((OUTPUT / target.name).relative_to(ROOT))] = sha(target)
        layouts[target.stem] = layout(target)
    platform = 'windows' if args.toolchain else 'linux'
    native = args.build / platform
    flags = [f'-DCMAKE_TOOLCHAIN_FILE={args.toolchain}'] if args.toolchain else []
    run(['cmake', '-S', SOURCE, '-B', native, f'-DGODOTCPP_DIR={args.godot_cpp}', *shared, *flags])
    run(['cmake', '--build', native, '-j', '6'])
    extension = 'dll' if args.toolchain else 'so'
    target = ROOT / f'game/src/native/bin/libpath_nrd.{extension}'
    shutil.copy2(native / target.name, target)
    # A .cfg descriptor loads lazily and isn't auto-discovered by export.
    # Desktop packaging copies this native binary beside the exported PCK.
    native_info = {}
    if (OUTPUT / 'build.json').exists():
        native_info = json.loads((OUTPUT / 'build.json').read_text()).get('native', {})
    native_info[platform] = {'file': str(target.relative_to(ROOT)), 'sha256': sha(target), 'sources': inputs()}
    for path in files:
        shutil.copy2(staging / Path(path).name, ROOT / path)
    manifest = {'version': '4.18.0', 'pins': {k: v[1] for k, v in PINS.items()},
                'native': native_info,
                'sources': inputs(), 'files': files, 'layouts': layouts, 'compiler_sha256': sha(args.dxc),
                'compiler': subprocess.check_output([args.dxc, '--version'], text=True).strip()}
    (OUTPUT / 'build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    notice = ROOT / 'game/src/native/NATIVE_NRD_NOTICES.txt'
    notice.write_text('This software contains source code provided by NVIDIA Corporation.\n'
        'NRD 4.18.0 is used under the NVIDIA RTX SDKs license below.\n'
        'The NRD component is separate from the application source license.\n\n' +
        (args.deps / 'NRD/LICENSE.txt').read_text() + '\n\nMathLib v11:\n' +
        (args.deps / 'MathLib/LICENSE.txt').read_text() + '\n\nShaderMake (build-time declarations):\n' +
        (args.deps / 'ShaderMake/LICENSE.txt').read_text())
    print('Built NRD', platform, 'adapter and', len(files), 'compute shaders')

if __name__ == '__main__': main()
