#!/usr/bin/env node
// Rebuild platform icon containers and web sizes from the approved, unmodified
// game/icon.png. Requires Node.js and sharp (npm install --no-save sharp).
// Resize the approved pixels and typeset the splash title, preserving alpha.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'game/icon.png');
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
const outputs = {};
async function save(name, data) {
  const destination = path.join(root, name);
  fs.mkdirSync(path.dirname(destination), {recursive: true});
  fs.writeFileSync(destination, data);
  outputs[name] = sha(data);
}
async function png(size) {
  return sharp(source).resize(size, size, {kernel: 'lanczos3'}).png().toBuffer();
}
const splashLayout = {
  canvas_size: 1024,
  logo_size: 512,
  title: 'Cursed Lands',
  font: 'game/fonts/LiberationSerif-Regular.ttf',
  font_size: 72,
  color: '#e4d7a7',
  gap: 32,
};
async function splash() {
  const layout = splashLayout;
  const logo = await png(layout.logo_size);
  const title = await sharp({text: {
    text: '<span foreground="' + layout.color + '">' + layout.title + '</span>',
    font: 'Liberation Serif ' + layout.font_size,
    fontfile: path.join(root, layout.font),
    rgba: true,
  }}).png().toBuffer({resolveWithObject: true});
  const top = Math.floor((layout.canvas_size - layout.logo_size - layout.gap - title.info.height) / 2);
  return sharp({create: {
    width: layout.canvas_size, height: layout.canvas_size, channels: 4,
    background: {r: 0, g: 0, b: 0, alpha: 0},
  }}).composite([
    {input: logo, left: (layout.canvas_size - layout.logo_size) / 2, top},
    {input: title.data, left: Math.floor((layout.canvas_size - title.info.width) / 2),
      top: top + layout.logo_size + layout.gap},
  ]).png().toBuffer();
}
async function main() {
  const metadata = await sharp(source).metadata();
  if (metadata.width !== metadata.height) throw new Error('The approved master must be square.');
  if (!metadata.hasAlpha) throw new Error('The approved icon must retain its transparent background.');
  const sourceHash = sha(fs.readFileSync(source));
  // Refresh GitHub's cached README image whenever the approved master changes.
  const readmePath = path.join(root, 'README.md');
  const readme = fs.readFileSync(readmePath, 'utf8');
  fs.writeFileSync(readmePath, readme.replace(/src="(?:https:\/\/raw\.githubusercontent\.com\/TheWWWorm\/CursedLands\/main\/)?game\/icon\.png(?:\?v=[a-f0-9]+)?"/,
    'src="https://raw.githubusercontent.com/TheWWWorm/CursedLands/main/game/icon.png?v=' + sourceHash.slice(0, 12) + '"'));
  const sizes = [16, 24, 32, 48, 64, 128, 256];
  const frames = await Promise.all(sizes.map(png));
  const directory = Buffer.alloc(6 + sizes.length * 16);
  directory.writeUInt16LE(1, 2);
  directory.writeUInt16LE(sizes.length, 4);
  let offset = directory.length;
  for (let i = 0; i < sizes.length; i++) {
    const at = 6 + i * 16;
    directory[at] = directory[at + 1] = sizes[i] === 256 ? 0 : sizes[i];
    directory.writeUInt16LE(1, at + 4);
    directory.writeUInt16LE(32, at + 6);
    directory.writeUInt32LE(frames[i].length, at + 8);
    directory.writeUInt32LE(offset, at + 12);
    offset += frames[i].length;
  }
  await save('game/assets/branding/icon.ico', Buffer.concat([directory, ...frames]));

  const chunks = [];
  for (const [type, size] of [['icp4',16], ['icp5',32], ['icp6',64], ['ic07',128], ['ic08',256], ['ic09',512], ['ic10',1024]]) {
    const data = await png(size);
    const header = Buffer.alloc(8);
    header.write(type);
    header.writeUInt32BE(data.length + 8, 4);
    chunks.push(header, data);
  }
  const icns = Buffer.alloc(8);
  icns.write('icns');
  icns.writeUInt32BE(8 + chunks.reduce((sum, chunk) => sum + chunk.length, 0), 4);
  await save('game/assets/branding/icon.icns', Buffer.concat([icns, ...chunks]));

  const splashImage = await splash();
  await save('game/assets/branding/splash.png', splashImage);
  await save('public/index.png', splashImage);

  for (const [name, size] of [
    ['public/index.icon.png', 64],
    ['public/index.apple-touch-icon.png', 180],
    ['public/icon-192.png', 192],
    ['public/icon-512.png', 512],
  ]) await save(name, await png(size));

  // Wiki updates are independent of the installed game's service-worker cache.
  for (const name of ['web/wiki/index.html', 'public/wiki/index.html']) {
    const file = path.join(root, name);
    fs.writeFileSync(file, fs.readFileSync(file, 'utf8').replace(
      /((?:src|href)="\/(?:icon-192|index\.icon)\.png)(?:\?v=[a-f0-9]+)?"/g,
      '$1?v=' + sourceHash.slice(0, 12) + '"'));
  }

  const publicDir = path.join(root, 'public');
  const workerPath = path.join(publicDir, 'service-worker.js');
  let worker = fs.readFileSync(workerPath, 'utf8');
  const hashesMatch = worker.match(/const HASHES = (\{[\s\S]*?\});/);
  if (!hashesMatch) throw new Error('Web cache manifest not found.');
  const hashes = JSON.parse(hashesMatch[1]);
  delete hashes['icon-maskable-512.png'];
  const cacheDigest = crypto.createHash('sha256');
  for (const name of Object.keys(hashes).sort()) {
    let data;
    if (name === 'index.wasm' && !fs.existsSync(path.join(publicDir,name))) {
      const parts = JSON.parse(fs.readFileSync(path.join(root,'parts.json'),'utf8'));
      // The deployed WASM is split; reconstruct only for computing its digest.
      const entry = parts[name] || parts['/' + name];
      if (!entry) throw new Error('Split WASM manifest missing.');
      const files = Array.isArray(entry) ? entry : entry.parts || Array.from({length:entry.count}, (_, i) => name + '.part' + i);
      if (!Array.isArray(files)) throw new Error('Unsupported split WASM manifest.');
      data = Buffer.concat(files.map(part => fs.readFileSync(path.join(publicDir,part))));
    } else data = fs.readFileSync(path.join(publicDir,name));
    hashes[name] = sha(data);
    cacheDigest.update(data);
  }
  const orderedHashes = Object.fromEntries(Object.keys(hashes).sort().map(name => [name,hashes[name]]));
  worker = worker.replace(/const HASHES = \{[\s\S]*?\};/, 'const HASHES = ' + JSON.stringify(orderedHashes,null,2) + ';')
    .replace(/const ENGINE_CACHE = '[^']+';/, "const ENGINE_CACHE = 'cursed-engine-2-" + cacheDigest.digest('hex').slice(0,20) + "';");
  fs.writeFileSync(workerPath, worker);
  const manifest = {
    approved_date: '2026-10-19',
    source: 'game/icon.png',
    source_sha256: sourceHash,
    approved_opaque_source_sha256: '5c19c62e46918724753142c6950f4c22e7683d8313f7be82a6f5315e224a9d04',
    source_dimensions: [metadata.width,metadata.height],
    artwork: 'Approved Cursed Lands copper-and-gold dragon CL monogram',
    generation: 'Built-in image_gen background removal from the approved artwork, requested on 2026-10-19',
    transparency: 'Keep the background and open spaces transparent on the website, GitHub and native icons.',
    derivatives: 'Lanczos resizing and platform file conversion with the alpha channel preserved',
    splash: {...splashLayout,
      scaling: 'Keep aspect ratio; the logo occupies half the shorter window dimension, with the title below. The group is centered.'},
    regenerate: 'node tools/generate_branding.cjs',
    packaging: {
      windows: 'Use the Windows export preset with application/modify_resources enabled. When using a qualified custom engine, set custom_template/release to that engine and export the executable; exporting only the PCK does not replace the Explorer icon.',
      macos: 'The macOS preset embeds assets/branding/icon.icns in the application bundle.',
      android: 'Godot uses application/config/icon for the launcher and adaptive foreground when the Android preset has no override.',
      staging: 'Copy game/icon.png and game/assets/branding along with the project. Resolve the project icon from config/icon instead of hardcoding icon.svg.',
      web: 'Regenerate web icon sizes and the service-worker hashes after changing the approved master.'
    },
    files: outputs
  };
  fs.mkdirSync(path.join(root,'docs/branding'), {recursive:true});
  fs.writeFileSync(path.join(root,'docs/branding/icon.json'),JSON.stringify(manifest,null,2)+'\n');
  console.log('Generated '+Object.keys(outputs).length+' icon assets; master '+manifest.source_sha256);
}
main().catch(error => {console.error(error);process.exitCode = 1;});

