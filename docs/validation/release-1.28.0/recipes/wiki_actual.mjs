// Isolated real standalone-wiki UI with freshly exported tutorial articles.
// Run under GPU Lab. No website or profile is modified.
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require = createRequire(import.meta.url);
const {chromium} = require(process.env.PLAYWRIGHT_PATH || 'playwright');
const args = Object.fromEntries(process.argv.slice(2).map(v => v.replace(/^--/, '').split(/=(.*)/s).slice(0,2)));
const root = path.resolve(args.public);
const fixtures = JSON.parse(await fs.readFile(args.fixture, 'utf8'));
await fs.mkdir(args.output, {recursive:true});
const mime = {'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.json':'application/json','.png':'image/png','.webp':'image/webp','.svg':'image/svg+xml'};
const server = http.createServer(async (req,res) => {
  const url = new URL(req.url,'http://localhost');
  const m = url.pathname.match(/^\/wiki\/data\/(en|ru|de)\/(index\.json|pages\/([^/]+))$/);
  try {
    let data;
    if(false && m && m[2]==='index.json') {
      const index = JSON.parse(await fs.readFile(path.join(root,url.pathname),'utf8'));
      index.entries.push(...fixtures[m[1]].entries);
      index.categories['Getting started'] = fixtures[m[1]].category;
      data = JSON.stringify(index);
    } else if(false && m && fixtures[m[1]].pages[m[3]]) data = JSON.stringify(fixtures[m[1]].pages[m[3]]);
    else {
      const name = path.resolve(root,'.'+decodeURIComponent(url.pathname)+(url.pathname.endsWith('/')?'index.html':''));
      if(!name.startsWith(root+'/')) throw Error('bad path');
      data = await fs.readFile(name);
    }
    res.writeHead(200,{'Content-Type':mime[path.extname(url.pathname)] || 'text/html'});res.end(data);
  } catch {res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser = await chromium.launch({executablePath:args.chrome,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
const page = await browser.newPage({viewport:{width:1280,height:800}});
const errors=[];page.on('pageerror', e=>errors.push(e.message));
const checks=[];
const base=`http://127.0.0.1:${server.address().port}/wiki/`;
const heading = '#article h1, #article-heading h1';
async function ready(){await page.waitForFunction(()=>document.querySelector('#article h1, #article-heading h1') && document.querySelector('#notice').textContent==='');}
try {
  for(const campaign of ['cursed_lands','lost_in_astral']) for(const lang of ['en','ru','de']) {
    await page.goto(`${base}?campaign=${campaign}&lang=${lang}`);await ready();
    const link = page.locator('.home-paths a').filter({hasText:fixtures[lang].category});
    assert.equal(await link.count(),1);checks.push(`${campaign}/${lang}: home entry`);
    await link.click();await page.waitForURL(/page=guide%2Fzt1|page=guide\/zt1/);await ready();
    assert.equal(await page.locator(heading).textContent(),fixtures[lang].entries.find(e=>e.key==='guide/zt1').title);checks.push(`${campaign}/${lang}: opens tutorial`);
    await page.reload();await ready();assert.match(page.url(),/page=guide/);checks.push(`${campaign}/${lang}: reload`);
    await page.goto(`${base}?campaign=${campaign}&lang=${lang}&page=guide%2Fzt7`);await ready();
    assert.equal(await page.locator(heading).textContent(),fixtures[lang].entries.find(e=>e.key==='guide/zt7').title);
    await page.goBack();await ready();assert.match(page.url(),/zt1/);checks.push(`${campaign}/${lang}: Back restores article`);
    await page.selectOption('#category','Getting started');
    await page.waitForTimeout(200);
    assert.equal(await page.locator('#category').inputValue(),'Getting started');checks.push(`${campaign}/${lang}: browse category`);
    await page.waitForFunction(()=>[...document.querySelectorAll('#results img')].slice(0,5).every(img=>img.complete && img.naturalWidth>0));
    checks.push(`${campaign}/${lang}: tutorial icons load`);
    await page.screenshot({path:path.join(args.output,campaign+'-'+lang+'.png'),fullPage:true});
  }
  assert.deepEqual(errors,[]);
  await fs.writeFile(path.join(args.output,'result.json'),JSON.stringify({checks,errors,scope:'Real packaged wiki data, both campaigns and all languages; no fixture injection.'},null,2));
  console.log(JSON.stringify({checks:checks.length,errors}));
} catch (error) {
  await page.screenshot({path:path.join(args.output,'failure.png'),fullPage:true});
  await fs.writeFile(path.join(args.output,'failure.json'),JSON.stringify({checks,errors,url:page.url(),notice:await page.locator('#notice').textContent(),error:String(error)},null,2));
  throw error;
} finally {await browser.close();await new Promise(r=>server.close(r));}
