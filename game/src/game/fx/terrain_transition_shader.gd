extends RefCounted
## Authored pair transitions and verified three/four-family junctions share one sampler.
## Keep the accepted pair program intact on maps without junctions. Junctions
## use R1's per-material scoring/normalized shares in a bounded local halo.
## FUNCTIONS is the accepted legacy pair path; JUNCTION_FUNCTIONS extends it.
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

const JUNCTION_FUNCTIONS := """
// Internal bound, always four. A uniform keeps GL compilers from expanding
// every material loop at all six terrain/contact relief sampling sites.
uniform int transition_junction_materials = 4;
uniform int transition_relief_passes = 4;
float transition_junction_lattice(ivec2 cell) {
	// Integer coordinates must give the same shared corner from either cell.
	// Floating sin/dot hashes can be reassociated differently at that boundary.
	uint h=uint(cell.x)*73856093u ^ uint(cell.y)*19349663u;
	h^=h>>16u; h*=0x7feb352du; h^=h>>15u; h*=0x846ca68bu; h^=h>>16u;
	return float(h&16777215u)/16777215.0;
}
float transition_junction_noise(vec2 p) {
	ivec2 cell=ivec2(floor(p)); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(transition_junction_lattice(cell),transition_junction_lattice(cell+ivec2(1,0)),f.x),
		mix(transition_junction_lattice(cell+ivec2(0,1)),transition_junction_lattice(cell+ivec2(1)),f.x),f.y);
}
vec4 transition_junction_row(ivec2 cell) {
	ivec2 size=textureSize(transition_tiles,0); size.y/=2;
	if (any(lessThan(cell,ivec2(0))) || any(greaterThanEqual(cell,size))) { return vec4(0.0); }
	return texelFetch(transition_tiles,cell+ivec2(0,size.y),0);
}
vec4 transition_junction_weights(vec4 metadata,vec2 p) {
	// Metadata contains exact integer-valued float32 channels. Adding 0.5
	// would corrupt odd 24-bit integers above 2^23 before conversion to int.
	int corners=int(metadata.g)&255;
	vec4 kernel=vec4((1.0-p.x)*(1.0-p.y),p.x*(1.0-p.y),(1.0-p.x)*p.y,p.x*p.y);
	vec4 weights=vec4(0.0);
	for (int k=0;k<4;k++) { weights[(corners>>(k*2))&3]+=kernel[k]; }
	return weights;
}
float transition_junction_dominance(vec4 weights) {
	return 1.0-smoothstep(0.82,1.0,max(max(weights.x,weights.y),max(weights.z,weights.w)));
}
float transition_junction_guard(int packed,vec2 p) {
	float amount=1.0;
	if ((packed&1)!=0) { amount*=smoothstep(0.15,0.40,p.x); }
	if ((packed&2)!=0) { amount*=smoothstep(0.15,0.40,1.0-p.x); }
	if ((packed&4)!=0) { amount*=smoothstep(0.15,0.40,p.y); }
	if ((packed&8)!=0) { amount*=smoothstep(0.15,0.40,1.0-p.y); }
	if ((packed&16)!=0) { amount*=smoothstep(0.15,0.40,max(p.x,p.y)); }
	if ((packed&32)!=0) { amount*=smoothstep(0.15,0.40,max(1.0-p.x,p.y)); }
	if ((packed&64)!=0) { amount*=smoothstep(0.15,0.40,max(p.x,1.0-p.y)); }
	if ((packed&128)!=0) { amount*=smoothstep(0.15,0.40,max(1.0-p.x,1.0-p.y)); }
	return amount;
}
vec3 transition_junction_sample(ivec2 cell,vec2 p,vec2 dx,vec2 dy,vec4 row,vec4 metadata,
		vec3 original,vec4 original_traits,out vec4 traits) {
	traits=original_traits;
	vec4 weights=transition_junction_weights(metadata,p);
	float guard=transition_junction_guard((int(metadata.g)>>8)&255,p);
	float amount=guard*transition_junction_dominance(weights);
	if (amount<=0.0) { return original; }
	vec2 grid=vec2(cell)+p;
	// The shared guard also damps the warp before an unsupported tile. Its
	// maximum displacement stays below the distance to that tile, avoiding
	// a discontinuous valid-field -> unwarped fallback inside the art fade.
	vec2 q=grid+0.28*guard*(vec2(transition_junction_noise(grid*0.72+vec2(3.1,-1.7)),transition_junction_noise(grid*0.72+vec2(-9.2,7.3)))*2.0-1.0);
	vec4 other=transition_junction_row(ivec2(floor(q)));
	// Both sides of a shared edge consume the entire same warped field,
	// including its additional families. Never project it onto a local pair.
	if (other.r>0.0) {
		metadata=other; row=transition_row(ivec2(floor(q)));
		weights=transition_junction_weights(metadata,fract(q));
	}
	amount*=transition_junction_dominance(weights);
	if (amount<=0.0) { return original; }
	int families=int(metadata.r); int packed=int(row.b);
	ivec4 ids=ivec4(families&63,(families>>6)&63,(families>>12)&63,(families>>18)&63);
	vec4 slots=vec4(row.r,row.g,float(int(metadata.b)&32767),float(int(metadata.a)&32767));
	ivec4 types=ivec4((packed>>12)&15,(packed>>16)&15,(int(metadata.b)>>15)&15,(int(metadata.a)>>15)&15);
	vec3 colors[4]; vec4 scores=vec4(-9.0); float mean=0.0;
	vec3 luma=vec3(0.2126,0.7152,0.0722);
	int material_count=transition_junction_materials;
	for (int i=0;i<material_count;i++) {
		colors[i]=vec3(0.0);
		if (weights[i]>0.0) {
			colors[i]=transition_fill(slots[i],grid,dx,dy);
			mean+=weights[i]*dot(colors[i],luma);
		}
	}
	float strongest=max(max(weights.x,weights.y),max(weights.z,weights.w));
	float contested=min(3.0*(1.0-strongest),1.0);
	for (int i=0;i<material_count;i++) {
		if (weights[i]>0.0) {
			vec2 seed=vec2(float(ids[i])*17.31,float(ids[i])*29.17);
			float noise=transition_junction_noise(grid*2.6+seed)-0.5;
			float height=clamp(dot(colors[i],luma)-mean,-0.25,0.25);
			scores[i]=weights[i]+contested*min(3.0*weights[i],1.0)*(0.16*noise+0.22*height);
		}
	}
	int first=0;
	for (int i=1;i<material_count;i++) { if (scores[i]>scores[first]) { first=i; } }
	// A hard/soft runner-up tie must not switch the width discontinuously.
	// Weight the softness field continuously; absent materials contribute zero.
	float soft=0.0;
	for (int i=0;i<material_count;i++) {
		if (types[i]==3 || types[i]==9 || types[i]==12) { soft+=weights[i]; }
	}
	float depth=mix(0.28,0.42,smoothstep(0.0,0.5,soft));
	// Every active material competes. No pair reduction drops a third/fourth
	// family at the centre. An absent family has score -9 and exactly no share.
	vec4 shares=max(scores-vec4(scores[first]-depth),vec4(0.0)); shares*=shares;
	shares/=dot(shares,vec4(1.0));
	vec3 color=vec3(0.0); vec4 surface=vec4(0.0);
	for (int i=0;i<material_count;i++) {
		color+=colors[i]*shares[i];
		surface+=tile_traits(float(types[i]))*shares[i];
	}
	traits=mix(original_traits,surface,amount);
	return mix(original,color,amount);
}
vec3 ground_sample(ivec2 cell,vec2 p,vec2 dx,vec2 dy,out vec4 traits) {
	ivec2 shift=ivec2(floor(p)); cell+=shift; p-=vec2(shift);
	vec4 row=transition_row(cell);
	// All pure tiles remain authored, even inside the junction halo.
	int influence=(int(row.b)>>20)&15;
	float blend=0.0; vec4 metadata=vec4(0.0);
	if (row.a!=0.0 && !(row.a>0.0 && row.r==row.g) && influence!=0) {
		vec4 flags=vec4(float(influence&1),float((influence>>1)&1),float((influence>>2)&1),float((influence>>3)&1));
		blend=smoothstep(0.0,1.0,mix(mix(flags.x,flags.y,p.x),mix(flags.z,flags.w,p.x),p.y));
		if (blend>0.0) {
			metadata=transition_junction_row(cell);
			if (metadata.r<=0.0) { blend=0.0; }
		}
	}
	// One call site avoids expanding the entire legacy program for each
	// mutually exclusive fallback. Zero influence returns it exactly.
	vec4 legacy_traits=vec4(0.0); vec3 legacy=vec3(0.0);
	if (blend<1.0) {
		legacy=transition_pair_sample(cell,p,dx,dy,legacy_traits);
		if (blend<=0.0) { traits=legacy_traits; return legacy; }
	}
	vec4 original_traits;
	vec3 original=transition_original_sample(cell,p,dx,dy,original_traits);
	vec3 junction=transition_junction_sample(cell,p,dx,dy,row,metadata,original,original_traits,traits);
	if (blend>=1.0) { return junction; }
	traits=mix(legacy_traits,traits,blend);
	return mix(legacy,junction,blend);
}
void transition_relief_samples(ivec2 tile,vec2 local,vec2 step_uv,vec2 dx,vec2 dy,
		out vec3 left,out vec3 right,out vec3 down,out vec3 up) {
	left=vec3(0.0); right=vec3(0.0); down=vec3(0.0); up=vec3(0.0);
	// Internal default is always four, like contact_query_passes. Keeping
	// one sampler call prevents repeated GL expansion of the complete field.
	for (int i=0;i<transition_relief_passes;i++) {
		vec2 point=local-step_uv;
		if (i==1) { point=local+step_uv; }
		if (i==2) { point=local-step_uv.yx; }
		if (i==3) { point=local+step_uv.yx; }
		vec4 unused_traits;
		vec3 color=ground_sample(tile,point,dx,dy,unused_traits);
		if (i==0) { left=color; }
		if (i==1) { right=color; }
		if (i==2) { down=color; }
		if (i==3) { up=color; }
	}
}
"""

