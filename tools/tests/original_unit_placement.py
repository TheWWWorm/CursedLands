"""Execute original placement writes; supplied map-link boundary, no renderer claim."""
import hashlib,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'parity'))
from native import Original
from cases import REFERENCE
binary=Path(sys.argv[1]); data=binary.read_bytes()
assert hashlib.sha256(data).hexdigest()==REFERENCE['executable_sha256']
rows=[]
for z in [-20.,-5.55,-.55,0.,1.25,20.]:
 o=Original(data);world=o.alloc(0x100);unit=o.alloc(0x400);point=o.alloc(12)
 o.write(world+4,100,100);o.floats(unit+0x1c,79.5225,59.2278,-20)
 o.write(unit+0x1b8,159,118);o.floats(point,79.5225,59.2278,z)
 # Native removes/reinserts the actor's footprint; fixture supplies a legal
 # same-cell placement. It does not calculate or write the coordinates.
 o.hook(0x5b6a80,lambda:o.ret(1,cleanup=8))
 result=o.run(0x5c11d0,this=world,args=[unit,point])
 rows.append({'requested_z':z,'actual_z':o.number(unit+0x24),'success':bool(result&255)})
 o.close()
report={'executable_sha256':REFERENCE['executable_sha256'],'entry':'0x5c11d0','scope':'Native XYZ placement writes for zone20 height values; legal same-cell map relink supplied, no movement/rendering equivalence claim.','rows':rows}
Path(sys.argv[2]).write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
