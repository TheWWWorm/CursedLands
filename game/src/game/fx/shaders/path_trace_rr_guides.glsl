#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform readonly image2D primary_guide;
layout(rgba16f,set=0,binding=1) uniform readonly image2D primary_albedo;
layout(rg16f,set=0,binding=2) uniform readonly image2D path_distance;
layout(rgba16f,set=0,binding=3) uniform readonly image2D primary_specular;
layout(set=0,binding=4) uniform sampler2D raster_depth;
layout(set=0,binding=5) uniform sampler2D raster_normal;
layout(rgba16f,set=0,binding=6) uniform writeonly image2D diffuse_albedo;
layout(rgba16f,set=0,binding=7) uniform writeonly image2D specular_albedo;
layout(rgba16f,set=0,binding=8) uniform writeonly image2D normal_roughness;
layout(r16f,set=0,binding=9) uniform writeonly image2D specular_distance;
layout(std140,set=0,binding=10) uniform Frame {
    mat4 inv_projection;
    mat4 camera_world;
    mat4 previous_view_projection;
    mat4 previous_view;
    vec4 padding[160];
} frame;
// Streamline 2.14.16 RR integration guide / Ray Tracing Gems chapter 32.
// Spell out rows to avoid GLSL's column-major matrix-constructor ambiguity.
vec3 env_brdf(vec3 f0,float alpha,float nv) {
    vec4 X=vec4(1.0,abs(nv),nv*nv,abs(nv*nv*nv));
    vec4 Y=vec4(1.0,alpha,alpha*alpha,alpha*alpha*alpha);
    float bias=dot(vec2(dot(vec2(.99044,-1.28514),X.xy),dot(vec2(1.29678,-.755907),X.xy)),Y.xy)/
        dot(vec3(dot(vec3(1.0,2.92338,59.4188),X.xyw),dot(vec3(20.3225,-27.0302,222.592),X.xyw),dot(vec3(121.563,626.13,316.627),X.xyw)),Y.xyw);
    float scale=dot(vec2(dot(vec2(.0365463,3.32707),X.xy),dot(vec2(9.0632,-9.04756),X.xy)),Y.xy)/
        dot(vec3(dot(vec3(1.0,3.59685,-1.36772),X.xzw),dot(vec3(9.04401,-16.3174,9.22949),X.xzw),dot(vec3(5.56589,19.7886,-20.2123),X.xzw)),Y.xyw);
    bias*=clamp(f0.g*50.0,0.0,1.0);
    return clamp(f0*max(scale,0.0)+max(bias,0.0),0.0,1.0);
}
void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy),size=imageSize(diffuse_albedo);
    if(any(greaterThanEqual(p,size)))return;
    float z=texelFetch(raster_depth,p,0).r;
    vec4 guide=imageLoad(primary_guide,p),material=imageLoad(primary_albedo,p);
    vec2 uv=(vec2(p)+.5)/vec2(size);
    vec4 view=frame.inv_projection*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,1.0-2.0*z,1.0);view/=view.w;
    vec3 diffuse=vec3(0.0),specular=vec3(0.0),normal=vec3(0.0);float roughness=1.0,hit=0.0;
    if(z>0.0) {
        uint surface=uint(round(material.a));
        bool matched=guide.w>0.0 && abs(guide.w+view.z)<max(.04,-view.z*.004);
        vec3 albedo;float metal,dielectric;
        if(matched) {
            normal=normalize(guide.xyz);roughness=float(surface&63u)/63.0;
            metal=float(surface>>6u)/31.0;albedo=clamp(material.rgb,0.0,1.0);
            dielectric=.08*imageLoad(primary_specular,p).a;
            hit=max(imageLoad(path_distance,p).g,0.0);
        } else {
            // Procedural grass, wind-deformed leaves and distant raster-only
            // surfaces have no matching PT material. Use their actual raster
            // normal/roughness and a neutral diffuse guide, never foreground PT.
            vec4 raster=texelFetch(raster_normal,p,0);
            normal=normalize(mat3(frame.camera_world)*(raster.xyz*2.0-1.0));
            roughness=clamp(min(raster.a,1.0-raster.a)*(255.0/127.0),0.0,1.0);
            albedo=vec3(1.0);metal=0.0;dielectric=.04;
        }
        vec3 f0=mix(vec3(dielectric),albedo,metal);
        // Orthographic view directions are parallel; perspective uses the ray.
        bool ortho=abs(frame.inv_projection[3][3]-1.0)<1e-5;
        vec3 v=normalize(mat3(frame.camera_world)*(ortho?vec3(0.0,0.0,1.0):-view.xyz));
        specular=env_brdf(f0,roughness*roughness,dot(normal,v));
        diffuse=albedo*(1.0-metal);
    }
    imageStore(diffuse_albedo,p,vec4(diffuse,1.0));
    imageStore(specular_albedo,p,vec4(specular,1.0));
    imageStore(normal_roughness,p,vec4(normal,roughness));
    imageStore(specular_distance,p,vec4(min(hit,65504.0),0.0,0.0,0.0));
}
