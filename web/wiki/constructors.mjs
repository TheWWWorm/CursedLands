import {art} from './art.mjs';
import {score} from './search.mjs';
// Mirrors Spells.parse/constr_rune_fits and Items.can_enchant. Inputs are
// exported from the selected campaign's real builders, not copied databases.
export function buildSpell(data, code, runes = []) {
  const base = Object.hasOwn(data.spells,code) ? data.spells[code] : null;
  if (!base || runes.length > data.max_runes) return null;
  const result = {...base, runes: [...runes]};
  for (const code of runes) {
    const r = Object.hasOwn(data.runes,code) ? data.runes[code] : null;
    if (!r || (r.type < 5 && !base.allowed[r.type])) return null;
    const field = {a:'area', e:'effect', r:'range', m:'mana', d:'duration', t:'targets'}[code[0]];
    if (field) {
      let addition = r.value * base[field];
      if (field === 'duration' || field === 'targets') addition = Math.trunc(addition);
      result[field] += addition;
      if (field !== 'targets') result[field] = Math.max(0, result[field]);
    }
    if (code[0] === 'f') result.filter |= {e:2,f:1,g:8,h:4,l:32,o:16}[code[1]] || 0;
    if (code[0] === 'i') result.flags |= {c:0x20000,t:0x10000}[code[1]] || 0;
    result.mana += r.mana; result.complex += r.complex; result.price += r.price;
  }
  result.mana = Math.max(base.mana, result.mana);
  result.radius = result.area > 0 ? Math.sqrt(result.area / Math.PI) : 0;
  return result;
}

export function canEnchant(item, spell) {
  return !!item && !!spell && ['weapon','armor','quick'].includes(item.kind)
    && (item.kind === 'quick' || spell.runes.some(r => ['ic','it'].includes(r)))
    && Math.trunc(spell.complex) <= item.slots && spell.mana <= item.energy;
}

export function itemResult(item, spell = null) {
  if (!item || (spell && !canEnchant(item,spell))) return null;
  const price = Math.max(1, Math.trunc(item.raw_price + (spell?.price || 0)));
  return {...item, price, construction: Math.trunc(price * item.construction_coefficient)};
}

