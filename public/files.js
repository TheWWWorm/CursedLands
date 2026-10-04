'use strict';
window.CursedFiles = {
  active: null, busy: false, generation: 0, cache: new Map(), cacheBytes: 0,
  // Resolves once the service worker holds the engine (onProgress(loaded,
  // total) follows its download) and the local data store is open.
  async initialize(onProgress) {
    if (!isSecureContext || !('serviceWorker' in navigator)) throw new Error('Open the game over HTTPS or localhost.');
    if (!crossOriginIsolated || typeof SharedArrayBuffer === 'undefined')
      throw new Error('This host must send Cross-Origin-Opener-Policy: same-origin and Cross-Origin-Embedder-Policy: require-corp. A current browser is required.');
    const container = navigator.serviceWorker;
    container.addEventListener('message', ({data}) => {
      if (data?.type === 'progress' && onProgress) onProgress(data.loaded, data.total);
    });
    container.startMessages();
    const registration = await container.register('service-worker.js');
    if (!registration.active) {
      // First visit: the worker downloads the engine before the game can start.
      const worker = registration.installing || registration.waiting;
      if (!worker) throw new Error('The game could not be downloaded. Check your connection and retry.');
      worker.postMessage('progress');
      await new Promise((resolve, reject) => {
        const check = () => {
          if (worker.state === 'activated') resolve();
          else if (worker.state === 'redundant') reject(new Error('The game could not be downloaded. Check your connection and retry.'));
        };
        worker.addEventListener('statechange', check); check();
      });
    }
    if (!container.controller) {
      // A forced reload bypasses the worker; the page asks to be controlled
      // again, and goes on without it rather than waiting forever.
      registration.active?.postMessage('claim');
      await Promise.race([new Promise(resolve => container.addEventListener('controllerchange', resolve, {once: true})),
        new Promise(resolve => setTimeout(resolve, 3000))]);
    }
    this.active = await getMeta('active');
    if (this.active) validateIndex(this.active.files);
    this.signal = new Int32Array(new SharedArrayBuffer(8));
    this.transfer = new Uint8Array(new SharedArrayBuffer(4 * 1024 * 1024));
    this.worker = new Worker('data-worker.js');
    await new Promise((resolve, reject) => {
      this.worker.onmessage = ({data}) => data.ready ? resolve() : reject(new Error(data.error));
      this.worker.onerror = event => reject(new Error(event.message));
      this.worker.postMessage({type: 'init', signal: this.signal.buffer, bytes: this.transfer.buffer});
    });
  },
  manifest_json() { return JSON.stringify(this.active ? this.active.files : {}); },
  read(path, offset, length) {
    const key = path + ':' + offset + ':' + length;
    if (this.cache.has(key)) {
      const bytes = this.cache.get(key); this.cache.delete(key); this.cache.set(key, bytes); return bytes;
    }
    try {
      // Godot's existing archive API is synchronous. Only the independent
      // data worker touches IndexedDB. A bounded shared mailbox bridges it to
      // the single-thread game; the install is never mirrored in WASM memory.
      if (!Number.isSafeInteger(length) || length < 0 || length > 128 * 1024 * 1024 || this.failed)
        throw new Error('Invalid range or unavailable data worker.');
      const bytes = new Uint8Array(length);
      for (let done = 0; done < length;) {
        const count = Math.min(this.transfer.length, length - done);
        Atomics.store(this.signal, 0, 0);
        this.worker.postMessage({type: 'read', path, offset: offset + done, length: count});
        const deadline = performance.now() + 20000;
        // Atomics.wait is unavailable on the browser main thread. Keep this
        // bounded: on timeout the mailbox is retired, never reused with a
        // late response. Reads happen during the engine's existing load work.
        while (Atomics.load(this.signal, 0) === 0) {
          if (performance.now() > deadline) { this.failed = true; this.worker.terminate(); throw new Error('Local storage timed out.'); }
        }
        if (Atomics.load(this.signal, 0) !== 1 || Atomics.load(this.signal, 1) !== count)
          throw new Error('Local data was removed or is incomplete.');
        bytes.set(this.transfer.subarray(0, count), done); done += count;
      }
      if (length <= 4 * 1024 * 1024) {
        while (this.cacheBytes + length > 16 * 1024 * 1024 && this.cache.size) {
          const oldest = this.cache.keys().next().value;
          this.cacheBytes -= this.cache.get(oldest).length; this.cache.delete(oldest);
        }
        this.cache.set(key, bytes); this.cacheBytes += length;
      }
      return bytes;
    } catch (error) {
      document.getElementById('runtime-error').textContent = 'Local game data could not be read. Reload and reimport if needed. ' + error.message;
      return null;
    }
  },
  choose(callback, folder) {
    if (this.busy) return;
    const input = document.createElement('input'); input.type = 'file';
    if (folder) { input.webkitdirectory = true; input.multiple = true; }
    // Phone pickers may grey out unknown extensions; the file is recognised by its contents.
    else if (!matchMedia('(pointer: coarse)').matches) input.accept = '.exe,.eipack';
    input.onchange = () => this.importFiles(Array.from(input.files), callback);
    input.click();
  },
  cancel() { this.generation++; if (this.stopUnpack) this.stopUnpack(); },
  // The GOG installer is unpacked in its own worker (installer-worker.js),
  // which reads it in bounded ranges and stores each game file under `id`.
  unpackInstaller(file, id, callback) {
    const worker = new Worker('installer-worker.js');
    return new Promise((resolve, reject) => {
      this.stopUnpack = () => reject(new Error('Import cancelled.'));
      worker.onmessage = ({data}) => {
        if (data.type === 'progress') callback('progress', data.key, data.arg);
        else if (data.type === 'done') resolve(data.files);
        else reject(Object.assign(new Error(data.key), {arg: data.arg}));
      };
      worker.onerror = event => { event.preventDefault(); reject(new Error(event.message || 'The installer could not be unpacked.')); };
      worker.postMessage({file, id});
    }).finally(() => { worker.terminate(); this.stopUnpack = null; });
  },
  async importFiles(selected, callback) {
    if (!selected.length || this.busy) return;
    this.busy = true; const generation = ++this.generation;
    let committed = false;
    const id = crypto.randomUUID();
    const current = () => { if (generation !== this.generation) throw new Error('Import cancelled.'); };
    try {
      callback('progress', 'Checking your local game files…');
      let files = {}, pack = false, payload = 0, unpacked = false;
      const single = selected.length === 1 ? selected[0] : null;
      const magic = single ? new TextDecoder().decode(await single.slice(0, 8).arrayBuffer()) : '';
      if (single && magic.startsWith('MZ')) {
        files = validateIndex(await this.unpackInstaller(single, id, callback)); unpacked = true;
      } else if (single && magic === 'EIPACK01') {
        const file = selected[0];
        const header = new Uint8Array(await file.slice(0, 12).arrayBuffer());
        const size = new DataView(header.buffer).getUint32(8, true);
        if (size < 2 || size > 4 * 1024 * 1024 || size + 12 > file.size) throw new Error('Invalid pack header.');
        payload = 12 + size;
        files = validateIndex(JSON.parse(await file.slice(12, payload).text()), file.size - payload); pack = true;
      } else if (single && !single.webkitRelativePath) {
        throw new Error('Choose the GOG installer (.exe), a data pack (.eipack) or the game folder.');
      } else {
        let offset = 0;
        for (const file of selected) {
          const parts = (file.webkitRelativePath || file.name).replaceAll('\\', '/').split('/');
          const start = parts.findIndex(p => ['res', 'maps', 'config', 'stream', 'movies', 'camera'].includes(p.toLowerCase()));
          if (start < 0) continue;
          const path = cleanPath(parts.slice(start).join('/'));
          if (files[path]) throw new Error('Duplicate data file: ' + path);
          files[path] = {size: file.size, offset, source: file}; offset += file.size;
        }
        validateIndex(files);
      }
      const bytes = pack ? selected[0].size : Object.values(files).reduce((n, f) => n + f.size, 0);
      const estimate = unpacked ? null : await navigator.storage?.estimate?.();
      if (estimate?.quota && estimate.quota - estimate.usage < bytes * 1.05) throw new Error('Not enough browser storage for this import. Free space and try again.');
      current();
      if (unpacked) { /* already stored by the installer worker */ }
      else if (pack) { callback('progress', 'Saving your data pack on this device…'); await putData('files', id + '/pack', selected[0]); }
      else {
        let done = 0;
        for (const [path, entry] of Object.entries(files)) {
          current(); callback('progress', 'Importing %s', path + ' (' + Math.round(done / bytes * 100) + '%)');
          await putData('files', id + '/' + path, entry.source); delete entry.source; done += entry.size;
        }
      }
      current();
      // Commit last. Cancelling or running out of space retains the old install.
      const active = {id, files, pack, payload};
      await putData('meta', 'active', active);
      committed = true;
      this.active = active; this.cache.clear(); this.cacheBytes = 0;
      const persistent = await Promise.resolve(navigator.storage?.persist?.()).catch(() => false);
      callback('complete', persistent ? 'Game data imported.' : 'Game data imported. Export saves regularly; browser storage may be cleared.');
      // Cleanup is best effort after commit. It must never roll back the
      // active install if another tab or the browser interrupts cleanup.
      await this.cleanup(id).catch(() => {});
    } catch (error) {
      if (!committed) await this.removeGeneration(id).catch(() => {});
      callback('error', error.name === 'QuotaExceededError' ? 'Browser storage is full. Free space and try again.' : String(error.message || error), error.arg);
    } finally { this.busy = false; }
  },
  // "Delete imported data" (Options): the active install and every stored
  // generation go; saves live in Godot's own storage and are kept. The page
  // then reloads into the setup screen (after the deletion, never during it).
  async forget() {
    if (this.busy) return;
    this.busy = true;
    try {
      const db = await openData();
      await new Promise((resolve, reject) => {
        const tx = db.transaction(['meta', 'files'], 'readwrite');
        tx.objectStore('meta').delete('active');
        tx.objectStore('files').clear();
        tx.oncomplete = resolve; tx.onabort = () => reject(tx.error);
      }); db.close();
      this.active = null; this.cache.clear(); this.cacheBytes = 0;
    } finally { this.busy = false; location.reload(); }
  },
  async removeGeneration(id) {
    const db = await openData();
    await new Promise((resolve, reject) => {
      const tx = db.transaction('files', 'readwrite');
      tx.objectStore('files').delete(IDBKeyRange.bound(id + '/', id + '/\uffff'));
      tx.oncomplete = resolve; tx.onabort = () => reject(tx.error);
    }); db.close();
  },
  async cleanup(keep) {
    const db = await openData();
    const keys = await requestResult(db.transaction('files').objectStore('files').getAllKeys()); db.close();
    for (const id of new Set(keys.map(key => key.split('/')[0]))) if (id !== keep) await this.removeGeneration(id);
  },
  insets() {
    const probe = document.getElementById('safe-probe'), style = getComputedStyle(probe);
    return JSON.stringify([parseFloat(style.paddingLeft) / innerWidth, parseFloat(style.paddingTop) / innerHeight,
      parseFloat(style.paddingRight) / innerWidth, parseFloat(style.paddingBottom) / innerHeight]);
  },
  fullscreen() {
    const canvas = document.documentElement;
    if (document.fullscreenElement) document.exitFullscreen();
    else if (canvas.requestFullscreen) canvas.requestFullscreen().catch(() => {});
    else alert('In Safari, use Share → Add to Home Screen → Open as Web App for a full-screen launch.');
  },
  chooseSave(callback) {
    const input = document.createElement('input'); input.type = 'file'; input.accept = '.eisaves';
    input.onchange = async () => {
      const file = input.files[0]; if (!file) return;
      if (file.size > 64 * 1024 * 1024) { callback('error', 'Save backup is too large.'); return; }
      try { callback('complete', await file.text()); }
      catch (error) { callback('error', 'Could not read the save backup: ' + error.message); }
    }; input.click();
  },
  download(name, text) {
    const url = URL.createObjectURL(new Blob([text], {type: 'application/json'}));
    const link = document.createElement('a'); link.href = url; link.download = name; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
  }
};
