from pathlib import Path
import io,struct,json,zipfile,hashlib
from PIL import Image
w=Path(__file__).resolve().parent;r=w.parent/'repo';exe=w/'CursedLands-1.31.1-windows-x86_64/CursedLands.exe';data=exe.read_bytes()
u16=lambda p:struct.unpack_from('<H',data,p)[0];u32=lambda p:struct.unpack_from('<I',data,p)[0]
pe=u32(0x3c);opt=pe+24;sections=opt+u16(pe+20);rsrc=u32(opt+112+16)
sec=[(u32(sections+i*40+12),u32(sections+i*40+8),u32(sections+i*40+20)) for i in range(u16(pe+6))]
def off(rva):
 for base,size,raw in sec:
  if base<=rva<base+size:return raw+rva-base
 raise ValueError(rva)
base=off(rsrc);resources={}
def walk(at,ids=[]):
 for i in range(u16(at+12)+u16(at+14)):
  name,dest=struct.unpack_from('<II',data,at+16+i*8)
  if name&0x80000000:
   pos=base+(name&0x7fffffff);name=data[pos+2:pos+2+u16(pos)*2].decode('utf-16le')
  if dest&0x80000000:walk(base+(dest&0x7fffffff),ids+[name])
  else:
   entry=base+dest;rva,n=struct.unpack_from('<II',data,entry);resources[tuple(ids+[name])]=data[off(rva):off(rva)+n]
walk(base)
ico=Image.open(r/'game/assets/branding/icon.ico');sizes=[]
for ids,b in resources.items():
 if ids[0]!=3:continue
 if b.startswith(b'\x89PNG'):im=Image.open(io.BytesIO(b)).convert('RGBA')
 else:
  # Rewrap this bitmap as a standalone ICO.
  width,height=struct.unpack_from('<ii',b,4);height//=2
  icon=struct.pack('<HHHBBBBHHII',0,1,1,width%256,height%256,0,0,1,32,len(b),22)+b
  im=Image.open(io.BytesIO(icon)).convert('RGBA')
 expected=ico.ico.getimage(im.size).convert('RGBA');assert im.tobytes()==expected.tobytes(),im.size
 assert im.getextrema()[3][0]==0 and im.getextrema()[3][1]==255
 sizes.append(im.width)
assert sorted(sizes)==[16,32,48,64,128,256],sizes
v=next(b for ids,b in resources.items() if ids[0]==16);assert '1.31.1.0'.encode('utf-16le') in v
with zipfile.ZipFile(w/'CursedLands-1.31.1-macos-universal/CursedLands.zip') as z:
 n=next(n for n in z.namelist() if n.endswith('.icns'));assert z.read(n)==(r/'game/assets/branding/icon.icns').read_bytes()
for n in ['index.png','index.icon.png','index.apple-touch-icon.png','icon-192.png','icon-512.png']:
 expected=r/('game/assets/branding/splash.png' if n=='index.png' else 'public/'+n)
 assert (w/'web/unsplit'/n).read_bytes()==expected.read_bytes()
result={'windows_icon_sizes':sorted(sizes),'windows_icon_pixels_exact':True,'windows_version':'1.31.1.0','macos_icon_exact':True,'web_icons_exact':True,'approved_master_sha256':hashlib.sha256((r/'game/icon.png').read_bytes()).hexdigest()}
(w/'branding-audit.json').write_text(json.dumps(result,indent=2)+'\n');print('PASS: embedded Windows/macOS icons, web derivatives and Windows version')
