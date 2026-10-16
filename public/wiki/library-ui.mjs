import {art} from './art.mjs';
import {score} from './search.mjs';

export function mountLibrary(host,{library,strings:s,catalog,campaign,getPage,onOpen,onAdd}) {
  const el=(tag,text,cls)=>{const n=document.createElement(tag);if(text)n.textContent=text;if(cls)n.className=cls;return n;};
  const button=(label,fn)=>{const b=el('button',label);b.type='button';b.onclick=fn;return b;};
  host.replaceChildren();
  const intro=el('p',s.localLibraryHelp,'library-intro'),controls=el('div','','library-controls'),queryLabel=el('label',s.searchSaved),query=el('input');query.type='search';queryLabel.append(query);
  const typeLabel=el('label',s.creationType),type=el('select');
  for(const [key,label] of [['','allCreations'],['item','savedItems'],['spell','savedSpells'],['character','savedCharacters']])type.append(new Option(s[label],key));typeLabel.append(type);controls.append(queryLabel,typeLabel);
  const status=el('p','','library-status'),list=el('div','','library-list');status.role='status';
  const body=el('section');body.id='article';body.tabIndex=-1;body.append(intro,controls,status,list);host.append(body);
  function error(e){status.textContent=s[e.message]||s.storageUnavailable;}
  function render(){
    list.replaceChildren();let records;try{records=library.list();}catch(e){error(e);return;}
    const matches=records.filter(r=>(!type.value||r.type===type.value)&&score(query.value,r.name)>=0);
    if(!matches.length){list.append(el('p',records.length?s.noSavedMatches:s.libraryEmpty,'library-empty'));return;}
    for(const record of matches){
      const row=el('article','','library-row'),text=el('div','','library-description'),heading=el('h2',record.name),actions=el('div','','library-actions');
      const entry=record.plan.campaign===campaign?catalog.entries.find(e=>e.key===record.plan.entries[0]?.key):null;
      const hero=catalog.entries.find(e=>e.key==='creature/human%20hero'&&e.image);
      const preview=art(record.type==='character'?hero||{kind:'creature'}:entry||{kind:record.type},64);row.append(preview);
      if(record.type==='item'&&entry)getPage(entry).then(page=>{const version=page.versions.find(v=>v.id===record.plan.entries[0].variant);if(version?.image&&preview.isConnected)preview.replaceWith(art({...entry,image:version.image},64));}).catch(()=>{});
      text.append(heading,el('p',s[{item:'savedItem',spell:'savedSpell',character:'savedCharacter'}[record.type]]+' · '+s[record.plan.campaign==='cursed_lands'?'baseGame':'lostInAstral']+' · '+new Intl.DateTimeFormat(document.documentElement.lang,{dateStyle:'medium',timeStyle:'short'}).format(record.updated)));
      actions.append(button(s.openCreation,()=>onOpen(record)));
      if(record.type!=='character')actions.append(button(s.addPlan,()=>onAdd(record)));
      const remove=button(s.remove,()=>{
        // The confirmation belongs to this row; cancelling never touches storage.
        actions.replaceChildren(el('span',s.removeSavedConfirm),button(s.remove,()=>{try{const removed=library.remove(record.id);render();status.replaceChildren(document.createTextNode(s.removedCreation+' '),button(s.undo,()=>{try{library.restore(removed);status.textContent=s.restoredCreation;render();}catch(e){error(e);}}));}catch(e){error(e);}}),button(s.cancel,render));
      });actions.append(remove);row.append(text,actions);list.append(row);
    }
  }
  query.oninput=render;type.onchange=render;render();
}

export function nameCreation({strings:s,name,onSave,onDone}) {
  const dialog=document.createElement('dialog');dialog.className='save-creation';
  const form=document.createElement('form'),heading=document.createElement('h2');heading.id='save-creation-heading';heading.textContent=s.saveLocally;dialog.setAttribute('aria-labelledby',heading.id);
  const label=document.createElement('label');label.textContent=s.creationName;
  const input=document.createElement('input');input.name='name';input.required=true;input.maxLength=120;input.value=name.slice(0,120);label.append(input);
  const help=document.createElement('p');help.textContent=s.localSaveHelp;
  const error=document.createElement('p');error.role='alert';
  const actions=document.createElement('div');actions.className='save-actions';
  const cancel=document.createElement('button');cancel.type='button';cancel.textContent=s.cancel;cancel.onclick=()=>dialog.close();
  const save=document.createElement('button');save.type='submit';save.textContent=s.saveLocally;actions.append(cancel,save);
  form.append(heading,label,help,error,actions);dialog.append(form);document.body.append(dialog);
  dialog.addEventListener('close',()=>dialog.remove(),{once:true});
  form.onsubmit=e=>{e.preventDefault();if(!input.value.trim()){input.setCustomValidity(s.nameRequired);input.reportValidity();return;}try{onSave(input.value.trim());dialog.close();onDone();}catch(e){error.textContent=s[e.message]||s.storageUnavailable;}};
  input.oninput=()=>input.setCustomValidity('');dialog.showModal();input.select();
}
