import {SKILLS,resolvePlan,EQUIPMENT_SLOTS,slotType,entrySlotType,assignSlot} from './plan.mjs';
import {art} from './art.mjs';
import {score} from './search.mjs';
export function mountPlan(host,{plan,catalog,data,getPage,strings:s,href,onChange,getSaved=()=>[]}) {
  const el=(tag,text,cls)=>{const n=document.createElement(tag);if(text)n.textContent=text;if(cls)n.className=cls;return n;};
  const button=(text,fn,cls)=>{const b=el('button',text,cls);b.type='button';b.onclick=fn;return b;};
  const num=n=>new Intl.NumberFormat(document.documentElement.lang,{maximumFractionDigits:2}).format(n);
  const slotLabels={weapon:s.weapons,quick:s.belt,helm:s.helmets,plate:s.chestArmour,leggins:s.leggings,shirt:s.shirts,pants:s.trousers,gloves:s.gloves,boots:s.boots,spell:s.spellChoice};
  const slotName=slot=>slotLabels[slotType(slot)]+(slot.match(/\d+$/)?' '+slot.match(/\d+$/)[0]:'');
  let revision=0,pickRevision=0,selection='',resultRows=[];
  host.replaceChildren();host.hidden=false;
  const character=el('div','','character-workshop'),training=el('div','','character-training'),equipment=el('div','','character-equipment');
  const stats=el('div','','plan-summary'),rows=el('div','','plan-rows'),materials=el('div','','plan-materials'),slotButtons=new Map();
  const fields=el('div','','character-fields');training.append(el('h2',s.character),fields);
  const input=(key,label,min,max,parent,object=plan)=> {
    const l=el('label',label),i=el('input');i.type='number';i.min=min;i.max=max;i.step=1;i.value=object[key]??0;
    i.addEventListener('change',()=>{if(!i.validity.valid){i.reportValidity();return;}object[key]=Number(i.value);onChange();update();});l.append(i);parent.append(l);
  };
  for(const [k,l] of [['strength','strength'],['dexterity','dexterity'],['intelligence','intelligence'],['experience','earnedExperience']])input(k,s[l],k==='experience'?0:1,k==='experience'?1e9:100,fields);
  const skills=el('div','','character-skills'),skillPanel=el('div','','character-skill-panel');skillPanel.append(el('h2',s.skills),skills);
  for(const k of SKILLS)input(k,data.planner.skills[k],0,100,skills,plan.skills);
  equipment.ariaLabel=s.equipment;
  function makeSlot(slot,parent,cls=''){
    const b=button('',()=>openPicker(slot),'equipment-slot '+cls);b.ariaLabel=s.chooseEquipment+': '+slotName(slot);b.title=slotName(slot);b.dataset.slot=slot;
    b.append(el('span',slotName(slot),'slot-label'));parent.append(b);slotButtons.set(slot,b);return b;
  }
  const ready=el('div','','ready-slots');for(const slot of EQUIPMENT_SLOTS.slice(0,8))makeSlot(slot,ready);equipment.append(ready);
  const doll=el('div','','equipment-doll');doll.role='group';doll.ariaLabel=s.armour;
  const hero=catalog.entries.find(e=>e.key==='creature/human%20hero'&&e.image);
  if(hero){const portrait=art(hero,240);portrait.className='equipment-portrait';doll.append(portrait);}
  for(const [slot,x,y] of [['helm',0,0],['plate',0,37.5],['leggins',0,75],['shirt',75,0],['gloves',75,25],['pants',75,50],['boots',75,75]]){
    const b=makeSlot(slot,doll,'armor-slot');b.style.left=x+'%';b.style.top=y+'%';
  }
  equipment.append(doll);const spellSlots=el('div','','spell-slots');for(const slot of EQUIPMENT_SLOTS.slice(15))makeSlot(slot,spellSlots);equipment.append(spellSlots);
  character.append(ready,training,doll,skillPanel,spellSlots);spellSlots.ariaLabel=s.spellsLabel;
  const workspace=el('div','','planner-workspace');workspace.append(character);
  const picker=el('section','','equipment-picker side-selector picker-idle');picker.ariaLabel=s.chooseEquipment;
  const pickerHeading=el('h3'),pickerClose=button('×',closePicker,'picker-close'),pickerHeader=el('div','','picker-header');pickerClose.ariaLabel=s.closePicker;pickerClose.title=s.closePicker;pickerHeader.append(pickerHeading,pickerClose);
  const searchLabel=el('label'),searchText=el('span',s.search,'sr-only'),search=el('input');searchLabel.append(searchText);search.type='search';search.placeholder=s.searchPlaceholder;searchLabel.append(search);
  const slotLabel=el('label'),slotChoice=el('select');slotLabel.append(el('span',s.equipment,'sr-only'));slotChoice.append(new Option(s.chooseEquipment,''));for(const slot of EQUIPMENT_SLOTS)slotChoice.append(new Option(slotName(slot),slot));slotLabel.append(slotChoice);slotChoice.onchange=()=>{if(slotChoice.value)openPicker(slotChoice.value);else closePicker();};
  const placeholder=el('p',s.chooseSlotHelp,'picker-placeholder');pickerHeading.textContent=s.chooseEquipment;
  const planned=el('div','','planned-choices'),saved=el('div','','saved-choices'),choices=el('div','','equipment-choices'),detail=el('div','','equipment-choice-detail'),empty=button(s.unequip,()=>{for(const row of plan.entries)if(row.slot===selection)row.slot='';onChange();update();closePicker();});
  const resultList=el('div','','picker-results'),pickerFooter=el('div','','picker-footer'),pickerActions=el('div','','picker-actions');resultList.append(planned,saved,choices);pickerActions.append(empty);pickerFooter.append(detail,pickerActions);picker.append(pickerHeader,slotLabel,placeholder,searchLabel,resultList,pickerFooter);
  search.oninput=()=>showChoices();picker.addEventListener('keydown',e=>{if(e.key==='Escape'){e.preventDefault();closePicker();}});
  function closePicker(){++pickRevision;picker.classList.add('picker-idle');slotChoice.value='';pickerHeading.textContent=s.chooseEquipment;slotButtons.get(selection)?.focus({preventScroll:true});}
  function openPicker(slot){++pickRevision;selection=slot;picker.classList.remove('picker-idle');slotChoice.value=slot;pickerHeading.textContent=slotName(slot);empty.hidden=!plan.entries.some(row=>row.slot===slot);search.value='';detail.replaceChildren();pickerActions.replaceChildren(empty);showChoices();picker.scrollIntoView({block:'nearest'});search.focus({preventScroll:true});}
  function showChoices(){
    choices.replaceChildren();planned.replaceChildren();saved.replaceChildren();
    const existing=resultRows.map((row,index)=>({row,index})).filter(({row})=>row.valid&&entrySlotType(catalog.entries.find(e=>e.key===row.key))===slotType(selection)&&score(search.value,row.title)>=0);
    planned.hidden=!existing.length;
    if(existing.length)planned.append(el('h4',s.fromPlan));
    for(const {row,index} of existing){const b=button('',()=>{assignSlot(plan,index,selection,catalog);onChange();update();closePicker();},'equipment-choice');b.append(art({...row,kind:slotType(selection)==='spell'?'spell':'item'},40),el('span',row.title));planned.append(b);}
    const savedMatches=getSaved().filter(record=>entrySlotType(catalog.entries.find(e=>e.key===record.plan.entries[0].key))===slotType(selection)&&score(search.value,record.name)>=0);
    saved.hidden=!savedMatches.length;if(savedMatches.length)saved.append(el('h4',s.localLibrary));
    for(const record of savedMatches){const b=button('',()=>chooseSaved(record),'equipment-choice'),entry=catalog.entries.find(e=>e.key===record.plan.entries[0].key);b.append(art(entry,40),el('span',record.name));saved.append(b);}
    const matches=catalog.entries.filter(e=>e.listed!==false&&entrySlotType(e)===slotType(selection)&&!decodeURIComponent(e.key).includes('{'))
      .map(e=>({e,n:score(search.value,e.title,e.search||'')})).filter(v=>v.n>=0).sort((a,b)=>b.n-a.n||a.e.title.localeCompare(b.e.title));
    if(!matches.length)choices.append(el('p',s.empty));
    for(const {e} of matches.slice(0,60)){
      const b=button('',()=>choose(e),'equipment-choice');b.append(art(e,40),el('span',e.title));choices.append(b);
    }
  }
  async function choose(entry){
    const chosenSlot=selection,pick=++pickRevision;pickerActions.replaceChildren(empty);detail.replaceChildren(el('p',s.loading));
    try{
      const page=await getPage(entry);if(pick!==pickRevision||picker.classList.contains('picker-idle')||selection!==chosenSlot||!host.isConnected)return;
      detail.replaceChildren();const variants=page.versions.filter(v=>!v.id.startsWith('bp:'));
      const label=el('label',s.variant),select=el('select');for(const v of variants){const material=catalog.entries.find(e=>e.key===v.plan?.material?.key);select.append(new Option(material?.title||v.title,v.id));}label.append(select);
      const preview=el('div','','equipment-choice-preview'),name=el('strong'),read=el('a',s.openArticle),craft=el('a',s.customize),add=button(s.equip,()=>{
        if(plan.entries.length>=32){detail.append(el('p',s.planFull));return;}
        const magic=entry.kind==='spell'?decodeURIComponent(entry.key.slice(6)).split('{')[0]:'';
        const row={key:entry.key,variant:select.value,spell:magic,runes:[],count:1,slot:''};plan.entries.push(row);assignSlot(plan,plan.entries.length-1,chosenSlot,catalog);onChange();update();closePicker();
      });
      function selectedVersion(){const v=variants.find(v=>v.id===select.value)||variants[0];preview.replaceChildren(art({...entry,image:v.image},100));name.textContent=v.plan?.material?entry.title:v.title;read.href=href(entry.key,v.id);const target=new URL(read.href,location.origin);target.searchParams.set('craft','1');target.searchParams.set('slot',chosenSlot);craft.href=target;craft.hidden=entry.kind!=='spell'&&!v.builder;}
      select.onchange=selectedVersion;selectedVersion();detail.append(preview,name);if(variants.length>1)detail.append(label);detail.append(read,craft);pickerActions.prepend(add);
    }catch{detail.replaceChildren(el('p',s.error));}
  }
  async function chooseSaved(record){
    const chosenSlot=selection,pick=++pickRevision;pickerActions.replaceChildren(empty);detail.replaceChildren(el('p',s.loading));
    try{
      const result=await resolvePlan(record.plan,{catalog,data,getPage});if(pick!==pickRevision||!host.isConnected)return;
      const row=result.rows[0];if(!row?.valid){detail.replaceChildren(el('p',s.planInvalid));return;}
      const preview=el('div','','equipment-choice-preview');preview.append(art({...row,kind:record.type},64));
      const read=el('a',s.customize),url=new URL(href(row.key,row.variant),location.origin);url.searchParams.set('craft','1');url.searchParams.set('slot',chosenSlot);if(row.spell)url.searchParams.set('spell',row.spell);url.searchParams.set('runes',row.runes.join(';'));read.href=url;
      detail.replaceChildren(preview,el('strong',record.name),el('small',row.title),read);
      pickerActions.prepend(button(s.equip,()=>{if(plan.entries.length>=32){detail.append(el('p',s.planFull));return;}plan.entries.push(structuredClone(record.plan.entries[0]));assignSlot(plan,plan.entries.length-1,chosenSlot,catalog);onChange();update();closePicker();}));
    }catch{detail.replaceChildren(el('p',s.error));}
  }
  workspace.append(picker);
  host.append(el('p',s.planHelp),workspace,stats,el('p',s.planLimits,'muted'),el('h2',s.plannedEquipment),rows,el('h2',s.materialsNeeded),materials);
  async function update(){
    const rev=++revision;
    try{
      const result=await resolvePlan(plan,{catalog,data,getPage});if(rev!==revision||!host.isConnected)return;resultRows=result.rows;
      stats.replaceChildren();
      for(const [label,value] of [[s.health,num(result.health)],[s.stamina,num(result.stamina)],[s.load,`${num(result.weight)} / ${num(result.capacity)}`],[s.trainingCost,num(result.training)],[s.priceLabel,num(result.value)],[s.constructionLabel,num(result.construction)]]){
        const d=el('div');d.append(el('span',label),el('strong',value));stats.append(d);
      }
      if(result.weight>result.capacity)stats.append(el('p',s.overCapacity,'constructor-error'));
      for(const [slot,b] of slotButtons){
        b.querySelector('img')?.remove();b.querySelector('.slot-name')?.remove();
        const row=resultRows.find(r=>r.slot===slot&&r.valid);b.classList.toggle('filled',!!row);
        b.title=row?row.title:slotName(slot);b.ariaLabel=slotName(slot)+': '+(row?row.title:s.chooseEquipment);
        if(row)b.prepend(art({...row,kind:slotType(slot)==='spell'?'spell':'item'},64));
      }
      rows.replaceChildren();if(!result.rows.length)rows.append(el('p',s.planEmpty));
      result.rows.forEach((row,index)=>{
        const r=el('div','','plan-row'),link=el('a',row.title||s.unavailable),target=new URL(href(row.key,row.variant),location.origin);
        if(row.spell&&row.key.startsWith('item/'))target.searchParams.set('spell',row.spell);if(row.runes.length)target.searchParams.set('runes',row.runes.join(';'));link.href=target;
        const detail=el('div');detail.append(link,el('small',!row.valid?s.planInvalid:row.ready?s.planReady:s.planNeedsTraining));
        const placement=el('label',s.equipment),select=el('select');select.append(new Option(s.inventory,''));
        const type=entrySlotType(catalog.entries.find(e=>e.key===row.key));for(const slot of EQUIPMENT_SLOTS.filter(slot=>slotType(slot)===type))select.append(new Option(slotName(slot),slot));select.value=row.slot||'';
        select.onchange=()=>{assignSlot(plan,index,select.value,catalog);onChange();update();};placement.append(select);placement.className='placement-label';
        const label=el('label',s.quantity),quantity=el('input');quantity.type='number';quantity.min=1;quantity.max=99;quantity.value=row.count;
        quantity.addEventListener('change',()=>{if(!quantity.validity.valid){quantity.reportValidity();return;}plan.entries[index].count=Number(quantity.value);onChange();update();});label.append(quantity);
        const remove=button(s.remove,()=>{plan.entries.splice(index,1);onChange();update();});
        r.append(art({...row,kind:row.key.startsWith('spell/')?'spell':'item'},48),detail,placement,label,remove);rows.append(r);
      });
      materials.replaceChildren();if(!result.materials.size)materials.append(el('p',s.noMaterials));
      for(const m of result.materials.values()){const p=el('p'),a=el('a',m.title);a.href=href(m.key);p.append(a,document.createTextNode(' × '+num(m.count)));materials.append(p);}
    }catch{rows.replaceChildren(el('p',s.error,'constructor-error'));}
  }
  update();
}
