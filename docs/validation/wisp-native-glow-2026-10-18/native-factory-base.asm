
/home/llm2x/Documents/EI/inspection/extracted/app/game.exe:     file format pei-i386


Disassembly of section .text:

0048559b <.text+0x8459b>:
  48559b:	8b 08                	mov    ecx,DWORD PTR [eax]
  48559d:	8d 93 70 01 00 00    	lea    edx,[ebx+0x170]
  4855a3:	8b 73 10             	mov    esi,DWORD PTR [ebx+0x10]
  4855a6:	bd 01 00 00 00       	mov    ebp,0x1
  4855ab:	89 0a                	mov    DWORD PTR [edx],ecx
  4855ad:	8b 48 04             	mov    ecx,DWORD PTR [eax+0x4]
  4855b0:	8d be 00 e0 ff ff    	lea    edi,[esi-0x2000]
  4855b6:	89 4a 04             	mov    DWORD PTR [edx+0x4],ecx
  4855b9:	8b 40 08             	mov    eax,DWORD PTR [eax+0x8]
  4855bc:	c7 83 e0 00 00 00 04 	mov    DWORD PTR [ebx+0xe0],0x4
  4855c3:	00 00 00 
  4855c6:	c7 83 cc 00 00 00 64 	mov    DWORD PTR [ebx+0xcc],0x64
  4855cd:	00 00 00 
  4855d0:	89 42 08             	mov    DWORD PTR [edx+0x8],eax
  4855d3:	8b 43 08             	mov    eax,DWORD PTR [ebx+0x8]
  4855d6:	24 e7                	and    al,0xe7
  4855d8:	c7 83 d8 00 00 00 f4 	mov    DWORD PTR [ebx+0xd8],0x1f4
  4855df:	01 00 00 
  4855e2:	0b c5                	or     eax,ebp
  4855e4:	83 ff 52             	cmp    edi,0x52
  4855e7:	89 43 08             	mov    DWORD PTR [ebx+0x8],eax
  4855ea:	c7 83 dc 00 00 00 10 	mov    DWORD PTR [ebx+0xdc],0x10
  4855f1:	00 00 00 
  4855f4:	0f 87 a6 31 00 00    	ja     0x4887a0
  4855fa:	b9 07 00 00 00       	mov    ecx,0x7
  4855ff:	33 d2                	xor    edx,edx
  485601:	8a 97 68 88 48 00    	mov    dl,BYTE PTR [edi+0x488868]
  485607:	ff 24 95 b8 87 48 00 	jmp    DWORD PTR [edx*4+0x4887b8]
