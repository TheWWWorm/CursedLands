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
global uniform float ei_pt_rr_active;
global uniform sampler2D ei_rt_gi : filter_nearest, repeat_disable;
global uniform sampler2D ei_rt_guide : filter_nearest, repeat_disable;
global uniform sampler2D ei_rt_shadow0 : filter_nearest, repeat_disable;
global uniform sampler2D ei_rt_shadow1 : filter_nearest, repeat_disable;
global uniform sampler2D ei_pt_direct_sun : filter_nearest, repeat_disable;
global uniform sampler2D ei_pt_ground_indirect : filter_nearest, repeat_disable;
global uniform sampler2D ei_pt_ground_sun : filter_nearest, repeat_disable;
global uniform float ei_pt_ground_active;
global uniform float ei_pt_grass_shadows;
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
#ifdef EI_GRASS_LIGHT
varying vec3 ei_rt_ground;
#endif
#ifdef EI_FOLIAGE_WIND
#ifdef EI_RT_REST_CONTACT
#define ei_rt_rest ei_rt_rest_contact.xyz
#else
varying vec3 ei_rt_rest;
#endif
#endif

vec3 ei_rt_position(ivec2 p,float depth,ivec2 size,mat4 trace_projection,mat4 trace_inverse) {
    vec2 uv=(vec2(p)+0.5)/vec2(size);
    vec4 near=trace_inverse*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0);near/=near.w;
    vec3 forward=-vec3(ei_rt_view[0][2],ei_rt_view[1][2],ei_rt_view[2][2]);
    float near_depth=dot(near.xyz-ei_rt_eye,forward);
    // Perspective clip.w changes with world position; orthographic does not.
    bool orthographic=abs(trace_projection[0][3])+abs(trace_projection[1][3])+abs(trace_projection[2][3])<0.001;
    return orthographic?near.xyz+forward*(depth-near_depth):ei_rt_eye+(near.xyz-ei_rt_eye)*(depth/near_depth);
}

