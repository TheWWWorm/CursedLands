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
uniform sampler2D query_light_inputs : filter_nearest, repeat_disable;
uniform sampler2DArray query_dense_light_inputs : filter_nearest, repeat_disable;
uniform sampler2D query_dense_light_tiles : filter_nearest, repeat_disable;
varying float contact_band;
varying vec4 contact_diffuse_weight;
varying vec4 contact_specular_dark;
varying vec3 contact_albedo;
varying vec3 contact_normal;
varying vec3 contact_surface;
varying vec3 contact_vpos;
varying vec4 contact_light_inputs;
"""

const FUNCTIONS := """
// Terrain's native light model, without the figure material factor. Keep
// the original packed vertex maxima and the terrain's wrapped point lights.
vec4 contact_vertex_point(vec4 pl, vec4 plc, vec3 p, vec3 n, float kw) {
	if (pl.w <= 0.0) { return vec4(0.0); }
	vec3 lv = pl.xyz - p;
	float d2 = dot(lv, lv);
	float a = 1.0 - d2 / (pl.w * pl.w);
	if (a <= 0.0) { return vec4(0.0); }
	vec3 l = lv * inversesqrt(max(d2, 1e-12));
	float k = dot(n, l);
	float f = (k > 0.0 ? 1.0 : max(k + 1.0, 0.0));
	float uw = max(1.0 - l.y * l.y * kw, 0.0);
	return vec4(plc.rgb * a * f * uw, 1.0);
}
void contact_light(vec3 p, vec3 n, vec4 inputs, out vec3 d, out vec3 s) {
	vec3 e=inputs.rgb; float kw=inputs.a*4.0;
	d=ei_ambient*max(1.0-kw,0.0); s=vec3(0.0);
	if (dot(ei_sun_dir,ei_sun_dir)>0.5) {
		float uw=max(1.0-ei_sun_dir.y*ei_sun_dir.y*kw,0.0);
		d=max(d,min(e+ei_sun*max(dot(n,ei_sun_dir),0.0)*uw,vec3(1.0)));
	}
	vec4 ps[4] = vec4[4](ei_pl0,ei_pl1,ei_pl2,ei_pl3);
	vec4 cs[4] = vec4[4](ei_plc0,ei_plc1,ei_plc2,ei_plc3);
	for (int i=0;i<4;i++) {
		vec4 value=contact_vertex_point(ps[i],cs[i],p,n,kw);
		if (value.w<=0.0) { continue; }
		vec3 c=min(e+value.rgb,vec3(1.0));
		if (cs[i].w > 0.5) { s = max(s,c); } else { d = max(d,c); }
	}
	d = ei_diffuse_byte(max(d,s));
	s = floor(clamp(s,vec3(0.0),vec3(1.0))*255.0)/255.0;
}
vec3 contact_vertex_normal(ivec2 p,ivec2 sector) { return texelFetch(query_normals,p+sector,0).rgb; }
// A sector owns its border COLOR; adjoining sectors can choose different
// liquid materials for the same grid vertex. Keep the selected cell's owner.
vec4 contact_vertex_inputs(ivec2 p,ivec2 sector) { return texelFetch(query_light_inputs,p+sector,0); }
vec4 contact_dense_vertex_inputs(vec3 barycentric,int parent,int layer) {
	if (layer<0) { return vec4(0.0); }
	// query_subdivision returns exact multiples of 1/16 in the original
	// parent's barycentric coordinates. Keep native row/parent identity.
	ivec2 q=ivec2(barycentric.yz*16.0);
	int vertex=17*q.y-q.y*(q.y-1)/2+q.x;
	return texelFetch(query_dense_light_inputs,ivec3(vertex,parent,layer),0);
}
// The mesh frame cannot come from derivatives of an object wall: they can
// have rank one. Reconstruct this selected triangle's affine P(u,v), then
// use the actual camera's UV/screen determinant. Camera/projection values
// are arguments from existing fragment built-ins, not material uniforms.
// camera = (eye,1) for perspective or (view +Z,0) for orthographic;
// projection = (view +Z, projection_x*projection_y*viewport_area/4).
// det(dScreen/dUV) = projection.w * dot(cross(P_u,P_v),toward_camera)
// divided by depth^3 for perspective. Its reciprocal preserves both the
// projected sign and the original 1e-12 shared-normalization floor.
mat3 contact_relief_frame(mat3 points,mat3 coordinates,vec3 raw_normal,vec3 base,vec4 camera,vec4 projection) {
	mat2 inverse_uv=inverse(mat2(coordinates[1].xy-coordinates[0].xy,coordinates[2].xy-coordinates[0].xy));
	vec3 e=points[1]-points[0]; vec3 f=points[2]-points[0];
	vec3 pu=e*inverse_uv[0].x+f*inverse_uv[0].y;
	vec3 pv=e*inverse_uv[1].x+f*inverse_uv[1].y;
	vec3 toward_camera=camera.xyz-base*camera.w;
	float facing=dot(cross(pu,pv),toward_camera);
	// Terrain is cull_disabled. Its native clockwise triangles flip the
	// interpolated fragment normal on a genuine backface (DO_SIDE_CHECK).
	if (facing<0.0) { raw_normal=-raw_normal; }
	float depth=camera.w>0.5 ? dot(projection.xyz,toward_camera) : 1.0;
	float screen_det=projection.w*facing;
	float uv_det=abs(screen_det)>1e-12 ? depth*depth*depth/screen_det : 0.0;
	vec3 tangent=cross(pv,raw_normal)*uv_det;
	vec3 bitangent=cross(raw_normal,pu)*uv_det;
	float frame_scale=inversesqrt(max(max(dot(tangent,tangent),dot(bitangent,bitangent)),1e-12));
	return mat3(tangent*frame_scale,bitangent*frame_scale,raw_normal);
}
float contact_ground_height(vec3 colour) { return sqrt(max(dot(colour,vec3(0.2126,0.7152,0.0722)),0.0)); }
// Same coverage-normalized age and fade as the terrain sector sampler.
vec2 contact_track(vec2 uv,float layer) {
	vec4 track=textureLod(query_tracks,vec3(uv,layer),0.0);
	float age=max(textureLod(query_clock,vec2(0.5),0.0).r-track.b/max(track.a,1e-5),0.0);
	return track.rg*clamp((240.0-age)/60.0,0.0,1.0);
}
void contact_ground_light(vec2 grid, float height, vec4 camera, vec4 projection, out vec3 normal, out vec3 d, out vec3 s, out mat3 frame, out vec2 height_gradient, out float compression, out vec4 light_inputs) {
	ivec2 cell=clamp(ivec2(floor(grid)),ivec2(0),textureSize(query_vertices,0)-2);
	vec2 local=clamp(grid-vec2(cell),vec2(0.0),vec2(1.0));
	bool upper=local.x+local.y>1.0;
	ivec2 a=cell+(upper ? ivec2(1,0):ivec2(0,1));
	ivec2 b=cell+(upper ? ivec2(0,1):ivec2(1,0));
	ivec2 c=cell+(upper ? ivec2(1):ivec2(0));
	vec3 weights=upper ? vec3(1.0-local.y,1.0-local.x,local.x+local.y-1.0):vec3(local.y,local.x,1.0-local.x-local.y);
	mat3 points=mat3(query_vertex(a),query_vertex(b),query_vertex(c));
	ivec2 sector=cell/32;
	vec4 inputs[3];
	mat3 normals=mat3(contact_vertex_normal(a,sector),contact_vertex_normal(b,sector),contact_vertex_normal(c,sector));
	mat3 coordinates=mat3(vec3(vec2(a)*0.5,0.0),vec3(vec2(b)*0.5,0.0),vec3(vec2(c)*0.5,0.0));
	vec2 state=texelFetch(query_tiles,clamp(cell/2,ivec2(0),textureSize(query_tiles,0)-1),0).rg;
	if (soft_ground && state.y>0.5 && !query_undeformed) {
		vec3 blend; mat3 subdiv=query_subdivision(weights,blend);
		int layer=int(texelFetch(query_dense_light_tiles,cell/2,0).r)-1;
		int parent=(cell.y%2)*4+(cell.x%2)*2+(upper ? 1:0);
		for (int i=0;i<query_vertex_count;i++) {
			inputs[i]=contact_dense_vertex_inputs(subdiv[i],parent,layer);
		}
		points*=subdiv; normals*=subdiv; coordinates*=subdiv; weights=blend;
	} else {
		inputs[0]=contact_vertex_inputs(a,sector);
		inputs[1]=contact_vertex_inputs(b,sector);
		inputs[2]=contact_vertex_inputs(c,sector);
	}
	compression=0.0;
	if (soft_ground && !query_undeformed) {
		for (int i=0;i<query_vertex_count;i++) {
			// Native soft_profile is evaluated before displacement at each
			// installed vertex, then interpolated. A fragment re-evaluation
			// has different shore/boundary weights and visible track seams.
			vec2 p=vec2(points[i].x,-points[i].z);
			vec2 profile=soft_surface(p,points[i].y);
			compression+=profile.y*weights[i];
			points[i].y+=profile.x;
			if (state.x>0.5 && !query_no_tracks) {
				vec2 uv=((p-vec2(cell/32)*32.0)*(511.0/32.0)+0.5)/512.0;
				points[i].y+=soft_height(contact_track(uv,state.x-1.0))*profile.y;
			}
		}
	}
	mat3 vertex_normals=mat3(normalize(normals[0]),normalize(normals[1]),normalize(normals[2]));
	vec3 geometric=cross(points[1]-points[0],points[2]-points[0]);
	height_gradient=vec2(-geometric.x,geometric.z)/geometric.y;
	frame=contact_relief_frame(points,coordinates,vertex_normals*weights,points*weights,camera,projection);
	normal=normalize(frame[2]); d=vec3(0.0); s=vec3(0.0);
	light_inputs=inputs[0]*weights.x+inputs[1]*weights.y+inputs[2]*weights.z;
	if (ei_surface_fx.x<0.5) {
		// Original appearance retains native per-vertex packed colours,
		// independently of the fragment normal used by rain and tracks.
		mat3 ds; mat3 ss;
		for (int i=0;i<query_vertex_count;i++) {
			vec3 pd; vec3 ps; contact_light(points[i],vertex_normals[i],inputs[i],pd,ps);
			ds[i]=pd; ss[i]=ps;
		}
		d=ds*weights; s=ss*weights;
	}
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
struct ContactResult { vec3 albedo; vec3 diffuse; vec3 specular; vec3 normal; vec3 surface; vec3 point; vec4 light_inputs; float weight; float dark; };
bool contact_locate(vec3 world,vec3 wn,float band,float distance_to_eye,out float strength,out float height,out vec2 grid,out ivec2 tile,out mat2 jacobian,out float rise,out vec2 folded) {
	vec2 p=vec2(world.x,-world.z);
	height=0.0; grid=vec2(0.0); tile=ivec2(0); jacobian=mat2(1.0); rise=0.0; folded=p;
	strength=contact_strength*(1.0-smoothstep(30.0,45.0,distance_to_eye));
	if (strength<=0.0 || band<=0.0) { return false; }
	ivec2 cell=ivec2(floor(p));
	if (any(lessThan(p,vec2(0.0))) || any(greaterThanEqual(p,vec2(textureSize(query_vertices,0)-1)))) { return false; }
	// A conservative bound from every source vertex of the nine candidate
	// cells. Loose material/banks can add at most 0.5 m; no track read needed.
	if (world.y>texelFetch(query_vertices,cell,0).a+0.5+band*2.5) { return false; }
	// Fold the adjacent strip up the wall. At zero rise this is exactly the
	// original ground point; upward faces retain an ordinary top projection.
	float horizontal=length(wn.xz);
	vec2 fold=horizontal>1e-3 ? vec2(wn.x,-wn.z)/horizontal*smoothstep(0.2,0.7,horizontal) : vec2(0.0);
	for (int pass=0;pass<contact_query_passes;pass++) {
		float sampled_height; vec2 sampled_grid; ivec2 sampled_tile; mat2 sampled_jacobian;
		if (!query_surface(folded,sampled_height,sampled_grid,sampled_tile,sampled_jacobian)) {
			if (pass==0) { return false; }
			// The folded strip can leave the map. Retain the first query's
			// complete state, including its original point and derivatives.
			folded=p; break;
		}
		height=sampled_height; grid=sampled_grid; tile=sampled_tile; jacobian=sampled_jacobian;
		if (pass==0) {
			rise=max(world.y-height,0.0);
			if (rise>band*2.5) { return false; }
			vec4 water=textureLod(terrain_cells,p/vec2(textureSize(terrain_cells,0)),0.0);
			float water_y=water.r+level[clamp(int(water.a+0.5),0,63)];
			strength*=smoothstep(0.025,0.10,height-water_y);
			if (strength<=0.0) { return false; }
			if (horizontal<=1e-3 || rise<=0.001) { break; }
			folded=p+fold*rise;
		}
	}
	return true;
}
ContactResult contact_prepare(vec3 world,vec3 wn,float band,float distance_to_eye,vec4 camera,vec4 projection) {
	ContactResult result=ContactResult(vec3(0.0),vec3(0.0),vec3(0.0),vec3(0,1,0),vec3(0.0,1.0,0.0),vec3(0.0),vec4(0.0),0.0,1.0);
	float strength; float height; vec2 grid; ivec2 tile; mat2 jacobian; float rise; vec2 folded;
	bool active=contact_locate(world,wn,band,distance_to_eye,strength,height,grid,tile,jacobian,rise,folded);
	// All fragment lanes rejoin after the query before taking derivatives.
	// This preserves the complete folded-wall footprint even when a helper
	// fragment leaves the contact band or its projected terrain triangle.
	vec2 folded_dx=dFdx(folded); vec2 folded_dy=dFdy(folded);
	vec2 dx=jacobian*folded_dx*0.5;
	vec2 dy=jacobian*folded_dy*0.5;
	if (!active) { return result; }
	vec4 water=textureLod(terrain_cells,folded/vec2(textureSize(terrain_cells,0)),0.0);
	float water_y=water.r+level[clamp(int(water.a+0.5),0,63)];
	int ground=int(water.g+0.5);
	vec2 uv=grid*0.5;
	vec4 traits;
	vec3 albedo=ground_sample(tile,uv-vec2(tile),dx,dy,traits);
	vec4 mean_traits;
	vec3 mean=ground_sample(tile,uv-vec2(tile),dx*4.0,dy*4.0,mean_traits);
	float grass=clamp((mean.g-max(mean.r,mean.b))*8.0/max(mean.g,0.05),0.0,1.0);
	vec2 blend=contact_weight(rise,band,wn.y,contact_noise(folded),grass,dot(albedo-mean,vec3(0.2126,0.7152,0.0722)));
	mat3 relief_frame; vec2 height_gradient; float compression;
	contact_ground_light(grid,height,camera,projection,result.normal,result.diffuse,result.specular,relief_frame,height_gradient,compression,result.light_inputs);
	result.point=vec3(folded.x,height,-folded.y);
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
		if (fade>0.0) {
			vec2 slope=vec2(contact_ground_height(right)-contact_ground_height(left),contact_ground_height(up)-contact_ground_height(down));
			float painted_relief=mix(mix(mix(1.1,2.4,traits.x),0.35,traits.y),0.15,traits.w);
			result.normal=normalize(relief_frame[2]-(relief_frame[0]*slope.x+relief_frame[1]*slope.y)*painted_relief*fade);
			// Copy the terrain's triplanar fine relief on the reconstructed
			// ground. Explicit footprints use this selected triangle's height
			// plane and reconverged wall-fold derivatives, not object-wall Y.
			vec3 gx=vec3(folded_dx.x,dot(height_gradient,folded_dx),-folded_dx.y);
			vec3 gy=vec3(folded_dy.x,dot(height_gradient,folded_dy),-folded_dy.y);
			vec3 bw=pow(abs(result.normal),vec3(4.0)); bw/=bw.x+bw.y+bw.z;
			vec2 a=textureGrad(detail_nm,result.point.zy*0.45,gx.zy*0.45,gy.zy*0.45).xy*2.0-1.0;
			vec2 b=textureGrad(detail_nm,result.point.xz*0.45,gx.xz*0.45,gy.xz*0.45).xy*2.0-1.0;
			vec2 e=textureGrad(detail_nm,result.point.xy*0.45,gx.xy*0.45,gy.xy*0.45).xy*2.0-1.0;
			vec2 f=textureGrad(detail_nm,result.point.xz*1.7+0.37,gx.xz*1.7,gy.xz*1.7).xy*2.0-1.0;
			vec2 fine=f*mix(0.25,0.85,traits.z);
			vec3 pert=vec3(0.0,a.y,a.x)*bw.x+vec3(b.x+fine.x,0.0,b.y+fine.y)*bw.y+vec3(e.x,e.y,0.0)*bw.z;
			pert-=result.normal*dot(result.normal,pert);
			float relief=mix(mix(mix(0.13,0.10,traits.x),0.055,traits.y),0.025,traits.w);
			result.normal=normalize(result.normal+pert*relief*fade);
		}
		float macro=texture(macro_tex,vec2(folded.x,-folded.y)*0.012).r;
		albedo*=mix(1.0,0.92+0.16*macro,detail*(1.0-traits.y*0.6));
		float wet=1.0-smoothstep(0.02,0.55,abs(height-water_y));
		if (int(water.b+0.5)==13 || ground==9 || ground==10 || ground==12) { wet=0.0; }
		albedo*=1.0-wet*detail*mix(0.20,0.08,traits.z);
	}
	if (ei_surface_fx.z>0.5 && ei_weather.x>0.0 && ground!=9 && ground!=10 && ground!=12 && ground!=13 && int(water.b+0.5)!=13) {
		float cover=textureLod(rain_cover,folded/vec2(textureSize(terrain_cells,0)),0.0).r;
		float wet=ei_weather.x*(1.0-smoothstep(0.08,0.40,cover-height))*smoothstep(-0.04,0.10,height-water_y)*smoothstep(0.05,0.65,abs(result.normal.y));
		albedo*=1.0-wet*mix(0.23,0.08,traits.z);
		result.surface=vec3(wet*mix(0.65,0.15,traits.z),mix(0.35,0.65,traits.z),0.0);
	}
	vec2 state=texelFetch(query_tiles,clamp(tile,ivec2(0),textureSize(query_tiles,0)-1),0).rg;
	if (soft_ground && state.x>0.5 && compression>0.0) {
		vec2 uv=((folded-vec2(tile/16)*32.0)*(511.0/32.0)+0.5)/512.0;
		vec2 step_uv=vec2(1.0/512.0,0.0);
		float layer=state.x-1.0;
		vec2 a=contact_track(uv-step_uv,layer); vec2 b=contact_track(uv+step_uv,layer);
		vec2 d=contact_track(uv-step_uv.yx,layer); vec2 e=contact_track(uv+step_uv.yx,layer);
		vec2 track=contact_track(uv,layer);
		vec2 slope=vec2(soft_height(b)-soft_height(a),soft_height(e)-soft_height(d))*compression*(511.0/64.0);
		vec3 track_normal=normalize(result.normal+vec3(-slope.x,0.0,slope.y));
		if (ei_surface_fx.x<0.5 && dot(ei_sun_dir,ei_sun_dir)>0.5) {
			float relief=dot(track_normal-result.normal,normalize(ei_sun_dir));
			albedo*=clamp(1.0+relief*0.5,0.78,1.06);
		}
		result.normal=track_normal;
		albedo*=1.0-track.r*(ground==3 ? 0.12:0.16);
	}
	if (ei_surface_fx.x>0.5) { contact_light(result.point,result.normal,result.light_inputs,result.diffuse,result.specular); }
	result.albedo=albedo;
	result.weight=blend.x*strength;
	result.dark=mix(1.0,blend.y,strength);
	return result;
}
"""

const FRAGMENT := """
	vec3 contact_world=(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
	vec3 contact_world_normal=normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).xyz);
	vec4 contact_camera=PROJECTION_MATRIX[3].w==0.0 ? vec4(INV_VIEW_MATRIX[3].xyz,1.0) : vec4(INV_VIEW_MATRIX[2].xyz,0.0);
	vec4 contact_projection=vec4(INV_VIEW_MATRIX[2].xyz,PROJECTION_MATRIX[0].x*PROJECTION_MATRIX[1].y*VIEWPORT_SIZE.x*VIEWPORT_SIZE.y*0.25);
	ContactResult contact=contact_prepare(contact_world,contact_world_normal,contact_band,length(VERTEX),contact_camera,contact_projection);
	contact_diffuse_weight=vec4(contact.diffuse,contact.weight);
	contact_specular_dark=vec4(contact.specular,contact.dark);
	// Compatibility decodes ALBEDO after fragment(), before light(). Our
	// extra fragment-to-light colour needs the same conversion explicitly.
	contact_albedo=OUTPUT_IS_SRGB ? ei_lin(contact.albedo) : contact.albedo;
	contact_normal=normalize((VIEW_MATRIX*vec4(contact.normal,0.0)).xyz);
	contact_surface=contact.surface;
	contact_light_inputs=contact.light_inputs;
	contact_vpos=(VIEW_MATRIX*vec4(contact.point,1.0)).xyz;
	// A zero albedo channel cannot carry any diffuse factor. The original
	// upper surface is untouched; the contact band needs this finite divisor.
	// GLES uses a cubic sRGB approximation with a smaller dark-end slope;
	// 0.01 encoded is safely above the light() denominator's 1e-4 floor.
	if (contact.weight>0.0) { ALBEDO=max(ALBEDO,vec3(OUTPUT_IS_SRGB ? 0.01 : 1e-4)); }
