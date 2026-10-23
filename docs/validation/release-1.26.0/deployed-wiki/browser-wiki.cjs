// Exercise the new public Cut content control in EN/RU/DE, Back and reload.
const {fs,W,port,launch,capture,assertClean}=require('./browser-common.cjs');
const path=require('path');
const output=process.env.CL_WIKI_OUTPUT_DIR||W;fs.mkdirSync(output,{recursive:true});
(async()=>{
 const base=process.env.CL_WIKI_BASE_URL||`http://127.0.0.1:${port+1}`;
 const labels=JSON.parse(fs.readFileSync(path.join(W,'../repo/web/wiki/i18n.json'),'utf8'));
 const browser=await launch(),rows=[];
 try{
  const context=await browser.newContext({viewport:{width:1280,height:800}}),page=await context.newPage(),logs=capture(page);
  const ready=async()=>page.waitForFunction(()=>document.querySelector('#article-heading h1, #article h1')&&document.querySelector('#notice').textContent==='',null,{timeout:60000});
  for(const campaign of ['cursed_lands','lost_in_astral'])for(const lang of ['en','ru','de']){
   const params=new URLSearchParams({lang,campaign,page:'home'});
   await page.goto(base+'/wiki/?'+params);await ready();
   const link=page.locator('a.home-guide').filter({hasText:labels[lang].cutContent});
   if(await link.count()!==1)throw Error(`${campaign}/${lang}: missing Cut content entry`);
   await link.click();await ready();
   if(new URL(page.url()).searchParams.get('page')!=='cut/overview')throw Error('Cut content control opened the wrong page');
   const before=await page.locator('#article').innerText();
   if(!before.trim()||await page.locator('html').getAttribute('lang')!==lang)throw Error('Missing localized article');
   await page.reload();await ready();if(await page.locator('#article').innerText()!==before)throw Error('Reload changed the Cut content article');
   await page.screenshot({path:path.join(output,`wiki-cut-${campaign}-${lang}.png`)});
   if(!await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth))throw Error('Horizontal overflow');
   await page.goBack();await ready();if(new URL(page.url()).searchParams.get('page')!=='home')throw Error('Back did not restore wiki home');
   rows.push({campaign,language:lang,control:true,reload:true,back:true,no_horizontal_overflow:true});
  }
  assertClean(logs);
  fs.writeFileSync(path.join(output,'wiki-browser.json'),JSON.stringify({version:'1.26.0',base,passed:true,checks:rows,logs},null,2)+'\n');
  console.log('PASS Cut content control, reload and Back in both campaigns and all three languages');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
