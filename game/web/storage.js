'use strict';
// The page imports data and the independent data worker reads bounded ranges.
const DATA_DB = 'cursed-lands-data-v1';
function openData() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATA_DB, 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore('files');
      request.result.createObjectStore('meta');
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}
function requestResult(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}
async function getMeta(key) {
  const db = await openData();
  try { return await requestResult(db.transaction('meta').objectStore('meta').get(key)); }
  finally { db.close(); }
}
async function putData(store, key, value) {
  const db = await openData();
  try {
    await new Promise((resolve, reject) => {
      const transaction = db.transaction(store, 'readwrite');
      transaction.objectStore(store).put(value, key);
      transaction.oncomplete = resolve;
      transaction.onabort = () => reject(transaction.error || new Error('Storage write aborted.'));
      transaction.onerror = () => reject(transaction.error);
    });
  } finally { db.close(); }
}
function cleanPath(name) {
  const path = name.replaceAll('\\', '/').toLowerCase();
  if (!path || path.startsWith('/') || path.split('/').some(p => !p || p === '.' || p === '..') || path.includes(':'))
    throw new Error('Invalid data path.');
  return path;
}
const REQUIRED_DATA = ['res/textures.res', 'res/figures.res', 'res/redress.res',
  'res/database.res', 'res/texts.res', 'maps/zone1.mpr', 'maps/zone1.mob'];
function validateIndex(files, payloadSize = Infinity) {
  if (!files || typeof files !== 'object' || Array.isArray(files)) throw new Error('Invalid data index.');
  const entries = Object.entries(files);
  if (!entries.length || entries.length > 20000) throw new Error('Invalid file count.');
  let end = 0;
  for (const [path, item] of entries.sort((a, b) => a[1].offset - b[1].offset)) {
    if (cleanPath(path) !== path || !Number.isSafeInteger(item.size) || item.size < 0 || item.size > 2 * 1024 * 1024 * 1024 ||
        !Number.isSafeInteger(item.offset) || item.offset < end || item.offset + item.size > payloadSize)
      throw new Error('Invalid data range: ' + path);
    end = item.offset + item.size;
  }
  for (const path of REQUIRED_DATA) if (!files[path]) throw new Error('Missing ' + path);
  return files;
}

// Store the active game and both installed editions in one transaction.
async function putLibrary(active, library) {
  const db = await openData();
  try {
    await new Promise((resolve, reject) => {
      const tx = db.transaction('meta', 'readwrite'), meta = tx.objectStore('meta');
      if (active) meta.put(active, 'active'); else meta.delete('active');
      meta.put(library, 'library');
      tx.oncomplete = resolve; tx.onabort = () => reject(tx.error);
    });
  } finally { db.close(); }
}

// Identify story data exactly as CampaignProfile does, before committing an
// import to its tab. This reads bounded ranges of texts.res, not executables.
async function campaignFromTexts(blob) {
  const range = async (at, size) => {
    if (at < 0 || size < 0 || at + size > blob.size || size > 32 * 1024 * 1024) throw new Error('Damaged game archive: res/texts.res');
    return new Uint8Array(await blob.slice(at, at + size).arrayBuffer());
  };
  const header = new DataView((await range(0, 16)).buffer);
  if (header.getUint32(0, true) !== 0x019ce23c) throw new Error('Damaged game archive: res/texts.res');
  const count = header.getUint32(4, true), at = header.getUint32(8, true), names = header.getUint32(12, true);
  if (count > 1000000 || names > 16777216) throw new Error('Damaged game archive: res/texts.res');
  const bytes = await range(at, count * 22 + names), table = new DataView(bytes.buffer), decoder = new TextDecoder('windows-1252');
  let map = '';
  for (let i = 0; i < count; i++) {
    const entry = i * 22, offset = table.getUint32(entry + 8, true), size = table.getUint32(entry + 4, true);
    const start = count * 22 + table.getUint32(entry + 18, true), length = table.getUint16(entry + 16, true);
    if (offset + size > blob.size || start + length > bytes.length) throw new Error('Damaged game archive: res/texts.res');
    if (decoder.decode(bytes.subarray(start, start + length)).toLowerCase() === 'map.txt') map = decoder.decode(await range(offset, size));
  }
  let zone = '', directive = '', first = '', jigran = false;
  for (const raw of map.split('\n')) {
    const line = raw.split('//')[0].trim().toLowerCase(), words = line.split(/\s+/);
    if (!line || line.startsWith('##')) continue;
    if (line[0] === '#') {
      directive = words[0];
      if (directive === '#zone') zone = words[1];
      if (directive === '#allod') { jigran ||= words[1] === 'jigran'; zone = ''; }
    } else if (directive === '#res' && zone === 'gz1g') first = words[0];
  }
  return first === 'zonezero' && jigran ? 'lost_in_astral' : 'cursed_lands';
}

async function campaignForInstall(active) {
  const db = await openData();
  let blob;
  try { blob = await requestResult(db.transaction('files').objectStore('files').get(active.id + '/' + (active.pack ? 'pack' : 'res/texts.res'))); }
  finally { db.close(); }
  if (!blob) throw new Error('Missing res/texts.res');
  const entry = active.files['res/texts.res'];
  return campaignFromTexts(active.pack ? blob.slice(active.payload + entry.offset, active.payload + entry.offset + entry.size) : blob);
}
