import bpy, math, json, argparse, sys
from pathlib import Path
from mathutils import Vector
# Run in an isolated Blender scene. No existing project is opened or modified.
p=argparse.ArgumentParser()
p.add_argument('--output',type=Path,required=True)
p.add_argument('--albedo',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
texture=bpy.data.images.load(str(a.albedo.resolve()), check_existing=True)
texture.pack()
material=bpy.data.materials.new('Weathered beach stone')
material.use_nodes=True
bsdf=material.node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Roughness'].default_value=.94
tex=material.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=texture
material.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
rows=[]
for variant in range(4):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3,radius=1)
 ob=bpy.context.object; ob.name=f'Beach pebble {variant+1}'
 axes=[(.100,.073,.047),(.084,.075,.042),(.111,.064,.047),(.092,.080,.052)][variant]
 for v in ob.data.vertices:
  x,y,z=v.co
  theta=math.atan2(y,x)
  # Broad erosion, not jagged displacement: four asymmetric rounded shapes.
  radius=1+.055*math.sin(theta*3+variant*1.7)*(1-z*z)+.025*x*z
  v.co=(x*axes[0]*radius+.007*z*z, y*axes[1]*radius+.006*x*z, z*axes[2]+.024+.004*x-.003*y*x)
 for poly in ob.data.polygons: poly.use_smooth=True
 ob.data.update()
 ob.data.materials.append(material)
 uv=ob.data.uv_layers.new(name='Stone UV')
 for poly in ob.data.polygons:
  us=[]; vs=[]
  for idx in poly.loop_indices:
   p=ob.data.vertices[ob.data.loops[idx].vertex_index].co
   n=Vector((p.x/axes[0],p.y/axes[1],(p.z-.024)/axes[2])).normalized()
   us.append(math.atan2(n.y,n.x)/(2*math.pi)+.5)
   vs.append(math.acos(max(-1,min(1,n.z)))/math.pi)
  if max(us)-min(us)>.5: us=[u+1 if u<.5 else u for u in us]
  for i,idx in enumerate(poly.loop_indices): uv.data[idx].uv=(us[i],vs[i])
 def export_mesh(mesh):
  mesh.calc_loop_triangles()
  result={'vertices':[],'normals':[],'uvs':[],'indices':[]}
  ids={}
  for tri in mesh.loop_triangles:
   # Blender front faces are CCW; Godot fronts are CW.
   for loop in (tri.loops[0],tri.loops[2],tri.loops[1]):
    v=mesh.vertices[mesh.loops[loop].vertex_index]
    p=v.co; n=v.normal; t=mesh.uv_layers.active.data[loop].uv
    item=tuple(round(float(k),8) for k in (p.x,p.z,-p.y,n.x,n.z,-n.y,t.x,t.y))
    if item not in ids:
     ids[item]=len(result['vertices'])
     result['vertices'].append(item[:3]);result['normals'].append(item[3:6]);result['uvs'].append(item[6:])
    result['indices'].append(ids[item])
  return result
 high=export_mesh(ob.data)
 mod=ob.modifiers.new('Distant silhouette','DECIMATE');mod.ratio=.15
 deps=bpy.context.evaluated_depsgraph_get()
 low=export_mesh(ob.evaluated_get(deps).to_mesh())
 ob.modifiers.remove(mod)
 rows.append({'name':ob.name,'near':high,'far':low})
 ob.location.x=variant*.27
bpy.ops.wm.save_as_mainfile(filepath=str(out/'beach_pebbles.blend'))
(out/'beach_pebbles.json').write_text(json.dumps(rows,separators=(',',':'))+'\n')
print('Saved four Blender pebble models and runtime coordinates to',out)
