import {mountConstructor} from './constructors.mjs';
import {score} from './search.mjs';
import {blank,decode,encode,autoSlot,assignSlot,EQUIPMENT_SLOTS,resolvePlan} from './plan.mjs';
import {mountPlan} from './plan-ui.mjs';
import {createLibrary} from './library.mjs';
import {mountLibrary,nameCreation} from './library-ui.mjs';
import {mapFigure} from './maps.mjs';
import {art} from './art.mjs';
const $ = selector => document.querySelector(selector);
const SUPPORTED = ['en', 'ru', 'de'];
const CAMPAIGNS = ['cursed_lands', 'lost_in_astral'];
const ITEM_TYPES = {
  weapon_sword: ['weapons', 'swords'], weapon_axe: ['weapons', 'axes'], weapon_dagger: ['weapons', 'daggers'],
  weapon_spear: ['weapons', 'spears'], weapon_hammer: ['weapons', 'hammers'], weapon_bow: ['weapons', 'bows'], weapon_crossbow: ['weapons', 'crossbows'],
  armor_helm: ['armour', 'helmets'], armor_plate: ['armour', 'chestArmour'], armor_leggings: ['armour', 'leggings'], armor_leggins: ['armour', 'leggings'],
  armor_shirt: ['armour', 'shirts'], armor_pants: ['armour', 'trousers'], armor_gloves: ['armour', 'gloves'], armor_boots: ['armour', 'boots'],
  quest: ['otherItems', 'questItems'], wand: ['otherItems', 'wands'], potion: ['otherItems', 'potions'], loot: ['otherItems', 'loot'], other: ['otherItems', 'otherItems']
};
const ALLOWED = new Set(['ARTICLE', 'H1', 'H2', 'H3', 'P', 'BR', 'TABLE', 'TBODY', 'TR', 'TH', 'TD', 'A', 'STRONG', 'EM']);
let lang = 'en', campaign = 'cursed_lands', strings, catalog, entry, page, constructors, generation = 0;
const indexes = new Map(), pages = new Map(), plans = new Map();
const library=createLibrary();
let activeVersion, draft, directory;

function route() {
  const params = new URLSearchParams(location.search);
  const requested = params.get('lang') || navigator.language.slice(0, 2);
  return {lang: SUPPORTED.includes(requested) ? requested : 'en',
    campaign: CAMPAIGNS.includes(params.get('campaign')) ? params.get('campaign') : 'cursed_lands',
    craft:params.get('craft')==='1',slot:EQUIPMENT_SLOTS.includes(params.get('slot'))?params.get('slot'):'',
    key: params.get('page') || 'home', variant: params.get('version') || '',
    creature:params.get('creature')||'',mapFilter:(params.get('mapFilter')||'').slice(0,256),
    mapLayers:params.has('mapLayers')?params.get('mapLayers').split(',').filter(kind=>['exit','quest','inhabitant'].includes(kind)):null,
    spell:params.get('spell') || '', runes:params.has('runes') ? params.get('runes').split(';').filter(Boolean) : null};
}

function href(key, variant = '', language = lang, game = campaign) {
  const params = new URLSearchParams({lang: language, page: key});
  if (game !== 'cursed_lands') params.set('campaign', game);
  if (variant) params.set('version', variant);
  // Put the context in the link itself so opening a new tab works too.
  if(key.startsWith('map/')&&entry?.kind==='creature'&&game===campaign)params.set('creature',entry.key);
  return '/wiki/?' + params + (plans.has(game) ? '#build='+encode(plans.get(game)) : '');
}

