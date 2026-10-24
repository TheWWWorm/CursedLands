import sys,json,hashlib,struct,re,io
from pathlib import Path
from PIL import Image,ImageChops
W=Path(__file__).resolve().parent;R=W.parent/'pt-quality-20261024/repo'
sys.path[:0]=[str(R/'tools'),str(W.parent/'release-1.27.0-20261024/release'),str(W.parent/'creature-projectiles-wisp-20261018/native-libs')]
from pack_audit import checked_pack_entries
from check_fsr_distribution import check_package
import pefile
sha=lambda b:hashlib.sha256(b).hexdigest()
audit={}
for platform,exe,ext in [('linux-x86_64','CursedLands.x86_64','so'),('windows-x86_64','CursedLands.exe','dll')]:
 root=W/'preview'/('CursedLands-1.28.0-experimental.1-'+platform)
 entries={n.removeprefix('res://'):b for n,b in checked_pack_entries('preview',(root/'CursedLands.pck').read_bytes())}
 assert b'1.28.0-experimental.1' in entries['project.binary']
 expected={str(p.relative_to(R/'game')).removesuffix('.gd')+'.gdc' for p in (R/'game/src').rglob('*.gd')}
 assert {n for n in entries if n.endswith('.gdc')}==expected
 for name in ['src/native/path_nrd.cfg','src/game/fx/shaders/nrd/build.json']:
  assert entries[name]==(R/'game'/name).read_bytes()
 assert (root/f'src/native/bin/libpath_nrd.{ext}').read_bytes()==(R/f'game/src/native/bin/libpath_nrd.{ext}').read_bytes()
 for name in entries:assert not re.search(r'(^|/)(tools|local|inspection|scratchpad|dev|debug)(/|$)|\.(sav|eisaves|eipack|mpr|mob|reg|bik|mmp|anm|fig|bon|cpp|hpp)$',name,re.I),name
 audit[platform]={'resource_count':len(entries),'compiled_scripts':len(expected),'pck_sha256':sha((root/'CursedLands.pck').read_bytes()),'exe_sha256':sha((root/exe).read_bytes()),'version':True,'all_scripts_present':True,'nrd_manifest_and_library_match':True,'original_data_absent':True}
 if ext=='dll':
  check_package(root)
  pe=pefile.PE(str(root/exe));icons=[];approved=Image.open(R/'game/assets/branding/icon.ico')
  for resource in pe.DIRECTORY_ENTRY_RESOURCE.entries:
   if resource.id!=3:continue
   for item in resource.directory.entries:
    for lang in item.directory.entries:
     b=pe.get_data(lang.data.struct.OffsetToData,lang.data.struct.Size)
     if b.startswith(b'\x89PNG'):im=Image.open(io.BytesIO(b)).convert('RGBA')
     else:
      width,height=struct.unpack_from('<II',b,4);height//=2
      icon=struct.pack('<HHHBBBBHHII',0,1,1,width%256,height%256,0,0,1,32,len(b),22)+b
      im=Image.open(io.BytesIO(icon)).convert('RGBA')
     ref=approved.ico.getimage(im.size).convert('RGBA')
     assert all(high==0 for low,high in ImageChops.difference(im,ref).getextrema())
     icons.append(im.size)
  assert len(icons)==6
  v=pe.VS_FIXEDFILEINFO[0];assert (v.FileVersionMS>>16,v.FileVersionMS&65535,v.FileVersionLS>>16,v.FileVersionLS&65535)==(1,28,0,0)
  native=pefile.PE(str(root/'src/native/bin/libpath_nrd.dll'))
  deps=[d.dll.decode() for d in native.DIRECTORY_ENTRY_IMPORT]
  assert not any(x.startswith(('libgcc','libstdc++','libwinpthread')) for x in deps)
  audit[platform].update(approved_icon_pixels=icons,windows_file_version='1.28.0.0',agility_runtime_verified=True,nrd_imports=deps)
(W/'preview/package-audit.json').write_text(json.dumps(audit,indent=2)+'\n')
print(json.dumps(audit,indent=2))
