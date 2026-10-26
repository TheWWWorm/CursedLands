import sys,subprocess,json,collections
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent/'analysis-libs'))
import cv2,numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).parent
src=Path('/home/llm2x/Documents/EI/Evidence/e2/Downloads 2026.10.26 - 00.53.34.04.DVR.mp4')
w,h,fps=640,360,60
p=subprocess.Popen(['/home/llm2x/.local/bin/ffmpeg','-v','error','-ss','202','-i',str(src),'-t','10','-vf',f'fps={fps},scale={w}:{h}','-pix_fmt','rgb24','-f','rawvideo','-'],stdout=subprocess.PIPE)
frames=[]
while True:
 b=p.stdout.read(w*h*3)
 if len(b)!=w*h*3:break
 frames.append(np.frombuffer(b,np.uint8).reshape(h,w,3).copy())
p.wait(); print('frames',len(frames),flush=True)
gray=[cv2.cvtColor(x,cv2.COLOR_RGB2GRAY) for x in frames]
y,x=np.mgrid[:h,:w].astype(np.float32)
rows=[]
for i in range(1,len(frames)-1):
 cur=gray[i]; matched=[]
 for j in [i-1,i+1]:
  flow=cv2.calcOpticalFlowFarneback(cur,gray[j],None,.5,3,25,3,5,1.2,0)
  matched.append(cv2.remap(gray[j],x+flow[:,:,0],y+flow[:,:,1],cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE))
 before,after=matched
 baseline=np.minimum(before,after).astype(np.float32)
 delta=baseline-cur
 # Candidate broad darkening after motion compensation, away from HUD/edges.
 mask=((delta>23)&(delta>baseline*.28)&(baseline>65)).astype(np.uint8)
 mask[:12]=0;mask[280:]=0;mask[:,:20]=0;mask[:,-20:]=0
 mask=cv2.morphologyEx(mask,cv2.MORPH_OPEN,np.ones((3,3),np.uint8))
 num,lab,stats,cent=cv2.connectedComponentsWithStats(mask)
 area=int(stats[1:,cv2.CC_STAT_AREA].max()) if num>1 else 0
 rows.append({'frame':i,'time':202+i/fps,'area':area,'pixels':int(mask.sum()),'mean_drop':float(delta[mask>0].mean()) if mask.any() else 0})
 if i%100==0:print(i,flush=True)
rows.sort(key=lambda r:r['area'],reverse=True)
(root/'video-single-frame.json').write_text(json.dumps(rows,indent=2))
chosen=[]
for r in rows:
 if all(abs(r['frame']-s['frame'])>12 for s in chosen):chosen.append(r)
 if len(chosen)==16:break
for page in range(2):
 sheet=Image.new('RGB',(960,8*200),(22,22,22));draw=ImageDraw.Draw(sheet)
 for k,r in enumerate(chosen[page*8:(page+1)*8]):
  for col,di in enumerate([-1,0,1]):
   im=Image.fromarray(frames[r['frame']+di]);im.thumbnail((320,180));sheet.paste(im,(col*320,k*200+20))
   draw.text((col*320+4,k*200+3),f"{r['time']+di/fps:.3f}s area={r['area']}" if col==1 else f"{r['time']+di/fps:.3f}s",fill='white')
 sheet.save(root/f'video-single-frame-{page}.jpg',quality=92)
print(json.dumps(chosen,indent=2))
