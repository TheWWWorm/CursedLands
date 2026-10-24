#include <windows.h>
#include <setupapi.h>
#include <initguid.h>
#include <devguid.h>
#include <devpropdef.h>
#include <stdio.h>
BOOL WINAPI SetupDiSetDevicePropertyW(HDEVINFO, PSP_DEVINFO_DATA, const DEVPROPKEY *, DEVPROPTYPE, const BYTE *, DWORD, DWORD);
DEFINE_DEVPROPKEY(gpu_uuid_key,0x233a9ef3,0xafc4,0x4abd,0xb5,0x64,0xc3,0x2f,0x21,0xf1,0x53,0x5c,2);
DEFINE_DEVPROPKEY(gpu_luid_key,0x60b193cb,0x5276,0x4d0f,0x96,0xfc,0xf1,0x73,0xab,0xad,0x3e,0xc6,2);
int main(int argc,char **argv) {
 if(argc!=2 || strlen(argv[1])!=32)return 2;
 unsigned char actual[16];for(int i=0;i<16;i++){unsigned v;if(sscanf(argv[1]+2*i,"%2x",&v)!=1)return 3;actual[i]=(unsigned char)v;}
 SendMessageW(GetDesktopWindow(),WM_NULL,0,0);
 HDEVINFO info=SetupDiGetClassDevsW(&GUID_DEVCLASS_DISPLAY,L"PCI",NULL,0);
 if(info==INVALID_HANDLE_VALUE)return 4;
 SP_DEVINFO_DATA d={.cbSize=sizeof(d)};DWORD index=0,type=0;int mapped=0;
 while(SetupDiEnumDeviceInfo(info,index++,&d)) {
  char device[512];SetupDiGetDeviceInstanceIdA(info,&d,device,sizeof(device),NULL);printf("adapter %s\n",device);
  unsigned char previous[16]={0}; LUID luid={0};
  BOOL has_uuid=SetupDiGetDevicePropertyW(info,&d,&gpu_uuid_key,&type,previous,sizeof(previous),NULL,0);
  printf("uuid result %d type %lx error %lu\n",has_uuid,type,GetLastError());
  BOOL has_luid=SetupDiGetDevicePropertyW(info,&d,&gpu_luid_key,&type,(BYTE*)&luid,sizeof(luid),NULL,0);
  printf("luid result %d type %lx value %08lx:%08lx error %lu\n",has_luid,type,luid.HighPart,luid.LowPart,GetLastError());
  if(has_luid && (strstr(device,"VEN_0000&DEV_0000") || !memcmp(previous,actual,16))) {
   if(!SetupDiSetDevicePropertyW(info,&d,&gpu_uuid_key,DEVPROP_TYPE_GUID,actual,16,0)){printf("set failed %lu\n",GetLastError());return 5;}
   mapped++;puts("Mapped Wine display adapter to real Vulkan UUID");
  }
 }
 SetupDiDestroyDeviceInfoList(info);return mapped==1?0:6;
}
