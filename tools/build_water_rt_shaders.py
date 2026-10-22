#!/usr/bin/env python3
"""Build matching DXR libraries and Vulkan SPIR-V from the same HLSL source."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHADERS = ROOT / 'game/src/game/fx/shaders'
STAGES = ['raygen', 'miss', 'closest_hit', 'any_hit']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dxc', type=Path, help='DXC 1.9.2609 executable; required when rebuilding')
    parser.add_argument('--check', action='store_true', help='Verify source/binary hashes; also reproduce outputs if --dxc is supplied')
    parser.add_argument('--shader', choices=['water_raytrace', 'scene_raytrace', 'path_trace'], default='water_raytrace')
    args = parser.parse_args()
    stages = [(stage, stage, []) for stage in STAGES]
    if args.shader == 'path_trace':
        # Keep scenes without emitters out of the larger raygen's register /
        # instruction footprint. Hit stages and payload layouts are shared.
        stages.append(('raygen_no_emitters', 'raygen', ['PATH_NO_EMITTERS']))
    prefix = args.shader + '_'
    source = SHADERS / (args.shader + '.hlsl')
    manifest_path = SHADERS / (args.shader + '_build.json')
    if args.check:
        manifest = json.loads(manifest_path.read_text())
        expected = {prefix + name + '.' + backend for name, _, _ in stages for backend in ['dxil', 'spv']}
        if (set(manifest['files']) != expected or manifest['source_sha256'] != sha(source)
                or manifest.get('builder_sha256') != sha(Path(__file__))):
            parser.error('Shader source, builder or stage list differs from the build manifest. Rebuild both backends.')
        for name, digest in manifest['files'].items():
            if not (SHADERS / name).is_file() or sha(SHADERS / name) != digest:
                parser.error('Shader binary differs from the build manifest: ' + name)
        if args.dxc is None:
            print('Verified shared source and all', len(expected), 'shader binaries')
            return
    elif args.dxc is None:
        parser.error('--dxc is required when rebuilding')
    compiler = args.dxc.resolve()
    version = subprocess.check_output([compiler, '--version'], text=True).strip()
    outputs = {}
    # Complete both backends before replacing any checked-in shader binaries.
    with tempfile.TemporaryDirectory() as work:
        for filename, stage, definitions in stages:
            common = [str(compiler), '-T', 'lib_6_3', '-HV', '2021', '-O3',
                      '-D', args.shader.split('_')[0].upper() + '_' + stage.upper(), str(source)]
            for definition in definitions:
                common += ['-D', definition]
            for backend in ['dxil', 'spv']:
                name = prefix + filename + '.' + backend
                target = Path(work) / name
                # DXC otherwise adds RayQueryKHR for an acceleration-structure
                # declaration even though these shaders only use RT pipelines.
                # Godot enables the pipeline extension, not ray queries.
                flags = ['-Qstrip_debug', '-Qstrip_reflect', '-Wno-ignored-attributes'] if backend == 'dxil' else [
                    '-spirv', '-fspv-target-env=vulkan1.2', '-fvk-use-gl-layout',
                    '-fspv-extension=SPV_KHR_ray_tracing']
                subprocess.run(common + flags + ['-Fo', str(target)], check=True)
                outputs[name] = sha(target)
        if args.check:
            if outputs != manifest['files']:
                parser.error('Compiler output differs from the checked-in shaders')
            print('Reproduced all', len(outputs), 'shader binaries without modifying them')
            return
        for name in outputs:
            (SHADERS / name).write_bytes((Path(work) / name).read_bytes())
    manifest = {'compiler': version, 'compiler_sha256': sha(compiler), 'builder_sha256': sha(Path(__file__)),
                'source_sha256': sha(source), 'files': outputs}
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    print('Built', len(outputs), 'matching ray-tracing shader binaries')

if __name__ == '__main__':
    main()
