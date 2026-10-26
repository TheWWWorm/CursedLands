extends RefCounted
## Render-thread ownership for the fused RTXDI direct-light pass. History is
## private to one PT scene; no cross-scene reservoir remapping is attempted.
var _rd: RenderingDevice
var _reservoirs:=RID()
var _surfaces:=RID()
var _neighbors:=RID()
var _control:=RID()
var _previous_frame:=RID()
var _last_frame:=PackedByteArray()
var _size:=Vector2i.ZERO
var _index:=0
var _valid:=false
var frames:=0
var resets:=0
var bytes:=0
var active:=false

func prepare_targets(rd: RenderingDevice,size: Vector2i) -> bool:
	_rd=rd
	if size==_size and active:return true
	release_targets()
	if not _neighbors.is_valid():
		# Golden-angle disk covers the SDK's 256-entry cyclic neighbor table.
		var offsets:=PackedFloat32Array()
		for i in 256:
			var angle:=float(i)*2.399963229728653
			var radius:=sqrt((float(i)+0.5)/256.0)
			offsets.append(cos(angle)*radius);offsets.append(sin(angle)*radius)
		_neighbors=_rd.storage_buffer_create(offsets.size()*4,offsets.to_byte_array())
		_control=_rd.uniform_buffer_create(160)
		_previous_frame=_rd.uniform_buffer_create(2816)
	var pixels:=ceili(size.x/16.0)*ceili(size.y/16.0)*256
	_reservoirs=_rd.storage_buffer_create(pixels*2*24)
	_surfaces=_rd.storage_buffer_create(pixels*2*32)
	active=[_reservoirs,_surfaces,_neighbors,_control,_previous_frame].all(func(r: RID):return r.is_valid())
	if not active:dispose();return false
	_size=size;bytes=pixels*112+160+2816+2048
	return true

func uniforms(motion: RID) -> Array[RDUniform]:
	var result: Array[RDUniform]=[]
	for pair in [[33,_reservoirs],[34,_surfaces],[35,_neighbors],[36,_control],[37,_previous_frame],[38,motion]]:
		var u:=RDUniform.new();u.binding=pair[0]
		u.uniform_type=RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER if pair[0] in [36,37] else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.add_id(pair[1]);result.append(u)
	return result

func _matrix(frame: PackedByteArray,offset: int) -> Projection:
	var m:=Projection()
	for c in 4:
		m[c]=Vector4(frame.decode_float(offset+c*16),frame.decode_float(offset+c*16+4),frame.decode_float(offset+c*16+8),frame.decode_float(offset+c*16+12))
	return m

func prepare(frame: PackedByteArray,rr: bool) -> bool:
	if not active:return false
	var history:=_valid and _last_frame.size()==2816 and frame.decode_float(82*4)>.5
	if not history:resets+=1
	var previous:=_last_frame if history else frame
	var view:=_matrix(previous,64).inverse()
	var projection:=_matrix(previous,0).inverse()*view
	var data:=PackedByteArray();data.resize(160)
	for m in 2:
		var matrix: Projection=projection if m==0 else view
		for c in 4:
			for row in 4:data.encode_float(m*64+c*16+row*4,matrix[c][row])
	for i in 4:data.encode_u32(128+i*4,[_size.x,_size.y,1-_index,_index][i])
	for i in 4:data.encode_u32(144+i*4,[int(history),16,int(rr),frames][i])
	return _rd.buffer_update(_control,0,data.size(),data)==OK and _rd.buffer_update(_previous_frame,0,2816,previous)==OK

func finish(frame: PackedByteArray) -> void:
	_last_frame=frame.duplicate();_valid=true;_index=1-_index;frames+=1

func invalidate() -> void:
	_valid=false

func release_targets() -> void:
	if _rd!=null:
		for rid in [_reservoirs,_surfaces]:
			if rid.is_valid():_rd.free_rid(rid)
	_reservoirs=RID();_surfaces=RID();_size=Vector2i.ZERO
	_valid=false;_last_frame.clear();_index=0;active=false;bytes=0

func dispose() -> void:
	release_targets()
	if _rd!=null:
		for rid in [_control,_neighbors,_previous_frame]:
			if rid.is_valid():_rd.free_rid(rid)
	_control=RID();_neighbors=RID();_previous_frame=RID()
