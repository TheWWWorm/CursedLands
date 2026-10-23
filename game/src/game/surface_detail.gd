class_name SurfaceDetail
extends RefCounted
## Authored linear data: RG tangent-normal XY, B roughness, A metalness.
## A source fingerprint prevents these atlas regions from misclassifying mods.
const SOURCES := {
	"stone03":"379da2ea1a3acc8ddfc473120f8a96a235bb582bcd6971f930eb709c0adc6126",
	"columnruins01":"58da94fa231fc508aa527c466d3f24cf96275f6ae671284edd52bf4d4bae5f3c",
	"bridge00":"65f4989267e4ff3fdc4e314af3a0492e7a929eee6042c271864d96dfd11292ec",
}
static var _maps := {}
# Diagnostic comparison keeps geometry, albedo and ordinary material settings.
static var _disabled := OS.get_cmdline_user_args().has("--ei-no-surface-detail")

static func matches_source(name: String,data: PackedByteArray) -> bool:
	if not SOURCES.has(name):return false
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(data)
	return hash.finish().hex_encode()==SOURCES[name]

static func texture_for(name: String,albedo: Texture2D) -> Texture2D:
	name=name.to_lower().trim_suffix(".mmp")
	if _disabled or not SOURCES.has(name) or albedo==null or GameData.textures==null:return null
	var key:="%s|%s|%s"%[GameData.root,name,albedo.get_instance_id()]
	if not _maps.has(key):
		var texture: Texture2D
		if matches_source(name,GameData.textures.read(name+".mmp")):
			texture=load("res://assets/materials/surface-detail/%s.png"%name) as Texture2D
		_maps[key]=texture
	return _maps[key]

const SHADER := """
uniform sampler2D surface_detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool surface_detail_enabled = false;
#ifndef EI_NO_MATERIALS
vec3 ei_surface_detail_normal(vec2 encoded, vec2 uv, vec3 p, vec3 n, vec3 view, float strength) {
	vec3 e1=dFdx(p),e2=dFdy(p);
	vec3 face=cross(e1,e2);
	if(dot(face,face)<1e-12) return n;
	face=normalize(face)*(dot(face,view)<0.0?-1.0:1.0);
	// A reflected instance can reverse raster winding independently of its
	// inverse-transpose vertex normal. Use the ray hit's visible hemisphere.
	if(dot(n,face)<0.0) n=-n;
	if(dot(n,view)<=0.0) n=face;
	vec2 uv1=dFdx(uv),uv2=dFdy(uv);
	float det=uv1.x*uv2.y-uv1.y*uv2.x;
	if(abs(det)<1e-10) return n;
	vec3 t=(e1*uv2.y-e2*uv1.y)/det;
	vec3 b=(e2*uv1.x-e1*uv2.x)/det;
	t-=n*dot(n,t);
	if(dot(t,t)<1e-12) return n;
	t=normalize(t);
	b=cross(n,t)*(dot(cross(n,t),b)<0.0?-1.0:1.0);
	vec2 xy=clamp(encoded*2.0-1.0,vec2(-1.0),vec2(1.0))*strength;
	float z=sqrt(max(1.0-dot(xy,xy),0.0));
	vec3 delta=t*xy.x+b*xy.y+n*(z-1.0);
	float bound=1.0;
	float facing=dot(delta,face);
	if(facing<0.0) bound=min(bound,0.8*max(dot(n,face),0.0)/-facing);
	facing=dot(delta,view);
	if(facing<0.0) bound=min(bound,0.8*max(dot(n,view),0.0)/-facing);
	return normalize(n+delta*bound);
}
#endif
"""
