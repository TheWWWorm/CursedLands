#!/usr/bin/env python3
"""Build optional SHaRC 1.8.3 ray/resolve programs for Vulkan and DX12.

SDK headers remain external licensed build inputs, like our NRD build. No
network access is performed. --check without a compiler verifies packaged data.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHADERS = ROOT / 'game/src/game/fx/shaders'
REVISION = '4e21b585c33c83d723ca9a1e11bbb1090d145793'
SDK_FILES = ['include/SharcCommon.h', 'include/SharcTypes.h', 'include/HashGridCommon.h',
             'include/HashGridTypes.h', 'License.md']
SOURCES = ['path_trace.hlsl', 'path_trace_sharc.hlsli', 'path_trace_sharc_resolve.hlsl']
MANIFEST = SHADERS / 'path_trace_sharc_build.json'
NOTICE = SHADERS / 'SHARC_NOTICES.txt'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs():
    return {name: sha(SHADERS / name) for name in SOURCES} | {'builder': sha(Path(__file__))}


def stages():
    result = []
    for update in (False, True):
        for deep in ((False,) if update else (False, True)):
            for emitters in (True, False):
                name = 'path_trace_raygen_sharc' + ('_update' if update else '')
                name += ('_deep' if deep else '') + ('_no_emitters' if not emitters else '')
                defines = ['PATH_RAYGEN', 'PATH_SHARC']
                if update: defines.append('PATH_SHARC_UPDATE')
                if deep: defines.append('PATH_ROULETTE')
                if not emitters: defines.append('PATH_NO_EMITTERS')
                result.append((name, 'path_trace.hlsl', defines, 'lib_6_3'))
    return result + [('path_trace_sharc_resolve', 'path_trace_sharc_resolve.hlsl', [], 'cs_6_2')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dxc', type=Path)
    parser.add_argument('--sdk', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    expected = {name + '.' + ext for name, _, _, target in stages()
                for ext in (('spv',) if target.startswith('cs') else ('spv', 'dxil'))}
    if args.check:
        manifest = json.loads(MANIFEST.read_text())
        assert manifest['sources'] == inputs(), 'SHaRC adapter changed; rebuild'
        assert manifest['sdk_revision'] == REVISION
        assert set(manifest['files']) == expected
        assert manifest['notice_sha256'] == sha(NOTICE)
        for name, digest in manifest['files'].items():
            assert sha(SHADERS / name) == digest, name
        if args.dxc is None:
            print('Verified SHaRC adapter, pinned SDK and', len(expected), 'shader binaries')
            return
    if not args.dxc or not args.sdk:
        parser.error('--dxc and --sdk (SHARC checkout) are required to compile')
    revision = subprocess.check_output(['git', '-C', args.sdk, 'rev-parse', 'HEAD'], text=True).strip()
    assert revision == REVISION, 'Use the pinned SHARC revision: ' + REVISION
    sdk_hashes = {name: sha(args.sdk / name) for name in SDK_FILES}
    for name in SDK_FILES:
        original = subprocess.check_output(['git', '-C', args.sdk, 'show', REVISION + ':' + name])
        assert hashlib.sha256(original).hexdigest() == sdk_hashes[name], 'Modified SDK input: ' + name
    outputs = {}
    with tempfile.TemporaryDirectory() as work:
        for name, source, defines, target in stages():
            common = [str(args.dxc), '-T', target, '-HV', '2021', '-O3', '-enable-16bit-types',
                      '-I', str(args.sdk / 'include'), str(SHADERS / source)]
            if target.startswith('cs'): common += ['-E', 'main']
            for define in defines: common += ['-D', define]
            for backend in (('spv',) if target.startswith('cs') else ('dxil', 'spv')):
                filename = name + '.' + backend
                flags = ['-Qstrip_debug', '-Qstrip_reflect', '-Wno-ignored-attributes'] if backend == 'dxil' else [
                    '-spirv', '-fspv-target-env=vulkan1.2', '-fvk-use-gl-layout',
                    '-fspv-extension=SPV_KHR_ray_tracing', '-fspv-extension=SPV_KHR_16bit_storage']
                if backend == 'spv' and target.startswith('cs'):
                    flags += ['-D', 'SHARC_VULKAN']
                subprocess.run(common + flags + ['-Fo', str(Path(work) / filename)], check=True)
                outputs[filename] = sha(Path(work) / filename)
        if args.check:
            assert outputs == manifest['files'], 'Compiler output changed'
            assert sdk_hashes == manifest['sdk_files'], 'SDK inputs changed'
            print('Reproduced all', len(outputs), 'SHaRC shader binaries')
            return
        for name in outputs: (SHADERS / name).write_bytes((Path(work) / name).read_bytes())
    NOTICE.write_text('This software contains source code provided by NVIDIA Corporation.\n'
                     'SHaRC 1.8.3 is used under the NVIDIA RTX SDKs license below.\n'
                     'The SHaRC component is separate from the application source license.\n\n' +
                     (args.sdk / 'License.md').read_text(), newline='\n')
    MANIFEST.write_text(json.dumps({'sdk_revision': REVISION, 'sdk_files': sdk_hashes,
        'sources': inputs(), 'files': outputs, 'notice_sha256': sha(NOTICE),
        'compiler_sha256': sha(args.dxc),
        'compiler': subprocess.check_output([args.dxc, '--version'], text=True).strip()}, indent=2) + '\n', newline='\n')
    print('Built', len(outputs), 'SHaRC shader binaries')


if __name__ == '__main__':
    main()
