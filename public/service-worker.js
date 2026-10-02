'use strict';
// Replaced with content hashes and engine-only files by tools/export_mobile.py.
const ENGINE_CACHE = 'cursed-engine-ea5c7df14fac1ecf6294';
const ENGINE_FILES = ["data-worker.js", "files.js", "icon-192.png", "icon-512.png", "index.apple-touch-icon.png", "index.audio.position.worklet.js", "index.audio.worklet.js", "index.html", "index.icon.png", "index.js", "index.pck", "index.png", "index.wasm", "manifest.webmanifest", "storage.js"];
self.addEventListener('install', event => event.waitUntil((async () => {
  const cache = await caches.open(ENGINE_CACHE);
  await cache.addAll(ENGINE_FILES);
  // Existing games keep their worker until all their tabs close.
})()));
self.addEventListener('activate', event => event.waitUntil((async () => {
  for (const key of await caches.keys())
    if (key.startsWith('cursed-engine-') && key !== ENGINE_CACHE) await caches.delete(key);
  await self.clients.claim();
})()));
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin || event.request.method !== 'GET') return;
  // Only explicitly packaged engine files are cached. Private files are
  // accessed inside data-worker.js and never requested from the network.
  event.respondWith((async () => {
    const cache = await caches.open(ENGINE_CACHE);
    const key = event.request.mode === 'navigate' ? new URL('index.html', self.registration.scope).href : event.request;
    return (await cache.match(key)) || fetch(event.request);
  })());
});
