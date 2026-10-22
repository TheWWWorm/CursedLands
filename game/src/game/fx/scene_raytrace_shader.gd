extends RefCounted
## Only the game's opaque, lit world materials participate. Reflections,
## previews, water and particles retain their own lighting models.
const COMMON := """
global uniform vec4 ei_rt_state; // enabled, shadows, GI, receiver radius
global uniform vec4 ei_rt_center;
global uniform mat4 ei_rt_view_projection;
global uniform mat4 ei_rt_inverse_view_projection;
global uniform mat4 ei_rt_view;
global uniform vec3 ei_rt_eye;
global uniform float ei_pt_active;
global uniform sampler2D ei_rt_gi : filter_nearest, repeat_disable;
global uniform sampler2D ei_rt_guide : filter_nearest, repeat_disable;
global uniform sampler2D ei_rt_shadow0 : filter_nearest, repeat_disable;
global uniform sampler2D ei_rt_shadow1 : filter_nearest, repeat_disable;
global uniform vec4 ei_rt_point0;
global uniform vec4 ei_rt_point1;
global uniform vec4 ei_rt_point2;
global uniform vec4 ei_rt_point3;
global uniform vec4 ei_rt_point4;
global uniform vec4 ei_rt_point5;
global uniform vec4 ei_rt_point6;
// Ground-contact variants already use all 32 varying declarations. Keep
// both fragment-to-light flags in the existing declaration budget.
varying vec2 ei_rt_flags;
#define ei_rt_valid ei_rt_flags.x
#define ei_pt_blend ei_rt_flags.y
varying vec4 ei_rt_visibility0;
varying vec4 ei_rt_visibility1;

vec3 ei_rt_position(ivec2 p,float depth,ivec2 size) {
    vec2 uv=(vec2(p)+0.5)/vec2(size);
    vec4 near=ei_rt_inverse_view_projection*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0);near/=near.w;
    vec3 forward=-vec3(ei_rt_view[0][2],ei_rt_view[1][2],ei_rt_view[2][2]);
    float near_depth=dot(near.xyz-ei_rt_eye,forward);
    // Perspective clip.w changes with world position; orthographic does not.
    bool orthographic=abs(ei_rt_view_projection[0][3])+abs(ei_rt_view_projection[1][3])+abs(ei_rt_view_projection[2][3])<0.001;
    return orthographic?near.xyz+forward*(depth-near_depth):ei_rt_eye+(near.xyz-ei_rt_eye)*(depth/near_depth);
}

bool ei_rt_sample(vec3 world,vec3 normal,out vec3 gi,out vec4 visibility0,out vec4 visibility1) {
    gi=vec3(0.0);visibility0=vec4(1.0);visibility1=vec4(1.0);
    if(ei_rt_state.x<0.5)return false;
    vec4 clip=ei_rt_view_projection*vec4(world,1.0);
    vec2 uv=vec2(clip.x,-clip.y)/clip.w*0.5+0.5;
    ivec2 size=textureSize(ei_rt_guide,0);
    // Evaluate derivatives before receiver-dependent branches so each quad
    // has a valid tangent plane even at the snapshot/viewport boundaries.
    vec3 dx=dFdx(world),dy=dFdy(world),plane=cross(dx,dy);
    plane=length(plane)>0.0000001?normalize(plane):normal;
    if(ei_pt_active>0.5) {
        // The tracer faces both sides of cutout leaves toward the camera.
        // The raster material retains authored normals on its back faces;
        // align the same way before rejecting an otherwise matching hit.
        bool parallel=abs(ei_rt_view_projection[0][3])+abs(ei_rt_view_projection[1][3])+abs(ei_rt_view_projection[2][3])<0.001;
        vec3 view=parallel?vec3(ei_rt_view[0][2],ei_rt_view[1][2],ei_rt_view[2][2]):normalize(ei_rt_eye-world);
        if(dot(plane,view)<0.0)plane=-plane;
        if(dot(normal,plane)<0.0)normal=-normal;
        if(dot(normal,view)<=0.0)normal=plane;
    }
    float footprint=max(length(dx)/max(length(dFdx(uv)*vec2(size)),0.001),
                        length(dy)/max(length(dFdy(uv)*vec2(size)),0.001));
    if(clip.w<=0.0||any(lessThan(uv,vec2(0.0)))||any(greaterThanEqual(uv,vec2(1.0))))return false;
    float distance=length(world-ei_rt_center.xyz);
    if(distance>=ei_rt_state.w)return false;
    float depth=-(ei_rt_view*vec4(world,1.0)).z;
    vec2 pixel=uv*vec2(size)-0.5,blend=fract(pixel);
    ivec2 base=ivec2(floor(pixel));
    float total=0.0;vec4 a=vec4(0.0),b=vec4(0.0);
    // Reconstruct from matching receivers only: ordinary bilinear sampling
    // would pull a foreground wall's darkness onto the floor behind it.
    for(int y=0;y<2;y++)for(int x=0;x<2;x++) {
        ivec2 p=clamp(base+ivec2(x,y),ivec2(0),size-1);
        vec4 guide=texelFetch(ei_rt_guide,p,0);
        if(guide.w<=0.0||dot(normal,guide.xyz)<0.45)continue;
        vec3 delta=ei_rt_position(p,guide.w,size)-world;
        if(abs(dot(delta,plane))>max(0.025,depth*0.0005)||length(delta)>max(0.1,footprint*2.5))continue;
        float w=(x==0?1.0-blend.x:blend.x)*(y==0?1.0-blend.y:blend.y);
        gi+=texelFetch(ei_rt_gi,p,0).rgb*w;
        a+=texelFetch(ei_rt_shadow0,p,0)*w;
        // PT's second shadow channel is the reconstruction material guide;
        // the raster receiver only consumes diffuse and glossy radiance.
        if(ei_pt_active<=0.5)b+=texelFetch(ei_rt_shadow1,p,0)*w;
        total+=w;
    }
    if(total<0.01)return false;
    float fade=1.0-smoothstep(ei_rt_state.w-12.0,ei_rt_state.w,distance);
    if(ei_pt_active>0.5) {
        gi/=total;visibility0=a/total;visibility1=b/total;
    } else {
        gi=mix(ei_lin(ei_ambient),gi/total,fade);
        visibility0=mix(vec4(1.0),a/total,fade);visibility1=mix(vec4(1.0),b/total,fade);
    }
    return true;
}

float ei_rt_point_visibility(vec3 world,vec3 direction,mat4 view,out float range_falloff) {
    vec4 points[7]=vec4[7](ei_rt_point0,ei_rt_point1,ei_rt_point2,ei_rt_point3,ei_rt_point4,ei_rt_point5,ei_rt_point6);
    range_falloff=-1.0;
    for(int i=0;i<7;i++) {
        vec3 delta=points[i].xyz-world;float distance=length(delta);
        if(points[i].w<=0.0||distance>=points[i].w||distance<0.001)continue;
        vec3 light_direction=normalize((view*vec4(delta,0.0)).xyz);
        if(dot(light_direction,direction)>0.99999) {
            range_falloff=max(1.0-distance*distance/(points[i].w*points[i].w),0.0);
            return i<3?ei_rt_visibility0[i+1]:ei_rt_visibility1[i-3];
        }
    }
    return 1.0;
}
"""

