class_name GroundContactShader
extends RefCounted
## Ground-contact band adapted from owned renderer R1 contact_blend.h:
## https://github.com/Ilufus/evil-islands-owned-renderer/blob/0092dc6e1d7c4aab3f74644a79e9bfca11ecf293/Source/contact_blend.h
## Godot Y is up. Ground is sampled from our actual displaced terrain, not a
## replacement material. Its lighting is blended after the figure's own tint.
const DECLARATIONS := """
uniform vec3 contact_extent = vec3(1.0);
uniform float contact_strength = 0.7;
// One call site for the two projections keeps GL compilers from expanding
// the complete displaced-surface search twice. Internal bound, always two.
uniform int contact_query_passes = 2;
uniform sampler2D query_normals : filter_nearest, repeat_disable;
varying float contact_band;
varying vec4 contact_diffuse_weight;
varying vec4 contact_specular_dark;
varying vec3 contact_albedo;
varying vec3 contact_normal;
"""

const FUNCTIONS := """
// Dry terrain's native light model, without the figure material factor. Keep
// the original packed vertex maxima and the terrain's wrapped point lights.
void contact_light(vec3 p, vec3 n, out vec3 d, out vec3 s) {
	d = ei_ambient; s = vec3(0.0);
	if (dot(ei_sun_dir,ei_sun_dir) > 0.5) { d = max(d, ei_sun * max(dot(n,ei_sun_dir),0.0)); }
	vec4 ps[4] = vec4[4](ei_pl0,ei_pl1,ei_pl2,ei_pl3);
	vec4 cs[4] = vec4[4](ei_plc0,ei_plc1,ei_plc2,ei_plc3);
	for (int i=0;i<4;i++) {
		if (ps[i].w <= 0.0) { continue; }
		vec3 delta = ps[i].xyz - p;
		float d2 = dot(delta,delta);
		float falloff = 1.0 - d2 / (ps[i].w * ps[i].w);
		if (falloff <= 0.0) { continue; }
		float facing = dot(n,delta * inversesqrt(max(d2,1e-12)));
		vec3 c = min(cs[i].rgb * falloff * (facing > 0.0 ? 1.0 : max(facing+1.0,0.0)),vec3(1.0));
		if (cs[i].w > 0.5) { s = max(s,c); } else { d = max(d,c); }
	}
	d = ei_diffuse_byte(max(d,s));
	s = floor(clamp(s,vec3(0.0),vec3(1.0))*255.0)/255.0;
}
vec3 contact_vertex_normal(ivec2 p) { return texelFetch(query_normals,p,0).rgb; }
void contact_ground_light(vec2 grid, float height, out vec3 normal, out vec3 d, out vec3 s) {
	ivec2 cell = clamp(ivec2(floor(grid)),ivec2(0),textureSize(query_vertices,0)-2);
	vec2 local = clamp(grid-vec2(cell),vec2(0.0),vec2(1.0));
	bool upper = local.x+local.y > 1.0;
	ivec2 a = cell + (upper ? ivec2(1,0) : ivec2(0,1));
	ivec2 b = cell + (upper ? ivec2(0,1) : ivec2(1,0));
	ivec2 c = cell + (upper ? ivec2(1) : ivec2(0));
	vec3 weights = upper ? vec3(1.0-local.y,1.0-local.x,local.x+local.y-1.0) : vec3(local.y,local.x,1.0-local.x-local.y);
	mat3 points = mat3(query_vertex(a),query_vertex(b),query_vertex(c));
	mat3 normals = mat3(contact_vertex_normal(a),contact_vertex_normal(b),contact_vertex_normal(c));
	vec3 base = points * weights;
	normal = normalize(normals * weights);
	if (ei_surface_fx.x > 0.5) {
		contact_light(vec3(base.x,height,base.z),normal,d,s);
		return;
	}
	vec2 state = texelFetch(query_tiles,clamp(cell/2,ivec2(0),textureSize(query_tiles,0)-1),0).rg;
	if (soft_ground && state.y > 0.5) {
		vec3 blend;
		mat3 subdiv = query_subdivision(weights,blend);
		points *= subdiv; normals *= subdiv; weights = blend;
	}
	mat3 ds; mat3 ss;
	for (int i=0;i<query_vertex_count;i++) {
		vec3 p = points[i];
		p.y = query_displace(p,vec2(cell/32)*32.0,state.x-1.0);
		vec3 pd; vec3 ps;
		contact_light(p,normalize(normals[i]),pd,ps);
		ds[i] = pd; ss[i] = ps;
	}
	d = ds * weights; s = ss * weights;
}
uint contact_hash(uint x) { x ^= x>>16u; x *= 0x7feb352du; x ^= x>>15u; x *= 0x846ca68bu; x ^= x>>16u; return x; }
float contact_lattice(ivec2 p) { return float(contact_hash(uint(p.x)*73856093u ^ uint(p.y)*19349663u)&65535u)/65535.0; }
float contact_noise1(vec2 p) {
	ivec2 i=ivec2(floor(p)); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(contact_lattice(i),contact_lattice(i+ivec2(1,0)),f.x),mix(contact_lattice(i+ivec2(0,1)),contact_lattice(i+ivec2(1)),f.x),f.y);
}
float contact_noise(vec2 p) {
	vec2 warp=vec2(contact_noise1(p*0.7+vec2(3.1,-1.7)),contact_noise1(p*0.7+vec2(-7.7,5.3)))-0.5;
	p+=warp*0.7;
	return clamp((contact_noise1(p*1.25)*0.55+contact_noise1(p*3.7+17.3)*0.3+contact_noise1(p*9.1-5.9)*0.15-0.5)*1.8+0.5,0.0,1.0);
}
vec2 contact_weight(float rise,float band,float up,float noise,float grass,float detail_value) {
	rise=max(rise,0.0);
	float facing=mix(0.75,1.25,clamp(up,0.0,1.0))*(1.0-0.4*clamp(-up,0.0,1.0));
	float material=mix(0.85,1.2+1.2*clamp(detail_value,-0.25,0.25),clamp(grass,0.0,1.0));
	float reach=band*facing*(0.5+0.8*noise)*material;
	float edge=min(reach,max(reach*0.25,0.015));
	float weight=1.0-smoothstep(reach-edge,reach,rise);
	float dark=1.0-0.2*(1.0-smoothstep(0.0,0.15,rise))-0.1*(1.0-smoothstep(0.0,band*0.6,rise));
	return vec2(weight,dark);
}
struct ContactResult { vec3 albedo; vec3 diffuse; vec3 specular; vec3 normal; float weight; float dark; };
ContactResult contact_prepare(vec3 world,vec3 wn,float band,float distance_to_eye) {
	ContactResult result=ContactResult(vec3(0.0),vec3(0.0),vec3(0.0),vec3(0,1,0),0.0,1.0);
	float strength=contact_strength*(1.0-smoothstep(30.0,45.0,distance_to_eye));
	if (strength<=0.0 || band<=0.0) { return result; }
	vec2 p=vec2(world.x,-world.z);
	ivec2 cell=ivec2(floor(p));
	if (any(lessThan(p,vec2(0.0))) || any(greaterThanEqual(p,vec2(textureSize(query_vertices,0)-1)))) { return result; }
	// A conservative bound from every source vertex of the nine candidate
	// cells. Loose material/banks can add at most 0.5 m; no track read needed.
	if (world.y>texelFetch(query_vertices,cell,0).a+0.5+band*2.5) { return result; }
	// Fold the adjacent strip up the wall. At zero rise this is exactly the
	// original ground point; upward faces retain an ordinary top projection.
	float horizontal=length(wn.xz);
	vec2 fold=horizontal>1e-3 ? vec2(wn.x,-wn.z)/horizontal*smoothstep(0.2,0.7,horizontal) : vec2(0.0);
	float height=0.0; vec2 grid=vec2(0.0); ivec2 tile=ivec2(0); mat2 jacobian=mat2(1.0);
	float rise=0.0; vec2 folded=p;
	for (int pass=0;pass<contact_query_passes;pass++) {
		float sampled_height; vec2 sampled_grid; ivec2 sampled_tile; mat2 sampled_jacobian;
		if (!query_surface(folded,sampled_height,sampled_grid,sampled_tile,sampled_jacobian)) {
			if (pass==0) { return result; }
			// The folded strip can leave the map. Retain the first query's
			// complete state, including its original point and derivatives.
			folded=p; break;
		}
		height=sampled_height; grid=sampled_grid; tile=sampled_tile; jacobian=sampled_jacobian;
		if (pass==0) {
			rise=max(world.y-height,0.0);
			if (rise>band*2.5) { return result; }
			vec4 water=textureLod(terrain_cells,p/vec2(textureSize(terrain_cells,0)),0.0);
			float water_y=water.r+level[clamp(int(water.a+0.5),0,63)];
			strength*=smoothstep(0.025,0.10,height-water_y);
			if (strength<=0.0) { return result; }
			if (horizontal<=1e-3 || rise<=0.001) { break; }
			folded=p+fold*rise;
		}
	}
	vec4 water=textureLod(terrain_cells,folded/vec2(textureSize(terrain_cells,0)),0.0);
	float water_y=water.r+level[clamp(int(water.a+0.5),0,63)];
	int ground=int(water.g+0.5);
	vec2 uv=grid*0.5;
	vec2 dx=jacobian*dFdx(folded)*0.5;
	vec2 dy=jacobian*dFdy(folded)*0.5;
	vec4 traits;
	vec3 albedo=ground_sample(tile,uv-vec2(tile),dx,dy,traits);
	vec3 mean=ground_sample(tile,uv-vec2(tile),dx*4.0,dy*4.0,traits);
	float grass=clamp((mean.g-max(mean.r,mean.b))*8.0/max(mean.g,0.05),0.0,1.0);
	vec2 blend=contact_weight(rise,band,wn.y,contact_noise(folded),grass,dot(albedo-mean,vec3(0.2126,0.7152,0.0722)));
	if (detail>0.0) {
		// Keep the terrain's bounded local contrast at the same view distance.
		float fade=detail*(1.0-smoothstep(25.0,70.0,distance_to_eye));
		float border=8.0*source_texel*tiles_per_axis;
		vec2 step_uv=vec2(source_texel*tiles_per_axis*1.5/(1.0-2.0*border),0.0);
		vec2 local=uv-vec2(tile); vec4 unused_traits;
		vec3 left=ground_sample(tile,local-step_uv,dx,dy,unused_traits);
		vec3 right=ground_sample(tile,local+step_uv,dx,dy,unused_traits);
		vec3 down=ground_sample(tile,local-step_uv.yx,dx,dy,unused_traits);
		vec3 up=ground_sample(tile,local+step_uv.yx,dx,dy,unused_traits);
		vec3 average=(left+right+down+up)*0.25;
		vec3 lo=min(albedo,min(min(left,right),min(down,up)));
		vec3 hi=max(albedo,max(max(left,right),max(down,up)));
		albedo=clamp(albedo+(albedo-average)*mix(0.38,0.16,traits.y)*fade,lo,hi);
		float macro=texture(macro_tex,vec2(folded.x,-folded.y)*0.012).r;
		albedo*=mix(1.0,0.92+0.16*macro,detail*(1.0-traits.y*0.6));
		float wet=1.0-smoothstep(0.02,0.55,abs(height-water_y));
		if (int(water.b+0.5)==13 || ground==9 || ground==10 || ground==12) { wet=0.0; }
		albedo*=1.0-wet*detail*mix(0.20,0.08,traits.z);
	}
	contact_ground_light(grid,height,result.normal,result.diffuse,result.specular);
	if (ei_surface_fx.z>0.5 && ei_weather.x>0.0 && ground!=9 && ground!=10 && ground!=12 && ground!=13 && int(water.b+0.5)!=13) {
		float cover=textureLod(rain_cover,folded/vec2(textureSize(terrain_cells,0)),0.0).r;
		float wet=ei_weather.x*(1.0-smoothstep(0.08,0.40,cover-height))*smoothstep(-0.04,0.10,height-water_y)*smoothstep(0.05,0.65,abs(result.normal.y));
		albedo*=1.0-wet*mix(0.23,0.08,traits.z);
	}
	vec2 state=texelFetch(query_tiles,clamp(tile,ivec2(0),textureSize(query_tiles,0)-1),0).rg;
	if (soft_ground && state.x>0.5) {
		vec2 profile=soft_surface(folded,height);
		vec2 track_uv=((folded-vec2(tile/16)*32.0)*(511.0/32.0)+0.5)/512.0;
		vec4 track=textureLod(query_tracks,vec3(track_uv,state.x-1.0),0.0);
		float age=max(textureLod(query_clock,vec2(0.5),0.0).r-track.b/max(track.a,1e-5),0.0);
		if (profile.y>0.0) { albedo*=1.0-track.r*clamp((240.0-age)/60.0,0.0,1.0)*(ground==3?0.12:0.16); }
	}
	result.albedo=albedo;
	result.weight=blend.x*strength;
	result.dark=mix(1.0,blend.y,strength);
	return result;
}
"""

