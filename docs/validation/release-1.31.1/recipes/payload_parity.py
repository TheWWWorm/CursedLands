from pathlib import Path
import hashlib,json,zipfile,tarfile,struct
from pack_audit import checked_pack_entries
w=Path.cwd();old=w.parents[1]/'release-1.31.0-20261026/release';r=w.parent/'repo';report={'all_payloads_except_version_and_scene_ids_identical':False,'platforms':{}}
def normalize_scene(data):
 marker=b'node_ids\0'+struct.pack('<II',32,1)
 assert data.count(marker)==1
 start=data.index(marker)+len(marker)
 return data[:start]+b'\0'*4+data[start+4:]
for platform in ['linux-x86_64','windows-x86_64','macos-universal','web']:
 archive=old/'assets'/('CursedLands-1.31.0-'+platform+('.tar.gz' if platform=='linux-x86_64' else '.zip'))
 if platform=='linux-x86_64':
  with tarfile.open(archive) as a:before=a.extractfile('CursedLands-1.31.0-linux-x86_64/CursedLands.pck').read()
 else:
  with zipfile.ZipFile(archive) as a:
   paths=[n for n in a.namelist() if n.endswith('.pck')];assert len(paths)==1;before=a.read(paths[0])
 if platform=='macos-universal':
  with zipfile.ZipFile(w/'CursedLands-1.31.1-macos-universal/CursedLands.zip') as a:after=a.read(next(n for n in a.namelist() if n.endswith('.pck')))
 else:after=(w/('web/unsplit/index.pck' if platform=='web' else 'CursedLands-1.31.1-'+platform+'/CursedLands.pck')).read_bytes()
 aa=dict(checked_pack_entries('before',before));bb=dict(checked_pack_entries('after',after));assert set(aa)==set(bb)
 changed=[n for n in aa if aa[n]!=bb[n]]
 for name in changed:
  if name=='project.binary':assert aa[name].replace(b'1.31.0',b'1.31.1')==bb[name]
  else:
   assert name.startswith('.godot/exported/') and name.endswith('-main.scn'),name
   assert normalize_scene(aa[name])==normalize_scene(bb[name]),name
 report['platforms'][platform]={'resources':len(aa),'changed_resources':changed,'only_version_string_and_generated_root_node_id_differ':True}
with zipfile.ZipFile(old/'assets/CursedLands-1.31.0-windows-x86_64.zip') as z:before=z.read('CursedLands-1.31.0-windows-x86_64/CursedLands.exe')
after=(w/'CursedLands-1.31.1-windows-x86_64/CursedLands.exe').read_bytes()
def sections(data):
 pe=struct.unpack_from('<I',data,0x3c)[0];count=struct.unpack_from('<H',data,pe+6)[0];at=pe+24+struct.unpack_from('<H',data,pe+20)[0];out={}
 for i in range(count):
  p=at+i*40;name=data[p:p+8].rstrip(b'\0').decode();size,offset=struct.unpack_from('<II',data,p+16)
  if name!='.rsrc':out[name]=hashlib.sha256(data[offset:offset+size]).hexdigest()
 return out
assert sections(before)==sections(after)
report['windows_engine_sections_except_resources']=sections(after);report['all_payloads_except_version_and_scene_ids_identical']=True
(w/'payload-parity.json').write_text(json.dumps(report,indent=2)+'\n')
with zipfile.ZipFile(w/'web-prearchive.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in (w/'web/unsplit').rglob('*'):
  if p.is_file():z.write(p,'CursedLands-1.31.1-web/'+str(p.relative_to(w/'web/unsplit')))
print('Game payload parity with 1.31.0 verified; only version strings and generated root-node IDs differ')
