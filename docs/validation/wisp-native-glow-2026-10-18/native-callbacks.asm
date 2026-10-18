
/home/llm2x/Documents/EI/inspection/extracted/app/game.exe:     file format pei-i386


Disassembly of section .text:

00495fb0 <.text+0x94fb0>:
  495fb0:	83 ec 38             	sub    esp,0x38
  495fb3:	8d 44 24 08          	lea    eax,[esp+0x8]
  495fb7:	53                   	push   ebx
  495fb8:	55                   	push   ebp
  495fb9:	56                   	push   esi
  495fba:	8b f1                	mov    esi,ecx
  495fbc:	57                   	push   edi
  495fbd:	8d 4c 24 3c          	lea    ecx,[esp+0x3c]
  495fc1:	50                   	push   eax
  495fc2:	51                   	push   ecx
  495fc3:	8b ce                	mov    ecx,esi
  495fc5:	e8 b6 f2 fe ff       	call   0x485280
  495fca:	8b 7c 24 4c          	mov    edi,DWORD PTR [esp+0x4c]
  495fce:	bd 0a 00 00 00       	mov    ebp,0xa
  495fd3:	33 db                	xor    ebx,ebx
  495fd5:	c7 47 58 ff ff ff 00 	mov    DWORD PTR [edi+0x58],0xffffff
  495fdc:	c7 47 44 03 00 00 00 	mov    DWORD PTR [edi+0x44],0x3
  495fe3:	b9 30 9d 7a 00       	mov    ecx,0x7a9d30
  495fe8:	e8 03 08 fd ff       	call   0x4667f0
  495fed:	89 44 24 1c          	mov    DWORD PTR [esp+0x1c],eax
  495ff1:	89 5c 24 20          	mov    DWORD PTR [esp+0x20],ebx
  495ff5:	df 6c 24 1c          	fild   QWORD PTR [esp+0x1c]
  495ff9:	b9 30 9d 7a 00       	mov    ecx,0x7a9d30
  495ffe:	dc 0d 08 c5 73 00    	fmul   QWORD PTR ds:0x73c508
  496004:	d8 25 4c b8 73 00    	fsub   DWORD PTR ds:0x73b84c
  49600a:	d9 5c 24 14          	fstp   DWORD PTR [esp+0x14]
  49600e:	e8 dd 07 fd ff       	call   0x4667f0
  496013:	89 44 24 24          	mov    DWORD PTR [esp+0x24],eax
  496017:	89 5c 24 28          	mov    DWORD PTR [esp+0x28],ebx
  49601b:	df 6c 24 24          	fild   QWORD PTR [esp+0x24]
  49601f:	68 00 00 80 3f       	push   0x3f800000
  496024:	68 00 00 80 bf       	push   0xbf800000
  496029:	b9 30 9d 7a 00       	mov    ecx,0x7a9d30
  49602e:	dc 0d 08 c5 73 00    	fmul   QWORD PTR ds:0x73c508
  496034:	d8 25 4c b8 73 00    	fsub   DWORD PTR ds:0x73b84c
  49603a:	d9 5c 24 18          	fstp   DWORD PTR [esp+0x18]
  49603e:	e8 2d 29 ff ff       	call   0x488970
  496043:	d9 54 24 4c          	fst    DWORD PTR [esp+0x4c]
  496047:	d8 4c 24 4c          	fmul   DWORD PTR [esp+0x4c]
  49604b:	d9 44 24 10          	fld    DWORD PTR [esp+0x10]
  49604f:	d8 4c 24 10          	fmul   DWORD PTR [esp+0x10]
  496053:	de c1                	faddp  st(1),st
  496055:	d9 44 24 14          	fld    DWORD PTR [esp+0x14]
  496059:	d8 4c 24 14          	fmul   DWORD PTR [esp+0x14]
  49605d:	de c1                	faddp  st(1),st
  49605f:	d8 1d 4c b8 73 00    	fcomp  DWORD PTR ds:0x73b84c
  496065:	df e0                	fnstsw ax
  496067:	f6 c4 01             	test   ah,0x1
  49606a:	75 09                	jne    0x496075
  49606c:	4d                   	dec    ebp
  49606d:	3b eb                	cmp    ebp,ebx
  49606f:	0f 8f 6e ff ff ff    	jg     0x495fe3
  496075:	8b 54 24 4c          	mov    edx,DWORD PTR [esp+0x4c]
  496079:	8b 44 24 10          	mov    eax,DWORD PTR [esp+0x10]
  49607d:	8b 4c 24 14          	mov    ecx,DWORD PTR [esp+0x14]
  496081:	52                   	push   edx
  496082:	50                   	push   eax
  496083:	51                   	push   ecx
  496084:	8d 4c 24 3c          	lea    ecx,[esp+0x3c]
  496088:	e8 53 bd f6 ff       	call   0x401de0
  49608d:	d9 44 24 18          	fld    DWORD PTR [esp+0x18]
  496091:	d8 0d a8 cc 73 00    	fmul   DWORD PTR ds:0x73cca8
  496097:	d9 44 24 30          	fld    DWORD PTR [esp+0x30]
  49609b:	d8 c9                	fmul   st,st(1)
  49609d:	d9 5c 24 24          	fstp   DWORD PTR [esp+0x24]
  4960a1:	d9 44 24 34          	fld    DWORD PTR [esp+0x34]
  4960a5:	d8 c9                	fmul   st,st(1)
  4960a7:	d9 5c 24 28          	fstp   DWORD PTR [esp+0x28]
  4960ab:	d8 4c 24 38          	fmul   DWORD PTR [esp+0x38]
  4960af:	d9 44 24 24          	fld    DWORD PTR [esp+0x24]
  4960b3:	d8 86 98 00 00 00    	fadd   DWORD PTR [esi+0x98]
  4960b9:	d9 44 24 28          	fld    DWORD PTR [esp+0x28]
  4960bd:	d8 86 9c 00 00 00    	fadd   DWORD PTR [esi+0x9c]
  4960c3:	d9 5c 24 34          	fstp   DWORD PTR [esp+0x34]
  4960c7:	d9 c9                	fxch   st(1)
  4960c9:	d8 86 a0 00 00 00    	fadd   DWORD PTR [esi+0xa0]
  4960cf:	8b 54 24 34          	mov    edx,DWORD PTR [esp+0x34]
  4960d3:	89 5f 0c             	mov    DWORD PTR [edi+0xc],ebx
  4960d6:	89 57 04             	mov    DWORD PTR [edi+0x4],edx
  4960d9:	d9 5c 24 38          	fstp   DWORD PTR [esp+0x38]
  4960dd:	8b 44 24 38          	mov    eax,DWORD PTR [esp+0x38]
  4960e1:	d9 1f                	fstp   DWORD PTR [edi]
  4960e3:	89 47 08             	mov    DWORD PTR [edi+0x8],eax
  4960e6:	a1 34 9d 7a 00       	mov    eax,ds:0x7a9d34
  4960eb:	8b c8                	mov    ecx,eax
  4960ed:	48                   	dec    eax
  4960ee:	85 c9                	test   ecx,ecx
  4960f0:	a3 34 9d 7a 00       	mov    ds:0x7a9d34,eax
  4960f5:	75 14                	jne    0x49610b
  4960f7:	b9 30 9d 7a 00       	mov    ecx,0x7a9d30
  4960fc:	e8 6f 8d 00 00       	call   0x49ee70
  496101:	b8 ff 00 00 00       	mov    eax,0xff
  496106:	a3 34 9d 7a 00       	mov    ds:0x7a9d34,eax
  49610b:	8b 14 85 38 9d 7a 00 	mov    edx,DWORD PTR [eax*4+0x7a9d38]
  496112:	89 5c 24 28          	mov    DWORD PTR [esp+0x28],ebx
  496116:	89 54 24 24          	mov    DWORD PTR [esp+0x24],edx
  49611a:	c7 47 50 14 00 00 00 	mov    DWORD PTR [edi+0x50],0x14
  496121:	df 6c 24 24          	fild   QWORD PTR [esp+0x24]
  496125:	dc 0d 10 ce 73 00    	fmul   QWORD PTR ds:0x73ce10
  49612b:	d8 05 38 c5 73 00    	fadd   DWORD PTR ds:0x73c538
  496131:	d9 5f 20             	fstp   DWORD PTR [edi+0x20]
  496134:	8b 8e 94 00 00 00    	mov    ecx,DWORD PTR [esi+0x94]
  49613a:	3b cb                	cmp    ecx,ebx
  49613c:	74 52                	je     0x496190
  49613e:	83 b9 64 02 00 00 03 	cmp    DWORD PTR [ecx+0x264],0x3
  496145:	75 13                	jne    0x49615a
  496147:	c7 86 d0 00 00 00 04 	mov    DWORD PTR [esi+0xd0],0x4
  49614e:	00 00 00 
  496151:	c7 47 50 05 00 00 00 	mov    DWORD PTR [edi+0x50],0x5
  496158:	eb 0a                	jmp    0x496164
  49615a:	c7 86 d0 00 00 00 01 	mov    DWORD PTR [esi+0xd0],0x1
  496161:	00 00 00 
  496164:	8b 01                	mov    eax,DWORD PTR [ecx]
  496166:	ff 90 dc 00 00 00    	call   DWORD PTR [eax+0xdc]
  49616c:	85 c0                	test   eax,eax
  49616e:	74 11                	je     0x496181
  496170:	8b 4e 08             	mov    ecx,DWORD PTR [esi+0x8]
  496173:	53                   	push   ebx
  496174:	83 e1 fa             	and    ecx,0xfffffffa
  496177:	89 4e 08             	mov    DWORD PTR [esi+0x8],ecx
  49617a:	8b ce                	mov    ecx,esi
  49617c:	e8 6f e8 fe ff       	call   0x4849f0
  496181:	5f                   	pop    edi
  496182:	5e                   	pop    esi
  496183:	5d                   	pop    ebp
  496184:	b8 01 00 00 00       	mov    eax,0x1
  496189:	5b                   	pop    ebx
  49618a:	83 c4 38             	add    esp,0x38
  49618d:	c2 08 00             	ret    0x8
  496190:	8b 4e 08             	mov    ecx,DWORD PTR [esi+0x8]
  496193:	53                   	push   ebx
  496194:	83 e1 fa             	and    ecx,0xfffffffa
  496197:	89 4e 08             	mov    DWORD PTR [esi+0x8],ecx
  49619a:	8b ce                	mov    ecx,esi
  49619c:	e8 4f e8 fe ff       	call   0x4849f0
  4961a1:	5f                   	pop    edi
  4961a2:	5e                   	pop    esi
  4961a3:	5d                   	pop    ebp
  4961a4:	33 c0                	xor    eax,eax
  4961a6:	5b                   	pop    ebx
  4961a7:	83 c4 38             	add    esp,0x38
  4961aa:	c2 08 00             	ret    0x8
  4961ad:	90                   	nop
  4961ae:	90                   	nop
  4961af:	90                   	nop
  4961b0:	83 ec 08             	sub    esp,0x8
  4961b3:	56                   	push   esi
  4961b4:	8b 74 24 10          	mov    esi,DWORD PTR [esp+0x10]
  4961b8:	57                   	push   edi
  4961b9:	8b f9                	mov    edi,ecx
  4961bb:	8b 46 50             	mov    eax,DWORD PTR [esi+0x50]
  4961be:	48                   	dec    eax
  4961bf:	89 46 50             	mov    DWORD PTR [esi+0x50],eax
  4961c2:	79 18                	jns    0x4961dc
  4961c4:	c7 46 58 ff ff ff 00 	mov    DWORD PTR [esi+0x58],0xffffff
  4961cb:	c7 46 0c 00 00 00 00 	mov    DWORD PTR [esi+0xc],0x0
  4961d2:	5f                   	pop    edi
  4961d3:	33 c0                	xor    eax,eax
  4961d5:	5e                   	pop    esi
  4961d6:	83 c4 08             	add    esp,0x8
  4961d9:	c2 04 00             	ret    0x4
  4961dc:	c7 46 58 ff ff ff ff 	mov    DWORD PTR [esi+0x58],0xffffffff
  4961e3:	a1 34 9d 7a 00       	mov    eax,ds:0x7a9d34
  4961e8:	8b c8                	mov    ecx,eax
  4961ea:	48                   	dec    eax
  4961eb:	85 c9                	test   ecx,ecx
  4961ed:	a3 34 9d 7a 00       	mov    ds:0x7a9d34,eax
  4961f2:	75 14                	jne    0x496208
  4961f4:	b9 30 9d 7a 00       	mov    ecx,0x7a9d30
  4961f9:	e8 72 8c 00 00       	call   0x49ee70
  4961fe:	b8 ff 00 00 00       	mov    eax,0xff
  496203:	a3 34 9d 7a 00       	mov    ds:0x7a9d34,eax
  496208:	8b 14 85 38 9d 7a 00 	mov    edx,DWORD PTR [eax*4+0x7a9d38]
  49620f:	c7 44 24 0c 00 00 00 	mov    DWORD PTR [esp+0xc],0x0
  496216:	00 
  496217:	89 54 24 08          	mov    DWORD PTR [esp+0x8],edx
  49621b:	df 6c 24 08          	fild   QWORD PTR [esp+0x8]
  49621f:	dc 0d b0 cc 73 00    	fmul   QWORD PTR ds:0x73ccb0
  496225:	d8 05 a8 cc 73 00    	fadd   DWORD PTR ds:0x73cca8
  49622b:	d8 8f 0c 01 00 00    	fmul   DWORD PTR [edi+0x10c]
  496231:	d8 4e 20             	fmul   DWORD PTR [esi+0x20]
  496234:	d9 5e 0c             	fstp   DWORD PTR [esi+0xc]
  496237:	8b 87 94 00 00 00    	mov    eax,DWORD PTR [edi+0x94]
  49623d:	85 c0                	test   eax,eax
  49623f:	75 12                	jne    0x496253
  496241:	8b 4f 08             	mov    ecx,DWORD PTR [edi+0x8]
  496244:	6a 00                	push   0x0
  496246:	83 e1 fa             	and    ecx,0xfffffffa
  496249:	89 4f 08             	mov    DWORD PTR [edi+0x8],ecx
  49624c:	8b cf                	mov    ecx,edi
  49624e:	e8 9d e7 fe ff       	call   0x4849f0
  496253:	5f                   	pop    edi
  496254:	b8 01 00 00 00       	mov    eax,0x1
  496259:	5e                   	pop    esi
  49625a:	83 c4 08             	add    esp,0x8
  49625d:	c2 04 00             	ret    0x4
  496260:	c2 04 00             	ret    0x4
  496263:	90                   	nop
  496264:	90                   	nop
  496265:	90                   	nop
  496266:	90                   	nop
  496267:	90                   	nop
  496268:	90                   	nop
  496269:	90                   	nop
  49626a:	90                   	nop
  49626b:	90                   	nop
  49626c:	90                   	nop
  49626d:	90                   	nop
  49626e:	90                   	nop
  49626f:	90                   	nop
