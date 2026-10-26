import sys,subprocess
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent/'analysis-libs'))
import cv2,numpy as np
from PIL import Image,ImageDraw
p=Path(__file__).parent
src='/home/llm2x/Documents/EI/Evidence/e2/Downloads 2026.10.26 - 00.53.34.04.DVR.mp4'
ims=[]
for t in [205.65,205.6666667,205.6833333]:
 b=subprocess.check_output(['/home/llm2x/.local/bin/ffmpeg','-v','error','-ss',str(t),'-i',src,'-frames:v','1','-f','rawvideo','-pix_fmt','rgb24','-']);ims.append(np.frombuffer(b,np.uint8).reshape(2160,3840,3))
g=[cv2.cvtColor(cv2.resize(z,(640,360)),cv2.COLOR_RGB2GRAY) for z in ims]
y,x=np.mgrid[:360,:640].astype(np.float32);aligned=[]
for j in [0,2]:
 f=cv2.calcOpticalFlowFarneback(g[1],g[j],None,.5,3,25,3,5,1.2,0);aligned.append(cv2.remap(g[j],x+f[:,:,0],y+f[:,:,1],cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE))
b=np.minimum(*aligned).astype(np.float32);d=b-g[1];mask=((d>23)&(d>b*.28)&(b>65)).astype(np.uint8);mask[:12]=0;mask[280:]=0;mask[:,:20]=0;mask[:,-20:]=0;mask=cv2.morphologyEx(mask,cv2.MORPH_OPEN,np.ones((3,3),np.uint8))
n,l,s,c=cv2.connectedComponentsWithStats(mask);rank=sorted(s[1:].tolist(),key=lambda z:z[4],reverse=True);print(rank[:4])
sheet=Image.new('RGB',(1800,600));draw=ImageDraw.Draw(sheet)
if rank:
 a,b,w,h,_=rank[0];cx=(a+w//2)*6;cy=(b+h//2)*6
 for i,im in enumerate(ims):
  crop=Image.fromarray(im).crop((cx-300,cy-280,cx+300,cy+280));sheet.paste(crop,(i*600,30));draw.text((i*600+4,4),str([205.65,205.6667,205.6833][i]),fill='white')
 sheet.save(p/'cliff-triplet.jpg',quality=97)
