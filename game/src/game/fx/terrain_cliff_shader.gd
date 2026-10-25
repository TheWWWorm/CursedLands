extends RefCounted
## A bounded subset of R1 terrain_cliff.h / native_shader.h: 40–55 degree
## side weights, a vertex facet guard, and symmetric neighbouring tile reads.
## Uses verified natural donors, geometric slope and the padded tile sampler.
const FUNCTIONS := """
uniform sampler2D cliff_tiles : filter_nearest, repeat_disable;
uniform sampler2D cliff_flatness : filter_nearest, repeat_disable;
uniform sampler2D cliff_blends : filter_nearest, repeat_disable;
float cliff_eligible(ivec2 cell) {
	if (any(lessThan(cell,ivec2(0))) || any(greaterThanEqual(cell,textureSize(cliff_tiles,0)))) { return 0.0; }
	return texelFetch(cliff_tiles,cell,0).r;
}
float cliff_guard(vec2 grid) {
	ivec2 a=clamp(ivec2(floor(grid)),ivec2(0),textureSize(cliff_flatness,0)-2);
	vec2 p=clamp(grid-vec2(a),vec2(0.0),vec2(1.0));
	float ne=texelFetch(cliff_flatness,a+ivec2(1,0),0).r;
	float sw=texelFetch(cliff_flatness,a+ivec2(0,1),0).r;
	if (p.x+p.y>1.0) { return ne*(1.0-p.y)+sw*(1.0-p.x)+texelFetch(cliff_flatness,a+ivec2(1),0).r*(p.x+p.y-1.0); }
	return texelFetch(cliff_flatness,a,0).r*(1.0-p.x-p.y)+ne*p.x+sw*p.y;
}
vec3 cliff_weights(ivec2 cell,vec2 p,vec3 normal,float distance_to_eye) {
	if (cliff_eligible(cell)<0.5) { return vec3(0.0); }
	vec3 n=abs(normalize(normal));
	float side=(1.0-smoothstep(0.57357644,0.76604444,n.y))*(1.0-smoothstep(80.0,140.0,distance_to_eye));
	if (side<=0.0) { return vec3(0.0); }
	side*=1.0-smoothstep(0.72,0.95,min(cliff_guard((vec2(cell)+p)*2.0),n.y));
	vec2 weight=0.5*(1.0-smoothstep(vec2(0.0),vec2(0.15),min(p,1.0-p)));
	ivec2 step_cell=ivec2(p.x<0.5 ? -1:1,p.y<0.5 ? -1:1);
	// An unsupported neighbour remains exactly original; the eligible side
	// reaches that same original colour at their shared edge and corner.
	if (cliff_eligible(cell+ivec2(step_cell.x,0))<0.5) { side*=1.0-2.0*weight.x; }
	if (cliff_eligible(cell+ivec2(0,step_cell.y))<0.5) { side*=1.0-2.0*weight.y; }
	if (cliff_eligible(cell+step_cell)<0.5) { side*=1.0-4.0*weight.x*weight.y; }
	vec2 axes=n.xz*n.xz; axes/=max(axes.x+axes.y,1e-8);
	axes=max(axes-0.02,vec2(0.0)); axes/=max(axes.x+axes.y,1e-8);
	return vec3(axes.x*side,side,axes.y*side);
}
// Integer lattice hashing is identical in raster and traced materials.
float cliff_hash(ivec2 cell) {
 uint h=uint(cell.x)*73856093u ^ uint(cell.y)*19349663u;
 h^=h>>16u; h*=0x7feb352du; h^=h>>15u; h*=0x846ca68bu; h^=h>>16u;
 return float(h&16777215u)/16777215.0;
}
// Value and analytic derivatives of a continuous world-anchored noise field.
vec3 cliff_noise(vec2 p) {
 ivec2 cell=ivec2(floor(p)); vec2 f=fract(p),u=f*f*(3.0-2.0*f),d=6.0*f*(1.0-f);
 float a=cliff_hash(cell),b=cliff_hash(cell+ivec2(1,0)),c=cliff_hash(cell+ivec2(0,1)),e=cliff_hash(cell+ivec2(1));
 return vec3(mix(mix(a,b,u.x),mix(c,e,u.x),u.y),mix(b-a,e-c,u.y)*d.x,mix(c-a,e-b,u.x)*d.y);
}
vec2 cliff_turn(vec2 p) { return vec2(0.8*p.x-0.6*p.y,0.6*p.x+0.8*p.y); }
struct CliffProjection { vec4 uv; vec4 gx; vec4 gy; float blend; };
CliffProjection cliff_project(vec2 p,vec2 dx,vec2 dy) {
 // Two differently oriented mirrored reads hide the non-seamless source
 // edges. A gentle continuous warp and irregular blend break the mirror
 // grid without random per-frame changes or a new texture allocation.
 vec3 noise=cliff_noise(p*0.43+vec2(7.1,-3.7));
 vec2 warp=vec2(0.55,-0.385),q=p+warp*(noise.x-0.5);
 vec2 gx=dx+warp*dot(noise.yz*0.43,dx),gy=dy+warp*dot(noise.yz*0.43,dy);
 vec4 phase=fract(vec4(q,cliff_turn(q)+vec2(0.37,0.83))*0.5);
 vec4 direction=mix(vec4(-1.0),vec4(1.0),lessThan(phase,vec4(0.5)));
 CliffProjection result;
 result.uv=1.0-abs(phase*2.0-1.0);
 result.gx=vec4(gx,cliff_turn(gx))*direction;result.gy=vec4(gy,cliff_turn(gy))*direction;
 result.blend=0.15+0.7*smoothstep(0.15,0.85,cliff_noise(p*0.63+vec2(-11.3,4.9)).x);
 return result;
}
vec3 cliff_sample(float packed,CliffProjection projection) {
 return mix(tile_sample(packed,projection.uv.xy,projection.gx.xy,projection.gy.xy),tile_sample(packed,projection.uv.zw,projection.gx.zw,projection.gy.zw),projection.blend);
}
vec3 cliff_projected_tile(float packed,vec3 planes,CliffProjection x,CliffProjection z) {
 vec3 c=vec3(0.0);
 if (planes.x>0.0) { c+=cliff_sample(packed,x)*planes.x; }
 if (planes.z>0.0) { c+=cliff_sample(packed,z)*planes.z; }
 return c;
}
vec3 cliff_tile(float packed,vec3 world,vec3 planes,vec3 wx,vec3 wy) {
 CliffProjection x=CliffProjection(vec4(0.0),vec4(0.0),vec4(0.0),0.0),z=x;
 if (planes.x>0.0) { x=cliff_project(vec2(-world.z,world.y)*0.5,vec2(-wx.z,wx.y)*0.5,vec2(-wy.z,wy.y)*0.5); }
 if (planes.z>0.0) { z=cliff_project(world.xy*0.5,wx.xy*0.5,wy.xy*0.5); }
 return cliff_projected_tile(packed,planes,x,z);
}
vec3 cliff_projected_surface(ivec2 cell,vec2 p,vec3 planes,CliffProjection x,CliffProjection z) {
	vec4 row=texelFetch(cliff_blends,cell,0);
	if (row.r<0.5) { return cliff_projected_tile(tile_info(cell).r,planes,x,z); }
	p=smoothstep(vec2(0.2),vec2(0.8),clamp(p,vec2(0.0),vec2(1.0)));
	vec4 weights=vec4((1.0-p.x)*(1.0-p.y),p.x*(1.0-p.y),(1.0-p.x)*p.y,p.x*p.y);
	vec3 colour=vec3(0.0);
	for (int k=0;k<4;k++) {
		for (int j=k+1;j<4;j++) { if (row[k]==row[j]) { weights[k]+=weights[j]; weights[j]=0.0; } }
		if (weights[k]>0.0) { colour+=cliff_projected_tile(row[k]-1.0,planes,x,z)*weights[k]; }
	}
	return colour;
}
vec3 cliff_albedo(vec3 original,ivec2 cell,vec2 p,vec3 world,vec3 planes) {
	if (planes.y<=0.0) { return original; }
	vec3 wx=dFdx(world); vec3 wy=dFdy(world);
	// Compute the world projection once, then share it across material donors.
 CliffProjection x=CliffProjection(vec4(0.0),vec4(0.0),vec4(0.0),0.0),z=x;
 if (planes.x>0.0) { x=cliff_project(vec2(-world.z,world.y)*0.5,vec2(-wx.z,wx.y)*0.5,vec2(-wy.z,wy.y)*0.5); }
 if (planes.z>0.0) { z=cliff_project(world.xy*0.5,wx.xy*0.5,wy.xy*0.5); }
 vec3 own=cliff_projected_surface(cell,p,planes,x,z);
	vec3 colour=own;
	vec2 weight=0.5*(1.0-smoothstep(vec2(0.0),vec2(0.15),min(p,1.0-p)));
	ivec2 step_cell=ivec2(p.x<0.5 ? -1:1,p.y<0.5 ? -1:1);
	if (weight.x>0.0 && cliff_eligible(cell+ivec2(step_cell.x,0))>0.5) {
		colour=mix(colour,cliff_projected_surface(cell+ivec2(step_cell.x,0),p-vec2(ivec2(step_cell.x,0)),planes,x,z),weight.x);
	}
	if (weight.y>0.0) {
		vec3 other=cliff_eligible(cell+ivec2(0,step_cell.y))>0.5 ? cliff_projected_surface(cell+ivec2(0,step_cell.y),p-vec2(ivec2(0,step_cell.y)),planes,x,z) : own;
		if (weight.x>0.0 && cliff_eligible(cell+step_cell)>0.5) {
			other=mix(other,cliff_projected_surface(cell+step_cell,p-vec2(step_cell),planes,x,z),weight.x);
		}
		colour=mix(colour,other,weight.y);
	}
	return original*(1.0-planes.y)+colour;
}
"""


static func source(original: String) -> String:
	var code := original.replace("shader_type spatial;", "shader_type spatial;\n#define EI_TERRAIN_CLIFFS")
	code = code.replace("float ground_height(vec3 colour)", FUNCTIONS + "\nfloat ground_height(vec3 colour)")
	code = code.replace("float stone = traits.x;", """vec3 cliff_normal=normalize(cross(dFdx(wpos),dFdy(wpos)));
		vec3 cliff_planes=cliff_weights(tile,clamp(local,vec2(0.0),vec2(1.0)),cliff_normal,length(VERTEX))*detail;
		float stone = traits.x;""")
	code = code.replace("* frame_scale * painted_relief * fade", "* frame_scale * painted_relief * fade * (1.0-cliff_planes.y)")
	code = code.replace("// large, soft brightness variation", "c=cliff_albedo(c,tile,clamp(local,vec2(0.0),vec2(1.0)),wpos,cliff_planes);\n\t\t// large, soft brightness variation")
	return code
