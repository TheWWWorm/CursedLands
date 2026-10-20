// Clustering follows displayed pixels, so zoom reveals the authored positions.
export function clusterPins(points,width,height,highlight='') {
  const groups=new Map();
  for(const p of points) {
    if(!Number.isFinite(p.x)||!Number.isFinite(p.y))continue;
    const cell=p.kind==='inhabitant'?82:42;
    const highlighted=p.kind==='inhabitant'&&p.key===highlight;
    // Keep the selected species separate even when it shares a cluster cell.
    const key=p.kind+':'+highlighted+':'+Math.floor(p.x*width/cell)+':'+Math.floor(p.y*height/cell);
    if(!groups.has(key))groups.set(key,{x:0,y:0,kind:p.kind,highlighted,points:[]});
    const g=groups.get(key);g.x+=p.x;g.y+=p.y;g.points.push(p);
  }
  return [...groups.values()].map(g=>({...g,x:g.x/g.points.length,y:g.y/g.points.length}));
}

export function filterPins(points,active,query='') {
  const term=query.trim().toLocaleLowerCase();
  return points.filter(p=>active.has(p.kind)&&(p.kind!=='inhabitant'||!term||p.title.toLocaleLowerCase().includes(term)));
}

// Like the objectives screen, arrows face into the map from the nearest edge.
export function exitAngle(x,y) {
  const distances=[y,1-x,1-y,x];
  return [180,270,0,90][distances.indexOf(Math.min(...distances))];
}
export function popupPosition(anchor,width,height,viewWidth,viewHeight) {
  const left=anchor.x+24+width<=viewWidth-10?anchor.x+24:anchor.x-24-width;
  return {left:Math.max(10,Math.min(viewWidth-width-10,left)),top:Math.max(10,Math.min(viewHeight-height-10,anchor.y-height/2))};
}

