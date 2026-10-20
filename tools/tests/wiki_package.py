"""Check that UI-only publishing detects stale copies and preserves data provenance."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('wiki_package', ROOT / 'tools/prepare_public_wiki.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class WikiPackageTests(unittest.TestCase):
    def test_refresh_and_reject_stale_package(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            output = Path(directory)
            report = package.read(ROOT / 'public/wiki/BUILD-INFO.json')
            for source in package.SOURCE.iterdir():
                shutil.copy2(source, output / source.name)
            for source in (ROOT / 'public/wiki/data').rglob('index.json'):
                target = output / source.relative_to(ROOT / 'public/wiki')
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
            package.write_manifest(output, {'version': report['version']})
            package.check_package(output)
            (output / 'maps.mjs').write_text('// stale interface\n')
            with self.assertRaisesRegex(AssertionError, 'Stale wiki interface'):
                package.check_package(output)
            package.refresh_ui(output)
            updated = package.read(output / 'BUILD-INFO.json')
            self.assertEqual(updated['version'], report['version'])
            self.assertEqual((output / 'maps.mjs').read_bytes(), (package.SOURCE / 'maps.mjs').read_bytes())
            (output / 'unexpected.txt').write_text('not in manifest')
            with self.assertRaisesRegex(AssertionError, 'inventory'):
                package.check_package(output)
            (output / 'unexpected.txt').unlink()
            index = output / 'data/en/index.json'
            data = package.read(index)
            data['version'] = '99.0.0'
            index.write_text(json.dumps(data))
            with self.assertRaisesRegex(AssertionError, 'Stale wiki manifest'):
                package.check_package(output)
            package.write_manifest(output, updated)
            with self.assertRaisesRegex(AssertionError, 'Catalogue version'):
                package.check_package(output)
            index.unlink()
            package.write_manifest(output, updated)
            with self.assertRaisesRegex(AssertionError, 'both campaigns'):
                package.check_package(output)


if __name__ == '__main__':
    unittest.main()