export function mountConstructor(host, {data,entry,version,versions=[],catalog,strings:s,state,onChange,onVersion,onSpell,onAdd,onSave,getSaved=()=>[],onValidity=()=>{}}) {
  const isSpell=entry.kind==='spell',item=version.builder,authored=isSpell?decodeURIComponent(entry.key.slice(6)):'';
  host.hidden=(isSpell&&!data.spells[authored.split('{')[0]])||(!isSpell&&!item);host.replaceChildren();if(host.hidden)return;
  let focusKey='',selectorQuery='';
  let code=isSpell?authored.split('{')[0]:data.spells[state.spell]?state.spell:'';
  let runes=state.runes??(authored.split('{')[1]||'').replace(/}$/,'').split(';').filter(Boolean),filter='e';
  if(code&&!buildSpell(data,code,runes))runes=[];
  const el=(tag,text,cls)=>{const n=document.createElement(tag);if(text)n.textContent=text;if(cls)n.className=cls;return n;};
  const num=n=>new Intl.NumberFormat(document.documentElement.lang,{maximumFractionDigits:3}).format(n);
  const button=(label,fn,cls='')=>{const b=el('button',label,cls);b.type='button';b.onclick=fn;return b;};
  const commit=()=>{onChange({spell:code,runes:[...runes]});render();if(focusKey)host.querySelector('[data-focus="'+focusKey+'"]')?.focus({preventScroll:true});};
  const categories=[['e','powerLabel'],['m','manaLabel'],['d','durationLabel'],['r','rangeLabel'],['a','areaLabel'],['t','targetsLabel'],['f','runeTargets'],['i','runeSpecial']];
  function render(){
    host.replaceChildren(el('h2',isSpell?s.spellConstructor:s.itemConstructor),el('p',s.workbenchHelp,'constructor-note'));
    const choices=el('div','','workbench-choices');
    if(item&&versions.length>1){const l=el('label',s.variant),select=el('select');select.ariaLabel=s.variant;
      for(const v of versions.filter(v=>v.builder))select.append(new Option(v.title,v.id));select.value=version.id;select.onchange=()=>onVersion(select.value);l.append(select);choices.append(l);}
    const label=el('label',isSpell?s.keystone:s.spellChoice),spellChoice=el('select');spellChoice.id='constructor-spell';
    if(!isSpell)spellChoice.append(new Option(s.noSpell,''));
    for(const [id,spell] of Object.entries(data.spells))spellChoice.append(new Option(spell.title,id));spellChoice.value=code;
    spellChoice.onchange=()=>{if(isSpell)onSpell(spellChoice.value);else{code=spellChoice.value;runes=[];commit();}};label.append(spellChoice);choices.append(label);host.append(choices);
    const spell=code?buildSpell(data,code,runes):null;
    const workshop=el('div','','workshop camp-constructor'),palette=el('div','','rune-palette');
    const top=el('div','','camp-top-tray');top.ariaLabel=isSpell?s.keystone:s.materialsLabel;
    function trayButton(row,title,action,key){const b=button('',action,'camp-component');b.title=title;b.ariaLabel=title;b.dataset.focus=key;b.append(art(row,80));return b;}
    if(isSpell){for(const [id,value] of Object.entries(data.spells)){const b=trayButton({...value,kind:'spell'},value.title,()=>onSpell(id),'spell-'+id);b.setAttribute('aria-pressed',String(id===code));top.append(b);}}
    else{for(const v of versions.filter(v=>v.builder)){const b=trayButton({image:v.image,kind:'item'},v.title,()=>onVersion(v.id),'version-'+v.id);b.setAttribute('aria-pressed',String(v.id===version.id));top.append(b);}}
    workshop.append(top);
    const context=el('aside','','camp-context');context.append(el('h3',isSpell?s.spellConstructor:s.itemConstructor));const detail=el('p',isSpell?s.campHelp:s.campItemHelp);context.append(detail);
    if(!isSpell){label.remove();context.append(label);}
    if(spell||item){
      const filterLabel=el('label',s.runeChoice),filters=el('select');filters.ariaLabel=s.runeChoice;filters.dataset.focus='rune-filter';
      for(const [prefix,key] of categories)filters.append(new Option(s[key],prefix));filters.value=filter;
      filters.onchange=()=>{filter=filters.value;render();host.querySelector('[data-focus="rune-filter"]')?.focus({preventScroll:true});};filterLabel.append(filters);context.append(filterLabel);
      const tray=el('div','','rune-tray');tray.role='group';tray.ariaLabel=s.runeChoice;
      for(const [id,rune] of Object.entries(data.runes).filter(([id])=>id.startsWith(filter))){
        const b=trayButton({...rune,kind:'rune'},s.addRune+': '+rune.title,()=>{focusKey='rune-'+id;runes.push(id);commit();},'rune-'+id);b.disabled=!spell||!buildSpell(data,code,[...runes,id]);
        const describe=()=>{detail.textContent=rune.title+' · '+s.manaLabel+': '+num(rune.mana)+' · '+s.complexityLabel+': '+num(rune.complex);};b.onmouseenter=describe;b.onfocus=describe;tray.append(b);
      }
      while(tray.children.length<8){const empty=el('div','','camp-component');empty.setAttribute('aria-hidden','true');tray.append(empty);}
      palette.append(tray);
    }
    const assembly=el('div','','workbench-assembly'),board=el('div','','craft-board '+(isSpell?'spell-board':'item-board'));
    board.role='group';board.ariaLabel=isSpell?s.spellConstructor:s.itemConstructor;
    function slot(x,y,row,label,fn,cls=''){
      const b=fn?button('',fn,'craft-slot '+cls):el('div','','craft-slot '+cls);
      b.style.left=x+'%';b.style.top=y+'%';b.title=label;if(fn)b.ariaLabel=label;
      if(row)b.append(art(row,80));board.append(b);return b;
    }
    slot(0,37.5,isSpell?{...data.spells[code],kind:'spell'}:{image:version.image,kind:'item'},s.result,null,'result-slot');
    if(isSpell){
      slot(25,37.5,{...data.spells[code],src:'./keystone-'+catalog.campaign+'-'+encodeURIComponent(code)+'.webp',kind:'spell'},s.keystone+': '+data.spells[code].title,null);
      for(let i=0;i<8;i++){
        const rune=runes[i]?data.runes[runes[i]]:null;
        slot(i<4?50:75,(i%4)*25,rune?{...rune,kind:'rune'}:null,rune?s.remove+': '+rune.title:s.emptyRuneSlot,rune?()=>{focusKey='rune-'+runes[i];runes.splice(i,1);commit();}:null);
      }
    }else{
      const blueprint=versions.find(v=>v.id.startsWith('bp:'));
      slot(25,25,{image:blueprint?.image||version.image,kind:'item'},s.blueprint,null);
      slot(25,50,spell?{...data.spells[code],kind:'spell'}:null,s.spellChoice,spell?()=>{code='';runes=[];commit();}:null);
      const material=catalog.entries.find(e=>e.key===version.plan?.material?.key);
      const count=Math.min(8,item.components);
      for(let i=0;i<8;i++){
        const b=slot(i<4?50:75,(i%4)*25,i<count?material:null,material?.title||s.componentsLabel,null);
        if(i===0&&item.components>8)b.append(el('span','×'+item.components,'slot-quantity'));
      }
    }
    const boardCaption=el('p',isSpell?s.spellAssembly:s.itemAssembly,'board-caption'),boardWrap=el('div','','board-wrap');boardWrap.append(board,boardCaption);assembly.append(boardWrap);
    const result=el('div','','workbench-result');
    result.append(el('p',isSpell?spell?.title:version.title,'constructed-title'));
    if(spell){const installed=el('div','','installed-runes');installed.ariaLabel=s.runeChoice;
      for(const [i,id] of runes.entries()){const b=button('',()=>{runes.splice(i,1);commit();},'installed-rune');b.ariaLabel=s.remove+': '+data.runes[id].title;b.title=b.ariaLabel;b.append(art({...data.runes[id],kind:'rune'},40));installed.append(b);}
      result.append(el('p',s.runeCount.replace('{count}',runes.length),'rune-count'));if(item&&runes.length)context.append(installed);
    }
    const rows=[];
    if(item){const built=itemResult(item,spell);result.append(el('p',built?s.validItem:s.invalidItem,built?'constructor-valid':'constructor-error'));
      for(const [key,label] of [['weight','weightLabel'],['slots','slotsLabel'],['energy','energyLabel'],['components','componentsLabel']])rows.push([s[label],num(item[key])]);
      if(built)rows.push([s.priceLabel,num(built.price)],[s.constructionLabel,num(built.construction)]);
    }
    if(spell)for(const [key,label] of [['effect','powerLabel'],['mana','manaLabel'],['complex','complexityLabel'],['range','rangeLabel'],['area','areaLabel'],['duration','durationLabel'],['targets','targetsLabel'],['price','spellPriceLabel']])rows.push([s[label],num(spell[key])]);
    const table=el('table');table.id='constructor-values';
    for(const [label,value] of rows){const tr=el('tr');tr.append(el('th',label),el('td',value));table.append(tr);}result.append(table);
    const actions=el('div','','workbench-actions'),add=button(s.addPlan,onAdd,'primary');add.disabled=!!item&&!itemResult(item,spell);actions.append(add);
    if(spell){const reset=button(s.resetSpell,()=>{runes=[];commit();});reset.id='constructor-reset';reset.disabled=!runes.length;actions.append(reset);}
    context.append(actions);workshop.append(result,boardWrap,context,palette);
    const workspace=el('div','','constructor-workspace'),selector=el('aside','','constructor-selector side-selector');selector.ariaLabel=s.spellChoice;
    selector.append(el('h3',isSpell?s.keystone:s.enchantSpell));
    if(item&&versions.filter(v=>v.builder).length>1){const l=el('label',s.variant),materials=el('select');for(const v of versions.filter(v=>v.builder)){const material=catalog.entries.find(e=>e.key===v.plan?.material?.key);materials.append(new Option(material?.title||v.title,v.id));}materials.value=version.id;materials.onchange=()=>onVersion(materials.value);l.append(materials);selector.append(l);}
    const searchLabel=el('label',s.searchSpells),search=el('input');search.type='search';search.value=selectorQuery;searchLabel.append(search);selector.append(searchLabel);
    const list=el('div','','picker-results'),footer=el('div','','picker-footer');selector.append(list,footer);
    function spellButton(title,value,mods=[],saved=false){
      const b=button('',()=>{if(isSpell)onSpell(value,mods);else{code=value;runes=[...mods];focusKey='';commit();}},'equipment-choice');
      if(value)b.append(art({...data.spells[value],kind:'spell'},40));b.append(el('span',title));b.setAttribute('aria-pressed',String(!saved&&value===code));return b;
    }
    function spellChoices(){
      list.replaceChildren();
      const saved=getSaved().filter(r=>r.type==='spell'&&buildSpell(data,r.plan.entries[0].spell,r.plan.entries[0].runes)&&score(selectorQuery,r.name)>=0);
      if(saved.length){list.append(el('h4',s.localLibrary));for(const r of saved)list.append(spellButton(r.name,r.plan.entries[0].spell,r.plan.entries[0].runes,true));}
      list.append(el('h4',s.spellsLabel));if(!isSpell)list.append(spellButton(s.noSpell,''));
      const matches=Object.entries(data.spells).filter(([,value])=>score(selectorQuery,value.title)>=0);
      for(const [id,value] of matches)list.append(spellButton(value.title,id));if(!matches.length&&!saved.length)list.append(el('p',s.empty));
    }
    search.oninput=()=>{selectorQuery=search.value;spellChoices();};spellChoices();
    footer.append(el('strong',spell?.title||s.noSpell));if(spell)footer.append(el('p',s.runeCount.replace('{count}',runes.length)));
    const save=button(s.saveLocally,onSave);save.disabled=add.disabled;footer.append(save);
    workspace.append(workshop,selector);host.append(workspace);if(isSpell)choices.hidden=true;
    host.dataset.runeCount=String(runes.length);host.dataset.valid=String(!item||!!itemResult(item,spell));onValidity(host.dataset.valid==='true');
  }
  render();
}