const CAPTURE := """
    ei_rt_valid=0.0;ei_pt_blend=0.0;ei_rt_visibility0=vec4(1.0);ei_rt_visibility1=vec4(1.0);
    if(!IN_SHADOW_PASS && (CAMERA_VISIBLE_LAYERS&1048576u)==0u &&
        distance(INV_VIEW_MATRIX[3].xyz,ei_rt_eye)<0.025) {
        vec3 indirect;vec4 a,b;
        vec3 world=(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
        vec3 normal=normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).xyz);
        if(ei_rt_sample(world,normal,indirect,a,b)) {
            if(ei_pt_active>0.5) {
                ei_pt_blend=1.0-smoothstep(ei_rt_state.w-12.0,ei_rt_state.w,length(world-ei_rt_center.xyz));
                // Retain the terrain's authored underwater attenuation. The
                // combined PT signal has no individual light direction, so
                // use the same diffuse-depth factor as the ambient path.
                vec3 reflected=(ALBEDO*ei_material_diffuse.rgb*indirect+a.rgb)*max(1.0-ei_k,0.0);
                EMISSION+=(reflected+ei_lin(ei_srgb(ALBEDO)*ei_e))*ei_pt_blend;
            } else {
                ei_rt_valid=1.0;ei_rt_visibility0=a;ei_rt_visibility1=b;
                vec3 ambient=mix(ei_lin(ei_ambient),indirect,ei_rt_state.z);
                EMISSION+=ALBEDO*ei_material_diffuse.rgb*ambient*max(1.0-ei_k,0.0)+ei_lin(ei_srgb(ALBEDO)*ei_e);
            }
        }
    }
"""