"""


static func source(original: String, cliffs := false) -> String:
	var code := original.replace("shader_type spatial;", "shader_type spatial;\n#define EI_GROUND_CONTACT")
	var helpers := GroundSurfaceShader.LAND_UNIFORMS + GroundSurfaceShader.SOFT_UNIFORMS \
		+ GroundSurfaceShader.SOFT_FUNCTIONS + GroundSurfaceShader.TILE_FUNCTIONS \
		+ GroundSurfaceShader.QUERY_SHADER + DECLARATIONS + FUNCTIONS
	if cliffs:
		code = code.replace("shader_type spatial;", "shader_type spatial;\n#define EI_TERRAIN_CLIFFS")
		helpers = helpers.replace("// Terrain's native light model", TerrainCliff.CliffShader.FUNCTIONS + "\n// Terrain's native light model")
		# Compute projection weights from the base mesh normal before painted
		# relief, and suppress that relief on the projected share like land.
		helpers = helpers.replace("\t\tvec3 average=", "\t\tvec3 planes=cliff_weights(tile,local,result.normal,distance_to_eye)*detail;\n\t\tvec3 average=")
		helpers = helpers.replace("*painted_relief*fade);", "*painted_relief*fade*(1.0-planes.y));")
		helpers = helpers.replace("\t\tfloat macro=", "\t\talbedo=cliff_albedo(albedo,tile,local,vec3(folded.x,height,-folded.y),planes);\n\t\tfloat macro=")
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
	# R1 keeps the object's shadow lookup, but the ground's material response
	# must not inherit a figure-facing guard. Keep every non-directional call
	# on the original helper, including the local-light pass correction.
	const DIRECTIONAL_CALL := "DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, ei_draw_factor(ei_alb, d, s, shadow, gd, gs, ground, dark));"
	assert(code.count(DIRECTIONAL_CALL) == 1)
	code = code.replace(DIRECTIONAL_CALL,
		"DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, contact_directional_factor(ei_alb, d, s, shadow, mix(0.5, 1.0, ATTENUATION), gd, gs, ground, dark));")
	code = code.replace("void light() {", """
