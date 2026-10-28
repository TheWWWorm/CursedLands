// Isolated Chromium regression check; never attaches to a user's browser.
// node tools/tests/public_wiki.mjs --public-dir=... --output=... --chrome=...
// Add --url=https://cursedlands.wwworm.com to validate the deployed website.
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
import {buildSpell,canEnchant} from '../../web/wiki/constructors.mjs';
const args = Object.fromEntries(process.argv.slice(2).map(v => v.replace(/^--/, '').split(/=(.*)/s).slice(0, 2)));
const root = path.resolve(args['public-dir']), output = path.resolve(args.output);
await fs.mkdir(output, {recursive: true});
const repo = path.resolve(new URL('../..', import.meta.url).pathname);
let source = await fs.readFile(path.join(repo, 'worker.js'), 'utf8');
source = source.replace("import parts from './parts.json';", 'const parts = ' + await fs.readFile(path.join(repo, 'parts.json'), 'utf8') + ';');
const worker = (await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'))).default;
const mime = {'.html':'text/html', '.css':'text/css', '.js':'text/javascript', '.mjs':'text/javascript', '.json':'application/json', '.webp':'image/webp', '.png':'image/png', '.svg':'image/svg+xml', '.ttf':'font/ttf'};
const requests = [], errors = [];
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://' + req.headers.host);
  try {
    const response = await worker.fetch(new Request(url, {method:req.method}), {ASSETS:{fetch: async request => {
      const target = new URL(typeof request === 'string' || request instanceof URL ? request : request.url);
      const name = decodeURIComponent(target.pathname) + (target.pathname.endsWith('/') ? 'index.html' : '');
      const file = path.resolve(root, '.' + name);
      if (!file.startsWith(root + '/')) return new Response('', {status:400});
      try {return new Response(await fs.readFile(file), {headers:{'Content-Type':mime[path.extname(file)] || 'application/octet-stream'}});}
      catch {return new Response('', {status:404});}
    }}});
    res.writeHead(response.status, Object.fromEntries(response.headers));
    res.end(req.method === 'HEAD' ? undefined : Buffer.from(await response.arrayBuffer()));
  } catch (error) {res.writeHead(500); res.end(String(error));}
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = args.url || `http://127.0.0.1:${server.address().port}`;
const profile = await fs.mkdtemp(path.join(output, 'profile-'));
const log = await fs.open(path.join(output, 'chrome.log'), 'w');
const chrome = spawn(args.chrome, ['--headless=new', '--no-sandbox', '--no-first-run', '--disable-dev-shm-usage', '--remote-debugging-port=0', '--user-data-dir=' + profile, 'about:blank'], {stdio:['ignore', log.fd, log.fd]});
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(fn, label, seconds = 30) {
  const end = Date.now() + seconds * 1000;
  while (Date.now() < end) {try {const value = await fn(); if (value) return value;} catch {} await sleep(100);}
  throw Error('Timeout: ' + label);
}
let ws, serial = 0, session;
const pending = new Map();
function command(method, params = {}, sessionId = session) {
  return new Promise((resolve, reject) => {
    const id = ++serial;
    pending.set(id, {resolve, reject});
    ws.send(JSON.stringify({id, method, params, ...(sessionId ? {sessionId} : {})}));
  });
}
async function evaluate(expression) {
  const result = await command('Runtime.evaluate', {expression, awaitPromise:true, returnByValue:true});
  if (result.exceptionDetails) throw Error(JSON.stringify(result.exceptionDetails));
  return result.result.value;
}
async function ready() {
  await until(() => evaluate("!!document.querySelector('#article-heading h1, #article h1') && document.querySelector('#notice').textContent === ''"), 'article ready');
  // Rows can arrive after the article. Request lazy thumbnails as they appear
  // so the check can still verify every illustration, including offscreen ones.
  await until(() => evaluate('(()=>{const images=Array.from(document.images);images.forEach(i=>{i.loading="eager"});return images.every(i=>i.complete && i.naturalWidth>0)})()'), 'illustrations loaded', 180);
}
async function select(selector, value) {
  await evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});e.value=${JSON.stringify(value)};e.dispatchEvent(new Event('change',{bubbles:true}));})()`);
}
async function search(value) {
  await evaluate(`(()=>{const e=document.querySelector('#search');e.value=${JSON.stringify(value)};e.dispatchEvent(new Event('input',{bubbles:true}));})()`);
}
async function openArticle(key, lang = 'en', version = '', campaign = 'cursed_lands') {
  const params = new URLSearchParams({lang,page:key});
  if (campaign !== 'cursed_lands') params.set('campaign', campaign);
  if (version) params.set('version', version);
  await command('Page.navigate', {url:origin + '/wiki/?' + params}); await ready();
}
async function screenshot(name) {
  const shot = await command('Page.captureScreenshot', {format:'png'});
  await fs.writeFile(path.join(output, name + '.png'), Buffer.from(shot.data, 'base64'));
}
const report = {version:'1.7.0', live:!!args.url, checks:[], languages:{}, errors};
function check(value, label) {assert(value, label); report.checks.push(label);}
try {
  const endpoint = await until(async () => (await fs.readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n'), 'Chromium', 20);
  ws = new WebSocket('ws://127.0.0.1:' + endpoint[0] + endpoint[1]);
  ws.addEventListener('message', ({data}) => {
    const m = JSON.parse(data);
    if (m.id) {const p = pending.get(m.id);pending.delete(m.id);if (p) m.error ? p.reject(Error(JSON.stringify(m.error))) : p.resolve(m.result);}
    else if (m.method === 'Runtime.exceptionThrown') errors.push(m.params.exceptionDetails);
    else if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') errors.push(m.params.args.map(v => v.value || v.description).join(' '));
    else if (m.method === 'Network.requestWillBeSent') requests.push(m.params.request.url);
  });
  await new Promise(resolve => ws.addEventListener('open', resolve, {once:true}));
  const {browserContextId} = await command('Target.createBrowserContext');
  const {targetId} = await command('Target.createTarget', {url:'about:blank', browserContextId});
  session = (await command('Target.attachToTarget', {targetId, flatten:true})).sessionId;
  await command('Runtime.enable'); await command('Page.enable'); await command('Network.enable');
  await command('Emulation.setDeviceMetricsOverride', {width:1280,height:800,deviceScaleFactor:1,mobile:false});
  const response = await fetch(origin + '/wiki?lang=en');
  check(response.ok && new URL(response.url).pathname === '/wiki/', 'bare /wiki redirects with language preserved');
  check(response.headers.get('content-security-policy')?.includes("object-src 'none'"), 'wiki security policy served');
  await command('Page.navigate', {url:origin + '/wiki?lang=en'});
  await ready();
  const clean = await evaluate('(async()=>({databases:await indexedDB.databases(),storage:localStorage.length,workers:(await navigator.serviceWorker.getRegistrations()).length,caches:await caches.keys()}))()');
  assert.deepEqual(clean, {databases:[],storage:0,workers:0,caches:[]});
  check(true, 'fresh wiki works without game data, caches, storage or service worker');
  check(!requests.some(url => /\.(wasm|pck)(\?|$)|\/(index|storage|files|data-worker)\.js(\?|$)/.test(url)), 'no game engine or importer requested');
  const index = JSON.parse(await fs.readFile(path.join(root, 'wiki/data/en/index.json'), 'utf8'));
  check(await evaluate('document.querySelectorAll("#results a").length') === index.entries.filter(v => v.listed !== false).length, 'all matching entries appear in one continuous list');
  check(await evaluate('!document.querySelector(".pagination,#previous,#next,#page-number")'), 'no pagination controls');
  let item;
  for (const row of index.entries.filter(v => v.kind === 'item')) {
    const page = JSON.parse(await fs.readFile(path.join(root, 'wiki/data/en/pages', row.file), 'utf8'));
    if (page.versions.length > 5 && page.versions[0].image && /sword|axe|bow|helmet/i.test(row.title)) {item = {row,page}; break;}
  }
  assert(item, 'illustrated item with material versions');
  const start = new URL(origin + '/wiki/'); start.search = new URLSearchParams({lang:'en',page:item.row.key});
  await command('Page.navigate', {url:start.href}); await ready();
  check(await evaluate('document.querySelectorAll("#variant option").length') === item.page.versions.length, 'all material and blueprint versions available');
  const first = await evaluate('document.querySelector("#article").innerText');
  const last = item.page.versions.at(-1);
  await select('#variant', last.id); await ready();
  check(await evaluate('document.querySelector("#article").innerText') !== first, 'material selection changes actual statistics');
  check(await evaluate('new URLSearchParams(location.search).get("version")') === last.id, 'selected version has shareable URL');
  await evaluate('history.back()'); await until(() => evaluate('new URLSearchParams(location.search).get("version") === null'), 'back'); await ready();
  check(await evaluate('document.querySelector("#article").innerText') === first, 'browser Back restores original version');
  for (const lang of ['en','ru','de']) {
    await select('#language', lang); await ready();
    check(await evaluate('document.documentElement.lang') === lang, lang + ' language updates page and interface');
    const shot = await command('Page.captureScreenshot', {format:'png'});
    await fs.writeFile(path.join(output, 'wiki-' + lang + '.png'), Buffer.from(shot.data, 'base64'));
    report.languages[lang] = await evaluate('({title:document.querySelector("#article-heading h1, #article h1").textContent, label:document.querySelector("label[for=search]").textContent})');
    check(await evaluate('document.documentElement.scrollWidth <= innerWidth'), lang + ' desktop has no horizontal overflow');
    const localized = JSON.parse(await fs.readFile(path.join(root, 'wiki/data', lang, 'index.json'), 'utf8'));
    await select('#category', 'Items');
    const types = [...new Set(localized.entries.filter(v => v.kind === 'item' && v.listed !== false).map(v => v.subcategory))];
    check(await evaluate('document.querySelectorAll("#item-category option").length') === types.length + 1, lang + ' every item subcategory is available');
    for (const type of types) {
      await select('#item-category', type);
      const expected = localized.entries.filter(v => v.kind === 'item' && v.listed !== false && v.subcategory === type).length;
      check(await evaluate('document.querySelectorAll("#results a").length') === expected, lang + ' item filter ' + type);
    }
    check(await evaluate('Array.from(document.querySelectorAll("#item-category option,#item-category optgroup")).every(e=>(e.label||e.textContent).trim() && !/undefined/.test(e.label||e.textContent))'), lang + ' dynamic subcategory labels are translated');
    await select('#item-category', 'armor_plate');
    await screenshot('wiki-filters-' + lang);
    await select('#category', 'Spells');
    check(await evaluate('document.querySelector("#item-filters").hidden'), lang + ' item filters stay within Items');
    const spells = localized.entries.filter(v => v.kind === 'spell' && v.listed !== false);
    check(await evaluate('document.querySelectorAll("#results a").length') === spells.length, lang + ' all base spells are listed');
    check(await evaluate('Array.from(document.querySelectorAll("#results a")).every(a=>!decodeURIComponent(new URL(a.href).searchParams.get("page")).includes("{"))'), lang + ' rune-equipped spells are absent from list');
    const acid = spells.find(v => v.key === 'spell/acid_ray');
    assert(acid);
    await select('#category', 'All pages'); await search(acid.title);
    const results = await evaluate('Array.from(document.querySelectorAll("#results a")).map(a=>new URL(a.href).searchParams.get("page"))');
    check(results.filter(key => key.startsWith('spell/')).length === 1 && results.includes(acid.key), lang + ' searching all categories returns one base Acid blast');
    await search('');
    const doll = localized.entries.find(v => v.key === 'item/wand%206');
    const horn = localized.entries.find(v => v.key === 'item/wand%205');
    for (const fixed of [doll, horn]) {
      await openArticle(fixed.key, lang);
      check(await evaluate('document.querySelector("#article-heading h1, #article h1").textContent') === fixed.title, lang + ' fixed item uses its authored name: ' + fixed.title);
      check(await evaluate('document.querySelector("#versions").hidden && document.querySelectorAll("#variant option").length === 1'), lang + ' fixed item has no material or blueprint choices: ' + fixed.title);
    }
  }
  await openArticle('item/wand%206', 'en', 'wand 6.granite');
  check(await evaluate('new URLSearchParams(location.search).get("version")') === 'wand 6.rock', 'old synthetic material deep link resolves to authored Goblin doll');
  await screenshot('wiki-goblin-doll');
  for (const key of ['item/gipat%20special%20high%20plate', 'item/gipat%20special%20brigand%20plate']) {
    await openArticle(key);
    const row = index.entries.find(v => v.key === key);
    check(await evaluate('document.querySelector("#article-heading h1, #article h1").textContent') === row.title, 'NPC armour has a distinct garment and wearer name: ' + row.title);
    check(await evaluate('!!document.querySelector("#article img") && document.querySelector("#versions").hidden'), 'NPC armour has an illustration and its fixed material');
    await select('#category', 'Items'); await select('#item-category', 'armor_plate');
    await screenshot(key.includes('brigand') ? 'wiki-estera-armour' : 'wiki-erfar-armour');
  }
  for (const name of ['Old stony harpy', 'Strong black banshee (variant 2)']) {
    const row = index.entries.find(v => v.title === name);
    assert(row, name);
    await openArticle(row.key);
    await screenshot(name.startsWith('Old') ? 'wiki-harpy' : 'wiki-banshee');
  }
  // The expansion reuses base-game record IDs. Exercise the visible campaign
  // switch, deep links, language changes and history with genuinely different
  // source articles, rather than only checking the tabs' appearance.
  const names = JSON.parse(await fs.readFile(path.join(repo, 'tools/wiki_spell_names.json'), 'utf8'));
  const astral = JSON.parse(await fs.readFile(path.join(root, 'wiki/data/lost_in_astral/en/index.json'), 'utf8'));
  const changedItem = astral.entries.find(row => row.subcategory === 'quest' && row.listed &&
    index.entries.some(base => base.key === row.key && base.listed && base.title !== row.title));
  assert(changedItem, 'an authored quest item differs between the two campaigns');
  const baseItem = index.entries.find(row => row.key === changedItem.key);
  await openArticle(baseItem.key);
  check(await evaluate('document.querySelector("#article-heading h1, #article h1").textContent') === baseItem.title, 'base campaign uses original quest-item name');
  await evaluate('document.querySelector("[data-campaign=lost_in_astral]").click()'); await ready();
  check(await evaluate('new URLSearchParams(location.search).get("campaign")') === 'lost_in_astral', 'campaign tab opens shareable expansion URL');
  check(await evaluate('document.querySelectorAll("#results a").length') === astral.entries.filter(v => v.listed !== false).length, 'expansion has its own complete continuous contents list');
  await evaluate('history.back()'); await until(() => evaluate('!new URLSearchParams(location.search).has("campaign")'), 'base campaign history'); await ready();
  check(await evaluate('document.querySelector("#article-heading h1, #article h1").textContent') === baseItem.title, 'browser Back restores base campaign and article');
  await openArticle(changedItem.key, 'en', '', 'lost_in_astral');
  check(await evaluate('document.querySelector("#article-heading h1, #article h1").textContent') === changedItem.title, 'same quest-item ID uses expansion name in expansion tab');
  const astralSight = {en:"Dead man's sight",ru:'Зрение мертвеца',de:'Totensicht'};
  for (const lang of ['en', 'ru', 'de']) {
    const localized = JSON.parse(await fs.readFile(path.join(root, 'wiki/data/lost_in_astral', lang, 'index.json'), 'utf8'));
    await openArticle('spell/detect_life', lang);
    check(await evaluate('document.querySelector("#article-heading h1, #article h1").textContent') === names.detect_life[lang], lang + ' missing base spell has a localized deep-link name');
    await select('#category', 'Spells');
    check(await evaluate('Array.from(document.querySelectorAll("#results a")).every(a=>new URL(a.href).searchParams.get("page") !== "spell/detect_life")'), lang + ' unnamed dormant base prototype does not clutter spell list');
    await openArticle('spell/detect_life', lang, '', 'lost_in_astral');
    check(await evaluate('document.querySelector("#article-heading h1, #article h1").textContent') === astralSight[lang], lang + ' expansion spell uses its authored name');
    check(await evaluate('document.querySelectorAll("#campaigns a").length === 2 && document.querySelector("#campaigns [aria-current=page]").dataset.campaign === "lost_in_astral"'), lang + ' exactly two campaign tabs with correct active state');
    await select('#category', 'Spells');
    check(await evaluate('document.querySelectorAll("#results a").length') === 35, lang + ' expansion lists 35 named base spells');
    check(await evaluate('Array.from(document.querySelectorAll("#results a")).every(a=>!decodeURIComponent(new URL(a.href).searchParams.get("page")).includes("{") && !["Spell","Заклинание","Zauber"].includes(a.textContent))'), lang + ' expansion spell list has no rune variants or generic names');
    check(await evaluate('Array.from(document.querySelectorAll("#article a")).every(a=>new URL(a.href).searchParams.get("campaign") === "lost_in_astral")'), lang + ' article links retain the expansion');
    await screenshot('wiki-astral-spell-' + lang);
    await evaluate('document.querySelector("#article a").click()'); await ready();
    check(await evaluate('new URLSearchParams(location.search).get("campaign")') === 'lost_in_astral', lang + ' linked mechanics stay in expansion');
    await evaluate('history.back()'); await until(() => evaluate('new URLSearchParams(location.search).get("page") === "spell/detect_life"'), 'expansion spell history'); await ready();
    await select('#language', lang === 'en' ? 'de' : 'en'); await ready();
    check(await evaluate('new URLSearchParams(location.search).get("campaign") === "lost_in_astral" && new URLSearchParams(location.search).get("page") === "spell/detect_life"'), lang + ' language change preserves campaign and article');
    await select('#language', lang); await ready();
    await select('#category', 'Items');
    const types = [...new Set(localized.entries.filter(v => v.kind === 'item' && v.listed !== false).map(v => v.subcategory))];
    for (const type of types) {
      await select('#item-category', type);
      check(await evaluate('document.querySelectorAll("#results a").length') === localized.entries.filter(v => v.listed && v.subcategory === type).length, lang + ' expansion item filter ' + type);
    }
    await command('Emulation.setDeviceMetricsOverride', {width:390,height:844,deviceScaleFactor:1,mobile:true});
    check(await evaluate('document.documentElement.scrollWidth <= innerWidth'), lang + ' mobile campaign tabs and article fit viewport');
    await evaluate('document.querySelector("main").scrollIntoView()');
    await screenshot('wiki-astral-mobile-' + lang);
    await command('Emulation.setDeviceMetricsOverride', {width:1280,height:800,deviceScaleFactor:1,mobile:false});
    await evaluate('scrollTo(0,0)');
  }
  const dragon = astral.entries.find(v => v.kind === 'creature' && /^Black dragon(?:$| \(variant \d+\))/.test(v.title));
  assert(dragon);
  await openArticle(dragon.key, 'en', '', 'lost_in_astral');
  check(await evaluate('!!document.querySelector("#article img")'), 'expansion creature has its own illustration');
  await screenshot('wiki-astral-dragon');
  await evaluate('document.querySelector("[data-campaign=cursed_lands]").click()'); await ready();
  check(await evaluate('!new URLSearchParams(location.search).has("campaign") && document.querySelector("#campaigns [aria-current=page]").dataset.campaign === "cursed_lands"'), 'base tab restores legacy base-game URL');
  const modifiedSpell = index.entries.find(v => v.kind === 'spell' && v.listed === false);
  await openArticle(modifiedSpell.key);
  check(await evaluate('document.querySelector("#article-heading h1, #article h1").textContent') === modifiedSpell.title, 'referenced rune-equipped spell remains accessible by deep link');
  await select('#category', 'Creatures');
  check(await evaluate('document.querySelectorAll("#results a").length') === index.entries.filter(v => v.kind === 'creature').length, 'all creatures available without paging');
  const bottom = await evaluate('(()=>{const e=document.querySelector("#results");e.scrollTop=e.scrollHeight;return e.scrollTop;})()');
  check(bottom > 0, 'continuous result list scrolls to its final entries');
  await evaluate('document.querySelector("#results a:last-child").click()'); await ready();
  check(Math.abs(await evaluate('document.querySelector("#results").scrollTop') - bottom) < 2, 'opening last entry retains result-list scroll position');
  await search('___missing___');
  check(await evaluate('document.querySelectorAll("#results a").length') === 0, 'empty search results');
  await search(''); await select('#category', 'Items'); await select('#item-category', 'quest');
  await command('Emulation.setDeviceMetricsOverride', {width:390,height:844,deviceScaleFactor:1,mobile:true});
  await sleep(200);
  check(await evaluate('document.documentElement.scrollWidth <= innerWidth'), 'mobile has no horizontal overflow');
  const mobile = await command('Page.captureScreenshot', {format:'png',captureBeyondViewport:true});
  await fs.writeFile(path.join(output, 'wiki-mobile.png'), Buffer.from(mobile.data, 'base64'));
  for (const campaign of ['cursed_lands','lost_in_astral']) {
    const directory=path.join(root,'wiki/data',campaign==='lost_in_astral' ? campaign : '');
    const data=JSON.parse(await fs.readFile(path.join(directory,'en/constructors.json'),'utf8'));
    const code=Object.keys(data.spells).find(code=>Object.keys(data.runes).some(r=>r.startsWith('e') && buildSpell(data,code,[r])));
    const rune=Object.keys(data.runes).find(r=>r.startsWith('e') && buildSpell(data,code,[r]));
    for (const lang of ['en','ru','de']) {
      const entries=JSON.parse(await fs.readFile(path.join(directory,lang,'index.json'),'utf8')).entries;
      check(entries.filter(e=>/^rune\/(?:c\d|ee\d)$/.test(e.key)).every(e=>e.listed===false),campaign+' '+lang+' internal colour/effect records excluded');
      for (const kind of ['map','quest']) {
        let row=entries.find(e=>e.kind===kind && e.listed);
        if (kind==='map') for (const candidate of entries.filter(e=>e.kind==='map' && e.listed)) {
          const page=JSON.parse(await fs.readFile(path.join(directory,lang,'pages',candidate.file),'utf8'));
          if (page.versions[0].image) {row=candidate;break;}
        }
        assert(row);
        await openArticle(row.key,lang,'',campaign);
        check(await evaluate('document.querySelector("#article-heading h1, #article h1").textContent')===row.title,campaign+' '+lang+' localized '+kind+' article');
        if (kind==='map') check(await evaluate('!!document.querySelector("#article figure.map-overview img")'),campaign+' '+lang+' authored map image');
      }
      await openArticle('spell/'+code,lang,'',campaign);
      await select('#constructor-rune',rune);
      await evaluate('document.querySelector("#constructor-add-rune").click()');
      check(await evaluate('document.querySelector("#constructor-rune").value')===rune,campaign+' '+lang+' rune selection survives addition');
      await evaluate('document.querySelector("#constructor-add-rune").click()'); await ready();
      check(await evaluate('document.querySelector("#constructor").dataset.runeCount')==='2',campaign+' '+lang+' repeated rune added');
      check(await evaluate('document.querySelector("#constructor img.rune-art").naturalWidth>0'),campaign+' '+lang+' selected rune artwork visible');
      await command('Page.reload'); await ready();
      check(await evaluate('document.querySelector("#constructor").dataset.runeCount')==='2',campaign+' '+lang+' shared URL restores spell draft');
      await select('#language',lang==='de'?'en':'de'); await ready();
      check(await evaluate('document.querySelector("#constructor").dataset.runeCount')==='2',campaign+' '+lang+' language switch retains draft');
      await command('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
      check(await evaluate('document.documentElement.scrollWidth<=innerWidth'),campaign+' '+lang+' constructor fits mobile');
      await evaluate('document.querySelector("#constructor").scrollIntoView()');
      await screenshot('wiki-constructor-'+campaign+'-'+lang);
      await command('Emulation.setDeviceMetricsOverride',{width:1280,height:800,deviceScaleFactor:1,mobile:false});
    }
    for (let i=2;i<8;i++) await evaluate('document.querySelector("#constructor-add-rune").click()');
    check(await evaluate('document.querySelector("#constructor").dataset.runeCount==="8" && document.querySelector("#constructor-add-rune").disabled'),campaign+' eight-rune limit enforced');
    await evaluate('document.querySelector("#constructor-remove-rune").click()');
    check(await evaluate('document.querySelector("#constructor").dataset.runeCount')==='7',campaign+' remove last rune');
    await evaluate('document.querySelector("#constructor-reset").click()');
    check(await evaluate('document.querySelector("#constructor").dataset.runeCount')==='0',campaign+' reset spell');
    const english=JSON.parse(await fs.readFile(path.join(directory,'en/index.json'),'utf8'));
    let sample;
    for (const row of english.entries.filter(r=>r.kind==='item' && !r.fixed)) {
      const page=JSON.parse(await fs.readFile(path.join(directory,'en/pages',row.file),'utf8'));
      for (const version of page.versions.filter(v=>v.builder)) {
        const spell=Object.keys(data.spells).find(s=>canEnchant(version.builder,buildSpell(data,s,['it'])));
        if (spell) {sample={row,version,spell,page};break;}
      }
      if (sample) break;
    }
    assert(sample,'real enchantable web item');
    await openArticle(sample.row.key,'en',sample.version.id,campaign);
    await select('#constructor-spell',sample.spell); await select('#constructor-rune','it');
    await evaluate('document.querySelector("#constructor-add-rune").click()');
    check(await evaluate('document.querySelector("#constructor").dataset.valid')==='true',campaign+' native legal item enchantment admitted');
    await command('Page.reload'); await ready();
    check(await evaluate('document.querySelector("#constructor").dataset.runeCount==="1" && document.querySelector("#constructor-spell").value')===sample.spell,campaign+' item draft restored from URL');
    const other=sample.page.versions.find(v=>v.builder && v.id!==sample.version.id);
    if (other) {
      await select('#variant',other.id); await ready();
      check(await evaluate('document.querySelector("#constructor").dataset.runeCount')==='1',campaign+' material switch retains enchantment draft');
    }
    await screenshot('wiki-item-constructor-'+campaign);
  }
  await command('Page.navigate', {url:origin + '/wiki/?lang=ru&page=not-a-page'});
  await until(() => evaluate('document.querySelector("#notice")?.textContent === "Страница недоступна"'), 'localized missing page');
  check(true, 'unknown deep link displays localized missing-page state');
  assert.deepEqual(errors, []);
  report.no_console_errors = true;
  report.network_requests = requests.length;
  report.no_engine_requests = !requests.some(url => /\.(wasm|pck)(\?|$)/.test(url));
  await fs.writeFile(path.join(output, 'result.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({checks:report.checks.length,languages:report.languages,no_engine_requests:report.no_engine_requests}));
} finally {
  if (ws?.readyState === WebSocket.OPEN) {try {await command('Browser.close', {}, undefined);} catch {} ws.close();}
  chrome.kill('SIGTERM'); server.close(); await log.close();
  await fs.writeFile(path.join(output, 'requests.json'), JSON.stringify(requests, null, 2));
}
