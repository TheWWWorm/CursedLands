// node tools/tests/wiki_map_browser.mjs --public-dir=public --output=/tmp/wiki-map-check --chrome=/path/to/chrome
// NODE_PATH may point to the supplied Playwright modules. --url=https://... checks the live deployment.
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {execFileSync} from 'node:child_process';
import {createRequire} from 'node:module';
import assert from 'node:assert/strict';
import {clusterPins,filterPins} from '../../web/wiki/maps.mjs';
const {chromium}=createRequire(import.meta.url)('playwright');
const args=Object.fromEntries(process.argv.slice(2).map(v=>v.replace(/^--/,'').split(/=(.*)/s).slice(0,2)));
const root=path.resolve(args['public-dir']||'public'),out=path.resolve(args.output),repo=path.resolve(new URL('../..',import.meta.url).pathname);
await fs.mkdir(out,{recursive:true});
const read=async p=>JSON.parse(await fs.readFile(p,'utf8'));
const translations=await read(path.join(root,'wiki/i18n.json'));
let source=await fs.readFile(path.join(repo,'worker.js'),'utf8');
source=source.replace("import parts from './parts.json';",'const parts = '+await fs.readFile(path.join(repo,'parts.json'),'utf8')+';');
const worker=(await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'))).default;
const mime={'.html':'text/html','.css':'text/css','.js':'text/javascript','.mjs':'text/javascript','.json':'application/json','.webp':'image/webp','.png':'image/png','.wasm':'application/wasm','.ttf':'font/ttf','.svg':'image/svg+xml'};
let old=!!args['previous-ref'];
const previous=new Map();
if(old)for(const name of ['index.html','wiki.js','maps.mjs','wiki.css','i18n.json'])
  previous.set('/wiki/'+name,execFileSync('git',['show',`${args['previous-ref']}:public/wiki/${name}`],{cwd:repo}));
const server=http.createServer(async(req,res)=>{
  try{
    const response=await worker.fetch(new Request('http://'+req.headers.host+req.url,{method:req.method}),{ASSETS:{fetch:async request=>{
      const url=new URL(request.url||request),name=decodeURIComponent(url.pathname)+(url.pathname.endsWith('/')?'index.html':'');
      const file=path.resolve(root,'.'+name);
      if(!file.startsWith(root+'/'))return new Response('',{status:400});
      try{return new Response(old&&previous.has(name)?previous.get(name):await fs.readFile(file),{headers:{'Content-Type':mime[path.extname(file)]||'application/octet-stream'}});}
      catch{return new Response('',{status:404});}
    }}});
    res.writeHead(response.status,Object.fromEntries(response.headers));res.end(Buffer.from(await response.arrayBuffer()));
  }catch(e){res.writeHead(500);res.end(String(e));}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin=args.url||`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({headless:true,executablePath:args.chrome,args:['--no-sandbox','--mute-audio']});
const context=await browser.newContext({viewport:{width:1440,height:1000}});
const page=await context.newPage(),errors=[],checks=[];
page.on('pageerror',e=>errors.push(e.message));
const check=(ok,label)=>{assert(ok,label);checks.push(label);};
async function ready(){
  await page.waitForFunction(()=>document.querySelector('#notice')?.textContent===''&&document.querySelector('#article-heading h1,#article h1'));
  await page.waitForFunction(()=>[...document.querySelectorAll('#article img')].every(i=>i.complete&&i.naturalWidth));
}
async function mapReady(){await ready();await page.locator('.map-pin.exit').first().waitFor();}
const count=selector=>page.locator(selector).count();
const positions=()=>page.locator('.map-pin.highlighted').evaluateAll(nodes=>nodes.reduce((sum,n)=>sum+Number(n.querySelector('.pin-count')?.textContent||1),0));
try{
  if(old&&!args.url){
    await page.goto(origin+'/wiki/?lang=en&page=map%2Fgz9g');await mapReady();
    check(await count('.map-search')===0,'previous public wiki reproduces missing name filter');
    await page.evaluate(async()=>{
      localStorage.setItem('wiki-update-sentinel','keep');
      await navigator.serviceWorker.register('/service-worker.js');
      await navigator.serviceWorker.ready;
    });
    await page.reload();await mapReady();
    check(await page.evaluate(()=>!!navigator.serviceWorker.controller),'old wiki controlled by installed game service worker');
    old=false;
    await page.reload();await mapReady();
    check(await count('.map-search')===1,'ordinary reload updates wiki with installed game service worker');
    check(await page.evaluate(()=>localStorage.getItem('wiki-update-sentinel'))==='keep','wiki update preserves local storage');
  }
  for(const campaign of ['cursed_lands','lost_in_astral']){
    const directory=path.join(root,'wiki/data',campaign==='lost_in_astral'?campaign:'');
    const en=await read(path.join(directory,'en/index.json'));
    let fixture;
    for(const entry of en.entries.filter(e=>e.kind==='map'&&e.listed)){
      const data=await read(path.join(directory,'en/pages',entry.file)),version=data.versions[0];
      if(!version.image||version.image_kind==='scene'||!version.pins?.some(p=>p.kind==='exit'))continue;
      const pin=version.pins.find(p=>p.kind==='inhabitant'&&p.key.includes('toad'));
      if(pin){fixture={map:entry.key,creature:pin.key};break;}
    }
    assert(fixture,'authored creature locations for '+campaign);
    for(const lang of ['en','ru','de']){
      const catalog=await read(path.join(directory,lang,'index.json')),s=translations[lang];
      const map=catalog.entries.find(e=>e.key===fixture.map),creature=catalog.entries.find(e=>e.key===fixture.creature);
      const data=await read(path.join(directory,lang,'pages',map.file)),points=data.versions[0].pins;
      const expected=points.filter(p=>p.kind==='inhabitant'&&p.key===creature.key).length;
      const clustered=clusterPins(points,330,320,creature.key);
      check(clustered.filter(g=>g.highlighted).every(g=>g.points.every(p=>p.key===creature.key)),campaign+' '+lang+' highlighted clusters never include another species');
      check(clustered.reduce((n,g)=>n+g.points.length,0)===points.length,campaign+' '+lang+' clustering preserves all authored positions');
      const params=new URLSearchParams({lang,page:creature.key,campaign});
      await page.goto(origin+'/wiki/?'+params);await ready();
      const link=page.locator('#article a').filter({hasText:map.title}).first();
      check(new URL(await link.getAttribute('href'),origin).searchParams.get('creature')===creature.key,campaign+' '+lang+' creature context included in map link');
      await link.click();await mapReady();
      check(await page.locator('.map-filters .inhabitant input').isChecked(),campaign+' '+lang+' linked map enables creatures');
      check(await positions()===expected,campaign+' '+lang+' all linked creature positions highlighted');
      check((await page.locator('.map-highlight').textContent()).includes(creature.title),campaign+' '+lang+' highlight names the selected creature');
      const unrelated=await count('.map-pin.exit,.map-pin.quest');
      const filter=page.getByRole('searchbox',{name:s.filterCreatures,exact:true});
      await filter.fill(creature.title.toLocaleUpperCase());
      check(await positions()===expected,campaign+' '+lang+' translated case-insensitive filter keeps matching positions');
      check(await count('.map-pin.exit,.map-pin.quest')===unrelated,campaign+' '+lang+' name filter retains exits and quests');
      const visible=filterPins(points,new Set(['exit','quest','inhabitant']),creature.title.toLocaleUpperCase());
      const expectedGroups=clusterPins(visible,330,320,creature.key);
      check(expectedGroups.every(g=>g.kind!=='inhabitant'||g.points.every(p=>p.title.toLocaleLowerCase().includes(creature.title.toLocaleLowerCase()))),campaign+' '+lang+' filter matches localized names');
      await page.locator('#contents').click();await ready();await page.goBack();await mapReady();
      check(await filter.inputValue()===creature.title.toLocaleUpperCase()&&await positions()===expected,campaign+' '+lang+' Back restores filter and highlight');
      await page.reload();await mapReady();
      check(await filter.inputValue()===creature.title.toLocaleUpperCase()&&await positions()===expected,campaign+' '+lang+' shared URL/reload restores map state');
      for(const [width,height] of [[1440,1000],[390,844]]){
        await page.setViewportSize({width,height});
        await page.locator('.map-filters').scrollIntoViewIfNeeded();
        await page.screenshot({path:path.join(out,`${campaign}-${lang}-${width}.png`)});
        check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),campaign+' '+lang+' no overflow at '+width);
        check((await filter.boundingBox()).width<=width,campaign+' '+lang+' filter fits at '+width);
      }
      await filter.fill('no such creature 192847');
      check(await count('.map-pin.inhabitant')===0&&await count('.map-pin.exit,.map-pin.quest')===unrelated,campaign+' '+lang+' unmatched filter hides only creatures');
      check(await page.locator('.map-search-empty').isVisible()&&await page.locator('.map-search-empty').textContent()===s.noMatchingCreatures,campaign+' '+lang+' localized empty state');
      await filter.fill('');await page.locator('.map-filters .inhabitant input').uncheck();
      check(await count('.map-pin.inhabitant')===0,campaign+' '+lang+' creature layer remains optional');
      await page.reload();await mapReady();
      check(!await page.locator('.map-filters .inhabitant input').isChecked(),campaign+' '+lang+' disabled creature layer survives reload');
      await filter.fill(creature.title);
      check(await page.locator('.map-filters .inhabitant input').isChecked(),campaign+' '+lang+' searching enables creatures');
      await page.locator('.map-pin.highlighted').first().click();
      check(await page.locator('.map-popup').isVisible(),campaign+' '+lang+' highlighted marker opens details');
      await page.keyboard.press('Escape');check(!await page.locator('.map-popup').isVisible(),campaign+' '+lang+' Escape dismisses marker details');
      await page.setViewportSize({width:1440,height:1000});
      // A new, unrelated map visit must not retain the previous creature.
      params.set('page',map.key);await page.goto(origin+'/wiki/?'+params);await mapReady();
      check(await count('.map-pin.highlighted')===0&&!await page.locator('.map-filters .inhabitant input').isChecked(),campaign+' '+lang+' direct map link uses uncluttered defaults');
    }
  }
  check(errors.length===0,'no browser exceptions');
  await fs.writeFile(path.join(out,'result.json'),JSON.stringify({live:!!args.url,origin,checks,errors},null,2)+'\n');
  console.log(JSON.stringify({checks:checks.length,errors}));
}finally{await browser.close();server.close();}
