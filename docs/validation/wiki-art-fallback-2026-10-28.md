# Public wiki artwork fallback

The public wiki used nonexistent `icon-mechanics.svg` and `icon-home.svg`
files for entries in Game mechanics without illustrations. The browser showed
broken thumbnails when those lazy-loaded rows came into view. Game mechanics
now uses the existing book icon, including when an illustration fails to load.

`node tools/tests/wiki_art.mjs` checks every published entry in both campaigns
and English, Russian and German. It failed on `mechanics/armor` before this
change and passes afterwards. The original game has no standalone public wiki,
so an original-game Wine comparison is not applicable to this browser UI.
An isolated Chromium run requested all 1,152 images on the English home page;
seven fallback images failed before the fix, and all loaded after it with no
failed responses.
