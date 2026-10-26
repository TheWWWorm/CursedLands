const fs=require('fs'),path=require('path');
const {chromium}=require('/home/llm2x/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core');
const W=__dirname,port=Number(process.env.CL_RELEASE_PORT||30990),wait=ms=>new Promise(r=>setTimeout(r,ms));
async function launch(){
  const cache=path.join(process.env.HOME,'.cache/ms-playwright');
  const candidates=fs.readdirSync(cache).filter(n=>/^chromium-\d+$/.test(n)).sort((a,b)=>Number(b.split('-')[1])-Number(a.split('-')[1]));
  const exe=process.env.CL_CHROMIUM||candidates.flatMap(n=>['chrome-linux64/chrome','chrome-linux/chrome'].map(p=>path.join(cache,n,p))).find(p=>fs.existsSync(p));
  if(!exe)throw Error('No installed Playwright Chromium; set CL_CHROMIUM to its executable');
  return chromium.launch({executablePath:exe,headless:true,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--mute-audio']});
}
function capture(page){
 const result={console:[],page_errors:[],failed_responses:[]};
 page.on('console',m=>result.console.push({level:m.type(),message:m.text(),url:m.location().url}));
 page.on('pageerror',e=>result.page_errors.push(String(e)));
 page.on('response',r=>{if(r.status()>=400)result.failed_responses.push({url:r.url(),status:r.status()});});
 return result;
}
function assertClean(result){
 const errors=result.console.filter(x=>x.level==='error'||/SCRIPT ERROR:|Parse Error|Compile Error/.test(x.message));
 if(result.page_errors.length||result.failed_responses.length||errors.length)throw Error(JSON.stringify({errors,page_errors:result.page_errors,failed_responses:result.failed_responses}));
}
async function action(page,id,expected){
 await page.click(id);
 await page.waitForFunction(()=>/FAILED|Test profile ready|Baseline saved|Update installed|PASSED/.test(document.querySelector('#state').textContent),null,{timeout:180000});
 const text=await page.textContent('#state');if(!text.startsWith(expected))throw Error(text);
}
async function startGame(page,url){
 await page.goto(url);await page.locator('#play').click({timeout:180000});
 await page.locator('#start').waitFor({state:'detached',timeout:180000});
 await page.locator('#canvas').waitFor({state:'visible',timeout:30000});
 await wait(12000);
 if(!await page.evaluate(()=>crossOriginIsolated))throw Error('Page is not cross-origin isolated');
}
module.exports={fs,W,port,wait,launch,capture,assertClean,action,startGame};
