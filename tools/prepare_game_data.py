#!/usr/bin/env python3
"""Create a private browser/Android data pack from your own game installation."""
import argparse
import json
import pathlib
import shutil
import struct

REQUIRED = {'res/textures.res', 'res/figures.res', 'res/redress.res', 'res/database.res',
            'res/texts.res', 'maps/zone1.mpr', 'maps/zone1.mob'}


def prepare(source, output):
    source, output = pathlib.Path(source).resolve(), pathlib.Path(output).resolve()
    if output.is_relative_to(source):
        raise ValueError('Write the data pack outside the source installation.')
    files, index, offset = [], {}, 0
    for path in sorted(source.rglob('*')):
        if not path.is_file() or path.is_symlink():
            continue
        name = path.relative_to(source).as_posix().lower()
        if name.split('/')[0] not in {'res', 'maps', 'config', 'stream', 'movies', 'camera'}:
            continue
        if name in index:
            raise ValueError('Duplicate case-insensitive filename: ' + name)
        size = path.stat().st_size
        if size > 512 * 1024 * 1024:
            raise ValueError('File exceeds supported size: ' + name)
        index[name] = {'offset': offset, 'size': size}
        offset += size
        files.append(path)
    missing = REQUIRED - index.keys()
    if missing:
        raise ValueError('Missing original data: ' + ', '.join(sorted(missing)))
    header = json.dumps(index, separators=(',', ':')).encode()
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + '.partial')
    try:
        with temporary.open('wb') as target:
            target.write(b'EIPACK01' + struct.pack('<I', len(header)) + header)
            for path in files:
                with path.open('rb') as data:
                    shutil.copyfileobj(data, target, 1024 * 1024)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    return len(files), offset


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=pathlib.Path)
    parser.add_argument('output', type=pathlib.Path)
    args = parser.parse_args()
    count, size = prepare(args.source, args.output)
    print(f'{args.output}: {count} files, {size / 1024**2:.1f} MiB. Keep this private; it contains your original game data.')
