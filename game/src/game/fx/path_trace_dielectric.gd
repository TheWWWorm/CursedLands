extends RefCounted
## Explicit authoring API. No texture/name/brightness heuristics turn original
## painted windows or crystal armour into transparent geometry.
const COMMON := """
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
global uniform float ei_pt_trans_active;
global uniform float ei_pt_rr_active;
global uniform sampler2D ei_pt_trans_colour : filter_nearest, repeat_disable;
global uniform sampler2D ei_pt_trans_guide : filter_nearest, repeat_disable;
global uniform mat4 ei_rt_view_projection;
global uniform mat4 ei_rt_view;
bool ei_transmission(vec3 world, vec3 normal, float kind, mat4 current_projection, out vec3 colour) {
    colour=vec3(0.0);
    if(ei_pt_trans_active<0.5)return false;
    mat4 projection=ei_rt_view_projection;
    if(ei_pt_rr_active>0.5) {
        // Match the main PT receiver: API Y-down/reverse depth back to the
        // ray camera's OpenGL clip convention, retaining the current jitter.
        mat4 undo=mat4(vec4(1.0,0.0,0.0,0.0),vec4(0.0,-1.0,0.0,0.0),vec4(0.0,0.0,-2.0,0.0),vec4(0.0,0.0,1.0,1.0));
        projection=undo*current_projection;
    }
    vec4 clip=projection*vec4(world,1.0);
    vec2 uv=vec2(clip.x,-clip.y)/clip.w*.5+.5;
    if(clip.w<=0.0||any(lessThan(uv,vec2(0.0)))||any(greaterThanEqual(uv,vec2(1.0))))return false;
    ivec2 size=textureSize(ei_pt_trans_guide,0);
    vec2 pixel=uv*vec2(size)-.5,blend=fract(pixel);
    ivec2 base=ivec2(floor(pixel));
    float depth=-(ei_rt_view*vec4(world,1.0)).z,total=0.0;
    float tolerance=kind<1.5?.3:max(.04,depth*.003);
    for(int y=0;y<2;y++)for(int x=0;x<2;x++) {
        ivec2 at=clamp(base+ivec2(x,y),ivec2(0),size-1);
        vec4 guide=texelFetch(ei_pt_trans_guide,at,0),light=texelFetch(ei_pt_trans_colour,at,0);
        if(guide.w<=0.0||abs(guide.w-depth)>tolerance||abs(dot(guide.xyz,normal))<.65||abs(light.a-kind)>.1)continue;
        float w=(x==0?1.0-blend.x:blend.x)*(y==0?1.0-blend.y:blend.y);
        colour+=light.rgb*w;total+=w;
    }
    if(total<.05)return false;
    colour/=total;return true;
}
#else
bool ei_transmission(vec3 world, vec3 normal, float kind, mat4 current_projection, out vec3 colour) { colour=vec3(0.0);return false; }
#endif
"""
const GLASS := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always;
uniform sampler2D albedo_tex : source_color;
uniform vec4 ei_material_diffuse=vec4(1.0);
uniform vec3 ei_material_emissive=vec3(0.0);
uniform vec4 surface_profile=vec4(0.0);
uniform sampler2D background : hint_screen_texture, filter_linear;
uniform vec3 fallback_tint=vec3(1.0);
varying vec3 glass_world;
TRANSMISSION_COMMON
void vertex(){glass_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
    vec3 colour=texture(background,SCREEN_UV).rgb*fallback_tint;
    vec3 traced;
    if(ei_transmission(glass_world,normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).xyz),2.0,PROJECTION_MATRIX*VIEW_MATRIX,traced))colour=traced;
    ALBEDO=colour;EMISSION=vec3(0.0);ALPHA=1.0;
}
"""
static func material(ior:=1.5,transmittance:=Color(.92,.98,.97),distance:=1.0,thin:=false,thickness:=.01) -> ShaderMaterial:
	Gfx.ensure_globals()
	var sigma:=Vector3(-log(clampf(transmittance.r,.0001,1.0)),-log(clampf(transmittance.g,.0001,1.0)),-log(clampf(transmittance.b,.0001,1.0)))/maxf(distance,.001)
	var result:=ShaderMaterial.new();var shader:=Shader.new()
	var code:=GLASS.replace("TRANSMISSION_COMMON",COMMON)
	if thin:code=code.replace("cull_back","cull_disabled")
	shader.code=code;result.shader=shader
	var white:=Image.create(1,1,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	result.set_shader_parameter("albedo_tex",ImageTexture.create_from_image(white))
	result.set_shader_parameter("fallback_tint",Vector3(transmittance.r,transmittance.g,transmittance.b))
	result.set_meta("pt_dielectric",PackedFloat32Array([sigma.x,sigma.y,sigma.z,clampf(ior,1.0,2.5),3.0 if thin else 2.0,maxf(thickness,.0001),0,0]))
	return result
