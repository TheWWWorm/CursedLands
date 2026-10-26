// Run with GPU Lab auto. The old cache comes from the published 1.31.0 ZIP.
const {fs,W,port,wait,launch,capture,assertClean,action,startGame}=require('./browser-common.cjs');
(async()=>{
 fs.writeFileSync(W+'/browser-phase.txt','old\n');const browser=await launch();const logs=[];
 try{
  const context=await browser.newContext({viewport:{width:1280,height:720}}),check=await context.newPage();logs.push(capture(check));
  const base=`http://127.0.0.1:${port}`;
  await check.goto(base+'/release-check.html');await action(check,'#setup','Test profile ready');
  const game=await context.newPage();logs.push(capture(game));await startGame(game,base+'/');
  await check.bringToFront();await action(check,'#seed','Baseline saved');
  fs.writeFileSync(W+'/browser-phase.txt','new\n');await action(check,'#update','Update installed');
  const state=await check.evaluate(()=>details());
  if(state.waiting!=='installed'||state.keys.length<1)throw Error('Expected waiting update while old game remains open');
  await check.screenshot({path:W+'/browser-update-waiting.png'});await game.close();await check.close();await wait(1500);
  const again=await context.newPage();logs.push(capture(again));await again.goto(base+'/release-check.html');
  await again.waitForFunction(async()=>{const r=await navigator.serviceWorker.getRegistration();return r&&r.active?.state==='activated'&&!r.waiting;},null,{timeout:120000});
  await action(again,'#verify','PASSED');await again.screenshot({path:W+'/browser-upgrade-passed.png'});
  const report=JSON.parse(fs.readFileSync(W+'/browser-validation.json','utf8'));
  if(!report.cache_upgrade.passed||report.previous_version!=='1.31.0')throw Error('Missing upgrade proof');
  for(const row of logs)assertClean(row);console.log('PASS published 1.31.0 -> 1.31.1 cache upgrade; IndexedDB preserved');
 }finally{fs.writeFileSync(W+'/browser-upgrade-logs.json',JSON.stringify(logs,null,2)+'\n');await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
