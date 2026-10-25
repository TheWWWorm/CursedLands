from pathlib import Path
import shutil,subprocess,os,json
s=Path(__file__).resolve().parent;r=s/'repo';dest=s/'actor-parts-profile-game';out=s/'actor-parts-profile'
assert not dest.exists();out.mkdir()
subprocess.run(['cp','-a','--reflink=auto',str(s/'mark-projection-profile-game'),str(dest)],check=True)
# Diagnostic-only splits of the existing animation flush. No gameplay logic
# or number/order of animation calls changes. A scope includes engine advance
# plus property setters; composition includes the root traversal afterwards.
p=dest/'src/game/unit.gd';t=p.read_text()
start=t.index('func _cpu_round4_',t.index('func anim_flush('))
end=t.index('\n\nfunc _set_action(',start)
a=t[start:end]
assert a.count('\t\tEIAnimPart.batch = true\n')==1
assert a.count('\t\tEIAnimPart.batch = false\n')==1
a=a.replace('\t\tEIAnimPart.batch = true\n','\t\tvar cpu_keys_start := Time.get_ticks_usec()\n\t\tEIAnimPart.batch = true\n')
a=a.replace('\t\tEIAnimPart.batch = false\n','\t\tEIAnimPart.batch = false\n\t\tif CpuActorParts.enabled: CpuActorParts.record("animation:keys_hidden" if defer_pose else "animation:keys_visible",Time.get_ticks_usec()-cpu_keys_start)\n')
a=a.replace('\t\tif not defer_pose:\n\t\t\tfor r: EIAnimPart in _anim_roots:', '\t\tif not defer_pose:\n\t\t\tvar cpu_compose_start := Time.get_ticks_usec()\n\t\t\tfor r: EIAnimPart in _anim_roots:')
a=a.replace('\t\t\t\t\tr._apply_key()\n','\t\t\t\t\tr._apply_key()\n\t\t\tif CpuActorParts.enabled: CpuActorParts.record("animation:compose_visible",Time.get_ticks_usec()-cpu_compose_start)\n')
t=t[:start]+a+t[end:];t=t.replace('extends Node3D\n','extends Node3D\nconst CpuActorParts = preload("res://cpu_scope.gd")\n',1);p.write_text(t)
p=dest/'src/ei/unit_model.gd';t=p.read_text();start=t.index('func flush_pending_pose(');end=t.index('\n\n## Vertex morph parts:',start);a=t[start:end]
a=a.replace('\t_pose_pending = false\n','\t_pose_pending = false\n\tvar cpu_pending_start := Time.get_ticks_usec()\n')
a+='\n\tif CpuActorParts.enabled: CpuActorParts.record("animation:materialize_pending",Time.get_ticks_usec()-cpu_pending_start)\n'
t=t[:start]+a+t[end:];t=t.replace('extends Node3D\n','extends Node3D\nconst CpuActorParts = preload("res://cpu_scope.gd")\n',1);p.write_text(t)
# Record the fixed source fragments so future profiling is reproducible.
(s/'actor-parts-profile-fragments.json').write_text(json.dumps({'unit':(dest/'src/game/unit.gd').read_text().split('func anim_flush(',1)[1].split('\n\nfunc _set_action(',1)[0], 'model':a},indent=2))
shutil.copy2(s/'mark-projection-final-linux/runtime.x86_64',out/'runtime.x86_64');shutil.copytree(r/'game/src/native/bin',out/'src/native/bin')
with (s/'actor-parts-profile-export.log').open('w') as log:result=subprocess.run(['/home/llm2x/.local/bin/godot-4','--headless','--path',str(dest),'--export-pack','Linux',str(out/'runtime.pck')],env=os.environ|{'XDG_DATA_HOME':str(s/'import-profile')},stdout=log,stderr=subprocess.STDOUT)
print('Actor parts profile export',result.returncode,flush=True);raise SystemExit(result.returncode)