function navigate(key, variant = '', language = lang) {
  const url = new URL(href(key, variant, language),location.origin);
  if (key === route().key) {
    const current = new URLSearchParams(location.search);
    for (const name of ['spell','runes','craft','slot','creature','mapFilter','mapLayers']) if (current.has(name)) url.searchParams.set(name,current.get(name));
  }
  if (document.body.classList.contains('workbench-mode') && /^(item|spell)\//.test(key)) url.searchParams.set('craft','1');
  if (location.href !== url.href) history.pushState(null, '', url);
  load();
}

async function json(url, cache) {
  if (!cache.has(url)) cache.set(url, fetch(url, {cache: 'no-cache'}).then(response => {
    if (!response.ok) throw new Error('HTTP ' + response.status);
    return response.json();
  }).catch(error => {cache.delete(url); throw error;}));
  return cache.get(url);
}

function translate() {
  document.documentElement.lang = lang;
  document.title = 'Cursed Lands · ' + strings.encyclopedia;
  $('meta[name=description]').content = strings.description;
  for (const el of document.querySelectorAll('[data-text]')) el.textContent = strings[el.dataset.text];
  $('#language').value = lang;
  $('#search').placeholder = strings.searchPlaceholder;
  $('#search').title = strings.searchHelp;
  $('#results').ariaLabel = strings.results;
  $('header nav').ariaLabel = strings.navigation;
  $('.brand').ariaLabel = 'Cursed Lands · ' + strings.encyclopedia;
  $('.brand').href = $('#contents').href = href('home');
  $('#campaigns').ariaLabel = strings.campaign;
  for (const tab of document.querySelectorAll('[data-campaign]')) {
    tab.href = href('home', '', lang, tab.dataset.campaign);
    if (tab.dataset.campaign === campaign) tab.setAttribute('aria-current', 'page');
    else tab.removeAttribute('aria-current');
  }
  $('#planner-link').href = href('mechanics/planning');
  $('#library-link').href = href('local-library');
  $('#toc').ariaLabel = strings.onThisPage;
  $('#share-fallback').ariaLabel = strings.copyLink;
  $('footer p').textContent = campaign === 'lost_in_astral' ? strings.astralSource : strings.source;
}

function search(resetScroll = false) {
  if (!catalog) return;
  const query = $('#search').value.trim();
  const category = $('#category').value, itemType = $('#item-category').value;
  $('#item-filters').hidden = category !== 'Items';
  let ranked = catalog.entries.filter(row => row.listed !== false && !(row.kind==='spell'&&decodeURIComponent(row.key).includes('{')) &&
    (category==='All pages'||row.category===category)&&(category!=='Items'||!itemType||row.subcategory===itemType))
    .map(row=>({row,rank:Math.max(score(query,row.title,[row.search,row.subtitle,catalog.categories[row.category],strings[ITEM_TYPES[row.subcategory]?.[1]]].filter(Boolean).join(' ')),...(row.aliases||[]).map(name=>score(query,name,'')))}))
    .filter(r=>r.rank>=0);
  if(ranked.some(r=>r.rank>=100))ranked=ranked.filter(r=>r.rank>=100);
  const found=ranked.sort((a,b)=>b.rank-a.rank||(query.trim()?Number(b.row.kind==='character')-Number(a.row.kind==='character'):0)||a.row.title.localeCompare(b.row.title,lang)).map(r=>r.row);
  $('#status').textContent = found.length ? strings.matches.replace('{count}', found.length.toLocaleString(lang)) : strings.empty;
  const scroll = resetScroll ? 0 : $('#results').scrollTop;
  $('#results').replaceChildren(...found.map(row => {
    const a = document.createElement('a');
    a.href = href(row.key);
    const name=document.createElement('span'),detail=document.createElement('small');name.textContent=row.title;detail.textContent=row.subtitle||catalog.categories[row.category];
    a.append(art(row));
    const text=document.createElement('span');text.append(name,detail);a.append(text);
    if (entry?.key === row.key) a.setAttribute('aria-current', 'page');
    return a;
  }));
  $('#results').scrollTop = scroll;
}

function itemCategories() {
  const available = new Set(catalog.entries.filter(row => row.listed !== false).map(row => row.subcategory));
  const groups = new Map();
  $('#item-category').replaceChildren(new Option(strings.allItems, ''));
  for (const [id, [group, label]] of Object.entries(ITEM_TYPES)) {
    if (!available.has(id)) continue;
    if (!groups.has(group)) {
      const el = document.createElement('optgroup'); el.label = strings[group];
      groups.set(group, el); $('#item-category').append(el);
    }
    groups.get(group).append(new Option(strings[label], id));
  }
}

// Articles are generated from escaped source text, but only the wiki's small
// semantic HTML vocabulary is admitted. Original text never becomes script,
// style, an external URL, an event handler or an arbitrary embedded object.
function article(html) {
  const parsed = new DOMParser().parseFromString(html, 'text/html');
  function safe(node) {
    if (node.nodeType === Node.TEXT_NODE) return document.createTextNode(node.textContent);
    if (node.nodeType !== Node.ELEMENT_NODE || !ALLOWED.has(node.tagName)) return document.createTextNode('');
    const el = document.createElement(node.tagName.toLowerCase());
    if (node.tagName === 'A') {
      const link = node.getAttribute('href') || '';
      if (link.startsWith('wiki://')) {
        const [key, query = ''] = link.slice(7).split('?');
        if (key.startsWith('category/')) {
          el.href = href('home');
          el.dataset.category = decodeURIComponent(key.slice(9));
        } else {
          el.href = href(key, new URLSearchParams(query).get('version') || '');
        }
      }
    }
    el.append(...Array.from(node.childNodes, safe));
    return el;
  }
  return safe(parsed.body.querySelector('article') || parsed.body);
}

function showVersion(id) {
  const version = page.versions.find(row => row.id === id) || page.versions[0];
  if (id && id !== version.id) {
    const url = new URL(location.href); url.searchParams.set('version',version.id);
    history.replaceState(null, '', url);
  }
  activeVersion=version;draft=route();
  $('#variant').value = version.id;
  const content = article(version.html);
  content.id = 'article'; content.tabIndex = -1;
  if(version.image&&entry.kind==='map'&&version.image_kind!=='scene'){
    const state=route(),highlight=catalog.entries.some(row=>row.key===state.creature&&row.kind==='creature')?state.creature:'';
    content.querySelector('h1').after(mapFigure(version,{strings,href,highlight,query:state.mapFilter,layers:state.mapLayers,onChange:map=>{
      const url=new URL(location.href);
      if(map.query)url.searchParams.set('mapFilter',map.query);else url.searchParams.delete('mapFilter');
      url.searchParams.set('mapLayers',map.layers.join(','));
      history.replaceState(null,'',url);
    }}));
  }
  else if(version.image){
    const figure=document.createElement('figure'),img=document.createElement('img'),caption=document.createElement('figcaption');
    img.src='/wiki/images/'+version.image+'.webp';img.alt=version.title;img.width=260;img.height=260;img.decoding='async';
    caption.textContent=version.image_caption||(version.representative_image?strings.imageRepresentative:strings.image);
    if(['scene','allod','map'].includes(version.image_kind)){figure.className='world-illustration';img.width=960;img.height=720;}
    figure.append(img,caption);content.querySelector('h1').after(figure);
  }
  if(entry.subtitle){const sub=document.createElement('p');sub.className='article-subtitle';sub.textContent=entry.subtitle;content.querySelector('h1').after(sub);}
  if(version.guide){const details=document.createElement('details'),summary=document.createElement('summary');summary.textContent=strings.questHints;details.className='quest-guide';details.open=true;details.append(summary,article('<article>'+version.guide+'</article>'));content.append(details);}
  const isPlan=entry.key==='mechanics/planning';
  document.body.classList.toggle('planner-mode',isPlan);document.body.classList.toggle('workbench-mode',route().craft&&['item','spell'].includes(entry.kind));
  $('#add-plan').textContent=route().slot?strings.craftEquip:strings.addPlan;
  $('#add-plan').disabled=false;$('#add-plan').hidden=!['item','spell'].includes(entry.kind)||version.id?.startsWith('bp:');
  $('#save-creation').hidden=!(isPlan||['item','spell'].includes(entry.kind)&&!version.id?.startsWith('bp:'));$('#save-creation').disabled=false;
  $('#plan').hidden=!isPlan;
  if(isPlan){if(!plans.has(campaign))plans.set(campaign,blank(campaign));mountPlan($('#plan'),{plan:plans.get(campaign),catalog,data:constructors,getPage:e=>json(directory+'/pages/'+e.file,pages),strings,href,onChange:savePlan,getSaved:()=>savedRecipes()});}
  if(entry.key==='home')home(content);
  $('#toc').hidden=entry.key==='home'||entry.kind==='map'||isPlan;
  $('#toc').replaceChildren();
  const sections=[...content.querySelectorAll('h2')];
  let contents=$('#toc');
  if(sections.length>10){
    const details=document.createElement('details'),summary=document.createElement('summary');
    summary.textContent=strings.onThisPage;contents=document.createElement('div');contents.className='toc-sections';
    details.append(summary,contents);$('#toc').append(details);
  }
  if(entry.key!=='home')for(const [i,h] of sections.entries()){h.id='section-'+i;const a=document.createElement('a');a.href='#'+h.id;a.textContent=h.textContent;contents.append(a);}
  $('#article-heading').replaceChildren();
  if(entry.key!=='home'){const heading=content.querySelector('h1'),subtitle=content.querySelector('.article-subtitle');if(heading)$('#article-heading').append(heading);if(subtitle)$('#article-heading').append(subtitle);}
  $('.article-tools').hidden=entry.key==='home';
  if(isPlan)content.replaceChildren();
  $('#content').replaceChildren(content);
  $('#spell-note').hidden = true;
  if (constructors) mountConstructor($('#constructor'), {data:constructors,entry,version,versions:page.versions,catalog,strings:{...strings,addPlan:route().slot?strings.craftEquip:strings.addPlan},state:route(),onVersion:id=>navigate(entry.key,id),onSpell:(id,runes=[])=>{const url=new URL(href('spell/'+encodeURIComponent(id)),location.origin);url.searchParams.set('craft','1');url.searchParams.set('runes',runes.join(';'));if(route().slot)url.searchParams.set('slot',route().slot);history.pushState(null,'',url);load();},onAdd:()=>$('#add-plan').click(),onSave:()=>$('#save-creation').click(),getSaved:()=>savedRecipes(),onValidity:valid=>{$('#add-plan').disabled=!valid;$('#save-creation').disabled=!valid;},onChange:state => {
    draft=state;
    const url=new URL(location.href);
    for (const key of ['spell','runes']) url.searchParams.delete(key);
    if (entry.kind === 'item' && state.spell) url.searchParams.set('spell',state.spell);
    if (state.runes.length || (entry.kind === 'spell' && decodeURIComponent(entry.key).includes('{'))) url.searchParams.set('runes',state.runes.join(';'));
    history.replaceState(null,'',url);
  }});
  let builderLink=$('#open-constructor');if(!builderLink){builderLink=document.createElement('a');builderLink.id='open-constructor';builderLink.href='#constructor';$('.article-tools').append(builderLink);}builderLink.textContent=document.body.classList.contains('workbench-mode')?strings.returnArticle:entry.kind==='spell'?strings.spellConstructor:strings.itemConstructor;builderLink.hidden=$('#constructor').hidden;builderLink.onclick=e=>{e.preventDefault();document.body.classList.toggle('workbench-mode');const target=new URL(location.href);if(document.body.classList.contains('workbench-mode'))target.searchParams.set('craft','1');else target.searchParams.delete('craft');history.replaceState(null,'',target);builderLink.textContent=document.body.classList.contains('workbench-mode')?strings.returnArticle:entry.kind==='spell'?strings.spellConstructor:strings.itemConstructor;window.scrollTo({top:0,behavior:'instant'});};
  document.title = version.title + ' · Cursed Lands';
}

async function load() {
  const token = ++generation, target = route();
  if(location.hash.startsWith('#build=')){const shared=decode(location.hash.slice(7));if(shared&&shared.campaign===target.campaign)plans.set(target.campaign,shared);}
  $('#plan').hidden=true;$('#toc').replaceChildren();$('#action-status').textContent='';$('#share-fallback').hidden=true;$('#add-plan').hidden=true;
  $('#save-creation').hidden=true;
  lang = target.lang; campaign = target.campaign; strings = translations[lang];
  translate();
  $('#notice').textContent = strings.loading;
  $('#versions').hidden = true;
  $('#spell-note').hidden = true;
  $('#content').replaceChildren();
  $('#constructor').hidden = true;
  try {
    directory = '/wiki/data/' + (campaign === 'lost_in_astral' ? campaign + '/' : '') + lang;
    const index = await json(directory + '/index.json', indexes);
    if (token !== generation) return;
    const changed = catalog !== index;
    catalog = index;
    if (changed) {
      $('#category').replaceChildren(...Object.entries(catalog.categories).map(([id, name]) => new Option(name, id)));
      itemCategories();
      $('#search').value = '';
    }
    $('#version').textContent = strings.dataVersion.replace('%s',catalog.version);
    if(target.key==='local-library'){entry=null;search(changed);showLibrary();$('#notice').textContent='';return;}
    entry = catalog.entries.find(row => row.key === target.key);
    search(changed);
    if (!entry) {
      $('#notice').textContent = strings.unavailable;
      return;
    }
    const loaded = await json(directory + '/pages/' + entry.file, pages);
    if (token !== generation) return;
    page = loaded;
    constructors = await json(directory + '/constructors.json', pages);
    if (token !== generation) return;
    $('#variant').replaceChildren(...page.versions.map(row => new Option(row.title, row.id)));
    $('#versions').hidden = page.versions.length < 2;
    $('#versions label').textContent = entry.kind === 'creature' ? strings.appearance : strings.variant;
    showVersion(target.variant);
    $('#notice').textContent = location.hash.startsWith('#build=')&&!decode(location.hash.slice(7)) ? strings.invalidLink : '';
  } catch (error) {
    if (token !== generation) return;
    $('#notice').textContent = strings.error + ' ';
    const button = document.createElement('button');
    button.textContent = strings.retry; button.onclick = load;
    $('#notice').append(button);
  }
}

function savePlan(){const url=new URL(location.href);url.hash='build='+encode(plans.get(campaign));history.replaceState(null,'',url);$('#planner-link').href=href('mechanics/planning');}
function savedRecipes(){try{return library.list().filter(r=>r.type!=='character'&&r.plan.campaign===campaign);}catch{return [];}}
function currentRecipe(){
  const authored=entry.kind==='spell'?decodeURIComponent(entry.key.slice(6)):'';
  const spell=entry.kind==='spell'?authored.split('{')[0]:(draft.spell||'');
  const runes=draft.runes??(authored.split('{')[1]||'').replace(/}$/, '').split(';').filter(Boolean);
  return {key:entry.kind==='spell'?'spell/'+encodeURIComponent(spell):entry.key,variant:activeVersion.id||'',spell,runes:[...runes],count:1};
}
function showLibrary(){
  document.body.classList.remove('planner-mode','workbench-mode');$('#toc').hidden=true;$('.article-tools').hidden=true;$('#article-heading').replaceChildren();
  const heading=document.createElement('h1');heading.textContent=strings.localLibrary;$('#article-heading').append(heading);document.title=strings.localLibrary+' · Cursed Lands';
  mountLibrary($('#content'),{library,strings,catalog,campaign,getPage:e=>json(directory+'/pages/'+e.file,pages),onOpen:record=>{
    if(record.type==='character'){plans.set(record.plan.campaign,structuredClone(record.plan));history.pushState(null,'',href('mechanics/planning','',lang,record.plan.campaign));load();return;}
    const row=record.plan.entries[0],url=new URL(href(row.key,row.variant,lang,record.plan.campaign),location.origin);url.searchParams.set('craft','1');if(row.spell)url.searchParams.set('spell',row.spell);url.searchParams.set('runes',row.runes.join(';'));history.pushState(null,'',url);load();
  },onAdd:record=>{
    const plan=plans.get(record.plan.campaign)||blank(record.plan.campaign);
    if(plan.entries.length>=32){$('#notice').textContent=strings.planFull;return;}
    // Keep the full recipe in inventory. Slot compatibility is checked by the planner.
    const row=structuredClone(record.plan.entries[0]);row.slot='';plan.entries.push(row);plans.set(record.plan.campaign,plan);
    history.pushState(null,'',href('mechanics/planning','',lang,record.plan.campaign));load();
  }});
}
function home(content){
  const el=(tag,text,cls)=>{const n=document.createElement(tag);if(text)n.textContent=text;if(cls)n.className=cls;return n;};
  content.replaceChildren(el('h1',strings.fieldGuide),el('p',strings.homeIntro,'home-intro'));
  const paths=el('div','','home-paths');
  for(const [category,label,help] of [['Characters','meetCharacters','meetCharactersHelp'],['Allods','discoverAllods','discoverAllodsHelp'],['Items','findEquipment','findEquipmentHelp'],['Maps','exploreMaps','exploreMapsHelp'],['Quests','followQuest','followQuestHelp'],['Spells','buildSpell','buildSpellHelp']]) {
    const a=el('a');a.href=href('home');a.dataset.category=category;
    const example=catalog.entries.find(e=>e.category===category&&e.listed!==false&&e.image);
    a.append(art(example||{category},72));
    const text=el('span');text.append(el('strong',strings[label]),el('span',strings[help]));a.append(text);paths.append(a);
  }
  content.append(paths,el('h2',strings.prepareAdventure));
  for(const [key,label,help] of [['mechanics/planning','planner','plannerIntro'],['mechanics/crafting','craftingGuide','craftingGuideHelp'],['mechanics/armor','combatGuide','combatGuideHelp'],['cut/overview','cutContent','cutContentHelp']]){const a=el('a','','home-guide');a.href=href(key);a.append(el('strong',strings[label]),el('span',strings[help]));content.append(a);}
}

