// Run with GPU Lab auto. Fresh context and muted isolated IndexedDB profile.
const {fs,W,port,launch,capture,assertClean,action,startGame}=require('./browser-common.cjs');
(async()=>{
 const browser=await launch();let result;
 try{
  const context=await browser.newContext({viewport:{width:1280,height:720}}),page=await context.newPage();
  result=capture(page);
  await page.goto(`http://127.0.0.1:${port+1}/release-check.html`);await action(page,'#setup','Test profile ready');
  await startGame(page,`http://127.0.0.1:${port+1}/`);
  await page.screenshot({path:W+'/browser-fresh-start.png'});assertClean(result);
  fs.writeFileSync(W+'/browser-fresh.json',JSON.stringify({version:'1.31.0',passed:true,engine_start_resolved:true,canvas_visible:true,isolated:true,original_game_data_imported:false,profile:{confine_mouse:0,show_fps:1,volume_sfx:0,volume_stream:0,volume_voice:0}},null,2)+'\n');
  console.log('PASS fresh browser start');
 }finally{if(result)fs.writeFileSync(W+'/browser-fresh-logs.json',JSON.stringify(result,null,2)+'\n');await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
