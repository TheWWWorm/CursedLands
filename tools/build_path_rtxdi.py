#!/usr/bin/env python3
"""Build ReSTIR DI against pinned, external RTXDI 3.1.0 shader headers.

No network access. --check without build arguments audits shipped binaries.
The proprietary SDK sources remain external, like the NRD and SHaRC inputs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHADERS = ROOT / 'game/src/game/fx/shaders'
PIN = ROOT / 'engine_patches/rtxdi-sdk.json'
MANIFEST = SHADERS / 'path_trace_rtxdi_build.json'
NOTICE = SHADERS / 'RTXDI_NOTICES.txt'
SOURCES = ['path_trace.hlsl', 'path_trace_rtxdi.hlsli', 'path_trace_sharc.hlsli']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs():
    return {name: sha(SHADERS / name) for name in SOURCES} | {'builder': sha(Path(__file__)), 'sdk_pin': sha(PIN)}


def stages():
    for sharc in (False, True):
        for deep in (False, True):
            for emitters in (True, False):
                name = 'path_trace_raygen_rtxdi' + ('_sharc' if sharc else '') + ('_deep' if deep else '') + ('_no_emitters' if not emitters else '')
                defines = ['PATH_RAYGEN', 'PATH_RTXDI']
                if sharc: defines += ['PATH_SHARC']
                if deep: defines += ['PATH_ROULETTE']
                if not emitters: defines += ['PATH_NO_EMITTERS']
                yield name, defines


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dxc', type=Path)
    parser.add_argument('--sdk', type=Path)
    parser.add_argument('--sharc-sdk', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    pin = json.loads(PIN.read_text())
    expected = {name + '.' + ext for name, _ in stages() for ext in ['spv', 'dxil']}
    if args.check:
        manifest = json.loads(MANIFEST.read_text())
        assert manifest['sources'] == inputs(), 'ReSTIR adapter changed; rebuild'
        assert manifest['sdk_revision'] == pin['library_commit']
        assert set(manifest['files']) == expected
        assert manifest['notice_sha256'] == sha(NOTICE)
        for name, digest in manifest['files'].items(): assert sha(SHADERS / name) == digest, name
        if not args.dxc:
            print('Verified RTXDI adapter, pinned SDK and', len(expected), 'shader binaries')
            return
    if not args.dxc or not args.sdk or not args.sharc_sdk:
        parser.error('--dxc, --sdk and --sharc-sdk are required to compile')
    for name, digest in pin['files'].items(): assert sha(args.sdk / name) == digest, 'Modified RTXDI SDK: ' + name
    sharc = json.loads((SHADERS / 'path_trace_sharc_build.json').read_text())
    for name, digest in sharc['sdk_files'].items(): assert sha(args.sharc_sdk / name) == digest, 'Modified SHaRC SDK: ' + name
    outputs = {}
    scratch = ROOT.parent / 'test-work'
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='rtxdi-build-', dir=scratch) as work:
        for name, defines in stages():
            common = [str(args.dxc), '-T', 'lib_6_3', '-HV', '2021', '-O3', '-enable-16bit-types',
                      '-I', str(args.sdk / 'Include'), '-I', str(args.sharc_sdk / 'include'), str(SHADERS / 'path_trace.hlsl')]
            for define in defines: common += ['-D', define]
            for backend in ['dxil', 'spv']:
                filename = name + '.' + backend
                flags = ['-Qstrip_debug', '-Qstrip_reflect', '-Wno-ignored-attributes'] if backend == 'dxil' else [
                    '-spirv', '-fspv-target-env=vulkan1.2', '-fvk-use-gl-layout', '-fspv-extension=SPV_KHR_ray_tracing', '-fspv-extension=SPV_KHR_16bit_storage']
                subprocess.run(common + flags + ['-Fo', str(Path(work) / filename)], check=True)
                outputs[filename] = sha(Path(work) / filename)
        if args.check:
            assert outputs == manifest['files'], 'Compiler output changed'
            print('Reproduced all', len(outputs), 'RTXDI shader binaries')
            return
        for name in outputs: (SHADERS / name).write_bytes((Path(work) / name).read_bytes())
    NOTICE.write_text('This software contains source code provided by NVIDIA Corporation.\n'
                      'RTXDI 3.1.0 is used under the NVIDIA RTX SDKs license below.\n'
                      'The RTXDI component is separate from the application source license.\n\n' + (args.sdk / 'LICENSE.txt').read_text(), newline='\n')
    MANIFEST.write_text(json.dumps({'sdk_revision': pin['library_commit'], 'sources': inputs(), 'files': outputs,
        'notice_sha256': sha(NOTICE), 'compiler_sha256': sha(args.dxc),
        'compiler': subprocess.check_output([args.dxc, '--version'], text=True).strip()}, indent=2) + '\n', newline='\n')
    print('Built', len(outputs), 'RTXDI shader binaries')


if __name__ == '__main__':
    main()
