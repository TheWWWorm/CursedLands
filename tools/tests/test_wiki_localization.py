import json
from pathlib import Path
import tempfile
import unittest

from tools.prepare_wiki_localization import prepare


class AstralTutorialLocalizationTest(unittest.TestCase):
    def test_harpy_crawl_example_uses_reviewed_expansion_text(self):
        key = "tutor zt13_text_screen2"
        astral_text = ('В данный момент следует использовать способ движения "ползком" - '
                       'в этом случае у вашего персонажа будет шанс проскользнуть мимо '
                       'гарпии незамеченным. Если этого не сделать, то вашему персонажу '
                       'грозит неминуемая гибель.')
        base = {
            lang: {"campaign": "cursed_lands", "language": lang, "texts": {key: value}}
            for lang, value in {
                "ru": astral_text.replace("гарпии", "людоеда"),
                "en": "Crawl past the ogre.",
                "de": "Krieche am Oger vorbei.",
            }.items()
        }
        astral = {"campaign": "lost_in_astral", "language": "ru", "texts": {key: astral_text},
                  "used": [key], "entries": {}}
        translations = json.loads((Path(__file__).resolve().parents[1] / "wiki_lia_translations.json").read_text())
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            self.assertTrue(prepare(base, astral, translations, output))
            self.assertIn("harpy", json.loads((output / "en.json").read_text())[key].lower())
            self.assertIn("harpyie", json.loads((output / "de.json").read_text())[key].lower())


if __name__ == "__main__":
    unittest.main()
