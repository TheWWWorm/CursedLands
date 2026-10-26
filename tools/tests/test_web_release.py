import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('web_release', Path(__file__).parents[1] / 'check_web_release.py')
web_release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(web_release)


class WebReleaseTests(unittest.TestCase):
    def test_complete_wiki_is_required_and_content_checked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            wiki = root / 'wiki'
            (wiki / 'data').mkdir(parents=True)
            (wiki / 'index.html').write_bytes(b'<main>Offline wiki</main>')
            (wiki / 'data/articles.json').write_bytes(b'{"en":[],"ru":[],"de":[]}')
            for mode in ['omitted', 'partial', 'changed', 'complete']:
                archive = root / (mode + '.zip')
                with zipfile.ZipFile(archive, 'w') as bundle:
                    bundle.writestr('CursedLands-web/BUILD-INFO.json', '{}')
                    if mode != 'omitted':
                        bundle.writestr('CursedLands-web/wiki/index.html', (wiki / 'index.html').read_bytes())
                    if mode in ['changed', 'complete']:
                        bundle.writestr('CursedLands-web/wiki/data/articles.json', b'{}' if mode == 'changed' else (wiki / 'data/articles.json').read_bytes())
                with self.subTest(mode=mode):
                    if mode == 'complete':
                        self.assertEqual(web_release.check_archive(archive, wiki)['wiki_files'], 2)
                    else:
                        with self.assertRaises(ValueError):
                            web_release.check_archive(archive, wiki)


if __name__ == '__main__':
    unittest.main()
