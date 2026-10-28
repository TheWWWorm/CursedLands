class_name TerrainSamplingShader
extends RefCounted
## Keep one expanded ground sampler on Mobile. Five separate call sites make
## the Adreno 650 program both expensive and visibly different from desktop.
## Coordinates, gradients, edge blending and the four relief taps stay intact.

const CENTER := "c = ground_sample(tile, clamp(local, vec2(0.0), vec2(0.99999)), dx, dy, traits);"
const FADE := "float fade = detail * (1.0 - smoothstep(25.0, 70.0, length(VERTEX)));"
const RELIEF := """vec3 left = ground_sample(tile, local - step_uv, dx, dy, unused_traits);
			vec3 right = ground_sample(tile, local + step_uv, dx, dy, unused_traits);
			vec3 down = ground_sample(tile, local - step_uv.yx, dx, dy, unused_traits);
			vec3 up = ground_sample(tile, local + step_uv.yx, dx, dy, unused_traits);"""
const JUNCTION_RELIEF := """vec3 left; vec3 right; vec3 down; vec3 up;
			transition_relief_samples(tile,local,step_uv,dx,dy,left,right,down,up);"""
const FUNCTIONS := """
// Internal bound, always five. A constant loop is unrolled by mobile drivers
// and recreates the original large program. This is not a quality setting.
uniform int terrain_sample_passes = 5;
void terrain_samples(ivec2 tile,vec2 local,vec2 dx,vec2 dy,vec2 step_uv,bool relief,
        out vec3 center,out vec4 traits,
        out vec3 left,out vec3 right,out vec3 down,out vec3 up) {
    center=vec3(0.0); traits=vec4(0.0);
    left=vec3(0.0); right=vec3(0.0); down=vec3(0.0); up=vec3(0.0);
    for (int i=0;i<terrain_sample_passes;i++) {
        if (i>0 && !relief) { break; }
        vec2 point=clamp(local,vec2(0.0),vec2(0.99999));
        if (i==1) { point=local-step_uv; }
        if (i==2) { point=local+step_uv; }
        if (i==3) { point=local-step_uv.yx; }
        if (i==4) { point=local+step_uv.yx; }
        vec4 sampled_traits;
        vec3 color=ground_sample(tile,point,dx,dy,sampled_traits);
        if (i==0) { center=color; traits=sampled_traits; }
        if (i==1) { left=color; }
        if (i==2) { right=color; }
        if (i==3) { down=color; }
        if (i==4) { up=color; }
    }
}
"""

static func compact(code: String) -> String:
	# The baked branch is already a small texture lookup; looping it adds
	# overhead on Adreno. Only the full atlas/blending program needs sharing.
	if code.contains("#define EI_BAKED_TERRAIN"):
		return code
	if not code.contains("#define EI_TERRAIN_LIGHT") or not code.contains(CENTER):
		return code
	if not code.contains(RELIEF) and not code.contains(JUNCTION_RELIEF):
		return code
	code = code.replace("float ground_height(vec3 colour)", FUNCTIONS + "\nfloat ground_height(vec3 colour)")
	code = code.replace(RELIEF, "").replace(JUNCTION_RELIEF, "").replace(FADE, "")
	return code.replace(CENTER, FADE + """
		vec3 left; vec3 right; vec3 down; vec3 up;
		vec2 sample_step=vec2(source_texel*tiles_per_axis*1.5/(1.0-2.0*border),0.0);
		terrain_samples(tile,local,dx,dy,sample_step,fade>0.0,c,traits,left,right,down,up);""")
