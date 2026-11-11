'use strict';
// Replaced with content hashes and engine-only files by tools/export_mobile.py.
// The "2" marks the cache layout that stores the shell under the scope URL;
// older caches stored a redirected copy of index.html and are deleted below.
const ENGINE_CACHE = 'cursed-engine-2-e0c95c06720dcf92af7d';
// Hosts may redirect /index.html to / (Cloudflare Workers assets do). A
// redirected response must never answer a navigation (the browser fails it
// with ERR_FAILED), so the shell is fetched and stored as "./".
const SHELL = new URL('./', self.registration.scope).href;
const HASHES = {
"data-worker.js": "fbd332570fb7109460a1e8c7f10a79012f37e02f12efef1d710dcb77f65582ae",
"files.js": "5c5ab8cf18d307f21732866ff9ea824d19a137cead0920ce2fd1db018c789a8d",
"icon-192.png": "0f2555619f403d73855f2d20beaf5cedd4a6ad3b92b0325f7f8da5f979dcceec",
"icon-512.png": "280a543feabeb6da1ae8f17e1452fa7a27537f2e1d2d261d6da9ce826f58a90d",
"index.apple-touch-icon.png": "1fa3fdee844f8a38b4a4d4c5908a53d857eaaf6950da1fa061fb5c1c2d46de41",
"index.audio.position.worklet.js": "be33985bc7160d6bf9646f259cd86b259cd67b02ccb297ee5c44f8ac84327bc8",
"index.audio.worklet.js": "5b476a9c9ce642c0ee4256436d1bc31d9c38f868aca0f9a8e2a57c18d2dec2a3",
"index.html": "e6a76f28f0ec0d8269ca544b767daed9e5cafa233ff2a1b0e57f8ce5016e0bfd",
"index.icon.png": "074eecd5dd87067e3f1b15c59c08fad1a700f431fe5c0b1cbc23f9a8b57aa8a4",
"index.js": "68586d6daafc93c6e697b3fb258976874aa7459b8931165ebb1dc3c9614cc42c",
"index.pck": "86018e1dd6aeec617e4351c3de43f827cb162f405b4600e5e44a872b26212c1b",
"index.png": "b9fe65d8c1b0bef09d7df97700ead5372582dc00851a24e53f4be3a839a48027",
"index.wasm": "7eda98958eb09135a1acb54a4323a00b1a55af1997f15fa1cdc2b93e3df46656",
"installer-worker.js": "147004bdaf5b7d80c0b9dffebca09cbc70e3d02a5c514743fbc5a1a68c9f8d8a",
"manifest.webmanifest": "959d316f9bd45b8d4c6cfd621aced7f55336f459e9472c3f5ce53fb9c7990ab5",
"storage.js": "f6b6f85e64975fdf1a90d95b76c4409eb9b5b82f9b043867969b0a394cd77129"
};   // file name → SHA-256
const ENGINE_FILES = Object.keys(HASHES).map(name => name === 'index.html' ? SHELL : new URL(name, SHELL).href);
let progress = {type: 'progress', loaded: 0, total: 0};
let lastBroadcast = 0;

async function broadcast(force) {
  if (!force && Date.now() - lastBroadcast < 150) return;
  lastBroadcast = Date.now();
  for (const client of await self.clients.matchAll({type: 'window', includeUncontrolled: true}))
    client.postMessage(progress);
}

async function sha256(blob) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', await blob.arrayBuffer())),
    b => b.toString(16).padStart(2, '0')).join('');
}

// An unchanged file (same SHA-256) is taken from the previous version's cache,
// so an update only downloads what changed.
async function reuse(url, hash) {
  for (const key of await caches.keys()) {
    if (!key.startsWith('cursed-engine-') || key === ENGINE_CACHE) continue;
    const old = await (await caches.open(key)).match(url);
    if (!old || old.redirected || old.type !== 'basic' && old.type !== 'default' || !old.ok) continue;
    const blob = await old.blob();
    if (await sha256(blob) !== hash) continue;
    const headers = new Headers(old.headers);
    headers.delete('Content-Encoding');
    headers.set('Content-Length', String(blob.size));
    return new Response(blob, {status: 200, statusText: 'OK', headers});
  }
  return null;
}

