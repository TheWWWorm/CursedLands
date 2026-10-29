extends RefCounted
## Render-thread ownership for the fused RTXDI direct-light pass. History is
## private to one PT scene; no cross-scene reservoir remapping is attempted.
var _rd: RenderingDevice
var _reservoirs:=RID()
var _surfaces:=RID()
var _neighbors:=RID()
var _control:=RID()
var _previous_frame:=RID()
var _current_frame:=RID()
var _last_frame:=PackedByteArray()
var _size:=Vector2i.ZERO
var _index:=0
var _valid:=false
var frames:=0
var resets:=0
var bytes:=0
var active:=false
## Initial light candidates streamed per pixel before reuse: the RTXDI library's
## default of eight; sixteen cost about 0.25 ms more per frame at 1280x720 and
## the temporal reservoir carries the effective sample count (diagnostic
## override --ei-pt-di-candidates=N).
var INITIAL_CANDIDATES:=_candidate_override(8)
## Spatial samples, disocclusion boost samples, permutation sampling and
## bias correction mode (1 = basic; 2 = pairwise MIS needs the shader built
## with that mode allowed and measured slower); diagnostic override
## --ei-pt-di-tuning=a,b,c,d.
## Two spatial neighbours per frame: the temporal reservoir carries most of
## the effective sample count, disocclusions still draw eight, and each
## neighbour costs about a quarter of a millisecond at 1280×720 on the
## river (five neighbours cost 1.0 ms more than one).
var TUNING:=_tuning_override([2,8,1,1])

static func _tuning_override(default: Array) -> Array:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ei-pt-di-tuning="):
			var parts:=arg.trim_prefix("--ei-pt-di-tuning=").split(",",false)
			if parts.size()==4:return [int(parts[0]),int(parts[1]),int(parts[2]),int(parts[3])]
	return default
## Diagnostic: --ei-pt-di-no-reuse disables temporal and spatial reuse.
var REUSE:=not OS.get_cmdline_user_args().has("--ei-pt-di-no-reuse")

static func _candidate_override(default: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ei-pt-di-candidates="):return clampi(int(arg.trim_prefix("--ei-pt-di-candidates=")),1,64)
	return default

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
		_control=_rd.uniform_buffer_create(176)
		# Frame copies as storage buffers: the shader gathers light records
		# with per-lane indices, which a constant buffer would serialise.
		_previous_frame=_rd.storage_buffer_create(2816)
		_current_frame=_rd.storage_buffer_create(2816)
	var pixels:=ceili(size.x/16.0)*ceili(size.y/16.0)*256
	_reservoirs=_rd.storage_buffer_create(pixels*2*24)
	_surfaces=_rd.storage_buffer_create(pixels*2*48)
	active=[_reservoirs,_surfaces,_neighbors,_control,_previous_frame,_current_frame].all(func(r: RID):return r.is_valid())
	if not active:dispose();return false
	_size=size;bytes=pixels*144+176+2816*2+2048
	return true

func uniforms(motion: RID) -> Array[RDUniform]:
	var result: Array[RDUniform]=[]
	for pair in [[33,_reservoirs],[34,_surfaces],[35,_neighbors],[36,_control],[37,_previous_frame],[38,motion],[44,_current_frame]]:
		var u:=RDUniform.new();u.binding=pair[0]
		u.uniform_type=RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER if pair[0]==36 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.add_id(pair[1]);result.append(u)
	return result

func _matrix(values: PackedFloat32Array,start: int) -> Projection:
	var m:=Projection()
	for c in 4:
		var o:=start+c*4
		m[c]=Vector4(values[o],values[o+1],values[o+2],values[o+3])
	return m

func prepare(frame: PackedByteArray,rr: bool) -> bool:
	if not active:return false
	var history:=REUSE and _valid and _last_frame.size()==2816 and frame.decode_float(82*4)>.5
	if not history:resets+=1
	var previous:=_last_frame if history else frame
	var values:=previous.slice(0,32*4).to_float32_array()
	var view:=_matrix(values,16).inverse()
	var projection:=_matrix(values,0).inverse()*view
	var packed:=PackedFloat32Array();packed.resize(32)
	for m in 2:
		var matrix: Projection=projection if m==0 else view
		for c in 4:
			var v: Vector4=matrix[c];packed[m*16+c*4]=v.x;packed[m*16+c*4+1]=v.y;packed[m*16+c*4+2]=v.z;packed[m*16+c*4+3]=v.w
	var data:=packed.to_byte_array();data.resize(176)
	for i in 4:data.encode_u32(128+i*4,[_size.x,_size.y,1-_index,_index][i])
	for i in 4:data.encode_u32(144+i*4,[int(history),INITIAL_CANDIDATES,int(rr),frames][i])
	for i in 4:data.encode_u32(160+i*4,TUNING[i])
	return _rd.buffer_update(_control,0,data.size(),data)==OK and _rd.buffer_update(_previous_frame,0,2816,previous)==OK \
		and _rd.buffer_update(_current_frame,0,2816,frame)==OK

func finish(frame: PackedByteArray) -> void:
	_last_frame=frame.duplicate();_valid=true;_index=1-_index;frames+=1

func invalidate() -> void:
	_valid=false

func release_targets(release: Callable=Callable()) -> void:
	if _rd!=null:
		for rid in [_reservoirs,_surfaces]:
			if rid.is_valid():
				if release.is_valid():release.call(rid)
				else:_rd.free_rid(rid)
	_reservoirs=RID();_surfaces=RID();_size=Vector2i.ZERO
	_valid=false;_last_frame.clear();_index=0;active=false;bytes=0

func dispose(release: Callable=Callable()) -> void:
	release_targets(release)
	if _rd!=null:
		for rid in [_control,_neighbors,_previous_frame,_current_frame]:
			if rid.is_valid():
				if release.is_valid():release.call(rid)
				else:_rd.free_rid(rid)
	_control=RID();_neighbors=RID();_previous_frame=RID();_current_frame=RID()
