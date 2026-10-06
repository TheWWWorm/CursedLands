'use strict';
importScripts('storage.js');
let signal, bytes;
const blobs = new Map();
self.onmessage = async ({data}) => {
  if (data.type === 'init') {
    signal = new Int32Array(data.signal);
    bytes = new Uint8Array(data.bytes);
    try { const db = await openData(); db.close(); self.postMessage({ready: true}); }
    catch (error) { self.postMessage({error: error.message}); }
    return;
  }
  if (data.type !== 'read') return;
  try {
    const active = data.campaign ? (await getMeta('library'))?.[data.campaign] : await getMeta('active');
    const entry = active?.files[cleanPath(data.path)];
    if (!entry || data.offset < 0 || data.length < 0 || data.offset + data.length > entry.size || data.length > bytes.length)
      throw new Error('Invalid local data range.');
    const key = active.id + '/' + (active.pack ? 'pack' : data.path);
    let blob = blobs.get(key);
    if (!blob) {
      const db = await openData();
      try { blob = await requestResult(db.transaction('files').objectStore('files').get(key)); }
      finally { db.close(); }
      if (!blob) throw new Error('Game data is no longer available.');
      if (blobs.size > 8) blobs.delete(blobs.keys().next().value);
      blobs.set(key, blob);
    }
    const start = (active.pack ? active.payload + entry.offset : 0) + data.offset;
    const slice = new Uint8Array(await blob.slice(start, start + data.length).arrayBuffer());
    bytes.set(slice);
    Atomics.store(signal, 1, slice.length);
    Atomics.store(signal, 0, 1);
  } catch (error) { Atomics.store(signal, 0, -1); }
};
