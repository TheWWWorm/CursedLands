extends RefCounted
## A bounded subset of R1 terrain_cliff.h / native_shader.h: 40–55 degree
## side weights, a vertex facet guard, and symmetric neighbouring tile reads.
## Uses original plain-rock atlas tiles and the existing padded tile sampler.
const FUNCTIONS := """
uniform sampler2D cliff_tiles : filter_nearest, repeat_disable;
uniform sampler2D cliff_flatness : filter_nearest, repeat_disable;
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
	side*=1.0-smoothstep(0.72,0.95,cliff_guard((vec2(cell)+p)*2.0));
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
vec3 cliff_tile(float packed,vec3 world,vec3 planes,vec3 wx,vec3 wy) {
	vec3 c=vec3(0.0);
	// Derivatives are taken before wrapping and atlas rotation. The existing
	// tile sampler keeps mip footprints inside each tile's authored gutter.
	if (planes.x>0.0) { c+=tile_sample(packed,fract(vec2(-world.z,world.y)*0.5),vec2(-wx.z,wx.y)*0.5,vec2(-wy.z,wy.y)*0.5)*planes.x; }
	if (planes.z>0.0) { c+=tile_sample(packed,fract(world.xy*0.5),wx.xy*0.5,wy.xy*0.5)*planes.z; }
	return c;
}
vec3 cliff_albedo(vec3 original,ivec2 cell,vec2 p,vec3 world,vec3 planes) {
	if (planes.y<=0.0) { return original; }
	vec3 wx=dFdx(world); vec3 wy=dFdy(world);
	vec3 own=cliff_tile(tile_info(cell).r,world,planes,wx,wy);
	vec3 colour=own;
	vec2 weight=0.5*(1.0-smoothstep(vec2(0.0),vec2(0.15),min(p,1.0-p)));
	ivec2 step_cell=ivec2(p.x<0.5 ? -1:1,p.y<0.5 ? -1:1);
	if (weight.x>0.0 && cliff_eligible(cell+ivec2(step_cell.x,0))>0.5) {
		colour=mix(colour,cliff_tile(tile_info(cell+ivec2(step_cell.x,0)).r,world,planes,wx,wy),weight.x);
	}
	if (weight.y>0.0) {
		vec3 other=cliff_eligible(cell+ivec2(0,step_cell.y))>0.5 ? cliff_tile(tile_info(cell+ivec2(0,step_cell.y)).r,world,planes,wx,wy) : own;
		if (weight.x>0.0 && cliff_eligible(cell+step_cell)>0.5) {
			other=mix(other,cliff_tile(tile_info(cell+step_cell).r,world,planes,wx,wy),weight.x);
		}
		colour=mix(colour,other,weight.y);
	}
	return original*(1.0-planes.y)+colour;
}
"""


static func source(original: String) -> String:
	var code := original.replace("shader_type spatial;", "shader_type spatial;\n#define EI_TERRAIN_CLIFFS")
	code = code.replace("float ground_height(vec3 colour)", FUNCTIONS + "\nfloat ground_height(vec3 colour)")
	code = code.replace("float stone = traits.x;", """vec3 cliff_normal=normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).xyz);
		vec3 cliff_planes=cliff_weights(tile,clamp(local,vec2(0.0),vec2(1.0)),cliff_normal,length(VERTEX))*detail;
		float stone = traits.x;""")
	code = code.replace("* frame_scale * painted_relief * fade", "* frame_scale * painted_relief * fade * (1.0-cliff_planes.y)")
	code = code.replace("// large, soft brightness variation", "c=cliff_albedo(c,tile,clamp(local,vec2(0.0),vec2(1.0)),wpos,cliff_planes);\n\t\t// large, soft brightness variation")
	return code