vec3 contact_directional_factor(vec3 albedo, vec3 d, vec3 s, float mesh_shadow, float ground_shadow, vec3 gd, vec3 gs, vec4 ground, float dark) {
	// Preserve the old arithmetic when the two responses agree, and beyond
	// the colour band. Contact darkening can extend past zero ground weight.
	if (ground.a <= 0.0 || mesh_shadow == ground_shadow) {
		return ei_draw_factor(albedo, d, s, mesh_shadow, gd, gs, ground, dark);
	}
	vec3 mesh_colour=clamp(ei_srgb(albedo)*d+s,0.0,1.0)*mesh_shadow;
	vec3 ground_colour=clamp(ei_srgb(ground.rgb)*gd+gs,0.0,1.0)*ground_shadow;
	return ei_lin(mix(mesh_colour,ground_colour,ground.a)*dark)/max(albedo,vec3(1e-4));
}
void light() {""")
	code = code.replace("vec3 ns = s;", """vec3 ns = s;
			float ground_k=dot(contact_normal,LIGHT);
			float ground_lz=(INV_VIEW_MATRIX*vec4(LIGHT,0.0)).y;
			float ground_uw=max(1.0-ground_lz*ground_lz*contact_light_inputs.a*4.0,0.0);
			vec3 ground_col=min(contact_light_inputs.rgb+min(ei_srgb(LIGHT_COLOR/PI),vec3(1.0))*a*(ground_k>0.0?1.0:max(ground_k+1.0,0.0))*ground_uw,vec3(1.0));
			vec3 gns=gs;
			if (SPECULAR_AMOUNT>0.0 && SPECULAR_AMOUNT<0.01) { gns=max(gns,floor(clamp(ground_col,vec3(0.0),vec3(1.0))*255.0)/255.0); }
			vec3 gnd=max(gd,ei_diffuse_byte(max(ground_col,gns)));""")
	code = code.replace("vec3 loc = ei_alb * LIGHT_COLOR / PI * nl * ATTENUATION * 0.75 /*EI_FA*/;", """
		vec3 local_colour=mix(ei_alb*nl,contact_albedo*max(dot(contact_normal,LIGHT),0.0),contact_diffuse_weight.a)*contact_specular_dark.a;
		vec3 loc=local_colour*LIGHT_COLOR/PI*ATTENUATION*0.75 /*EI_FA*/;""")
	# Reuse the assembled native highlight response, including the current
	# cloud-shadow specialization, but evaluate the copied ground profile.
	var begin := code.find("\tif (ei_surface.x > 0.001")
	var end := code.find("\tif (ei_leaf > 0.001)",begin)
	assert(begin>=0 and end>begin)
	var highlight := code.substr(begin,end-begin)
	highlight = highlight.replace("ei_surface","contact_surface").replace("NORMAL","contact_normal")
	highlight = highlight.replace("ei_alb","contact_albedo").replace("ei_vpos","contact_vpos")
	highlight = highlight.replace("+ VIEW;","+ normalize(-contact_vpos);")
	highlight = highlight.replace("* 0.22 /*EI_FA*/;","* 0.22 * contact_diffuse_weight.a * contact_specular_dark.a /*EI_FA*/;")
	code = code.replace("* 0.22 /*EI_FA*/;", "* 0.22 * (1.0-contact_diffuse_weight.a) /*EI_FA*/;")
	code = code.replace("\tif (ei_leaf > 0.001)",highlight+"\tif (ei_leaf > 0.001)")
	return code


# Runtime-bounded loop keeps GL from expanding the terrain sampler four times.
# Invoked only without admitted Natural transitions, which own their sampler.
const RELIEF_FUNCTION := """
uniform int contact_relief_passes = 4;
void contact_relief_samples(ivec2 tile,vec2 local,vec2 step_uv,vec2 dx,vec2 dy,
		out vec3 left,out vec3 right,out vec3 down,out vec3 up) {
	left=vec3(0.0); right=vec3(0.0); down=vec3(0.0); up=vec3(0.0);
	// Internal default is always four, like contact_query_passes. Keeping
	// one sampler call prevents repeated GL expansion of the complete field.
	for (int i=0;i<contact_relief_passes;i++) {
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
const RELIEF_CALLS := """vec3 left=ground_sample(tile,local-step_uv,dx,dy,unused_traits);
		vec3 right=ground_sample(tile,local+step_uv,dx,dy,unused_traits);
		vec3 down=ground_sample(tile,local-step_uv.yx,dx,dy,unused_traits);
		vec3 up=ground_sample(tile,local+step_uv.yx,dx,dy,unused_traits);"""


static func compact_relief(code: String) -> String:
	# GLES cold preparation expands one complete terrain sampler instead of three.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility": return compact_samples(code)
	# Retain Mobile's program until the physical-device repeat control is stable.
	if RenderingServer.get_current_rendering_method() == "mobile": return code
	if not code.contains(RELIEF_CALLS): return code
	code=code.replace("// Terrain's native light model",RELIEF_FUNCTION+"\n// Terrain's native light model")
	return code.replace(RELIEF_CALLS,"""vec3 left; vec3 right; vec3 down; vec3 up;
		contact_relief_samples(tile,local,step_uv,dx,dy,left,right,down,up);""")


static func compact_samples(code: String) -> String:
	if RenderingServer.get_current_rendering_method() == "mobile": return code
	if not code.contains(RELIEF_CALLS): return code
	code=code.replace("// Terrain's native light model",SAMPLE_FUNCTION+"\n// Terrain's native light model")
	code=code.replace(SAMPLE_CALLS,"""	vec4 traits; vec3 albedo; vec3 mean;
	vec3 left; vec3 right; vec3 down; vec3 up;
	contact_ground_samples(tile,uv-vec2(tile),dx,dy,detail>0.0,albedo,mean,traits,left,right,down,up);""")
	return code.replace(RELIEF_CALLS,"")

const SAMPLE_FUNCTION := """
uniform int contact_sample_passes = 6;
void contact_ground_samples(ivec2 tile,vec2 local,vec2 dx,vec2 dy,bool relief,
        out vec3 albedo,out vec3 mean,out vec4 traits,
        out vec3 left,out vec3 right,out vec3 down,out vec3 up) {
    albedo=vec3(0.0); mean=vec3(0.0); traits=vec4(0.0);
    left=vec3(0.0); right=vec3(0.0); down=vec3(0.0); up=vec3(0.0);
    float border=8.0*source_texel*tiles_per_axis;
    vec2 step_uv=vec2(source_texel*tiles_per_axis*1.5/(1.0-2.0*border),0.0);
    for (int i=0;i<contact_sample_passes;i++) {
        if (i>=2 && !relief) { break; }
        vec2 point=local; vec2 gx=dx; vec2 gy=dy;
        if (i==1) { gx=dx*4.0; gy=dy*4.0; }
        if (i==2) { point=local-step_uv; }
        if (i==3) { point=local+step_uv; }
        if (i==4) { point=local-step_uv.yx; }
        if (i==5) { point=local+step_uv.yx; }
        vec4 sampled_traits;
        vec3 color=ground_sample(tile,point,gx,gy,sampled_traits);
        if (i==0) { albedo=color; traits=sampled_traits; }
        if (i==1) { mean=color; }
        if (i==2) { left=color; }
        if (i==3) { right=color; }
        if (i==4) { down=color; }
        if (i==5) { up=color; }
    }
}
"""
const SAMPLE_CALLS := """	vec4 traits;
	vec3 albedo=ground_sample(tile,uv-vec2(tile),dx,dy,traits);
	vec4 mean_traits;
	vec3 mean=ground_sample(tile,uv-vec2(tile),dx*4.0,dy*4.0,mean_traits);"""
