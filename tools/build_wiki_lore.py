#!/usr/bin/env python3
"""Compile reviewed lore against private exports from export_wiki_lore_evidence.gd.

Only original-source fingerprints, model references and authored prose are emitted.
Original dialogue, scripts and game archives remain in the evidence directory.
"""
import argparse, collections, hashlib, json, re
from pathlib import Path
from wiki_lore_content import DATA, headings, lia_names

def actor_id(actor):
    value=0
    for byte in actor.upper().encode('ascii',errors='ignore'):
        value=(value*5+byte)&0xffffffff
    return value%1000000000+1000000000

def actor_models(world):
    actors={a.lower() for k,t in world['texts'].items() if k.startswith('briefing ') for a in re.findall(r'(?im)^#phrase\s+(\S+)\s+\d+',t)}
    result={a:[] for a in actors}
    for actor in actors:
        # Evidence is keyed by .mob filename, which need not equal zone ID
        # (e.g. bz1g -> basecam). Resolve the authored campaign map first.
        for zone,record in world['zones'].items():
            objects=world['objects'].get(record.get('mob',''),[])
            for obj in objects:
                if obj.get('name','').lower()==actor or (actor.isascii() and int(obj.get('nid',0))==actor_id(actor)):
                    entry=[zone,obj.get('prototype','')]
                    if entry[1] and entry not in result[actor]:result[actor].append(entry)
    return result

def digest(s):return hashlib.sha256(s.replace('\r','').strip().encode()).hexdigest()
def compile_data():
 DATA['sources']={}
 for campaign,prefix in [('cursed_lands','base-en'),('lost_in_astral','astral-ru')]:
  records=DATA['campaigns'][campaign];w=world[campaign];models=actor_models(w)
  names={x['name'].lower() for x in w['prototypes']};valid_zones={id for id,z in w['zones'].items() if z.get('type')!='edge' and z.get('mpr') and w['texts'].get('zone '+id,'').strip()}
  if campaign=='lost_in_astral':records['allod/gipat']['name_key']='allod gipat2';records['character/guru']['actors'].append('мозгодер')
  records['character/hero']['role']='Protagonist'
  records['character/hero']['prototypes']=['human hero','jun male hero'] if campaign=='cursed_lands' else ['human hero']
  records['character/hero']['locations']=['gz1g','bz1g','bz7g','bz11k','bz13h','bz14h','gz20g'] if campaign=='cursed_lands' else ['bz1r','bz1h','bz3h','bz14g','bz21k','bz31j']
  sources={};DATA['sources'][campaign]=sources
  editions=[raw['base-'+l] for l in ['en','ru','de']] if campaign=='cursed_lands' else [raw['astral-ru']]
  for key,r in records.items():
   r['id']=key.split('/',1)[1]
   if r['kind']=='character':
    r['placements']=[]
    for actor in r['actors']:
     for zone,prototype in models.get(actor,[]):
      if campaign=='lost_in_astral' and actor=='trader' and zone!='bz21k':continue
      item={'zone':zone,'actor':actor,'prototype':prototype.lower()}
      if item not in r['placements']:r['placements'].append(item)
    r['prototypes']=list(dict.fromkeys(r.get('prototypes',[])+[x['prototype'] for x in r['placements']]))
    assert all(x in names for x in r['prototypes']),(key,r['prototypes'])
    assert r['prototypes'],key
    locations=list(r.get('locations',[]))
    for x in r['placements']:
     zone=x['zone']
     if zone in valid_zones:locations.append(zone)
     else:
      mpr=w['zones'].get(zone,{}).get('mpr','')
      locations.extend(z for z in valid_zones if w['zones'][z].get('mpr')==mpr)
    r['locations']=list(dict.fromkeys(locations))
    assert all(z in valid_zones for z in r['locations']),(key,r['locations'])
    original=raw[prefix][r['name_key']].strip()
    localized={l:raw['base-'+l][r['name_key']].strip() for l in ['en','ru','de']} if campaign=='cursed_lands' else dict(zip(['en','ru','de'],[lia_names[r['id']][0],original,lia_names[r['id']][1]]))
    r['names']=localized;r['name_hashes']=list(dict.fromkeys(digest(e.get(r['name_key'],'')) for e in editions))
    if r['id']=='hero' and campaign=='cursed_lands':r['alias_names']={l:raw['base-'+l]['pers junboy'].strip() for l in ['en','ru','de']}
   for s in r['sections']:
    assert s['heading'] in DATA['texts'],s['heading']
    ids=[]
    for src in s['sources']:
     source_key=src.replace(':',' ',1) if ':' in src else 'briefing '+src
     assert source_key in raw[prefix],(key,source_key)
     ids.append(source_key)
     if source_key not in sources:
      source={'hashes':list(dict.fromkeys(digest(e[source_key]) for e in editions if source_key in e))}
      if source_key.startswith('briefing '):
       phrases=re.findall(r'(?im)^#phrase\s+(\S+)\s+\d+',raw[prefix][source_key]);source['actors']=list(dict.fromkeys(x.lower() for x in phrases))
      else:source['world']=source_key
      sources[source_key]=source
    s['sources']=ids
    for text in [s['text'],*DATA['texts'][s['text']]]:
     for link in re.findall(r'\[\[([^]]+)\]\]',text):assert link.split('|',1)[0] in records,(key,link)
  speakers={a.lower() for k,t in raw[prefix].items() if k.startswith('briefing ') for a in re.findall(r'(?im)^#phrase\s+(\S+)\s+\d+',t)}
  covered={a for r in records.values() for a in r.get('actors',[])}
  exclusions=set() if campaign=='cursed_lands' else {'amadios', "exe'ник", 'vas', 'все_хором', 'кувшин', 'матильда', 'неписяи', 'пауки', 'солдат', 'хуман_маил', 'хуман_фемаил'}
  assert speakers-covered==exclusions,('Unreviewed dialogue speakers',campaign,sorted(speakers-covered-exclusions))
  ignored={a:('Background battle cry; no conversation with the protagonist.' if a=='солдат' else 'Developer credits or unused joke dialogue, not a story conversation.') for a in sorted(exclusions)}
  DATA.setdefault('coverage',{})[campaign]={'speakers':sorted(speakers),'excluded':ignored}
 # Every runtime key has translations, and orphaned first drafts are omitted.
 used={s['text'] for records in DATA['campaigns'].values() for r in records.values() for s in r['sections']}
 used.update(h[0] for h in headings)
 DATA['texts']={k:v for k,v in DATA['texts'].items() if k in used}
 return DATA

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence',required=True,type=Path)
    parser.add_argument('--output',type=Path,default=Path(__file__).resolve().parents[1]/'game/src/game/wiki_lore_data.gd')
    args=parser.parse_args(); E=args.evidence
    exported={n:json.loads((E/(n+'-world.json')).read_text()) for n in ['base-en','base-ru','base-de','astral-ru']}
    world={c:exported[n] for c,n in [('cursed_lands','base-en'),('lost_in_astral','astral-ru')]}
    raw={n:value['texts'] for n,value in exported.items()}
    data=compile_data()
    args.output.write_text('class_name WikiLoreData\nextends RefCounted\n## Authored encyclopedia prose, EN → RU/DE, and verified original source fingerprints.\n## Maintain with tools/wiki_lore_content.py and tools/build_wiki_lore.py.\nconst DATA := '+json.dumps(data,ensure_ascii=False,indent='\t')+'\n')
    print('WIKI_LORE_CONTENT', {c:dict(collections.Counter(r['kind'] for r in rows.values())) for c,rows in data['campaigns'].items()},len(data['texts']))
