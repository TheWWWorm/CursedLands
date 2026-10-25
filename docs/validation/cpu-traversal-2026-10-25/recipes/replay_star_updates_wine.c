/* Executes the original x86 update instructions in a private Wine process.
 * No original code is embedded. The mapped executable is read-only on disk.
 * Only its data inputs are supplied: particle state, retained carrier, size
 * and a single queued random value. No original scene or renderer is run. */
typedef unsigned int U32;
typedef unsigned char U8;
#define WIN __attribute__((stdcall,dllimport))
extern void *WIN CreateFileA(const char*,U32,U32,void*,U32,U32,void*);
extern U32 WIN GetFileSize(void*,void*);
extern int WIN ReadFile(void*,void*,U32,U32*,void*);
extern void *WIN VirtualAlloc(void*,U32,U32,U32);
extern void WIN ExitProcess(U32);
extern int __attribute__((dllimport)) printf(const char*,...);
typedef int (__attribute__((thiscall)) *Update)(void*,void*);
static void copy(U8 *d,const U8 *s,U32 n){while(n--)*d++=*s++;}
static U32 get32(U8*p){return *(U32*)p;}
static U32 get16(U8*p){return *(unsigned short*)p;}
void _start(void){
 const char *path="Z:/home/llm2x/Documents/EI/inspection/extracted/app/game.exe";
 void *f=CreateFileA(path,0x80000000,1,0,3,0,0);if(f==(void*)-1)ExitProcess(2);
 U32 size=GetFileSize(f,0),read=0;U8 *raw=VirtualAlloc((void*)0x20000000,size,0x3000,4);
 if(!raw||!ReadFile(f,raw,size,&read,0)||read!=size)ExitProcess(3);
 U8 *nt=raw+get32(raw+0x3c),*opt=nt+24;
 if(get32(nt)!=0x4550||get16(nt+4)!=0x14c||get32(opt+28)!=0x400000)ExitProcess(4);
 U32 pages[4]={0x490000,0x730000,0x780000,0x7a0000};
 for(U32 page=0;page<4;page++){
  U32 base=pages[page];U8 *dest=VirtualAlloc((void*)base,0x10000,0x3000,0x40);
  if(dest!=(void*)base){printf("mapping failed at %x\n",base);ExitProcess(5);}
  U8 *sec=opt+get16(nt+20);
  for(U32 i=0;i<get16(nt+6);i++,sec+=40){
   U32 begin=0x400000+get32(sec+12),end=begin+get32(sec+16);
   U32 left=begin>base?begin:base,right=end<base+0x10000?end:base+0x10000;
   if(right>left)copy((U8*)left,raw+get32(sec+20)+left-begin,right-left);
  }
 }
 printf("{\"method\":\"Original x86 particle update instructions executed under Wine; PE sections mapped at authored addresses; retained carrier, emitter size, particle input and RNG queue supplied; no scene/rendering/spawn execution\",\"rows\":[");
 int first=1;
 for(U32 kind=0;kind<2;kind++)for(U32 trial=0;trial<4;trial++){
  U32 e[128]={0},p[25]={0};float *fp=(float*)p;
  e[8/4]=0x13;e[0x94/4]=1;*(float*)((U8*)e+0x10c)=0.05f;
  fp[0]=3.25f;fp[1]=-2.5f;fp[2]=1.125f;fp[3]=0.0f;
  fp[8]=kind?0.9f:0.08f;fp[0xb]=1.0f;p[0x11]=kind?3:trial*4;p[0x14]=kind?20:15;p[0x16]=kind?0xffffff:0xff6060;
  Update fn=(Update)(kind?0x4961b0:0x492f40);
  for(U32 tick=0;tick<24;tick++){
   U32 draw=0x12345678u+trial*0x21731415u+tick*0x01020304u;
   *(U32*)0x7a9d34=1;*(U32*)0x7a9d38=draw;
   int result=fn(e,p);
   printf("%s{\"type\":%u,\"trial\":%u,\"tick\":%u,\"draw\":%u,\"return\":%d,\"life\":%d,\"z\":%.9g,\"size\":%.9g,\"frame\":%u,\"color\":%u,\"rng_used\":%u}",first?"":",",kind?0x204d:0x2038,trial,tick,draw,result,(int)p[0x14],fp[2],fp[3],p[0x11],p[0x16],1-*(U32*)0x7a9d34);
   first=0;if(!result)break;
  }
 }
 printf("]}\n");ExitProcess(0);
}
