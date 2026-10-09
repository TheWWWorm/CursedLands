extends RefCounted
## Two-family subset of R1 terrain_tile_blend.hlsl: authored corner field,
## bounded domain warp and texel-height edge variation. Original own art is
## retained at pure endpoints and beside every unsupported neighbour.
const FUNCTIONS := """
uniform sampler2D transition_tiles : filter_nearest, repeat_disable;
vec4 transition_row(ivec2 cell) {
	if (any(lessThan(cell,ivec2(0))) || any(greaterThanEqual(cell,textureSize(transition_tiles,0)))) { return vec4(0.0); }
	return texelFetch(transition_tiles,cell,0);
}
float transition_noise(vec2 p) {
	vec2 cell=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	vec4 q=vec4(dot(cell,vec2(127.1,311.7)),dot(cell+vec2(1.0,0.0),vec2(127.1,311.7)),
		dot(cell+vec2(0.0,1.0),vec2(127.1,311.7)),dot(cell+vec2(1.0),vec2(127.1,311.7)));
	vec4 h=fract(sin(q)*43758.5453);
	return mix(mix(h.x,h.y,f.x),mix(h.z,h.w,f.x),f.y);
}
float transition_weight(vec4 row,vec2 p,int family_b) {
	int pair=int(row.a+0.5); int a=pair&63; int b=pair>>6;
	if (a==b) { return b==family_b ? 1.0 : 0.0; }
	int bits=int(row.b+0.5)&15;
	vec4 w=vec4(float(bits&1),float((bits>>1)&1),float((bits>>2)&1),float((bits>>3)&1));
	float weight=mix(mix(w.x,w.y,p.x),mix(w.z,w.w,p.x),p.y);
	return b==family_b ? weight : 1.0-weight;
}
bool transition_pair(vec4 row,int pair) {
	int other=int(row.a+0.5); int family=other&63;
	return other==pair || (family>0 && family==(other>>6) && (family==(pair&63) || family==(pair>>6)));
}
vec3 transition_fill(float slot,vec2 grid,vec2 dx,vec2 dy) {
	// Mirror at each whole-tile boundary: continuous original donor texels,
	// with analytic gradients so wrapping cannot select the wrong mip level.
	vec2 phase=fract(grid*0.5); vec2 p=1.0-abs(phase*2.0-1.0);
	vec2 direction=vec2(phase.x<0.5 ? 1.0:-1.0,phase.y<0.5 ? 1.0:-1.0);
	return tile_sample(slot-1.0,p,dx*direction,dy*direction);
}
vec3 ground_sample(ivec2 cell,vec2 p,vec2 dx,vec2 dy,out vec4 traits) {
	vec3 original=transition_original_sample(cell,p,dx,dy,traits);
	ivec2 shift=ivec2(floor(p)); cell+=shift; p-=vec2(shift);
	vec4 row=transition_row(cell);
	if (row.a<0.5 || row.r==row.g) { return original; }
	int packed=int(row.b+0.5); int pair=int(row.a+0.5);
	float amount=1.0;
	// A 30 cm untouched strip is wider than all painted-relief gradient
	// taps. Thus paths and unsupported art keep both colour AND lighting.
	if ((packed&16)!=0) { amount*=smoothstep(0.15,0.40,p.x); }
	if ((packed&32)!=0) { amount*=smoothstep(0.15,0.40,1.0-p.x); }
	if ((packed&64)!=0) { amount*=smoothstep(0.15,0.40,p.y); }
	if ((packed&128)!=0) { amount*=smoothstep(0.15,0.40,1.0-p.y); }
	if ((packed&256)!=0) { amount*=smoothstep(0.15,0.40,max(p.x,p.y)); }
	if ((packed&512)!=0) { amount*=smoothstep(0.15,0.40,max(1.0-p.x,p.y)); }
	if ((packed&1024)!=0) { amount*=smoothstep(0.15,0.40,max(p.x,1.0-p.y)); }
	if ((packed&2048)!=0) { amount*=smoothstep(0.15,0.40,max(1.0-p.x,1.0-p.y)); }
	if (amount<=0.0) { return original; }
	vec2 grid=vec2(cell)+p;
	vec2 q=grid+0.28*(vec2(transition_noise(grid*0.72+vec2(3.1,-1.7)),transition_noise(grid*0.72+vec2(-9.2,7.3)))*2.0-1.0);
	vec4 other=transition_row(ivec2(floor(q)));
	float weight=transition_weight(row,p,pair>>6);
	amount*=1.0-smoothstep(0.82,1.0,max(weight,1.0-weight));
	if (transition_pair(other,pair)) { weight=transition_weight(other,fract(q),pair>>6); }
	// Keep authored material endpoints, including tiny isolated corner paint.
	amount*=1.0-smoothstep(0.82,1.0,max(weight,1.0-weight));
	vec3 a=transition_fill(row.r,grid,dx,dy); vec3 b=transition_fill(row.g,grid,dx,dy);
	float noise=transition_noise(grid*2.6+vec2(17.7,4.3))-0.5;
	float height=clamp(dot(b-a,vec3(0.2126,0.7152,0.0722)),-0.25,0.25);
	int type_a=(packed>>12)&15; int type_b=(packed>>16)&15;
	bool soft=type_a==9 || type_a==12 || type_b==9 || type_b==12 || type_a==3 || type_b==3;
	float width=soft ? 0.42 : 0.28;
	float score=weight+0.16*noise+0.22*height;
	float blend=smoothstep(0.5-width,0.5+width,score);
	traits=mix(traits,mix(tile_traits(float(type_a)),tile_traits(float(type_b)),blend),amount);
	return mix(original,mix(a,b,blend),amount);
}
"""


static func source(original: String) -> String:
	var code := original.replace("shader_type spatial;", "shader_type spatial;\n#define EI_TERRAIN_TRANSITIONS")
	code = code.replace("vec3 ground_sample(", "vec3 transition_original_sample(")
	return code.replace("// END_GROUND_TILE_SAMPLER", FUNCTIONS)
