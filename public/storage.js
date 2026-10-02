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
    if (cleanPath(path) !== path || !Number.isSafeInteger(item.size) || item.size < 0 || item.size > 512 * 1024 * 1024 ||
        !Number.isSafeInteger(item.offset) || item.offset < end || item.offset + item.size > payloadSize)
      throw new Error('Invalid data range: ' + path);
    end = item.offset + item.size;
  }
  for (const path of REQUIRED_DATA) if (!files[path]) throw new Error('Missing ' + path);
  return files;
}
