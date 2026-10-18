"""Replay the shipped x86 wisp callbacks, with only engine inputs stubbed.
No original executable code is redistributed. Requires unicorn and pefile.
"""
import argparse, hashlib, json, random, struct
from pathlib import Path
import pefile
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_ECX, UC_X86_REG_EAX
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("binary", type=Path, help="Original Evil Islands game.exe")
parser.add_argument("--out", type=Path, default=Path(__file__).with_name("fixtures") / "wisp_native_callbacks.json")
args = parser.parse_args()
binary = args.binary
assert hashlib.sha256(binary.read_bytes()).hexdigest() == "d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8", "Unknown native binary; recheck callback addresses before replaying."
pe=pefile.PE(str(binary)); image=pe.get_memory_mapped_image()
BASE=pe.OPTIONAL_HEADER.ImageBase
E,P,C,VT,DEAD,STOP=[0x20000000+i*0x1000 for i in range(6)]
STACK=0x10000000

def replay(label, seed, gait=2, dead=False, carrier=True, forced=None):
    uc=Uc(UC_ARCH_X86,UC_MODE_32)
    uc.mem_map(BASE,(len(image)+4095)&~4095); uc.mem_write(BASE,image)
    uc.mem_map(STACK,0x10000); uc.mem_map(E,0x10000)
    draws=forced if forced is not None else [random.Random(seed+i).getrandbits(32) for i in range(256)]
    used=0
    def u32(a): return struct.unpack('<I',uc.mem_read(a,4))[0]
    def put(a,v): uc.mem_write(a,struct.pack('<I',v&0xffffffff))
    def fl(a,v): uc.mem_write(a,struct.pack('<f',v))
    def next_draw():
        nonlocal used
        v=draws[used]; used+=1; return v
    def ret(n, v=None):
        sp=uc.reg_read(UC_X86_REG_ESP)
        uc.reg_write(UC_X86_REG_EIP,u32(sp)); uc.reg_write(UC_X86_REG_ESP,sp+4+n)
        if v is not None: uc.reg_write(UC_X86_REG_EAX,v)
    radius=1.6 if carrier else .1
    def hook(uc,addr,size,data):
        if addr==0x485280:
            sp=uc.reg_read(UC_X86_REG_ESP)
            fl(u32(sp+4),1.2); fl(u32(sp+8),radius); ret(8)
        elif addr==0x4667f0: ret(0,next_draw())
        elif addr in (0x488970,0x4960e6,0x4961e3):
            put(0x7a9d34,1); put(0x7a9d38,next_draw())
        elif addr==0x4849f0:
            sp=uc.reg_read(UC_X86_REG_ESP); put(E+0x94,u32(sp+4)); ret(4)
        elif addr==DEAD: ret(0,int(dead))
        elif addr==STOP: uc.emu_stop()
    uc.hook_add(UC_HOOK_CODE,hook)
    put(C,VT); put(VT+0xdc,DEAD); put(C+0x264,gait)
    put(E+8,0x13); put(E+0x94,C if carrier else 0); put(E+0xd0,1)
    fl(E+0x10c,.05)
    origin=[3.25,-2.5,1.125]
    for i,v in enumerate(origin): fl(E+0x98+i*4,v)
    def call(address,args):
        sp=STACK+0xf000
        uc.mem_write(sp,struct.pack('<'+'I'*(len(args)+1),STOP,*args))
        uc.reg_write(UC_X86_REG_ESP,sp); uc.reg_write(UC_X86_REG_ECX,E)
        uc.emu_start(address,STOP,count=100000)
        particle=list(struct.unpack('<25I',uc.mem_read(P,100)))
        for i in list(range(0,0x11)):
            particle[i]=struct.unpack('<f',struct.pack('<I',particle[i]))[0]
        # Lifetimes are signed, colours remain unsigned.
        particle[0x14]=struct.unpack('<i',struct.pack('<I',particle[0x14]))[0]
        return {'return':uc.reg_read(UC_X86_REG_EAX)!=0,'particle':[particle[i] for i in [0,1,2,3,8,0x11,0x14,0x16]],
                'flags':u32(E+8),'d0':u32(E+0xd0),'carrier':bool(u32(E+0x94)),'rng_used':used}
    steps=[call(0x495fb0,[P,0])]
    # Emitter motion after birth must not drag its existing stars along.
    for i,v in enumerate([13.25,7.5,11.125]): fl(E+0x98+i*4,v)
    for _ in range(23 if gait!=3 else 8): steps.append(call(0x4961b0,[P]))
    return {'label':label,'draws':draws[:used],'gait':gait,'dead':dead,'carrier':carrier,
            'radius':radius,'origin':origin,'steps':steps}

cases=[replay('walk-'+str(i),i*300) for i in range(12)]
cases += [replay('run',9000,gait=3),replay('dead',9400,dead=True),replay('missing',9800,carrier=False)]
cases += [replay('ten-rejections',0,forced=[0xffffffff]*256)]
result={'source_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),
        'addresses':{'spawn':'0x495fb0','update':'0x4961b0'},
        'method':'Unicorn 2.1.4 x86 callbacks; carrier bounds, gait/death and deterministic RNG inputs stubbed. Actual x87 math, rejection loop, lifetime, position and colour instructions executed.',
        'cases':cases}
output=args.out
output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(result,indent=2)+'\n')
print('native wisp callback cases:',len(cases),'steps:',sum(len(c['steps']) for c in cases))

