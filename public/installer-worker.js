'use strict';
// Unpacks the GOG installer (setup_evil_islands_*.exe, Inno Setup 5.5
// unicode) in the browser without running it, like src/ei/inno_setup.gd and
// src/ei/lzma.gd do on desktop and Android. The installer is only read in
// bounded ranges; one game file at a time is decoded in memory and stored in
// IndexedDB under the import's id, exactly like a folder import.
//   in:  {file: File, id}
//   out: {type: 'progress', key, arg} | {type: 'done', files} | {type: 'error', key, arg}
importScripts('storage.js');

const OFFSET_MAGIC = [0x72, 0x44, 0x6c, 0x50, 0x74, 0x53, 0xcd, 0xe6, 0xd7, 0x7b, 0x0b, 0x2a];
const CHUNK_MAGIC = [0x7a, 0x6c, 0x62, 0x1a];   // "zlb\x1a"
const DATA_ENTRY = 74;
const FLAG_CALL_FILTER = 1 << 4, FLAG_COMPRESSED = 1 << 7;
// The browser keeps what a folder import keeps (see files.js).
const DATA_DIRS = ['res', 'maps', 'config', 'stream', 'movies'];
const reader = new FileReaderSync();

class ImportError extends Error {
  constructor(key, arg) { super(key); this.key = key; this.arg = arg; }
}
function read(file, start, length) {
  if (start < 0 || start + length > file.size) throw new ImportError('Could not read the selected installer.');
  return new Uint8Array(reader.readAsArrayBuffer(file.slice(start, start + length)));
}
function u64(view, at) { return view.getUint32(at, true) + view.getUint32(at + 4, true) * 4294967296; }
function find(bytes, pattern) {
  for (let i = bytes.indexOf(pattern[0]); i >= 0 && i + pattern.length <= bytes.length; i = bytes.indexOf(pattern[0], i + 1)) {
    let k = 1;
    while (k < pattern.length && bytes[i + k] === pattern[k]) k++;
    if (k === pattern.length) return i;
  }
  return -1;
}

// ---------------------------------------------------------------- LZMA
// LZMA1 / LZMA2 decoder after the reference LzmaSpec.cpp (LZMA2 framing as
// in xz). Inno compresses its header with LZMA1 and the files with LZMA2.
const IS_REP = 192, IS_REP_G0 = 204, IS_REP_G1 = 216, IS_REP_G2 = 228, IS_REP0_LONG = 240;
const POS_SLOT = 432, POS_DEC = 688, ALIGN = 803, LEN = 819, REP_LEN = 1333;
const TOP = 16777216;

