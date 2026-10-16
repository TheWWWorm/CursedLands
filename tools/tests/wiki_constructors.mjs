// Compare the browser calculators against wiki_features.gd's real native
// builders. node tools/tests/wiki_constructors.mjs /path/constructor-oracles.json
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {buildSpell, canEnchant, itemResult} from '../../web/wiki/constructors.mjs';
const oracle=JSON.parse(await fs.readFile(process.argv[2],'utf8'));
let checks=0;
for (const row of oracle.cases) {
  const actual=buildSpell(oracle.data,row.code,row.runes);
  assert(actual,`admitted spell: ${row.code} ${row.runes}`); checks++;
  for (const [field,value] of Object.entries(row.expected)) {
    assert(Math.abs(actual[field]-value)<=1e-8*Math.max(1,Math.abs(value)),`${row.code} ${row.runes}: ${field} ${actual[field]} != ${value}`); checks++;
  }
}
for (const row of oracle.items) {
  const spell=row.code ? buildSpell(oracle.data,row.code,row.runes) : null;
  assert.equal(!row.code || canEnchant(row.item,spell),row.valid,'native enchantment admission'); checks++;
  const actual=itemResult(row.item,spell);
  assert.equal(!!actual,row.valid,'invalid item cannot be constructed'); checks++;
  if (actual) {assert.equal(actual.price,row.price);assert.equal(actual.construction,row.construction); checks+=2;}
}
const code=Object.keys(oracle.data.spells)[0];
assert.equal(buildSpell(oracle.data,code,Array(9).fill('it')),null); checks++;
assert.equal(buildSpell(oracle.data,code,['unknown-rune']),null); checks++;
console.log(JSON.stringify({checks,spells:oracle.cases.length,items:oracle.items.length}));
