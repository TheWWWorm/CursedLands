import assert from 'node:assert/strict';
import {createLibrary,LIBRARY_KEY,LIBRARY_LIMIT} from '../../web/wiki/library.mjs';
import {blank,encode,decode} from '../../web/wiki/plan.mjs';

const values=new Map(),storage={getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value)};
const first=createLibrary(()=>storage),otherTab=createLibrary(()=>storage);
const recipe=(key,spell,runes,variant='')=>({...blank(),entries:[{key,spell,runes,variant,count:3,slot:key.startsWith('spell/')?'spell1':'weapon1'}]});
const enchanted=recipe('item/long%20sword','arrow',['it'],'long sword.steel');
const sword=first.save({name:'Меч · Feuer',type:'item',plan:enchanted});
assert.equal(first.list()[0].name,'Меч · Feuer');
assert.deepEqual(first.list()[0].plan.entries[0],{key:'item/long%20sword',variant:'long sword.steel',spell:'arrow',runes:['it'],count:1,slot:''});
enchanted.entries[0].runes.push('e1');
assert.deepEqual(otherTab.list()[0].plan.entries[0].runes,['it'],'Saving freezes the recipe');
const loaded=otherTab.list()[0];loaded.plan.entries[0].runes.push('e1');
assert.deepEqual(first.list()[0].plan.entries[0].runes,['it'],'Loading does not mutate a snapshot');
const spell=otherTab.save({name:'Acid reach',type:'spell',plan:recipe('spell/acid_ray','acid_ray',['e1','r1'])});
const character=blank('lost_in_astral');character.strength=37;character.skills.melee=61;character.entries=enchanted.entries;
const hero=first.save({name:'Explorer',type:'character',plan:character});
assert.equal(createLibrary(()=>storage).list().length,3,'New page instance restores all three types');
const restored=first.list().find(r=>r.id===hero.id).plan;
assert.equal(restored.campaign,'lost_in_astral');assert.equal(restored.strength,37);assert.equal(restored.skills.melee,61);assert.equal(restored.entries[0].slot,'weapon1');assert.equal(restored.entries[0].count,3);
assert.deepEqual(decode(encode(restored)),restored,'Saved characters remain shareable');
assert.equal(first.list().some(r=>r.id===spell.id),true,'Writes preserve another tab’s saves');
const removed=otherTab.remove(sword.id);assert.equal(first.list().length,2);first.restore(removed);assert.equal(otherTab.list().length,3);first.restore(removed);assert.equal(first.list().length,3,'Undo is idempotent');
assert.throws(()=>first.save({name:'Wrong kind',type:'item',plan:spell.plan}),/invalidCreation/);
assert.throws(()=>first.save({name:'   ',type:'character',plan:character}),/invalidCreation/);
assert.throws(()=>first.save({name:'Invalid',type:'character',plan:{...character,strength:NaN}}),/invalidCreation/);
const blocked=createLibrary(()=>{throw new Error('SecurityError');});assert.throws(()=>blocked.list(),/storageUnavailable/);assert.throws(()=>blocked.save({name:'a',type:'character',plan:character}),/storageUnavailable/);
const full=createLibrary(()=>({getItem:()=>null,setItem:()=>{throw Object.assign(new Error(),{name:'QuotaExceededError'});}}));assert.throws(()=>full.save({name:'a',type:'character',plan:character}),/storageFull/);
const healthy=values.get(LIBRARY_KEY);
for(const bad of ['not json',JSON.stringify({v:2,records:[]}),JSON.stringify({v:1,records:[{...sword,plan:{}}]}),JSON.stringify({v:1,records:[sword,sword]})]){
  values.set(LIBRARY_KEY,bad);assert.throws(()=>first.list(),/storageCorrupt/);assert.throws(()=>first.save({name:'a',type:'character',plan:character}),/storageCorrupt/);assert.equal(values.get(LIBRARY_KEY),bad,'Unreadable storage is never overwritten');
}
values.set(LIBRARY_KEY,healthy);
for(let i=3;i<LIBRARY_LIMIT;i++)first.save({name:'Build '+i,type:'character',plan:blank()});
assert.throws(()=>first.save({name:'Over limit',type:'character',plan:blank()}),/libraryFull/);assert.equal(first.list().length,LIBRARY_LIMIT);
console.log('Wiki library: item, spell and character reloads; snapshot isolation; campaigns; share links; concurrent tabs; remove/undo; invalid data; blocked/full storage; 100-entry limit passed.');