const translations = await fetch('/wiki/i18n.json', {cache: 'no-cache'}).then(r => {
  if (!r.ok) throw new Error('Translation catalogue unavailable');
  return r.json();
}).catch(() => {
  $('#notice').textContent = 'Could not load. Reload to retry. / Ошибка загрузки. Обновите страницу. / Laden fehlgeschlagen. Bitte neu laden.';
  return null;
});
if (translations) {
  document.addEventListener('click', event => {
    const a = event.target.closest('a');
    if (event.defaultPrevented || !a || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if (a.dataset.category) {
      event.preventDefault();
      $('#category').value = a.dataset.category;
      $('#search').value = ''; search(true);document.body.classList.add('browse-open');$('#browse-toggle').setAttribute('aria-expanded','true');$('#search').focus();
    } else if (a.getAttribute('href')?.startsWith('#')) {
      const section=document.getElementById(a.getAttribute('href').slice(1));
      if(section){event.preventDefault();section.scrollIntoView({block:'start'});if(section.hasAttribute('tabindex'))section.focus({preventScroll:true});}
    } else if (new URL(a.href).pathname === '/wiki/') {
      event.preventDefault();
      const url=new URL(a.href),targetCampaign=url.searchParams.get('campaign')||'cursed_lands';
      // Links already rendered in search results must not restore an older draft.
      if(plans.has(targetCampaign))url.hash='build='+encode(plans.get(targetCampaign));
      history.pushState(null, '', url); document.body.classList.remove('browse-open');$('#browse-toggle').setAttribute('aria-expanded','false');load();
    }
  });
  $('#search').addEventListener('input', () => search(true));
  $('#category').addEventListener('change', () => search(true));
  $('#item-category').addEventListener('change', () => search(true));
  $('#language').addEventListener('change', () => navigate(route().key, route().variant, $('#language').value));
  $('#variant').addEventListener('change', () => navigate(entry.key, $('#variant').value));
  $('#browse-toggle').onclick=()=>{const open=document.body.classList.toggle('browse-open');$('#browse-toggle').setAttribute('aria-expanded',String(open));if(open)$('#search').focus();};
  $('#share-page').onclick=async()=>{if(entry?.key==='mechanics/planning')savePlan();try{await navigator.clipboard.writeText(location.href);$('#action-status').textContent=strings.copied;}catch{$('#share-fallback').hidden=false;$('#share-fallback').value=location.href;$('#share-fallback').select();$('#action-status').textContent=strings.copyManually;}};
  $('#save-creation').onclick=async()=>{
    const isPlan=entry.key==='mechanics/planning',plan=structuredClone(isPlan?plans.get(campaign):blank(campaign));
    if(!isPlan)plan.entries.push(currentRecipe());
    const type=isPlan?'character':entry.kind,token=generation;
    let name=strings.savedCharacter;
    if(!isPlan){try{const result=await resolvePlan(plan,{catalog,data:constructors,getPage:e=>json(directory+'/pages/'+e.file,pages)});if(token!==generation)return;if(!result.rows[0]?.valid){$('#action-status').textContent=strings.invalidCreation;return;}name=result.rows[0].title;}catch{if(token===generation)$('#action-status').textContent=strings.error;return;}}
    nameCreation({strings,name,onSave:name=>library.save({type,name,plan}),onDone:()=>{$('#action-status').textContent=strings.savedLocally;}});
  };
  $('#add-plan').onclick=()=>{
    if($('#constructor').dataset.valid==='false'&&!$('#constructor').hidden){$('#action-status').textContent=strings.invalidItem;return;}
    if(!plans.has(campaign))plans.set(campaign,blank(campaign));const plan=plans.get(campaign);
    if(plan.entries.length>=32){$('#action-status').textContent=strings.planFull;return;}
    const planned=currentRecipe();autoSlot(plan,planned,entry);plan.entries.push(planned);const slot=route().slot;if(slot)assignSlot(plan,plan.entries.length-1,slot,catalog);savePlan();if(slot)navigate('mechanics/planning');else $('#action-status').textContent=strings.addedPlan;
  };
  document.addEventListener('keydown',e=>{if(e.key==='/'&&!e.ctrlKey&&!e.metaKey&&!['INPUT','SELECT','TEXTAREA'].includes(e.target.tagName)){e.preventDefault();document.body.classList.add('browse-open');$('#browse-toggle').setAttribute('aria-expanded','true');$('#search').focus();}});
  window.addEventListener('popstate', load);
  window.addEventListener('storage',event=>{if(event.key?.startsWith('cursed-lands.wiki.')&&route().key==='local-library')showLibrary();});
  load();
}
