#!/usr/bin/env python3
"""Verify that a standalone browser release retains the complete public wiki."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def check_archive(archive, wiki):
    expected = {p.relative_to(wiki).as_posix(): p for p in wiki.rglob('*') if p.is_file()}
    if not expected:
        raise ValueError('The reference wiki is empty')
    with zipfile.ZipFile(archive) as bundle:
        names = bundle.namelist()
        roots = {name.rsplit('/', 1)[0] for name in names if name.endswith('/BUILD-INFO.json') and '/wiki/' not in name}
        if len(roots) != 1:
            raise ValueError('Expected one browser build root')
        prefix = roots.pop() + '/wiki/'
        actual = {name[len(prefix):] for name in names if name.startswith(prefix) and not name.endswith('/')}
        if actual != expected.keys():
            raise ValueError(f'Wiki file set differs: {len(expected.keys() - actual)} missing, {len(actual - expected.keys())} unexpected')
        digest = hashlib.sha256()
        for name, path in sorted(expected.items()):
            data = bundle.read(prefix + name)
            if data != path.read_bytes():
                raise ValueError(f'Wiki content differs: {name}')
            digest.update(name.encode() + b'\0' + hashlib.sha256(data).digest())
    return {'passed': True, 'wiki_files': len(expected), 'wiki_tree_sha256': digest.hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--wiki', type=Path, default=Path(__file__).resolve().parents[1] / 'public/wiki')
    args = parser.parse_args()
    try:
        result = check_archive(args.archive, args.wiki)
    except (ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, f'FAIL: {error}\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