// A plain stored copy: never marked redirected, body already decoded, with
// the real Content-Length so the engine's loader shows true progress.
async function request(url, i) {
  const kept = await reuse(url, HASHES[Object.keys(HASHES)[i]]).catch(() => null);
  if (kept) return {kept};
  const response = await fetch(new Request(url, {cache: 'no-cache', credentials: 'same-origin'}));
  if (!response.ok || response.type !== 'basic') throw new Error('Could not download ' + url + ' (' + response.status + ')');
  return {response, length: Number(response.headers.get('Content-Length')) || 0};
}
async function receive({kept, response, length}) {
  if (kept) return kept;
  const reader = response.body.getReader(), parts = [];
  let size = 0;
  for (;;) {
    const {done, value} = await reader.read();
    if (done) break;
    parts.push(value); size += value.length; progress.loaded += value.length;
    if (!length) progress.total += value.length;
    broadcast(false);
  }
  if (length && size !== length) throw new Error('Incomplete download: ' + response.url);
  const headers = new Headers(response.headers);
  headers.delete('Content-Encoding');
  headers.set('Content-Length', String(size));
  return new Response(new Blob(parts), {status: 200, statusText: 'OK', headers});
}

self.addEventListener('install', event => event.waitUntil((async () => {
  const cache = await caches.open(ENGINE_CACHE);
  // All headers first, so the total (Content-Length) is known before progress is shown.
  const started = await Promise.all(ENGINE_FILES.map(request));
  for (const file of started) progress.total += file.length || 0;
  const copies = await Promise.all(started.map(receive));
  await Promise.all(copies.map((response, i) => cache.put(ENGINE_FILES[i], response)));
  progress.done = true; await broadcast(true);
  // Existing games keep their worker until all their tabs close. A page the
  // old worker failed to load is not a client, so this one then takes over.
})()));
self.addEventListener('activate', event => event.waitUntil((async () => {
  for (const key of await caches.keys())
    if (key.startsWith('cursed-engine-') && key !== ENGINE_CACHE) await caches.delete(key);
  await self.clients.claim();
})()));
self.addEventListener('message', event => {
  // A page loaded without the worker (e.g. a forced reload) asks to be controlled;
  // a page opened during the install asks for the download progress.
  if (event.data === 'claim') event.waitUntil(self.clients.claim());
  else if (event.data === 'progress' && event.source) event.source.postMessage(progress);
});
self.addEventListener('fetch', event => {
  const request = event.request, url = new URL(request.url);
  if (url.origin !== self.location.origin || request.method !== 'GET') return;
  let key = request;
  if (request.mode === 'navigate') {
    // Only the game page comes from the cache; other documents (the licence
    // files) load normally.
    const path = url.pathname, root = new URL(SHELL).pathname;
    if (path !== root && path !== root + 'index.html') return;
    key = SHELL;
  }
  // Only packaged engine files are cached. Private game files are read inside
  // data-worker.js and never requested from the network.
  event.respondWith((async () => {
    const cache = await caches.open(ENGINE_CACHE);
    const cached = await cache.match(key, {ignoreSearch: request.mode === 'navigate'});
    if (cached && !cached.redirected && cached.type !== 'opaqueredirect') return cached;
    const response = await fetch(request);
    // fetch() follows redirects for subresources; such a response is only
    // valid for them, never for a navigation.
    if (request.mode === 'navigate' && response.redirected)
      return new Response(response.body, {status: response.status, statusText: response.statusText, headers: response.headers});
    return response;
  })());
});
