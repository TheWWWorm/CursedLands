import {buildSpell,itemResult} from './constructors.mjs';
export const EQUIPMENT_SLOTS=['weapon1','weapon2','weapon3','weapon4','quick1','quick2','quick3','quick4','helm','plate','leggins','shirt','pants','gloves','boots','spell1','spell2','spell3','spell4','spell5','spell6','spell7','spell8'];
export function slotType(slot){return slot.replace(/\d+$/,'');}
export function entrySlotType(entry){
  if(entry?.kind==='spell')return 'spell';
  const sub=entry?.subcategory||'';
  if(sub.startsWith('weapon_'))return 'weapon';
  if(sub.startsWith('armor_'))return sub.slice(6).replace('leggings','leggins');
  if(['wand','potion'].includes(sub))return 'quick';
  return '';
}
export function assignSlot(plan,index,slot,catalog){
  const row=plan.entries[index],entry=catalog.entries.find(e=>e.key===row?.key);
  if(!row||slot&&(!EQUIPMENT_SLOTS.includes(slot)||slotType(slot)!==entrySlotType(entry)))return false;
  if(slot)for(const other of plan.entries)if(other!==row&&other.slot===slot)other.slot='';
  row.slot=slot;return true;
}
export function autoSlot(plan,row,entry){
  const slot=EQUIPMENT_SLOTS.find(s=>slotType(s)===entrySlotType(entry)&&!plan.entries.some(e=>e.slot===s));
  row.slot=slot||'';
}
export const SKILLS=['melee','archery','science','elemental','sense','astral'];
export function blank(campaign='cursed_lands') {return {v:1,campaign,strength:25,dexterity:25,intelligence:25,experience:50000,skills:{},entries:[]};}
export function validate(value) {
  if (!value || value.v!==1 || !['cursed_lands','lost_in_astral'].includes(value.campaign)) return null;
  const out=blank(value.campaign);
  for (const key of ['strength','dexterity','intelligence','experience']) {
    const n=value[key]??out[key]; if (!Number.isFinite(n)||n<(key==='experience'?0:1)||n>(key==='experience'?1e9:100)) return null;
    out[key]=Math.trunc(n);
  }
  if (!value.skills || typeof value.skills!=='object' || Array.isArray(value.skills) || !Array.isArray(value.entries)||value.entries.length>32) return null;
  for(const key of SKILLS) {const n=value.skills[key]??0;if(!Number.isFinite(n)||n<0||n>100)return null;out.skills[key]=Math.trunc(n);}
  for(const entry of value.entries) {
    if(!entry||typeof entry!=='object')return null;
    const row={key:'',variant:'',spell:'',runes:[],count:1};
    for(const key of ['key','variant','spell']) {const v=entry[key]??'';if(typeof v!=='string'||v.length>512)return null;row[key]=v;}
    if(!row.key.startsWith('item/')&&!row.key.startsWith('spell/'))return null;
    const runes=entry.runes??[];if(!Array.isArray(runes)||runes.length>8||runes.some(r=>typeof r!=='string'||r.length>32))return null;
    if(!row.spell&&runes.length)return null;
    const count=entry.count??1;if(!Number.isFinite(count)||count<1||count>99)return null;
    row.runes=[...runes];row.count=Math.trunc(count);
    if(Object.hasOwn(entry,'slot')){if(typeof entry.slot!=='string'||entry.slot&&!EQUIPMENT_SLOTS.includes(entry.slot))return null;row.slot=entry.slot;if(row.slot&&out.entries.some(e=>e.slot===row.slot))return null;}
    out.entries.push(row);
  }
  if(new TextEncoder().encode(JSON.stringify(out)).length>18000)return null;
  return out;
}
export function encode(plan) {const clean=validate(plan);if(!clean)return '';return btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(clean)))).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');}
export function decode(text) {try {text=text.split('#build=').at(-1);if(!text||text.length>24000||/[^A-Za-z0-9_-]/.test(text))return null;return validate(JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Uint8Array.from(atob(text.replaceAll('-','+').replaceAll('_','/')),c=>c.charCodeAt(0)))));}catch{return null;}}
export function character(plan,rules) {
  const pool=(attr,v)=>attr/v[0]*v[1]*Math.pow(v[3],Math.log(Math.max(plan.experience,1)/v[2])/Math.log(v[4]));
  const c=rules.skill_cost;
  return {health:pool(plan.strength,rules.hp),stamina:pool(plan.dexterity,rules.mp),capacity:plan.strength*12,
    training:SKILLS.reduce((sum,k)=>sum+Math.trunc(c[0]*Math.pow(1.61,(plan.skills[k]||0)/c[1])-c[0]),0)};
}
export async function resolvePlan(plan,{catalog,data,getPage}) {
  const result={...character(plan,data.planner),weight:0,value:0,construction:0,materials:new Map(),rows:[]};
  for(const row of plan.entries) {
    const entry=catalog.entries.find(e=>e.key===row.key),out={...row,valid:false,ready:false,title:entry?.title||'',image:entry?.image||''};result.rows.push(out);
    if(!entry||row.slot&&slotType(row.slot)!==entrySlotType(entry))continue;
    const spell=row.spell?buildSpell(data,row.spell,row.runes):null;
    if(row.spell&&!spell)continue;
    if(entry.kind==='item') {
      const page=await getPage(entry),v=page.versions.find(v=>v.id===row.variant&&!v.id.startsWith('bp:'));
      if(!v)continue;out.title=v.title;out.image=v.image;
      if(!v.plan)continue;
      const item=spell?itemResult(v.builder,spell):v.plan;
      if(!item)continue;
      result.weight+=item.weight*row.count;result.value+=item.price*row.count;
      if(v.builder) {const crafted=itemResult(v.builder,spell);result.construction+=crafted.construction*row.count;
        if(v.plan.material) {const m=v.plan.material,old=result.materials.get(m.key)||{...m,count:0};old.count+=v.builder.components*row.count;result.materials.set(m.key,old);}}
      if(spell)out.title+=' · '+spell.title;
      out.ready=true;
    } else if(entry.kind==='spell'&&spell&&row.spell===decodeURIComponent(entry.key.slice(6)).split('{')[0]) {
      out.title=spell.title;out.ready=(plan.skills[spell.school]||0)+plan.intelligence-25>=spell.complex&&result.stamina>=spell.mana;result.value+=Math.trunc(spell.price)*row.count;
    } else continue;
    if(spell?.runes.length)out.title+=' · '+spell.runes.map(r=>data.runes[r].title).join(', ');
    out.valid=true;
  }
  return result;
}
