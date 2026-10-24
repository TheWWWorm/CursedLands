from pathlib import Path
import hashlib,json,re,shutil
W=Path(__file__).resolve().parent;R=W.parent/'pt-quality-20261024/repo'
D=R/'docs/validation/path-tracing-traversal-2026-10-24';D.mkdir(parents=True,exist_ok=True)
tags=['recording-final-before','recording-final-after','recording-marks-fixed-first','blood-animation-dx12','blood-animation-vulkan','blood-animation-gl','blood-soft-vulkan','preview2-receivers-dx12','preview2-receivers-gl','preview2-nrd-dx12','preview2-nrd-vulkan','preview2-blood-save-vulkan']
summary=[]
for tag in tags:
    src=W/'checks'/tag
    if not (src/'result.json').exists():continue
    row=json.loads((src/'result.json').read_text());assert row['exit']==0 and not row['errors'],tag
    dst=D/tag;dst.mkdir(exist_ok=True)
    todo=[row['suite']+'.gd'];names=set()
    while todo:
        name=todo.pop()
        if name in names or not (src/'fixtures'/name).exists():continue
        names.add(name)
        for dep in re.findall(r'([A-Za-z_0-9]+\.gd)"',(src/'fixtures'/name).read_text()):
            if dep not in names:todo.append(dep)
    row['fixture_hashes']={n:h for n,h in row['fixture_hashes'].items() if n in names}
    row['full_result_sha256']=hashlib.sha256((src/'result.json').read_bytes()).hexdigest()
    row['summary']=[x for x in row['summary'] if x.startswith(('PASS','FAIL','RECORDING_ROUTE','GROUND_MARK','SOFT_PROJECTED_MARKS','SCENE_RT_DEVICE','BLOOD_POOL_SAVE'))]
    (dst/'result.json').write_text(json.dumps(row,indent=2)+'\n')
    for p in src.glob('*.json'):
        if p.name not in ['result.json','fsr-status.json']:shutil.copy2(p,dst/p.name)
    summary.append({'tag':tag,'suite':row['suite'],'platform':row['platform'],'renderer':row['renderer'],'exit':row['exit'],'errors':row['errors'],'summary':row['summary']})
# This diagnostic run established the cause but contains two obsolete fixture
# assertions: units leave the world map before their nodes are freed. Retain
# its complete outcome explicitly; do not count it as a passed test.
src=W/'checks/recording-marks-isolation'
dst=D/'diagnostic-marks-isolation';dst.mkdir(exist_ok=True)
shutil.copy2(src/'marks-profile.json',dst/'marks-profile.json')
row=json.loads((src/'result.json').read_text());row.pop('fixture_hashes',None)
row['qualification']='diagnostic only; two loot-check timing assertions failed; fixed in the retained route fixture'
row['full_result_sha256']=hashlib.sha256((src/'result.json').read_bytes()).hexdigest()
(dst/'result.json').write_text(json.dumps(row,indent=2)+'\n')
for source,target in [('blood-animation-dx12/blood-animated.png','blood-animated.png'),('blood-animation-dx12/blood-cpu-reference.png','blood-reference.png'),('preview2-blood-save-vulkan/blood-pool-before.png','blood-save-before.png'),('preview2-blood-save-vulkan/blood-pool-after.png','blood-save-after.png')]:
    if (W/'checks'/source).exists():shutil.copy2(W/'checks'/source,D/target)
for label in ['slope','beach','final']:
    p=W/'checks/recording-final-after'/('route-'+label+'.png')
    if p.exists():shutil.copy2(p,D/p.name)
shutil.copy2(W/'preview2/package-audit.json',D/'package-audit.json')
for name in ['delivery2.py','audit_preview2.py','run.py','recording_final_compare.py','qualify_marks_preview.py','collect_traversal_evidence.py']:
    shutil.copy2(W/name,D/name)
(D/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print('Retained',len(summary),'passed runs and a separately identified diagnostic')
