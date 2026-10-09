extends RefCounted
## CPU counterpart of GroundSurfaceShader's visible loose-ground query for
## at most two small animals. Reads the existing CPU track images; no GPU
## readback, navigation mutation or extra footprint field is introduced.


static func profile(terrain: EITerrain, tile: Vector2i) -> Vector2:
	var size:=Vector2i(terrain.sectors_x*16,terrain.sectors_y*16)
	tile=tile.clamp(Vector2i.ZERO,size-Vector2i.ONE)
	var id:=int(terrain.land_tile[tile.y*size.x+tile.x])&0x3fff
	var type:=int(terrain.tile_types[id]) if id<terrain.tile_types.size() else 0
	# EITerrain._build_surface_data stores these B/A values in terrain_tiles.
	match type:
		9: return Vector2(0.20,0.30)
		12: return Vector2(0.075,0.12)
		3: return Vector2(0.008,0.025)
	return Vector2.ZERO


static func surface(terrain: EITerrain, p: Vector2, height: float) -> Vector2:
	var tile:=Vector2i((p*0.5).floor())
	if profile(terrain,tile).x==0.0: return Vector2.ZERO
	var grid:=p*0.5-Vector2.ONE*0.5; var base:=Vector2i(grid.floor())
	var f:=grid-Vector2(base); f=Vector2(smoothstep(0,1,f.x),smoothstep(0,1,f.y))
	var value:=profile(terrain,base).lerp(profile(terrain,base+Vector2i(1,0)),f.x).lerp(
		profile(terrain,base+Vector2i(0,1)).lerp(profile(terrain,base+Vector2i.ONE),f.x),f.y)
	var local:=p-Vector2(tile)*2.0; var mask:=1.0
	if profile(terrain,tile+Vector2i(-1,0)).x==0.0: mask*=smoothstep(0,0.6,local.x)
	if profile(terrain,tile+Vector2i(1,0)).x==0.0: mask*=smoothstep(0,0.6,2.0-local.x)
	if profile(terrain,tile+Vector2i(0,-1)).x==0.0: mask*=smoothstep(0,0.6,local.y)
	if profile(terrain,tile+Vector2i(0,1)).x==0.0: mask*=smoothstep(0,0.6,2.0-local.y)
	var size:=Vector2i(terrain.size_ei()); var cell:=Vector2i(p.floor()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
	var index:=cell.y*size.x+cell.x; var water:=float(terrain.water_base[index])
	if not is_finite(water): water=-10000.0
	var material:=int(terrain.water_mat[index]); material=material if material<64 else 0
	water+=float(terrain.water_offsets.get(material,0.0))
	return value*mask*smoothstep(0.025,0.10,height-water)


static func texel(image: Image, p: Vector2) -> Color:
	var size:=image.get_size(); var lo:=Vector2i(p.floor()); var f:=p-Vector2(lo)
	var hi:=(lo+Vector2i.ONE).clamp(Vector2i.ZERO,size-Vector2i.ONE)
	lo=lo.clamp(Vector2i.ZERO,size-Vector2i.ONE)
	return image.get_pixel(lo.x,lo.y).lerp(image.get_pixel(hi.x,lo.y),f.x).lerp(
		image.get_pixel(lo.x,hi.y).lerp(image.get_pixel(hi.x,hi.y),f.x),f.y)


static func displaced(terrain: EITerrain, p: Vector3, origin: Vector2, image: Image, clock: float) -> float:
	var xy:=Vector2(p.x,-p.z); var amount:=surface(terrain,xy,p.y)
	var height:=p.y+amount.x
	if image!=null:
		var track:=texel(image,(xy-origin)*(511.0/32.0))
		var age:=maxf(clock-track.b/maxf(track.a,0.00001),0.0)
		var fade:=clampf((240.0-age)/60.0,0.0,1.0)
		var depth:=track.r*fade; var bank:=track.g*fade
		height+=(bank*(1.0-smoothstep(0.05,0.30,depth))-depth)*amount.y
	return height


static func elevation(terrain: EITerrain, a: Vector3, b: Vector3, c: Vector3, w: Vector3, cell: Vector2i) -> float:
	if terrain._land_mat==null or not terrain._land_mat.get_shader_parameter("soft_ground"):
		return a.y*w.x+b.y*w.y+c.y*w.z
	var image: Image; var clock:=0.0; var dense:=false
	if is_instance_valid(terrain.details) and is_instance_valid(terrain.details.soft_ground):
		var field: SoftGroundField=terrain.details.soft_ground.field
		if field!=null:
			var tile:=(cell/2).clamp(Vector2i.ZERO,field._tile_image.get_size()-Vector2i.ONE)
			var state:=field._tile_image.get_pixelv(tile); var layer:=int(state.r)-1
			if layer>=0 and layer<field._images.size():
				image=field._images[layer]; dense=state.g>0.5
				clock=field._clock_image.get_pixel(0,0).r
	var points: Array[Vector3]=[a,b,c]; var blend:=w
	if dense:
		# Match the installed 16-way subdivision in authored barycentrics,
		# including skewed/jittered triangles, not an invented regular grid.
		var q:=Vector2(w.y,w.z)*16.0; var lo:=q.floor(); var f:=q-lo
		var weights: Array[Vector2]
		if f.x+f.y<=1.0:
			weights=[lo,lo+Vector2(1,0),lo+Vector2(0,1)]; blend=Vector3(1.0-f.x-f.y,f.x,f.y)
		else:
			weights=[lo+Vector2(1,0),lo+Vector2.ONE,lo+Vector2(0,1)]; blend=Vector3(1.0-f.y,f.x+f.y-1.0,1.0-f.x)
		for i in 3:
			var uv:=weights[i]/16.0; points[i]=a*(1.0-uv.x-uv.y)+b*uv.x+c*uv.y
	var origin:=Vector2(cell/32)*32.0; var result:=0.0
	for i in 3: result+=blend[i]*displaced(terrain,points[i],origin,image,clock)
	return result