class Lzma {
  constructor(out) { this.out = out; this.o = 0; }
  props(d) { this.lc = d % 9; d = Math.floor(d / 9); this.lp = d % 5; this.pb = Math.floor(d / 5); }
  reset() {
    this.lit = new Uint16Array(0x300 << (this.lc + this.lp)).fill(1024);
    this.p = new Uint16Array(1847).fill(1024);
    this.state = 0; this.rep0 = this.rep1 = this.rep2 = this.rep3 = 0;
  }
  byte() { return this.sp < this.send ? this.buf[this.sp++] : (this.sp++, 0); }
  initRc() {
    this.rng = 0xFFFFFFFF; this.code = 0; this.sp++;
    for (let i = 0; i < 4; i++) this.code = this.code * 256 + this.byte();
  }
  bit(p, i) {
    const prob = p[i], bound = (this.rng >>> 11) * prob;
    let b = 0;
    if (this.code < bound) { this.rng = bound; p[i] = prob + ((2048 - prob) >> 5); }
    else { this.rng -= bound; this.code -= bound; p[i] = prob - (prob >> 5); b = 1; }
    if (this.rng < TOP) { this.rng *= 256; this.code = this.code * 256 + this.byte(); }
    return b;
  }
  tree(base, bits) {
    let m = 1;
    for (let i = 0; i < bits; i++) m = (m << 1) + this.bit(this.p, base + m);
    return m - (1 << bits);
  }
  rtree(base, bits) {
    let m = 1, sym = 0;
    for (let i = 0; i < bits; i++) { const b = this.bit(this.p, base + m); m = (m << 1) + b; sym |= b << i; }
    return sym;
  }
  direct(bits) {
    let res = 0;
    for (let i = 0; i < bits; i++) {
      this.rng = this.rng >>> 1;
      let b = 0;
      if (this.code >= this.rng) { this.code -= this.rng; b = 1; }
      res = res * 2 + b;
      if (this.rng < TOP) { this.rng *= 256; this.code = this.code * 256 + this.byte(); }
    }
    return res;
  }
  len(base, posState) {
    if (this.bit(this.p, base) === 0) return this.tree(base + 2 + (posState << 3), 3);
    if (this.bit(this.p, base + 1) === 0) return 8 + this.tree(base + 2 + 128 + (posState << 3), 3);
    return 16 + this.tree(base + 2 + 256, 8);
  }
  grow(n) {
    const out = new Uint8Array(Math.max(n, this.out.length * 2));
    out.set(this.out); this.out = out; return out;
  }
  // Decodes up to oEnd, or with `unknown` until the end marker / the input runs out.
  run(oEnd, unknown) {
    const p = this.p, lit = this.lit, lc = this.lc;
    const pbMask = (1 << this.pb) - 1, lpMask = (1 << this.lp) - 1;
    let o = this.o, out = this.out;
    while (unknown || o < oEnd) {
      if (unknown && this.sp > this.send + 4) break;
      const posState = o & pbMask, st = this.state;
      if (this.bit(p, (st << 4) + posState) === 0) {
        if (o >= out.length) out = this.grow(o + 1);
        const prev = o > 0 ? out[o - 1] : 0;
        const base = 0x300 * (((o & lpMask) << lc) + (prev >> (8 - lc)));
        let sym = 1;
        if (st >= 7) {
          let mb = out[o - this.rep0 - 1];
          while (sym < 0x100) {
            const mbit = (mb >> 7) & 1; mb <<= 1;
            const b = this.bit(lit, base + ((1 + mbit) << 8) + sym);
            sym = (sym << 1) | b;
            if (mbit !== b) break;
          }
        }
        while (sym < 0x100) sym = (sym << 1) | this.bit(lit, base + sym);
        out[o++] = sym - 0x100;
        this.state = st < 4 ? 0 : st < 10 ? st - 3 : st - 6;
        continue;
      }
      let len;
      if (this.bit(p, IS_REP + st)) {
        if (o === 0) throw new Error('LZMA: rep before any output');
        if (this.bit(p, IS_REP_G0 + st) === 0) {
          if (this.bit(p, IS_REP0_LONG + (st << 4) + posState) === 0) {
            this.state = st < 7 ? 9 : 11;
            if (o >= out.length) out = this.grow(o + 1);
            out[o] = out[o - this.rep0 - 1]; o++;
            continue;
          }
        } else {
          let dist;
          if (this.bit(p, IS_REP_G1 + st) === 0) dist = this.rep1;
          else {
            if (this.bit(p, IS_REP_G2 + st) === 0) dist = this.rep2;
            else { dist = this.rep3; this.rep3 = this.rep2; }
            this.rep2 = this.rep1;
          }
          this.rep1 = this.rep0; this.rep0 = dist;
        }
        len = this.len(REP_LEN, posState);
        this.state = st < 7 ? 8 : 11;
      } else {
        this.rep3 = this.rep2; this.rep2 = this.rep1; this.rep1 = this.rep0;
        len = this.len(LEN, posState);
        this.state = st < 7 ? 7 : 10;
        const slot = this.tree(POS_SLOT + (Math.min(len, 3) << 6), 6);
        if (slot < 4) this.rep0 = slot;
        else {
          const nd = (slot >> 1) - 1;
          let dist = (2 | (slot & 1)) * 2 ** nd;
          if (slot < 14) dist += this.rtree(POS_DEC + dist - slot, nd);
          else dist += this.direct(nd - 4) * 16 + this.rtree(ALIGN, 4);
          this.rep0 = dist;
          if (dist === 0xFFFFFFFF) break;   // end marker
        }
      }
      len += 2;
      if (this.rep0 >= o) throw new Error('LZMA: distance beyond output');
      let need = o + len;
      if (unknown) { if (need > out.length) out = this.grow(need); }
      else need = Math.min(need, oEnd);
      let from = o - this.rep0 - 1;
      if (this.rep0 + 1 >= len) { out.copyWithin(o, from, from + need - o); o = need; }
      else while (o < need) out[o++] = out[from++];
    }
    this.o = o;
    return o;
  }
}

// LZMA1 with unknown size (Inno's header blocks): 5 property bytes, then the stream.
function lzma1(src) {
  const d = new Lzma(new Uint8Array(Math.max(src.length * 8, 65536)));
  d.buf = src; d.sp = 5; d.send = src.length;
  d.props(src[0]); d.reset(); d.initRc();
  return d.out.subarray(0, d.run(0, true));
}