#ifdef EI_GRASS_LIGHT
// Procedural blades and cover are not in the RT scene. Sample their planted
// root instead of matching a raised blade/cap to the underlying terrain.
// Reject walls, foreground objects and unrelated ground planes.
vec3 ei_rt_ground_light(ivec2 p,out vec3 sun) {
    vec3 raw=texelFetch(ei_rt_gi,p,0).rgb;
    sun=ei_pt_active>.5?texelFetch(ei_pt_direct_sun,p,0).rgb:vec3(0.0);
    if(ei_pt_active>.5&&ei_pt_rr_active>.5&&ei_pt_ground_active>.5) {
        vec4 indirect=texelFetch(ei_pt_ground_indirect,p,0);
        vec4 direct=texelFetch(ei_pt_ground_sun,p,0);
        if(indirect.a>.5&&direct.a>.5) {sun=direct.rgb;return indirect.rgb+sun;}
    }
    return raw;
}
bool ei_rt_ground_sample(mat4 trace_projection,mat4 trace_inverse,out vec3 gi,out vec4 visibility0,out vec4 visibility1) {
    gi=vec3(0.0);visibility0=vec4(0.0);visibility1=vec4(0.0);
    if(ei_rt_state.x<0.5||distance(ei_rt_ground,ei_rt_center.xyz)>=ei_rt_state.w)return false;
    vec4 clip=trace_projection*vec4(ei_rt_ground,1.0);
    vec2 uv=vec2(clip.x,-clip.y)/clip.w*0.5+0.5;
    if(clip.w<=0.0||any(lessThan(uv,vec2(0.0)))||any(greaterThanEqual(uv,vec2(1.0))))return false;
    ivec2 size=textureSize(ei_rt_guide,0);
    vec2 pixel=uv*vec2(size)-0.5,blend=fract(pixel);
    ivec2 base=ivec2(floor(pixel));
    float total=0.0;
    float depth=-(ei_rt_view*vec4(ei_rt_ground,1.0)).z;
    float nearby=ei_pt_grass_shadows*(1.0-smoothstep(18.0,24.0,distance(ei_rt_ground,ei_rt_eye)));
    for(int y=0;y<2;y++)for(int x=0;x<2;x++) {
        ivec2 p=clamp(base+ivec2(x,y),ivec2(0),size-1);
        vec4 guide=texelFetch(ei_rt_guide,p,0);
        if(guide.w<=0.0||guide.y<0.35)continue;
        vec3 delta=ei_rt_position(p,guide.w,size,trace_projection,trace_inverse)-ei_rt_ground;
        if(abs(dot(delta,guide.xyz))>0.12||length(delta)>max(0.5,depth*0.006))continue;
        float w=(x==0?1.0-blend.x:blend.x)*(y==0?1.0-blend.y:blend.y);
        vec3 sun;gi+=ei_rt_ground_light(p,sun)*w;
        if(ei_pt_active<=0.5) {
            visibility0+=texelFetch(ei_rt_shadow0,p,0)*w;
            visibility1+=texelFetch(ei_rt_shadow1,p,0)*w;
        } else if(nearby>0.0) {
            visibility0.rgb+=sun*w*nearby;
        }
        total+=w;
    }
    if(total<0.01 && ei_pt_active>0.5) {
        // A thin foreground edge can cover all four root taps while the
        // raised plant remains visible. Recover compatible ground nearby,
        // so a one-pixel edge motion cannot relight the entire plant with
        // conventional lighting. Keep the same world-space rejection as
        // the fast path: this must never borrow a wall or another floor.
        ivec2 nearest=ivec2(floor(pixel+0.5));
        for(int y=-2;y<=2;y++)for(int x=-2;x<=2;x++) {
            ivec2 p=nearest+ivec2(x,y);
            if(any(lessThan(p,ivec2(0)))||any(greaterThanEqual(p,size)))continue;
            vec4 guide=texelFetch(ei_rt_guide,p,0);
            if(guide.w<=0.0||guide.y<0.35)continue;
            vec3 delta=ei_rt_position(p,guide.w,size,trace_projection,trace_inverse)-ei_rt_ground;
            if(abs(dot(delta,guide.xyz))>0.12||length(delta)>max(0.5,depth*0.006))continue;
            vec2 offset=vec2(p)-pixel;
            float w=exp(-dot(offset,offset));
            vec3 sun;gi+=ei_rt_ground_light(p,sun)*w;
            if(nearby>0.0)visibility0.rgb+=sun*w*nearby;
            total+=w;
        }
    }
    // Diagonal recovery taps can have a small Gaussian weight even though
    // their surface is valid. Normalize them before judging the lighting.
    if(total<(ei_pt_active>0.5?0.000001:0.01))return false;
    gi/=total;visibility0/=total;visibility1/=total;
    if(ei_pt_active>0.5)visibility0.rgb=clamp(visibility0.rgb,vec3(0.0),gi);
    // Grass uses the ground's diffuse illumination, never its glossy lobe.
    if(ei_pt_active<=0.5) {
        float fade=1.0-smoothstep(ei_rt_state.w-12.0,ei_rt_state.w,distance(ei_rt_ground,ei_rt_center.xyz));
        gi=mix(ei_lin(ei_ambient),gi,fade);
        visibility0=mix(vec4(1.0),visibility0,fade);visibility1=mix(vec4(1.0),visibility1,fade);
    }
    return true;
}
#endif

float ei_pt_material_weight(ivec2 p,vec2 surface) {
    if(ei_pt_active<=0.5||surface.x<0.0)return 1.0;
    uint code=uint(round(texelFetch(ei_rt_shadow1,p,0).a));
    vec2 traced=vec2(float(code&63u)/63.0,float(code>>6u)/31.0);
    vec2 difference=abs(traced-surface);
    // Geometry alone cannot separate armour from adjacent skin, or a glossy
    // inset from rough stone. Allow quantization and texture minification,
    // while rejecting incompatible material lobes before upsampling them.
    return (1.0-smoothstep(0.15,0.35,difference.x))*(1.0-smoothstep(0.10,0.25,difference.y));
}