const TERRAIN_RELIEF := """vec3 left = ground_sample(tile, local - step_uv, dx, dy, unused_traits);
			vec3 right = ground_sample(tile, local + step_uv, dx, dy, unused_traits);
			vec3 down = ground_sample(tile, local - step_uv.yx, dx, dy, unused_traits);
			vec3 up = ground_sample(tile, local + step_uv.yx, dx, dy, unused_traits);"""
const CONTACT_RELIEF := """vec3 left=ground_sample(tile,local-step_uv,dx,dy,unused_traits);
		vec3 right=ground_sample(tile,local+step_uv,dx,dy,unused_traits);
		vec3 down=ground_sample(tile,local-step_uv.yx,dx,dy,unused_traits);
		vec3 up=ground_sample(tile,local+step_uv.yx,dx,dy,unused_traits);"""
const SHARED_RELIEF := """vec3 left; vec3 right; vec3 down; vec3 up;
			transition_relief_samples(tile,local,step_uv,dx,dy,left,right,down,up);"""


# Retain byte-identical legacy programs outside the qualified Forward+ path.
static func _reuse_junction_functions() -> String:
	var code := JUNCTION_FUNCTIONS
	code = code.replace("""vec3 transition_junction_sample(ivec2 cell,vec2 p,vec2 dx,vec2 dy,vec4 row,vec4 metadata,
		vec3 original,vec4 original_traits,out vec4 traits) {""", """vec3 transition_cached_fill(float slot,vec2 grid,vec2 dx,vec2 dy,
		vec2 cached_slots,vec3 cached_a,vec3 cached_b) {
	// Both fields use the identical grid and explicit gradients. Only an
	// exact donor-slot match can reuse color; a warped extra family samples.
	if (slot==cached_slots.x) { return cached_a; }
	if (slot==cached_slots.y) { return cached_b; }
	return transition_fill(slot,grid,dx,dy);
}
vec3 transition_junction_sample(ivec2 cell,vec2 p,vec2 dx,vec2 dy,vec4 row,vec4 metadata,
		vec3 original,vec4 original_traits,vec2 cached_slots,vec3 cached_a,vec3 cached_b,out vec4 traits) {""")
	code = code.replace("""colors[i]=transition_fill(slots[i],grid,dx,dy);""", """colors[i]=transition_cached_fill(slots[i],grid,dx,dy,cached_slots,cached_a,cached_b);""")
	code = code.replace("""	// One call site avoids expanding the entire legacy program for each
	// mutually exclusive fallback. Zero influence returns it exactly.
	vec4 legacy_traits=vec4(0.0); vec3 legacy=vec3(0.0);
	if (blend<1.0) {
		legacy=transition_pair_sample(cell,p,dx,dy,legacy_traits);
		if (blend<=0.0) { traits=legacy_traits; return legacy; }
	}
	vec4 original_traits;
	vec3 original=transition_original_sample(cell,p,dx,dy,original_traits);
	vec3 junction=transition_junction_sample(cell,p,dx,dy,row,metadata,original,original_traits,traits);""", """	// The two fields share this immutable original sample. Keep each
	// field's scoring, traits and interpolation order unchanged.
	vec4 original_traits;
	vec3 original=transition_original_sample(cell,p,dx,dy,original_traits);
	vec4 legacy_traits=original_traits; vec3 legacy=vec3(0.0);
	vec2 cached_slots=vec2(-1.0); vec3 cached_a=vec3(0.0); vec3 cached_b=vec3(0.0);
	if (blend<1.0) {
		legacy=transition_pair_sample(cell,p,dx,dy,row,original,legacy_traits,cached_slots,cached_a,cached_b);
		if (blend<=0.0) { traits=legacy_traits; return legacy; }
	}
	vec3 junction=transition_junction_sample(cell,p,dx,dy,row,metadata,original,original_traits,cached_slots,cached_a,cached_b,traits);""")
	return code


