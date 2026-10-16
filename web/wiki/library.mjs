import {validate} from './plan.mjs';

export const LIBRARY_KEY='cursed-lands.wiki.library.v1';
export const LIBRARY_LIMIT=100;
const TYPES=['item','spell','character'];
const fail=code=>{throw new Error(code);};

function cleanRecord(record) {
  if(!record||typeof record.id!=='string'||!/^[\w-]{1,80}$/.test(record.id)||!TYPES.includes(record.type)
    ||typeof record.name!=='string'||!record.name.trim()||record.name.length>120
    ||!Number.isSafeInteger(record.updated)||record.updated<0)return null;
  const plan=validate(record.plan);
  if(!plan||record.type!=='character'&&(plan.entries.length!==1||!plan.entries[0].key.startsWith(record.type+'/')))return null;
  if(record.type!=='character'){plan.entries[0].slot='';plan.entries[0].count=1;}
  return {id:record.id,type:record.type,name:record.name.trim(),updated:record.updated,plan};
}

// Read again before every write, so another tab's saves are not replaced by an
// old in-memory list. Snapshots are validated and copied before leaving storage.
export function createLibrary(getStorage=()=>localStorage) {
  function read() {
    let raw;
    try{raw=getStorage().getItem(LIBRARY_KEY);}catch{fail('storageUnavailable');}
    if(raw===null)return [];
    try{
      if(raw.length>2_000_000)fail('storageCorrupt');
      const value=JSON.parse(raw);
      if(value?.v!==1||!Array.isArray(value.records)||value.records.length>LIBRARY_LIMIT)fail('storageCorrupt');
      const records=value.records.map(cleanRecord);
      if(records.some(r=>!r)||new Set(records.map(r=>r.id)).size!==records.length)fail('storageCorrupt');
      return records.sort((a,b)=>b.updated-a.updated);
    }catch{fail('storageCorrupt');}
  }
  function write(records){
    try{getStorage().setItem(LIBRARY_KEY,JSON.stringify({v:1,records}));}
    catch(error){fail(error.name==='QuotaExceededError'?'storageFull':'storageUnavailable');}
  }
  return {
    list:read,
    save({type,name,plan}) {
      const records=read();
      if(records.length>=LIBRARY_LIMIT)fail('libraryFull');
      const record=cleanRecord({id:crypto.randomUUID(),type,name,plan,updated:Date.now()});
      if(!record)fail('invalidCreation');
      records.unshift(record);write(records);return record;
    },
    remove(id){const records=read(),removed=records.find(r=>r.id===id);if(!removed)return null;write(records.filter(r=>r.id!==id));return removed;},
    restore(record){const records=read(),clean=cleanRecord(record);if(!clean)fail('invalidCreation');if(records.some(r=>r.id===clean.id))return;if(records.length>=LIBRARY_LIMIT)fail('libraryFull');records.push(clean);write(records);}
  };
}