bool ei_rt_sample_surface(vec3 world,vec3 normal,vec2 surface,mat4 trace_projection,mat4 trace_inverse,out vec3 gi,out vec4 visibility0,out vec4 visibility1) {
    gi=vec3(0.0);visibility0=vec4(1.0);visibility1=vec4(1.0);
    if(ei_rt_state.x<0.5)return false;
    vec4 clip=trace_projection*vec4(world,1.0);
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
        bool parallel=abs(trace_projection[0][3])+abs(trace_projection[1][3])+abs(trace_projection[2][3])<0.001;
        vec3 view=parallel?vec3(ei_rt_view[0][2],ei_rt_view[1][2],ei_rt_view[2][2]):normalize(ei_rt_eye-world);
        if(dot(plane,view)<0.0)plane=-plane;
#ifdef EI_TERRAIN_LIGHT
        // Match the tracer's continuous terrain hemisphere correction.
        normal=normalize(normal+plane*max(0.05-dot(normal,plane),0.0));
#else
        if(dot(normal,plane)<0.0)normal=-normal;
#endif
        normal=normalize(normal+view*max(0.05-dot(normal,view),0.0));
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
        vec3 delta=ei_rt_position(p,guide.w,size,trace_projection,trace_inverse)-world;
        if(abs(dot(delta,plane))>max(0.025,depth*0.00075)||length(delta)>max(0.1,footprint*2.5))continue;
        float w=(x==0?1.0-blend.x:blend.x)*(y==0?1.0-blend.y:blend.y)*ei_pt_material_weight(p,surface);
        gi+=texelFetch(ei_rt_gi,p,0).rgb*w;
        a+=texelFetch(ei_rt_shadow0,p,0)*w;
        if(ei_pt_active<=0.5)b+=texelFetch(ei_rt_shadow1,p,0)*w;
#ifdef EI_TERRAIN_LIGHT
        else b.rgb+=texelFetch(ei_pt_direct_sun,p,0).rgb*w;
#endif
        total+=w;
    }
    if(total<0.01 && ei_pt_active>0.5) {
        // At half resolution a thin leaf can cover all four bilinear samples.
        // Search one extra texel ring for the actual receiver before falling
        // back. Depth/plane checks keep background light off the foreground.
        ivec2 nearest=ivec2(floor(pixel+0.5));
        for(int y=-2;y<=2;y++)for(int x=-2;x<=2;x++) {
            ivec2 p=nearest+ivec2(x,y);
            if(any(lessThan(p,ivec2(0)))||any(greaterThanEqual(p,size)))continue;
            vec4 guide=texelFetch(ei_rt_guide,p,0);
            if(guide.w<=0.0||dot(normal,guide.xyz)<0.45)continue;
            vec3 delta=ei_rt_position(p,guide.w,size,trace_projection,trace_inverse)-world;
            if(abs(dot(delta,plane))>max(0.025,depth*0.00075)||length(delta)>max(0.1,footprint*3.5))continue;
            vec2 offset=vec2(p)-pixel;
            float w=exp(-dot(offset,offset))*ei_pt_material_weight(p,surface);
            gi+=texelFetch(ei_rt_gi,p,0).rgb*w;
            a+=texelFetch(ei_rt_shadow0,p,0)*w;total+=w;
#ifdef EI_TERRAIN_LIGHT
            b.rgb+=texelFetch(ei_pt_direct_sun,p,0).rgb*w;
#endif
        }
    }
    // Ring samples have Gaussian weights, unlike the bilinear fast path.
    // A valid diagonal tap can weigh exp(-8); its absolute weight must not
    // turn an otherwise compatible receiver into conventional-lighting holes.
    if(total<(ei_pt_active>0.5?0.000001:0.01))return false;
    float fade=1.0-smoothstep(ei_rt_state.w-12.0,ei_rt_state.w,distance);
    if(ei_pt_active>0.5) {
        gi/=total;visibility0=a/total;visibility1=b/total;
#ifdef EI_TERRAIN_LIGHT
        // Procedural grass is absent from the acceleration structure. Keep
        // its nearby native shadows on the ground as well as on the blades.
        float nearby=ei_pt_grass_shadows*(1.0-smoothstep(18.0,24.0,length(world-ei_rt_eye)));
        visibility1.rgb=clamp(visibility1.rgb*nearby,vec3(0.0),gi);
#endif
    } else {
        gi=mix(ei_lin(ei_ambient),gi/total,fade);
        visibility0=mix(vec4(1.0),a/total,fade);visibility1=mix(vec4(1.0),b/total,fade);
    }
    return true;
}