const LIGHT := """
    // A fully traced receiver already supplied all lighting in fragment().
    // The fade band and unmatched/distant receivers still need raster light.
    if(ei_pt_blend<1.0) {
    vec3 ei_pt_previous_diffuse=DIFFUSE_LIGHT,ei_pt_previous_specular=SPECULAR_LIGHT;
    if(ei_rt_valid>0.5) {
        vec3 direction=LIGHT;
        vec3 colour=LIGHT_COLOR/PI;
        float attenuation=ATTENUATION;
        bool sun=LIGHT_IS_DIRECTIONAL && abs(SPECULAR_AMOUNT-0.371)<0.002;
        vec3 world=(INV_VIEW_MATRIX*vec4(ei_vpos,1.0)).xyz;
        if(sun) {
            direction=normalize((VIEW_MATRIX*vec4(ei_sun_dir,0.0)).xyz);
            colour=ei_lin(ei_sun);
            if(ei_rt_state.y>0.5)attenuation=ei_rt_visibility0.x;
            colour*=EI_RT_CLOUD;
        } else if(!LIGHT_IS_DIRECTIONAL && ei_rt_state.y>0.5) {
            float falloff;
            float visibility=ei_rt_point_visibility(world,LIGHT,VIEW_MATRIX,falloff);
            if(falloff>=0.0)attenuation=falloff*visibility;
        }
        float nl=max(dot(NORMAL,direction),0.0);
        float underwater=max(1.0-pow((INV_VIEW_MATRIX*vec4(direction,0.0)).y,2.0)*ei_k,0.0);
        DIFFUSE_LIGHT+=colour*ei_material_diffuse.rgb*nl*attenuation*underwater;
        if(ei_surface.x>0.001) {
            vec3 half_vector=normalize(direction+VIEW);
            float roughness=clamp(ei_surface.y,0.2,1.0);
            float highlight=pow(max(dot(NORMAL,half_vector),0.0),mix(128.0,10.0,roughness*roughness))*nl;
            vec3 tint=mix(vec3(0.4),clamp(ALBEDO*1.8,vec3(0.06),vec3(0.9)),ei_surface.z);
            SPECULAR_LIGHT+=min(colour,vec3(1.5))*tint*highlight*attenuation*ei_surface.x*0.22 /*EI_FA*/;
        }
        if(ei_leaf>0.001) {
            float transmission=pow(max(dot(-NORMAL,direction),0.0),1.5);
            SPECULAR_LIGHT+=ALBEDO*colour*transmission*attenuation*ei_leaf*0.22;
        }
    } else {
"""

static func requested() -> bool:
	return GameData.option("rt_shadows")>0 or GameData.option("rt_gi")>0 or GameData.option("pt_mode")>0

static func applicable(code: String,lit: bool) -> bool:
	return lit and requested() and RenderingServer.get_current_rendering_method()=="forward_plus" \
		and preload("res://src/game/fx/water_raytrace_device.gd").supported() \
		and not code.contains("#define EI_WATER_FX") and not code.contains("#define EI_WATER_WAVES")

static func inject(code: String,clouds: bool) -> String:
	var at := code.find("\nvoid ")
	code = code.insert(at+1,COMMON)
	code = Gfx._function_tail(code,"fragment",CAPTURE)
	code = Gfx._function_tail(code,"light","\n    }\n    DIFFUSE_LIGHT=mix(DIFFUSE_LIGHT,ei_pt_previous_diffuse,ei_pt_blend);\n    SPECULAR_LIGHT=mix(SPECULAR_LIGHT,ei_pt_previous_specular,ei_pt_blend);\n    }\n")
	return code.replace("void light() {","void light() {"+LIGHT.replace("EI_RT_CLOUD","ei_cloud_sun(world)" if clouds else "1.0"))

static func globals() -> void:
	for key in [&"ei_rt_state",&"ei_rt_center"]:
		RenderingServer.global_shader_parameter_add(key,RenderingServer.GLOBAL_VAR_TYPE_VEC4,Vector4.ZERO)
	for key in [&"ei_rt_view_projection",&"ei_rt_inverse_view_projection",&"ei_rt_view"]:
		RenderingServer.global_shader_parameter_add(key,RenderingServer.GLOBAL_VAR_TYPE_MAT4,Projection())
	RenderingServer.global_shader_parameter_add(&"ei_rt_eye",RenderingServer.GLOBAL_VAR_TYPE_VEC3,Vector3.ZERO)
	RenderingServer.global_shader_parameter_add(&"ei_pt_active",RenderingServer.GLOBAL_VAR_TYPE_FLOAT,0.0)
	for key in [&"ei_rt_gi",&"ei_rt_guide",&"ei_rt_shadow0",&"ei_rt_shadow1"]:
		RenderingServer.global_shader_parameter_add(key,RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D,null)
	for i in 7:
		RenderingServer.global_shader_parameter_add(StringName("ei_rt_point%d"%i),RenderingServer.GLOBAL_VAR_TYPE_VEC4,Vector4.ZERO)