// LZMA2 of known output size, read from the installer in bounded windows
// (an LZMA2 chunk holds at most 64 KiB of input).
function lzma2(file, start, packed, size, report) {
  const d = new Lzma(new Uint8Array(size));
  const end = start + packed;
  let base = start;
  d.buf = new Uint8Array(0); d.sp = 0; d.send = 0;
  const ensure = n => {
    if (d.sp + n <= d.buf.length || base + d.buf.length >= end) return;
    base += d.sp;
    d.buf = read(file, base, Math.min(Math.max(n, 1 << 20), end - base));
    d.sp = 0; d.send = d.buf.length;
  };
  ensure(1); d.sp = 1;   // Inno's dictionary-size byte
  while (d.o < size) {
    ensure(6);
    const c = d.byte();
    if (c === 0) break;
    if (c < 0x80) {
      // Stored chunk (1: dictionary reset, 2: none).
      const n = ((d.byte() << 8) | d.byte()) + 1;
      ensure(n);
      if (d.o + n > size || d.sp + n > d.buf.length) throw new Error('LZMA2: bad stored chunk');
      d.out.set(d.buf.subarray(d.sp, d.sp + n), d.o);
      d.sp += n; d.o += n;
    } else {
      const usize = (((c & 0x1F) << 16) | (d.byte() << 8) | d.byte()) + 1;
      const psize = ((d.byte() << 8) | d.byte()) + 1;
      const mode = (c >> 5) & 3;
      if (mode >= 2) { ensure(1); d.props(d.byte()); }
      if (mode >= 1) d.reset();
      ensure(psize);
      const next = d.sp + psize;
      d.initRc();
      d.run(Math.min(d.o + usize, size), false);
      d.sp = next;
    }
    report(d.o);
  }
  if (d.o !== size) throw new Error('LZMA2: short output');
  return d.out;
}

// ---------------------------------------------------------------- header

// One setup-0 block: CRC, size, compressed flag, then 4096-byte pieces each after its CRC32.
function block(file, at) {
  const head = read(file, at, 9), view = new DataView(head.buffer);
  const size = view.getUint32(4, true), packed = head[8] !== 0;
  const raw = read(file, at + 9, size), body = new Uint8Array(size);
  let n = 0;
  for (let p = 0; p + 4 < raw.length; p += 4096 + 4) {
    const piece = raw.subarray(p + 4, Math.min(p + 4 + 4096, raw.length));
    body.set(piece, n); n += piece.length;
  }
  return {bytes: packed ? lzma1(body.subarray(0, n)) : body.subarray(0, n), next: at + 9 + size};
}

const utf16 = new TextDecoder('utf-16le');
function entry(h, view, q, chunkCount) {
  let dest = '';
  for (let k = 0; k < 10; k++) {
    if (q + 4 > h.length) return null;
    const n = view.getUint32(q, true);
    if (n > 8000 || n % 2 || q + 4 + n > h.length) return null;
    if (k === 1) dest = utf16.decode(h.subarray(q + 4, q + 4 + n));
    q += 4 + n;
  }
  q += 20;
  if (q + 23 > h.length) return null;
  const loc = view.getUint32(q, true);
  if ((loc >= chunkCount && loc !== 0xFFFFFFFF) || h[q + 22] > 3) return null;
  return {dest, loc, next: q + 23};
}

// File entries are found as the longest run of well-formed entries that starts
// at a "{app}" destination (see inno_setup.gd).
function findFiles(h, chunks) {
  const view = new DataView(h.buffer, h.byteOffset, h.length);
  const app = [0x7b, 0, 0x61, 0, 0x70, 0, 0x70, 0, 0x7d, 0];   // "{app}" in UTF-16
  let bestStart = -1, bestN = 0, covered = -1;
  for (let i = 8; i < h.length - app.length; i++) {
    if (h[i] !== 0x7b || h[i + 1] !== 0 || h[i + 2] !== 0x61 || i - 8 <= covered) continue;
    let k = 3;
    while (k < app.length && h[i + k] === app[k]) k++;
    if (k < app.length) continue;
    let q = i - 8, n = 0;
    for (let r; (r = entry(h, view, q, chunks.length)); q = r.next) n++;
    if (n > bestN) { bestN = n; bestStart = i - 8; }
    if (n > 0) covered = q;
  }
  const files = [], seen = new Set();
  for (let q = bestStart, r; bestStart >= 0 && (r = entry(h, view, q, chunks.length)); q = r.next) {
    let name = r.dest;
    if (!name.startsWith('{app}\\') || name.endsWith('\\') || r.loc >= chunks.length) continue;
    // Lower case: Windows paths are case-insensitive and the editions differ.
    name = name.slice(6).replaceAll('\\', '/').toLowerCase();
    if (name.startsWith('__support/') || seen.has(name)) continue;
    if (chunks[r.loc].flags & FLAG_CALL_FILTER || /\.(exe|dll|asi)$/.test(name)) continue;   // never read
    seen.add(name);
    files.push({name, chunk: r.loc});
  }
  return files;
}