bool ei_rt_sample(vec3 world,vec3 normal,out vec3 gi,out vec4 visibility0,out vec4 visibility1) {
    return ei_rt_sample_surface(world,normal,vec2(-1.0),ei_rt_view_projection,ei_rt_inverse_view_projection,gi,visibility0,visibility1);
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
        vec2 surface=ei_surface.yz;
        mat4 trace_projection=ei_rt_view_projection,trace_inverse=ei_rt_inverse_view_projection;
        if(ei_pt_rr_active>0.5) {
            // API reverse depth/Y-down -> the tracer's OpenGL clip convention.
            mat4 correction=mat4(vec4(1.0,0.0,0.0,0.0),vec4(0.0,-1.0,0.0,0.0),vec4(0.0,0.0,-0.5,0.0),vec4(0.0,0.0,0.5,1.0));
            mat4 undo=mat4(vec4(1.0,0.0,0.0,0.0),vec4(0.0,-1.0,0.0,0.0),vec4(0.0,0.0,-2.0,0.0),vec4(0.0,0.0,1.0,1.0));
            trace_projection=undo*PROJECTION_MATRIX*VIEW_MATRIX;
            trace_inverse=INV_VIEW_MATRIX*INV_PROJECTION_MATRIX*correction;
        }
#ifdef EI_TERRAIN_LIGHT
        // Terrain's traced material includes biome/wetness layers that are
        // richer than the conventional shader's highlight-only profile.
        surface=vec2(-1.0);
#endif
#ifdef EI_GRASS_LIGHT
        bool matched=ei_rt_ground_sample(trace_projection,trace_inverse,indirect,a,b);
#else
#ifdef EI_FOLIAGE_WIND
        // The acceleration structure contains the undeformed tree. Follow
        // that same surface as its visible vertices sway, instead of switching
        // between unrelated background light and conventional shading.
        bool matched=ei_rt_sample_surface(ei_rt_rest,normal,surface,trace_projection,trace_inverse,indirect,a,b);
#else
        bool matched=ei_rt_sample_surface(world,normal,surface,trace_projection,trace_inverse,indirect,a,b);
#endif
#endif
        if(matched) {
            if(ei_pt_active>0.5) {
                ei_pt_blend=1.0-smoothstep(ei_rt_state.w-12.0,ei_rt_state.w,length(world-ei_rt_center.xyz));
                // Retain the terrain's authored underwater attenuation. The
                // combined PT signal has no individual light direction, so
                // use the same diffuse-depth factor as the ambient path.
#ifdef EI_GRASS_LIGHT
                // Remove the same direct signal supplied by the root sampler.
                // The native double-sided caster then attenuates it in light().
                ei_rt_visibility0=a;
                vec3 reflected=ALBEDO*ei_material_diffuse.rgb*(indirect-a.rgb)*max(1.0-ei_k,0.0);
#else
#ifdef EI_TERRAIN_LIGHT
                ei_rt_visibility0=b;
                vec3 reflected=(ALBEDO*ei_material_diffuse.rgb*(indirect-b.rgb)+a.rgb)*max(1.0-ei_k,0.0);
#else
                vec3 reflected=(ALBEDO*ei_material_diffuse.rgb*indirect+a.rgb)*max(1.0-ei_k,0.0);
#endif
#endif
                vec3 authored_emission=ei_e;
#ifdef EI_UNIT_CUTOUT
                // Selection is a presentation cue, not a luminous body.
                // Preserve traced shadows, metals and indirect light under it.
                reflected*=1.0+0.35*unit_highlight;
                authored_emission=max(unit_emission,ei_material_emissive);
#endif
                EMISSION+=(reflected+ei_lin(ei_srgb(ALBEDO)*authored_emission))*ei_pt_blend;
            } else {
                ei_rt_valid=1.0;ei_rt_visibility0=a;ei_rt_visibility1=b;
                vec3 ambient=mix(ei_lin(ei_ambient),indirect,ei_rt_state.z);
                EMISSION+=ALBEDO*ei_material_diffuse.rgb*ambient*max(1.0-ei_k,0.0)+ei_lin(ei_srgb(ALBEDO)*ei_e);
            }
        }
    }
