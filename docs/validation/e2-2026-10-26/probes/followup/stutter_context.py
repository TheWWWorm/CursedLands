import subprocess
from pathlib import Path
from PIL import Image,ImageDraw
p=Path(__file__).parent
src='/home/llm2x/Documents/EI/Evidence/e2/Downloads 2026.10.26 - 01.02.28.06.DVR.mp4'
times=[125,129,130.7,131.8,133.1,138,140.8,142,143.5,145,150,155]
sheet=Image.new('RGB',(1280,6*380));d=ImageDraw.Draw(sheet)
for i,t in enumerate(times):
 a=subprocess.check_output(['/home/llm2x/.local/bin/ffmpeg','-v','error','-ss',str(t),'-i',src,'-frames:v','1','-vf','scale=640:360','-pix_fmt','rgb24','-f','rawvideo','-'])
 im=Image.frombytes('RGB',(640,360),a);sheet.paste(im,(i%2*640,i//2*380+20));d.text((i%2*640+5,i//2*380+3),str(t),fill='white')
sheet.save(p/'stutter-context.jpg',quality=93)