function readHeader(file) {
  const head = read(file, 0, Math.min(file.size, 8 << 20));
  const at = find(head, OFFSET_MAGIC);
  if (at < 0) throw new ImportError('Not an Inno Setup installer (no offset table).');
  const table = new DataView(head.buffer, at + 12);
  if (table.getUint32(0, true) !== 1) throw new ImportError('Unsupported installer loader.');
  const offset0 = table.getUint32(20, true), offset1 = table.getUint32(24, true);
  const version = new TextDecoder('latin1').decode(read(file, offset0, 64)).replace(/\0.*$/s, '');
  if (!version.startsWith('Inno Setup Setup Data (5.5')) throw new ImportError('Unsupported installer version: %s', version);
  let header, data;
  try {
    const first = block(file, offset0 + 64);
    header = first.bytes; data = block(file, first.next).bytes;
  } catch (error) { throw new ImportError('Could not read the installer header.'); }
  if (!header.length || !data.length) throw new ImportError('Could not read the installer header.');
  const view = new DataView(data.buffer, data.byteOffset, data.length), chunks = [];
  for (let e = 0; e + DATA_ENTRY <= data.length; e += DATA_ENTRY)
    chunks.push({start: view.getUint32(e + 8, true), sub: u64(view, e + 12), size: u64(view, e + 20),
      packed: u64(view, e + 28), sha1: data.slice(e + 36, e + 56), flags: view.getUint16(e + 72, true)});
  const files = findFiles(header, chunks).filter(f => DATA_DIRS.includes(f.name.split('/')[0]));
  if (!files.length) throw new ImportError('No game files found in the installer.');
  for (const path of REQUIRED_DATA)
    if (!files.some(f => f.name === path)) throw new ImportError('The installer does not contain %s.', path);
  return {offset1, chunks, files};
}

// ---------------------------------------------------------------- import

async function unpack(file, id) {
  post({type: 'progress', key: 'Reading the installer…'});
  const {offset1, chunks, files} = readHeader(file);
  const byChunk = new Map();
  for (const f of files) byChunk.set(f.chunk, [...(byChunk.get(f.chunk) || []), f.name]);
  const order = [...byChunk.keys()].sort((a, b) => chunks[a].start - chunks[b].start);
  let total = 0, stored = 0;
  for (const c of order) { total += chunks[c].size; stored += chunks[c].size * byChunk.get(c).length; }
  const estimate = await self.navigator.storage?.estimate?.().catch(() => null);
  if (estimate?.quota && estimate.quota - estimate.usage < stored * 1.05)
    throw new ImportError('Not enough browser storage for this import. Free space and try again.');
  const index = {};
  let offset = 0, written = 0, last = 0;
  const report = done => {
    const now = Date.now();
    if (now - last < 200) return;
    last = now;
    post({type: 'progress', key: 'Unpacking installer: %d%%', arg: Math.floor((written + done) * 100 / Math.max(1, total))});
  };
  for (const c of order) {
    const chunk = chunks[c], at = offset1 + chunk.start;
    if (find(read(file, at, 4), CHUNK_MAGIC) !== 0) throw new ImportError('Bad data chunk %d in the installer.', c);
    const size = chunk.sub + chunk.size;
    let out;
    try {
      out = chunk.flags & FLAG_COMPRESSED ? lzma2(file, at + 4, chunk.packed, size, report) : read(file, at + 4, size);
    } catch (error) {
      if (error instanceof ImportError) throw error;
      throw new ImportError('Bad data chunk %d in the installer.', c);
    }
    out = out.subarray(chunk.sub, size);
    const sha1 = new Uint8Array(await crypto.subtle.digest('SHA-1', out));
    if (sha1.some((b, i) => b !== chunk.sha1[i])) throw new ImportError('Checksum mismatch in the installer (chunk %d).', c);
    const blob = new Blob([out]);
    out = null;
    for (const name of byChunk.get(c)) {
      await putData('files', id + '/' + name, blob);
      index[name] = {size: blob.size, offset}; offset += blob.size;
    }
    written += chunk.size;
    report(0);
  }
  return validateIndex(index);
}

function post(message) { self.postMessage(message); }

self.onmessage = async ({data}) => {
  try {
    post({type: 'done', files: await unpack(data.file, data.id)});
  } catch (error) {
    if (error instanceof ImportError) post({type: 'error', key: error.key, arg: error.arg});
    else if (error?.name === 'QuotaExceededError') post({type: 'error', key: 'Browser storage is full. Free space and try again.'});
    else post({type: 'error', key: 'The installer could not be unpacked: %s', arg: String(error?.message || error)});
  }
};