export function mapFigure(version,{strings:s,href,highlight='',query='',layers=null,onChange=()=>{}}) {
  const el=(tag,text,cls)=>{const n=document.createElement(tag);if(text)n.textContent=text;if(cls)n.className=cls;return n;};
  const figure=el('figure','','map-overview'),controls=el('div','','map-controls'),filters=el('div','','map-filters');
  const viewport=el('div','','map-viewport'),canvas=el('div','','map-canvas'),img=el('img');
  img.src='/wiki/images/'+version.image+'.webp';img.alt=version.title;img.draggable=false;
  canvas.append(img);viewport.append(canvas);
  const popup=el('section','','map-popup');popup.hidden=true;popup.role='dialog';popup.ariaLabel=s.mapSelection;
  viewport.append(popup);
  const active=new Set(layers??['exit','quest']),labels={exit:s.exits,quest:s.questAreas,inhabitant:s.creatures};
  if(layers===null&&(highlight||query.trim()))active.add('inhabitant');
  const points=(version.pins||[]).filter(p=>Number.isFinite(p.x)&&Number.isFinite(p.y));
  const search=el('label',s.filterCreatures,'map-search'),input=el('input');
  input.type='search';input.value=query;input.maxLength=256;input.placeholder=s.filterCreaturesPlaceholder;
  input.title=s.filterCreaturesHelp;input.setAttribute('aria-describedby','map-search-help');
  search.append(input);
  const help=el('p',s.filterCreaturesHelp,'map-search-help');help.id='map-search-help';
  const empty=el('p',s.noMatchingCreatures,'map-search-empty');empty.role='status';empty.hidden=true;
  const highlighted=points.find(p=>p.kind==='inhabitant'&&p.key===highlight);
  const highlightNote=el('p',highlighted?s.mapHighlight.replace('%s',highlighted.title):'','map-highlight');
  highlightNote.hidden=!highlighted;
  const checks=new Map(),groups=new Map();
  const changed=()=>onChange({query:input.value,layers:[...active]});
  const visiblePoints=()=>filterPins(points,active,input.value);
  let scale=1,x=0,y=0,start,selected=null,originButton=null;
  function close(focus=false){popup.hidden=true;selected=null;if(originButton){originButton.setAttribute('aria-expanded','false');if(focus&&originButton.isConnected)originButton.focus();}}
  function geometry(){const fit=Math.min(viewport.clientWidth/img.naturalWidth,viewport.clientHeight/img.naturalHeight);return {w:img.naturalWidth*fit,h:img.naturalHeight*fit};}
  function positionPopup(){
    if(!selected||popup.hidden)return;
    const {w,h}=geometry();
    const anchor={x:viewport.clientWidth/2+(selected.x-.5)*w*scale+x,y:viewport.clientHeight/2+(selected.y-.5)*h*scale+y};
    const p=popupPosition(anchor,popup.offsetWidth,popup.offsetHeight,viewport.clientWidth,viewport.clientHeight);
    popup.style.left=p.left+'px';popup.style.top=p.top+'px';
  }
  function showGroup(group,button){
    close();selected=group;originButton=button;button.setAttribute('aria-expanded','true');popup.replaceChildren();popup.hidden=false;
    const header=el('div','','map-popup-header'),title=el('strong',labels[group.kind]);
    const dismiss=el('button','','map-popup-close');dismiss.type='button';dismiss.ariaLabel=s.closePopup;dismiss.title=s.closePopup;dismiss.onclick=()=>close(true);header.append(title,dismiss);popup.append(header);
    const counts=new Map();for(const p of group.points){if(!counts.has(p.key))counts.set(p.key,{...p,count:0});counts.get(p.key).count++;}
    const links=el('div','','map-popup-links');
    for(const p of counts.values()){
      const a=el('a');a.href=href(p.key);a.append(el('strong',p.title+(p.count>1?' ×'+p.count:'')),el('span',s.openArticle));links.append(a);
    }
    popup.append(links);positionPopup();dismiss.focus({preventScroll:true});
  }
  function markers(){
    canvas.querySelectorAll('.map-pin').forEach(p=>p.remove());if(!img.naturalWidth)return;
    const {w,h}=geometry(),left=(viewport.clientWidth-w)/2,top=(viewport.clientHeight-h)/2;
    for(const g of clusterPins(visiblePoints(),w*scale,h*scale,highlight)){
      const b=el('button','','map-pin '+g.kind+(g.points.length>1?' cluster':'')+(g.highlighted?' highlighted':''));b.type='button';
      b.style.left=(left+g.x*w)+'px';b.style.top=(top+g.y*h)+'px';b.style.transform=`translate(-50%,-50%) scale(${1/scale})`;
      if(g.kind==='exit')b.style.setProperty('--exit-angle',exitAngle(g.x,g.y)+'deg');
      const names=[...new Set(g.points.map(p=>p.title))];b.title=names.join('\n');
      b.ariaLabel=g.points.length>1?s.mapGroup.replace('%d',g.points.length)+': '+names.join(', '):names[0];
      if(g.highlighted)b.ariaLabel=s.mapHighlight.replace('%s',b.ariaLabel);
      b.setAttribute('aria-haspopup','dialog');b.setAttribute('aria-expanded','false');
      if(g.points.length>1)b.append(el('span',String(g.points.length),'pin-count'));
      b.onclick=()=>showGroup(g,b);canvas.append(b);
      if(selected&&g.points.some(p=>selected.points.includes(p))){originButton=b;b.setAttribute('aria-expanded','true');}
    }
    positionPopup();
  }
  const paint=()=>{canvas.style.transform=`translate(${x}px,${y}px) scale(${scale})`;markers();};
  const button=(text,fn)=>{const b=el('button',text);b.type='button';b.onclick=fn;controls.append(b);};
  button(s.zoomIn,()=>{scale=Math.min(5,scale*1.35);paint();});button(s.zoomOut,()=>{scale=Math.max(1,scale/1.35);if(scale===1)x=y=0;paint();});button(s.resetView,()=>{scale=1;x=y=0;close();paint();});
  viewport.addEventListener('keydown',e=>{if(e.key==='Escape'&&!popup.hidden){e.preventDefault();e.stopPropagation();close(true);}});
  viewport.addEventListener('pointerdown',e=>{
    if(e.target.closest('button,a,.map-popup')||start)return;
    close();start={id:e.pointerId,x:e.clientX,y:e.clientY,px:x,py:y};viewport.setPointerCapture(e.pointerId);
  });
  viewport.addEventListener('pointermove',e=>{
    if(!start||e.pointerId!==start.id||scale===1)return;
    x=start.px+e.clientX-start.x;y=start.py+e.clientY-start.y;
    const bx=viewport.clientWidth*(scale-1)/2,by=viewport.clientHeight*(scale-1)/2;x=Math.max(-bx,Math.min(bx,x));y=Math.max(-by,Math.min(by,y));
    canvas.style.transform=`translate(${x}px,${y}px) scale(${scale})`;positionPopup();
  });
  const end=e=>{if(start&&e.pointerId===start.id){start=null;if(viewport.hasPointerCapture(e.pointerId))viewport.releasePointerCapture(e.pointerId);}};
  for(const event of ['pointerup','pointercancel','lostpointercapture'])viewport.addEventListener(event,end);
  const list=el('details'),summary=el('summary',s.mapLocations);list.append(summary);
  function refresh(){
    const visible=visiblePoints();
    for(const [kind,group] of groups){
      group.hidden=!active.has(kind);
      const unique=new Map(visible.filter(p=>p.kind===kind).map(p=>[p.key,p]));
      group.replaceChildren(...[...unique.values()].map(p=>{const a=el('a',p.title);a.href=href(p.key);return a;}));
    }
    empty.hidden=!active.has('inhabitant')||!input.value.trim()||visible.some(p=>p.kind==='inhabitant');
    highlightNote.hidden=!highlighted||!visible.some(p=>p.key===highlight);
    close();markers();
  }
  for(const kind of ['exit','quest','inhabitant']){
    const categoryPoints=points.filter(p=>p.kind===kind);if(!categoryPoints.length)continue;
    const l=el('label','',kind),check=el('input');check.type='checkbox';check.checked=active.has(kind);l.append(check,document.createTextNode(labels[kind]));filters.append(l);
    const group=el('div');groups.set(kind,group);checks.set(kind,check);
    list.append(group);check.addEventListener('change',()=>{if(check.checked)active.add(kind);else active.delete(kind);refresh();changed();});
  }
  input.addEventListener('input',()=>{
    if(input.value.trim()&&checks.has('inhabitant')){active.add('inhabitant');checks.get('inhabitant').checked=true;}
    refresh();changed();
  });
  refresh();
  img.addEventListener('load',markers);const observer=new ResizeObserver(()=>{if(!figure.isConnected){observer.disconnect();return;}markers();});observer.observe(viewport);
  figure.append(filters,search,help,empty,highlightNote,viewport,controls,el('figcaption',s.mapHelp),list);return figure;
}
