#!/usr/bin/env python3
"""Prepare an exported Web build for a static host with a per-file size limit.

Cloudflare rejects assets larger than 25 MiB, and the Godot engine binary
(index.wasm, about 36 MiB) exceeds that. Oversized files are split into
numbered parts that publish/worker.js streams back together under the original
path. Their total size and part count go into parts.json next to worker.js, so
the rejoined response carries a Content-Length (the loading bar needs it) and a
missing part ends in an error rather than a short file. The parts stay uncompressed: Cloudflare negotiates its own
Content-Encoding for the response, so storing them pre-compressed would only
fight that and strip the encoding header.

The archive bridge (web/files.js, web/data-worker.js) reads the player's game
files through SharedArrayBuffer, which browsers only allow on a cross-origin
isolated page. Every response therefore carries COOP/COEP; worker.js adds the
same headers to the files it rejoins, because _headers does not apply to
responses built by the Worker.
"""
import argparse
import json
import pathlib
import shutil

LIMIT = 25 * 1024 * 1024
CHUNK = 20 * 1024 * 1024
BASE_HEADERS = """# Served by static hosts that read _headers (Cloudflare Workers assets, Pages, Netlify).
# The archive bridge needs SharedArrayBuffer, so every page must be cross-origin isolated.
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
  Cross-Origin-Resource-Policy: same-origin

/*.wasm
  Content-Type: application/wasm

# The shell and the service worker must be revalidated, so a new export is picked up.
/
  Cache-Control: no-cache

/index.html
  Cache-Control: no-cache

/service-worker.js
  Cache-Control: no-cache
"""


def split(path, chunk=CHUNK):
    """Replace a file with sequential .part0, .part1, ... siblings."""
    raw = path.read_bytes()
    parts = [raw[offset:offset + chunk] for offset in range(0, len(raw), chunk)]
    for index, payload in enumerate(parts):
        path.with_name(f'{path.name}.part{index}').write_bytes(payload)
    path.unlink()
    return len(raw), len(parts)


def prepare(source, output, limit=LIMIT, chunk=CHUNK, manifest=None):
    if chunk > limit:
        raise ValueError('Chunk size must not exceed the host limit')
    source, output = pathlib.Path(source).resolve(), pathlib.Path(output).resolve()
    if not (source / 'index.html').is_file():
        raise ValueError(f'{source} does not hold a Web export (no index.html)')
    if output == source or source.is_relative_to(output):
        raise ValueError('The output directory must not contain the source')
    if output.exists():
        shutil.rmtree(output)
    shutil.copytree(source, output, symlinks=False)
    divided = {}
    for path in sorted(output.rglob('*')):
        if path.is_file() and path.stat().st_size > limit:
            size, count = split(path, chunk)
            name = '/' + path.relative_to(output).as_posix()
            divided[name] = {'count': count, 'size': size}
            print(f'  split {name}: {size/1048576:.1f} MiB into {count} parts')
    (output / '_headers').write_text(BASE_HEADERS)
    over = [p for p in output.rglob('*') if p.is_file() and p.stat().st_size > limit]
    if over:
        raise ValueError('Still over the host limit: ' + ', '.join(p.name for p in over))
    if manifest is None:
        manifest = output.parent / 'parts.json'
    pathlib.Path(manifest).write_text(json.dumps(divided, indent=2, sort_keys=True) + '\n')
    return {'files': sum(1 for p in output.rglob('*') if p.is_file()), 'split': len(divided)}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--source', required=True, type=pathlib.Path, help='Exported Web build directory')
    parser.add_argument('--output', required=True, type=pathlib.Path, help='Directory to write, replaced if present')
    parser.add_argument('--limit', type=int, default=LIMIT, help='Per-file host limit in bytes')
    parser.add_argument('--chunk', type=int, default=CHUNK, help='Maximum size of each written part')
    args = parser.parse_args()
    print(prepare(args.source, args.output, args.limit, args.chunk))


if __name__ == '__main__':
    main()
