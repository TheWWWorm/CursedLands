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
    parser.add_argument('--shader', choices=['water_raytrace', 'scene_raytrace', 'path_trace',
                                            'path_trace_terrain_sun'], default='water_raytrace')
    args = parser.parse_args()
    stages = [(stage, stage, []) for stage in STAGES]
    # The terrain sun cache uses the four standard PATH_* stages. Only the
    # main path integrator needs the material, transport and emitter variants.
    if args.shader == 'path_trace':
        # Keep scenes without emitters out of the larger raygen's register /
        # instruction footprint. Hit stages and payload layouts are shared.
        stages.append(('raygen_no_emitters', 'raygen', ['PATH_NO_EMITTERS']))
        # Two-bounce mode avoids the deep-tail shader's register footprint.
        stages.append(('raygen_deep', 'raygen', ['PATH_ROULETTE']))
        stages.append(('raygen_deep_no_emitters', 'raygen', ['PATH_ROULETTE', 'PATH_NO_EMITTERS']))
        stages.append(('closest_hit_terrain', 'closest_hit', ['PATH_TERRAIN_MATERIALS']))
        stages.append(('closest_hit_transitions', 'closest_hit', ['PATH_TERRAIN_MATERIALS', 'PATH_TERRAIN_TRANSITIONS']))
        # Ground relief maps (TerrainSurfaceMaps) get their own hit programs,
        # so the established terrain programs stay unchanged while it is off.
        stages.append(('closest_hit_terrain_maps', 'closest_hit', ['PATH_TERRAIN_MATERIALS', 'PATH_TERRAIN_SURFACE_MAPS']))
        stages.append(('closest_hit_transitions_maps', 'closest_hit', ['PATH_TERRAIN_MATERIALS', 'PATH_TERRAIN_TRANSITIONS', 'PATH_TERRAIN_SURFACE_MAPS']))
        for deep in (False, True):
            for no_emitters in (False, True):
                name = 'raygen_water' + ('_deep' if deep else '') + ('_no_emitters' if no_emitters else '')
                definitions = ['PATH_WATER_REFLECTION'] + (['PATH_ROULETTE'] if deep else []) + (['PATH_NO_EMITTERS'] if no_emitters else [])
                stages.append((name, 'raygen', definitions))
    if args.shader == 'path_trace':
        # The refraction program follows the main integrator's depth variants:
        # four-bounce play uses the compensated roulette tail there too.
        for deep in (False, True):
            for no_emitters in (False, True):
                stages.append(('raygen_transmission'+('_deep' if deep else '')+('_no_emitters' if no_emitters else ''), 'raygen',
                               ['PATH_TRANSMISSION']+(['PATH_ROULETTE'] if deep else [])+(['PATH_NO_EMITTERS'] if no_emitters else [])))
        for name, definitions in [('closest_hit', []), ('closest_hit_terrain', ['PATH_TERRAIN_MATERIALS']), ('closest_hit_transitions', ['PATH_TERRAIN_MATERIALS', 'PATH_TERRAIN_TRANSITIONS']),
                                  ('closest_hit_terrain_maps', ['PATH_TERRAIN_MATERIALS', 'PATH_TERRAIN_SURFACE_MAPS']),
                                  ('closest_hit_transitions_maps', ['PATH_TERRAIN_MATERIALS', 'PATH_TERRAIN_TRANSITIONS', 'PATH_TERRAIN_SURFACE_MAPS'])]:
            stages.append((name+'_transmission', 'closest_hit', definitions+['PATH_TRANSMISSION_HIT']))
    prefix = args.shader + '_'
    source = SHADERS / (args.shader + '.hlsl')
    manifest_path = SHADERS / (args.shader + '_build.json')
    includes = {p.name: sha(p) for p in SHADERS.glob('path_trace_transmission.hlsli')} if args.shader == 'path_trace' else {}
    if args.check:
        manifest = json.loads(manifest_path.read_text())
        expected = {prefix + name + '.' + backend for name, _, _ in stages for backend in ['dxil', 'spv']}
        if (set(manifest['files']) != expected or manifest['source_sha256'] != sha(source)
                or manifest.get('builder_sha256') != sha(Path(__file__)) or manifest.get('includes', {}) != includes):
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
                'source_sha256': sha(source), 'includes': includes, 'files': outputs}
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', newline='\n')
    print('Built', len(outputs), 'matching ray-tracing shader binaries')

if __name__ == '__main__':
    main()