"""

const LIGHT := """
#ifdef EI_PT_NATIVE_SUN
    if(ei_pt_blend>0.0 && LIGHT_IS_DIRECTIONAL && abs(SPECULAR_AMOUNT-0.371)<0.002) {
        DIFFUSE_LIGHT+=ei_rt_visibility0.rgb*ei_material_diffuse.rgb*ATTENUATION*ei_pt_blend*max(1.0-ei_k,0.0);
    }
#endif
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
	if code.contains("#define EI_GRASS_LIGHT") or code.contains("#define EI_TERRAIN_LIGHT"):
		code = code.replace("shader_type spatial;","shader_type spatial;\n#define EI_PT_NATIVE_SUN\n")
	if code.contains("#define EI_FOLIAGE_WIND"):
		var capture := "ei_rt_rest=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;"
		if code.contains("varying float contact_band;"):
			# Both values travel vertex -> fragment. Share a location so wind,
			# ground contact and volumetric fog fit the 32-varying RD limit.
			code=code.replace("varying float contact_band;","#define EI_RT_REST_CONTACT\nvarying vec4 ei_rt_rest_contact;\n#define contact_band ei_rt_rest_contact.w")
			capture="ei_rt_rest_contact=vec4((MODEL_MATRIX*vec4(VERTEX,1.0)).xyz,0.0);"
		code = code.replace("void vertex() {", "void vertex() {\n    "+capture+"\n")
	var at := code.find("\nvoid ")
	code = code.insert(at+1,COMMON)
	if code.contains("#define EI_GRASS_LIGHT"):
		code = Gfx._function_tail(code,"vertex","\n    ei_rt_ground=origin;\n")
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
	RenderingServer.global_shader_parameter_add(&"ei_pt_rr_active",RenderingServer.GLOBAL_VAR_TYPE_FLOAT,0.0)
	RenderingServer.global_shader_parameter_add(&"ei_pt_ground_active",RenderingServer.GLOBAL_VAR_TYPE_FLOAT,0.0)
	for key in [&"ei_rt_gi",&"ei_rt_guide",&"ei_rt_shadow0",&"ei_rt_shadow1",&"ei_pt_direct_sun",&"ei_pt_ground_indirect",&"ei_pt_ground_sun"]:
		RenderingServer.global_shader_parameter_add(key,RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D,null)
	RenderingServer.global_shader_parameter_add(&"ei_pt_grass_shadows",RenderingServer.GLOBAL_VAR_TYPE_FLOAT,
		0.0 if OS.get_cmdline_user_args().has("--ei-pt-no-grass-shadows") else 1.0)
	for i in 7:
		RenderingServer.global_shader_parameter_add(StringName("ei_rt_point%d"%i),RenderingServer.GLOBAL_VAR_TYPE_VEC4,Vector4.ZERO)
