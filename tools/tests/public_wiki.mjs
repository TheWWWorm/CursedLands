// Isolated Chromium regression check; never attaches to a user's browser.
// node tools/tests/public_wiki.mjs --public-dir=... --output=... --chrome=...
// Add --url=https://cursedlands.wwworm.com to validate the deployed website.
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
const args = Object.fromEntries(process.argv.slice(2).map(v => v.replace(/^--/, '').split(/=(.*)/s).slice(0, 2)));
const root = path.resolve(args['public-dir']), output = path.resolve(args.output);
await fs.mkdir(output, {recursive: true});
const repo = path.resolve(new URL('../..', import.meta.url).pathname);
let source = await fs.readFile(path.join(repo, 'worker.js'), 'utf8');
source = source.replace("import parts from './parts.json';", 'const parts = ' + await fs.readFile(path.join(repo, 'parts.json'), 'utf8') + ';');
const worker = (await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'))).default;
const mime = {'.html':'text/html', '.css':'text/css', '.js':'text/javascript', '.json':'application/json', '.webp':'image/webp', '.png':'image/png'};
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
  await until(() => evaluate("!!document.querySelector('#article h1') && document.querySelector('#notice').textContent === ''"), 'article ready');
  await until(() => evaluate('Array.from(document.images).every(i=>i.complete && i.naturalWidth>0)'), 'illustrations loaded');
}
async function select(selector, value) {
  await evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});e.value=${JSON.stringify(value)};e.dispatchEvent(new Event('change',{bubbles:true}));})()`);
}
const report = {version:'1.6.0', live:!!args.url, checks:[], languages:{}, errors};
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
    report.languages[lang] = await evaluate('({title:document.querySelector("#article h1").textContent, label:document.querySelector("label[for=search]").textContent})');
    check(await evaluate('document.documentElement.scrollWidth <= innerWidth'), lang + ' desktop has no horizontal overflow');
  }
  await select('#category', 'Creatures');
  check(await evaluate('document.querySelectorAll("#results a").length') === 40, 'category list is paginated');
  await evaluate('document.querySelector("#next").click()');
  check(await evaluate('document.querySelector("#page-number").textContent.startsWith("2")'), 'next result page works');
  await evaluate('(()=>{const e=document.querySelector("#search");e.value="___missing___";e.dispatchEvent(new Event("input"));})()');
  check(await evaluate('document.querySelectorAll("#results a").length') === 0, 'empty search results');
  await command('Emulation.setDeviceMetricsOverride', {width:390,height:844,deviceScaleFactor:1,mobile:true});
  await sleep(200);
  check(await evaluate('document.documentElement.scrollWidth <= innerWidth'), 'mobile has no horizontal overflow');
  const mobile = await command('Page.captureScreenshot', {format:'png',captureBeyondViewport:true});
  await fs.writeFile(path.join(output, 'wiki-mobile.png'), Buffer.from(mobile.data, 'base64'));
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
