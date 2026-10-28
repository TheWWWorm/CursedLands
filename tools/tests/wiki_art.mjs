import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {art} from '../../web/wiki/art.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
globalThis.document = {createElement(tag) {
  assert.equal(tag, 'img');
  return {addEventListener(name, callback) { if (name === 'error') this.fail = callback; }};
}};
let checked = 0;
for (const campaign of ['', 'lost_in_astral']) for (const language of ['en', 'ru', 'de']) {
  const index = JSON.parse(fs.readFileSync(path.join(repo, 'public/wiki/data', campaign, language, 'index.json')));
  for (const row of index.entries) {
    const image = art(row);
    image.fail(); // An absent original illustration must still get a valid fallback.
    assert.match(image.src, /^\.\/icon-[a-z]+\.svg$/);
    const fallback = path.join(repo, 'web/wiki', image.src);
    assert(fs.existsSync(fallback) && fs.statSync(fallback).isFile(), `${campaign || 'base'} ${language} ${row.key}: ${image.src}`);
    assert.equal(image.className, 'fallback-art');
    checked++;
  }
}
console.log(`Verified fallback artwork for ${checked} wiki entries across both campaigns and all languages.`);
