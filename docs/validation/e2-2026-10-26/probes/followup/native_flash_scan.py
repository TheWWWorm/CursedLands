from pathlib import Path
import subprocess,json,collections,heapq
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
root=Path(__file__).parent
src=Path('/home/llm2x/Documents/EI/Evidence/e2/Downloads 2026.10.26 - 00.53.34.04.DVR.mp4')
ff='/home/llm2x/.local/bin/ffmpeg';w,h=640,360
hash_rows=[x.split(',') for x in (root/'native.md5').read_text().splitlines() if x and not x.startswith('#')]
sampled=[x.split(',')[-1].strip() for x in (root/'sampled.md5').read_text().splitlines() if x and not x.startswith('#')]
ca=collections.Counter(x[-1].strip() for x in hash_rows);cb=collections.Counter(sampled);missing=ca-cb
p=subprocess.Popen([ff,'-v','error','-ss','195','-i',str(src),'-t','37','-map','0:v:0','-vf',f'scale={w}:{h}','-fps_mode','passthrough','-pix_fmt','rgb24','-f','rawvideo','-'],stdout=subprocess.PIPE)
recent=collections.deque(maxlen=3);rows=[];i=0;best=[]
while True:
 b=p.stdout.read(w*h*3)
 if len(b)!=w*h*3:break
 im=Image.frombytes('RGB',(w,h),b)
 gray=np.asarray(im.convert('L').filter(ImageFilter.BoxBlur(2)),dtype=np.float32)
 recent.append(gray)
 if len(recent)==3:
  before,cur,after=recent;ref=np.minimum(before,after);drop=ref-cur
  mask=(cur<65)&(drop>13)&(drop>ref*.20)&(ref>35)
  mask[:18]=False;mask[270:]=False;mask[:,:65]=False;mask[:,555:]=False
  mask[:95,140:430]=False
  # Broad patch counts survive texture variation; genuine blackening need not reach RGB zero.
  tiles=mask[:264,:640].reshape(33,8,80,8).mean(axis=(1,3));broad=float(np.maximum(tiles-.20,0).sum())
  idx=i-1
  row={'index':idx,'pts_seconds':195+int(hash_rows[idx][2])/60,'dark_pixels':int(mask.sum()),'broad_darkness':broad,'peak_drop':float(drop.max()),'omitted_by_fps':hash_rows[idx][-1].strip() in missing}
  rows.append(row)
 i+=1
p.wait();assert i==len(hash_rows),(i,len(hash_rows))
rows.sort(key=lambda x:x['broad_darkness'],reverse=True)
chosen=[]
for row in rows:
 if all(abs(row['index']-x['index'])>10 for x in chosen):chosen.append(row)
 if len(chosen)==30:break
(root/'native-scan.json').write_text(json.dumps({'native_frames':i,'fps60_frames':len(sampled),'omitted_frame_occurrences':sum(missing.values()),'extra_frame_occurrences':sum((cb-ca).values()),'candidates':chosen,'all_frames':rows},indent=2))
indices=sorted(set(v for r in chosen for v in [r['index']-1,r['index'],r['index']+1]))
expr='+'.join(f'eq(n\\,{i})' for i in indices)
p=subprocess.Popen([ff,'-v','error','-ss','195','-i',str(src),'-t','37','-map','0:v:0','-vf',f'select={expr},scale={w}:{h}','-fps_mode','passthrough','-pix_fmt','rgb24','-f','rawvideo','-'],stdout=subprocess.PIPE)
frames={}
for idx in indices:
 b=p.stdout.read(w*h*3);assert len(b)==w*h*3
 frames[idx]=Image.frombytes('RGB',(w,h),b)
p.wait()
for page in range(5):
 sheet=Image.new('RGB',(1440,6*292),(18,18,18));d=ImageDraw.Draw(sheet)
 for rr,row in enumerate(chosen[page*6:(page+1)*6]):
  for col,di in enumerate([-1,0,1]):
   idx=row['index']+di;im=frames[idx].resize((480,270));sheet.paste(im,(col*480,rr*292+22))
   d.text((col*480+3,rr*292+3),f"{195+int(hash_rows[idx][2])/60:.4f} s  n={idx}"+(' omitted' if row['omitted_by_fps'] and di==0 else ''),fill='white')
 sheet.save(root/f'native-candidates-{page}.jpg',quality=94)
print(json.dumps({'native_frames':i,'omitted':sum(missing.values()),'candidates':chosen[:5]},indent=2))