const FRAGMENT := """
	vec3 contact_world=(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
	vec3 contact_world_normal=normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).xyz);
	ContactResult contact=contact_prepare(contact_world,contact_world_normal,contact_band,length(VERTEX));
	contact_diffuse_weight=vec4(contact.diffuse,contact.weight);
	contact_specular_dark=vec4(contact.specular,contact.dark);
	// Compatibility decodes ALBEDO after fragment(), before light(). Our
	// extra fragment-to-light colour needs the same conversion explicitly.
	contact_albedo=OUTPUT_IS_SRGB ? ei_lin(contact.albedo) : contact.albedo;
	contact_normal=normalize((VIEW_MATRIX*vec4(contact.normal,0.0)).xyz);
	// A zero albedo channel cannot carry any diffuse factor. The original
	// upper surface is untouched; the contact band needs this finite divisor.
	// GLES uses a cubic sRGB approximation with a smaller dark-end slope;
	// 0.01 encoded is safely above the light() denominator's 1e-4 floor.
	if (contact.weight>0.0) { ALBEDO=max(ALBEDO,vec3(OUTPUT_IS_SRGB ? 0.01 : 1e-4)); }
"""


static func source(original: String) -> String:
	var code := original.replace("shader_type spatial;", "shader_type spatial;\n#define EI_GROUND_CONTACT")
	var helpers := GroundSurfaceShader.LAND_UNIFORMS + GroundSurfaceShader.SOFT_UNIFORMS \
		+ GroundSurfaceShader.SOFT_FUNCTIONS + GroundSurfaceShader.TILE_FUNCTIONS \
		+ GroundSurfaceShader.QUERY_SHADER + DECLARATIONS + FUNCTIONS
	code = code.replace("void vertex() {", helpers + "\nvoid vertex() {\n\tcontact_band=min(0.4,max(0.01,dot(abs(vec3(MODEL_MATRIX[0].y,MODEL_MATRIX[1].y,MODEL_MATRIX[2].y)),contact_extent)*0.125));")
	# Eligible figure sources end with fragment(); keep the original alpha,
	# normals, material response and alpha-to-coverage path in that function.
	code = code.strip_edges().trim_suffix("}") + FRAGMENT + "\n}\n"
	return code