## Used only where the complete sector and its relief-sampling halo have
## no junction influence. Keep the pair arithmetic and the four relief taps
## identical; removing the unreachable junction branch reduces GPU work.
static func _pair_only_junction_functions() -> String:
	var code := _reuse_junction_functions()
	var start := code.find("vec3 ground_sample(")
	var end := code.find("void transition_relief_samples(", start)
	return code.substr(0, start) + """vec3 ground_sample(ivec2 cell,vec2 p,vec2 dx,vec2 dy,out vec4 traits) {
	ivec2 shift=ivec2(floor(p)); cell+=shift; p-=vec2(shift);
	vec4 row=transition_row(cell);
	vec4 original_traits;
	vec3 original=transition_original_sample(cell,p,dx,dy,original_traits);
	vec4 legacy_traits=original_traits;
	vec2 cached_slots=vec2(-1.0); vec3 cached_a=vec3(0.0); vec3 cached_b=vec3(0.0);
	vec3 legacy=transition_pair_sample(cell,p,dx,dy,row,original,legacy_traits,cached_slots,cached_a,cached_b);
	traits=legacy_traits;
	return legacy;
}
""" + code.substr(end)


static func source(original: String, junctions := false, pair_only := false) -> String:
	var code := original.replace("shader_type spatial;", "shader_type spatial;\n#define EI_TERRAIN_TRANSITIONS")
	code = code.replace("vec3 ground_sample(", "vec3 transition_original_sample(")
	var functions := FUNCTIONS
	if junctions:
		functions = functions.replace("textureSize(transition_tiles,0)", "ivec2(textureSize(transition_tiles,0).x,textureSize(transition_tiles,0).y/2)")
		functions = functions.replace("int(row.b+0.5)", "int(row.b)")
		functions = functions.replace("vec3 ground_sample(", "vec3 transition_pair_sample(")
		# Mobile retains strict residuals; this test build limits reuse to Forward+.
		if RenderingServer.get_current_rendering_method() == "forward_plus":
			# Partial junction halos evaluate both fields at the same original point.
			# Pass the original/row and exact donor samples through once; relief taps
			# and the different pair/junction noise hashes remain independent.
			functions = functions.replace("""vec3 transition_pair_sample(ivec2 cell,vec2 p,vec2 dx,vec2 dy,out vec4 traits) {
	vec3 original=transition_original_sample(cell,p,dx,dy,traits);
	ivec2 shift=ivec2(floor(p)); cell+=shift; p-=vec2(shift);
	vec4 row=transition_row(cell);""", """vec3 transition_pair_sample(ivec2 cell,vec2 p,vec2 dx,vec2 dy,vec4 row,vec3 original,
		inout vec4 traits,out vec2 cached_slots,out vec3 cached_a,out vec3 cached_b) {
	// The caller has already resolved this exact cell, original and metadata.
	cached_slots=vec2(-1.0); cached_a=vec3(0.0); cached_b=vec3(0.0);""")
			functions = functions.replace("""	vec3 a=transition_fill(row.r,grid,dx,dy); vec3 b=transition_fill(row.g,grid,dx,dy);""", """	vec3 a=transition_fill(row.r,grid,dx,dy); vec3 b=transition_fill(row.g,grid,dx,dy);
	cached_slots=row.rg; cached_a=a; cached_b=b;""")
			functions += _pair_only_junction_functions() if pair_only else _reuse_junction_functions()
		else:
			functions += JUNCTION_FUNCTIONS
		# These exact blocks keep their four coordinates and downstream math.
		# Pair-only programs retain their original relief source byte-for-byte.
		code = code.replace(TERRAIN_RELIEF, SHARED_RELIEF).replace(CONTACT_RELIEF, SHARED_RELIEF)
	return code.replace("// END_GROUND_TILE_SAMPLER", functions)
