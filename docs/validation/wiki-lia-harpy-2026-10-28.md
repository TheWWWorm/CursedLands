# Lost in Astral public wiki tutorial localization

During the 1.34.0 public wiki export, the expansion's crawl tutorial example
could not be translated using the old private text overlay. The original
Russian LiA text names a harpy; the corresponding base-game text names an
ogre, so reusing the base translation by key would change its meaning.

The localized export now uses reviewed English and German translations for
the expansion text. `tools/tests/test_wiki_localization.py` exercises the
actual localization preparer with the different base and expansion strings:
it failed before the translation was added and passes afterwards. The complete
private reference-text audit is also run before packaging the public wiki.

The comparison here is between the original localized text archives and the
public wiki export. An original-game Wine interaction is not applicable to
this static translated export; it was not used as evidence.