static func lighting(code: String) -> String:
	# Only contact variants use the extended light-colour arguments. Other
	# materials keep Gfx.light_code byte-for-byte, including characters.
	code = code.replace("vec3 ei_draw_colour(vec3 albedo, vec3 d, vec3 s)",
		"vec3 ei_draw_colour(vec3 albedo, vec3 d, vec3 s, vec3 gd, vec3 gs, vec4 ground, float dark)")
	code = code.replace("return clamp(ei_srgb(albedo) * d + s, 0.0, 1.0);", """
	vec3 mesh_colour=clamp(ei_srgb(albedo)*d+s,0.0,1.0);
	vec3 ground_colour=clamp(ei_srgb(ground.rgb)*gd+gs,0.0,1.0);
	return mix(mesh_colour,ground_colour,ground.a)*dark;""")
	code = code.replace("vec3 ei_draw_factor(vec3 albedo, vec3 d, vec3 s, float shadow)",
		"vec3 ei_draw_factor(vec3 albedo, vec3 d, vec3 s, float shadow, vec3 gd, vec3 gs, vec4 ground, float dark)")
	code = code.replace("ei_draw_colour(albedo, d, s)", "ei_draw_colour(albedo, d, s, gd, gs, ground, dark)")
	code = code.replace("vec3 s = ei_vertex_specular;", "vec3 s = ei_vertex_specular;\n\tvec3 gd=contact_diffuse_weight.rgb; vec3 gs=contact_specular_dark.rgb;\n\tvec4 ground=vec4(contact_albedo,contact_diffuse_weight.a); float dark=contact_specular_dark.a;")
	code = code.replace("ei_draw_colour(ei_alb, d, s)", "ei_draw_colour(ei_alb, d, s, gd, gs, ground, dark)")
	code = code.replace("ei_draw_colour(ei_alb, nd, ns)", "ei_draw_colour(ei_alb, nd, ns, gnd, gns, ground, dark)")
	for shadow in ["shadow", "1.0"]:
		code = code.replace("ei_draw_factor(ei_alb, d, s, %s)" % shadow, "ei_draw_factor(ei_alb, d, s, %s, gd, gs, ground, dark)" % shadow)
		code = code.replace("ei_draw_factor(ei_alb, nd, ns, %s)" % shadow, "ei_draw_factor(ei_alb, nd, ns, %s, gnd, gns, ground, dark)" % shadow)
	code = code.replace("vec3 ns = s;", """vec3 ns = s;
			float ground_k=dot(contact_normal,LIGHT);
			vec3 ground_col=min(ei_srgb(LIGHT_COLOR/PI),vec3(1.0))*a*(ground_k>0.0?1.0:max(ground_k+1.0,0.0));
			vec3 gns=gs;
			if (SPECULAR_AMOUNT>0.0 && SPECULAR_AMOUNT<0.01) { gns=max(gns,floor(clamp(ground_col,vec3(0.0),vec3(1.0))*255.0)/255.0); }
			vec3 gnd=max(gd,ei_diffuse_byte(max(ground_col,gns)));""")
	code = code.replace("vec3 loc = ei_alb * LIGHT_COLOR / PI * nl * ATTENUATION * 0.75 /*EI_FA*/;", """
		vec3 local_colour=mix(ei_alb*nl,contact_albedo*max(dot(contact_normal,LIGHT),0.0),contact_diffuse_weight.a)*contact_specular_dark.a;
		vec3 loc=local_colour*LIGHT_COLOR/PI*ATTENUATION*0.75 /*EI_FA*/;""")
	code = code.replace("* 0.22 /*EI_FA*/;", "* 0.22 * (1.0-contact_diffuse_weight.a) /*EI_FA*/;")
	return code
