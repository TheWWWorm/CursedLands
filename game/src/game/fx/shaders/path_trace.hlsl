// Bounded multi-bounce diffuse/glossy path tracing. Primary diffuse is
// demodulated so the raster receiver retains its original texture detail.
// Each stage is compiled to native DXIL and SPIR-V by build_water_rt_shaders.py.
[[vk::binding(0,0)]] RaytracingAccelerationStructure scene : register(t0);
[[vk::binding(1,0),vk::image_format("rgba16f")]] RWTexture2D<float4> indirect_image : register(u100000);
[[vk::binding(2,0)]] ByteAddressBuffer vertices : register(t200000);
[[vk::binding(3,0)]] Texture2DArray<float4> colours : register(t300000);
[[vk::binding(5,0)]] ByteAddressBuffer geometry : register(t500000);
[[vk::binding(6,0)]] SamplerState colour_sampler : register(s600000);
[[vk::binding(7,0),vk::image_format("rgba16f")]] RWTexture2D<float4> guide_image : register(u700000);
[[vk::binding(8,0),vk::image_format("rgba16f")]] RWTexture2D<float4> shadow_image0 : register(u800000);
[[vk::binding(9,0),vk::image_format("rgba16f")]] RWTexture2D<float4> shadow_image1 : register(u900000);
[[vk::binding(10,0)]] ByteAddressBuffer instance_geometry : register(t1000000);
[[vk::binding(11,0)]] ByteAddressBuffer emitters : register(t1100000);
[[vk::binding(12,0)]] ByteAddressBuffer emitter_lookup : register(t1200000);
[[vk::binding(13,0)]] ByteAddressBuffer terrain_data : register(t1300000);
[[vk::binding(14,0)]] Texture2DArray<float4> terrain_colours : register(t1400000);
// TerrainSurfaceMaps: the padded atlas layout; RG slope, B roughness, A sand.
// Without derived maps this aliases terrain_colours and is never sampled.
[[vk::binding(41,0)]] Texture2DArray<float4> terrain_surface : register(t4100000);
[[vk::binding(15,0)]] Texture2D<float4> cloud_texture : register(t1500000);
[[vk::binding(16,0)]] SamplerState cloud_sampler : register(s1600000);
// Secondary path distances for NRD. Keep primary placement identity intact.
[[vk::binding(18,0),vk::image_format("rg16f")]] RWTexture2D<float2> path_distance : register(u1800000);
[[vk::binding(19,0),vk::image_format("rgba16f")]] RWTexture2D<float4> path_direct_specular : register(u1900000);
// Direct sunlight only, before albedo. Nearby raster grass can remove the
// part its detailed blade shadows block without darkening indirect light.
[[vk::binding(20,0),vk::image_format("rgba16f")]] RWTexture2D<float4> path_direct_sun : register(u2000000);
[[vk::binding(21,0)]] ByteAddressBuffer lighting_offsets : register(t2100000);
// Shared world-vertex terrain self visibility.
[[vk::binding(42,0)]] ByteAddressBuffer terrain_sun_samples : register(t4200000);
[[vk::binding(43,0)]] ByteAddressBuffer terrain_sun_values : register(t4300000);
// First angular moments of the radiance being denoised. These are light/path
// directions, never receiver normals. XYZ is the weighted mean (not unit
// length); W is its energy. SHARC owns bindings 22 through 27.
[[vk::binding(28,0),vk::image_format("rgba16f")]] RWTexture2D<float4> path_diffuse_direction : register(u2800000);
[[vk::binding(29,0),vk::image_format("rgba16f")]] RWTexture2D<float4> path_specular_direction : register(u2900000);
#ifdef PATH_WATER_REFLECTION
[[vk::binding(30,0),vk::image_format("rgba16f")]] RWTexture2D<float4> water_emission_coverage : register(u3000000);
[[vk::binding(31,0),vk::image_format("rgba16f")]] RWTexture2D<float4> water_edge_colour : register(u3100000);
struct WaterFrame { float4 plane_fog; float4 sky; };
[[vk::binding(32,0)]] ConstantBuffer<WaterFrame> water_frame : register(b3200000);
#endif
struct Frame {
    column_major float4x4 inv_projection;
    column_major float4x4 camera_world;
    column_major float4x4 previous_view_projection;
    column_major float4x4 previous_view;
    float4 sun;              // Linear diffuse illumination, W enables RT shadows.
    float4 sun_direction;    // Direction to sun, W angular radius in radians.
    float4 sky;              // Sky radiance; W enables diffuse GI.
    float4 settings;         // Frame, GI rays, direct-shadow rays, camera near.
    float4 camera;           // Orthographic, far, valid history, secondary reach.
    float4 center_radius;
    float4 point_position[7];
    float4 point_colour[7];  // Linear illumination, W emitter radius.
    float4 path;             // Continuation bounces, history limit, stationary, directional sky.
    column_major float4x4 previous_inverse_view_projection;
    float4 sky_zenith;
    float4 sky_horizon;
    float4 sky_ground;
    float4 cloud_state;      // Threshold, strength, height, 0 off/1 sheet/2 field.
    float4 cloud_phases;
    float4 cloud_domain;     // Volume field minimum xz, span, texture size.
    float4 local_state;      // Count; W enables the extended local-light table.
    float4 local_position[64];
    float4 local_colour[64];  // Signed radius: negative disables specular.
};
[[vk::binding(4,0)]] ConstantBuffer<Frame> frame : register(b400000);
struct Vertex { float4 position_u; float4 normal_v; float4 diffuse; float4 emission_layer; };
struct Surface { float3 position; float offset; float3 normal; float hit; float3 albedo; float visible; float3 emission; float cone; float roughness; float metalness; float specular; uint instance_id; float3 geometric_normal; uint primitive_id; };
// Ordinary visibility rays skip closest-hit. Their miss flag shares the word used by
// closest-hit for leaf transmission, keeping the payload at 96 bytes.
// cone enters closest-hit as the texture footprint. After material sampling
// it stores 1 + interpolated terrain self-visibility (zero on
// other surfaces). A negative cone marks only a foreign-component query.
// It never changes the incoming material footprint.
struct Attributes { float2 bary; };
uint terrain_component(uint instance,uint primitive) {
    uint base=terrain_sun_samples.Load(32u+instance*4u);
    if(base==0xffffffffu)return 0xffffffffu;
    return terrain_sun_samples.Load(terrain_sun_samples.Load(20u)+(base/3u+primitive)*4u);
}
Vertex vertex_at(uint i) {
    Vertex v;
    v.position_u=asfloat(vertices.Load4(i*64));
    v.normal_v=asfloat(vertices.Load4(i*64+16));
    v.diffuse=asfloat(vertices.Load4(i*64+32));
    v.emission_layer=asfloat(vertices.Load4(i*64+48));
    return v;
}
float3 linear_colour(float3 c) {
    c=max(c,0.0);
    return lerp(c/12.92,pow((c+0.055)/1.055,2.4),step(0.04045,c));
}
float2 hit_uv(Vertex a,Vertex b,Vertex c,float3 weights) {
    return float2(dot(weights,float3(a.position_u.w,b.position_u.w,c.position_u.w)),
                  dot(weights,float3(a.normal_v.w,b.normal_v.w,c.normal_v.w)));
}
#if defined(PATH_RAYGEN)
#ifdef PATH_SHARC
#include "path_trace_sharc.hlsli"
SharcHitData sharc_hit(Surface s) {
    SharcHitData h;h.positionWorld=s.position;h.normalWorld=s.geometric_normal;
    h.materialDemodulation=max(s.albedo,0.05);h.emissive=0.0;return h;
}
#endif
static const float PI=3.14159265359;
// Footprint carried by visibility rays. Shadow and emitter rays from the
// visible surface test cutouts at mip zero like the raster scissor; rays
// leaving a continuation vertex use the bounce footprint, so canopies that
// only shade bounce light are tested at the averaged coverage of a coarse mip
// with resident texels instead of per-sample alias noise.
static float shadow_cone=0.0;
void add_direction(float3 radiance,float3 direction,inout float4 moment) {
    // NRD SH stores the first-order moment of YCoCg luminance. Preserve its
    // magnitude when combining samples: normalizing would turn broad or
    // opposing illumination into an artificially sharp directional lobe.
    float energy=dot(max(radiance,0.0),float3(0.25,0.5,0.25));
    moment+=float4(direction*energy,energy);
}
float4 mean_direction(float4 moment,float3 radiance) {
    // The authored ambient floor is isotropic and contributes no first moment.
    float energy=dot(max(radiance,0.0),float3(0.25,0.5,0.25));
    return float4(moment.xyz/max(max(energy,moment.w),1e-10),min(energy,60000.0));
}
float3 sky_radiance(float3 direction) {
    if(frame.path.w<0.5)return frame.sky.rgb;
    // Continuous at the horizon. The directional sun is sampled separately;
    // adding its disk here would count its energy twice.
    return direction.y>=0.0?lerp(frame.sky_horizon.rgb,frame.sky_zenith.rgb,direction.y):
        lerp(frame.sky_horizon.rgb,frame.sky_ground.rgb,saturate(-direction.y*4.0));
}
uint sample_hash(uint seed) {
    seed=seed*747796405u+2891336453u;
    uint x=((seed>>((seed>>28u)+4u))^seed)*277803737u;
    return (x>>22u)^x;
}
// Adapted from pbrt-v4's FastOwenScrambler (Apache-2.0).
// Copyright(c) 1998-2020 Matt Pharr, Wenzel Jakob, and Greg Humphreys.
// See PATH_SAMPLING_NOTICES.txt for attribution and the license.
uint scramble_owen(uint value,uint seed) {
    value=reversebits(value);
    value^=value*0x3d20adeau;value+=seed;value*=(seed>>16u)|1u;
    value^=value*0x05526c56u;value^=value*0x53a22864u;
    return reversebits(value);
}
struct PathSampler { uint index; uint pixel; uint vertex; };
PathSampler path_sampler(uint index,uint pixel) {
    PathSampler sampler;sampler.index=index;sampler.pixel=sample_hash(pixel+1u);sampler.vertex=0u;
    return sampler;
}
float2 path_random(PathSampler sampler,uint purpose) {
    // Fixed purpose slots keep a lobe/light's sequence unchanged when an
    // unrelated light is skipped or a preceding path terminates early.
    uint key=sample_hash(sampler.pixel^((sampler.vertex*16u+purpose)*0x9e3779b9u));
    // Shuffle the index as well as scrambling coordinates: independent output
    // scrambles alone leave correlations between emitter selection, its sampled
    // position and BSDF decisions. Nested index shuffling preserves dyadic nets.
    // Burley 2020: https://jcgt.org/published/0009/04/01/
    uint index=scramble_owen(sampler.index,sample_hash(key^0x967a889bu));
    // The first two Sobol generators are bit reversal and the binary Pascal
    // transform. These five XOR stages multiply the second generator without
    // a direction-number table or a 32-iteration per-sample loop.
    uint y=index;
    y^=(y>>1u)&0x55555555u;y^=(y>>2u)&0x33333333u;
    y^=(y>>4u)&0x0f0f0f0fu;y^=(y>>8u)&0x00ff00ffu;y^=y>>16u;
    uint2 value=uint2(scramble_owen(reversebits(index),key),
                     scramble_owen(reversebits(y),sample_hash(key^0x68bc21ebu)));
    // Upper 24 bits stay in [0,1), including near the frame-counter wrap.
    return float2(value>>8u)*(1.0/16777216.0);
}
void basis(float3 n,out float3 t,out float3 b) {
    t=normalize(cross(abs(n.z)<0.99?float3(0,0,1):float3(0,1,0),n)); b=cross(n,t);
}
float3 cosine_ray(float3 n,float2 u) {
    float r=sqrt(u.x),phi=2.0*PI*u.y;
    float3 t,b; basis(n,t,b);
    return normalize(t*(r*cos(phi))+b*(r*sin(phi))+n*sqrt(max(1.0-r*r,0.0)));
}
float3 area_ray(float3 direction,float angular_radius,float2 u) {
    if(angular_radius<=0.0)return direction;
    float3 t,b; basis(direction,t,b);
    float r=sqrt(u.x)*angular_radius,phi=u.y*2.0*PI;
    return normalize(direction+t*(r*cos(phi))+b*(r*sin(phi)));
}
float3 surface_origin(Surface s,float3 direction) {
    // closest-hit bounds reconstruction, intersection and instance transforms.
    // Preserve the final FMA so rounding cannot erase the small normal offset.
    precise float3 origin=mad(s.geometric_normal,dot(direction,s.geometric_normal)>=0.0?s.offset:-s.offset,s.position);
    return origin;
}
float visibility(Surface s,float3 direction,float reach,bool directional,uint mask=2u) {
    Surface result=(Surface)0;result.cone=shadow_cone;
    float3 origin=surface_origin(s,direction);
    // Reconnect to the sampled light from the displaced origin. A fixed
    // endpoint gap misses blockers near a lamp; extending it shadows objects
    // behind the lamp. Exclude only the last representable distance instead.
    RayDesc ray={origin,0.0,direction,reach};
    // Sun rays stay parallel and have no finite endpoint to reconnect to.
    if(!directional) {
        float3 delta=direction*reach+(s.position-origin);
        float distance=length(delta);
        ray.Direction=delta/distance;ray.TMax=asfloat(asuint(distance)-1u);
    }
    TraceRay(scene,RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH|RAY_FLAG_SKIP_CLOSEST_HIT_SHADER,mask,0,0,0,ray,result);
    return result.visible;
}
float terrain_sun_visibility(Surface s,float3 direction) {
    if(s.cone<=0.0)return visibility(s,direction,frame.camera.w,true);
    float self=saturate(s.cone-1.0);
    if(self<=0.0)return 0.0;
    // Every object uses the original exact ray, retaining opaque traversal.
    float objects=visibility(s,direction,frame.camera.w,true,16u);
    uint active_components=terrain_sun_samples.Load(24u);
    if(objects<=0.0 || active_components==0u)return self*objects;
    uint component=terrain_component(s.instance_id,s.primitive_id);
    if(active_components==1u && component==terrain_sun_samples.Load(28u))return self*objects;
    // The common one-component world never pays for this fallback. Multiple
    // or mixed-component placements work without a fixed mask/count limit.
    Surface result=(Surface)0;result.cone=-1.0;
    result.instance_id=component;
    RayDesc ray={surface_origin(s,direction),0.0,direction,frame.camera.w};
    TraceRay(scene,RAY_FLAG_FORCE_NON_OPAQUE|RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH|
        RAY_FLAG_SKIP_CLOSEST_HIT_SHADER,32u,0,0,0,ray,result);
    return self*objects*result.visible;
}
float3 f0(Surface s) {return lerp((0.08*s.specular).xxx,s.albedo,s.metalness);}
float ggx_d(float nh,float alpha2) {
    float d=nh*nh*(alpha2-1.0)+1.0;
    return alpha2/max(PI*d*d,1e-12);
}
float smith_g1(float nv,float alpha2) {
    return 2.0*nv/max(nv+sqrt(alpha2+(1.0-alpha2)*nv*nv),1e-6);
}
float specular_chance(Surface s,float nv) {
    // Pure metals have no diffuse lobe. For dielectrics, include the grazing
    // Fresnel increase while keeping support for both demodulated signals.
    if(s.metalness>=1.0)return 1.0;
    float3 reflectance=f0(s);
    float f=max(reflectance.x,max(reflectance.y,reflectance.z));
    return clamp(f+(1.0-f)*pow(1.0-saturate(nv),5.0),0.05,0.95);
}
// Texture footprint of a continuation ray. A diffuse lobe integrates a wide
// solid angle, so its hit samples the mip the integrator would otherwise
// average over many samples; that halves bounce texture bandwidth and the
// colour noise of indirect light. Glossy and metal lobes keep the narrow
// cone that preserves sharp reflections of texture detail.
float bounce_cone(Surface s,float3 v) {
    float narrow=max(0.002,s.roughness*0.02);
    return lerp(0.15,narrow,specular_chance(s,dot(s.normal,v)));
}
void bsdf(Surface s,float3 v,float3 l,out float3 diffuse,out float3 specular,out float pdf) {
    diffuse=0.0;specular=0.0;pdf=0.0;
    float nv=dot(s.normal,v),nl=dot(s.normal,l);
    if(nv<=0.0||abs(nl)<1e-7)return;
    float transmission=s.visible;
    if(nl<0.0) {
        if(transmission<=0.0||dot(s.geometric_normal,l)>=0.0)return;
        // Thin diffuse leaves divide their existing diffuse energy between
        // hemispheres. Trunks have a zero authored mask and remain opaque.
        float vh=saturate(dot(v,normalize(v-l)));
        float3 reflectance=f0(s),f=reflectance+(1.0-reflectance)*pow(1.0-vh,5.0);
        diffuse=(1.0-s.metalness)*(1.0-f)*transmission/PI;
        pdf=(1.0-specular_chance(s,nv))*transmission*(-nl)/PI;
        return;
    }
    if(dot(s.geometric_normal,l)<=0.0)return;
    float3 h=normalize(v+l);
    float nh=saturate(dot(s.normal,h)),vh=saturate(dot(v,h));
    float a=s.roughness*s.roughness,a2=a*a;
    float3 reflectance=f0(s),f=reflectance+(1.0-reflectance)*pow(1.0-vh,5.0);
    float d=ggx_d(nh,a2);
    diffuse=(1.0-s.metalness)*(1.0-f)*(1.0-transmission)/PI;
    specular=f*d*smith_g1(nv,a2)*smith_g1(nl,a2)/max(4.0*nv*nl,1e-6);
    float chance=specular_chance(s,nv);
    // Visible-normal GGX density, transformed from half vectors to outgoing
    // directions. This must match sample_bsdf, including its mixture weight.
    pdf=(1.0-chance)*(1.0-transmission)*nl/PI+chance*d*smith_g1(nv,a2)/max(4.0*nv,1e-6);
}
float3 sample_bsdf(Surface s,float3 v,PathSampler sampler) {
    float chance=specular_chance(s,dot(s.normal,v));
    float2 u=path_random(sampler,11u);
    float2 lobe=path_random(sampler,10u);
    if(lobe.x>=chance)return cosine_ray(lobe.y<s.visible?-s.normal:s.normal,u);
    float3 t,b;basis(s.normal,t,b);
    float a=s.roughness*s.roughness;
    // Heitz 2018, GGX visible-normal sampling: stretch the view, sample its
    // projected hemisphere, then transform the normal back to world space.
    // https://jcgt.org/published/0007/04/01/
    float3 view=normalize(float3(a*dot(v,t),a*dot(v,b),dot(v,s.normal)));
    float length2=dot(view.xy,view.xy);
    float3 tangent=length2>0.0?float3(-view.y,view.x,0)*rsqrt(length2):float3(1,0,0);
    float3 bitangent=cross(view,tangent);
    float radius=sqrt(u.x),phi=2.0*PI*u.y;
    float x=radius*cos(phi),y=radius*sin(phi),blend=0.5*(1.0+view.z);
    y=lerp(sqrt(max(0.0,1.0-x*x)),y,blend);
    float3 hemisphere=tangent*x+bitangent*y+view*sqrt(max(0.0,1.0-x*x-y*y));
    float3 local=normalize(float3(a*hemisphere.xy,max(hemisphere.z,0.0)));
    float3 h=t*local.x+b*local.y+s.normal*local.z;
    float3 reflected=reflect(-v,h);
    // A rough GGX reflection can fall below the shading hemisphere. It is
    // a rejected specular sample, never an extra diffuse-transmission sample.
    return dot(reflected,s.normal)>0.0?reflected:float3(0,0,0);
}
float cloud_visibility(float3 position) {
    if(frame.cloud_state.w<0.5||frame.cloud_state.y<=0.0||frame.sun_direction.y<0.12)return 1.0;
    if(frame.cloud_state.w>1.5) {
        if(frame.cloud_domain.w<=0.0||frame.sun_direction.y<0.18||position.y>=2200.0)return 1.0;
        float2 uv=(position.xz-position.y*frame.sun_direction.xz/frame.sun_direction.y-frame.cloud_domain.xy)/frame.cloud_domain.z;
        float margin=0.5/frame.cloud_domain.w;
        if(any(uv<margin)||any(uv>1.0-margin))return 1.0;
        return saturate(cloud_texture.SampleLevel(cloud_sampler,uv,0.0).r);
    }
    if(position.y>=frame.cloud_state.z)return 1.0;
    float2 projected=position.xz+frame.sun_direction.xz*max(frame.cloud_state.z-position.y,0.0)/max(frame.sun_direction.y,0.18);
    float coarse=cloud_texture.SampleLevel(cloud_sampler,frac(projected/384.0+frame.cloud_phases.xy),2.0).r;
    float detail=cloud_texture.SampleLevel(cloud_sampler,frac(float2(projected.y,-projected.x)/128.0+frame.cloud_phases.zw),1.0).r;
    float density=smoothstep(frame.cloud_state.x-0.14,frame.cloud_state.x+0.14,coarse*0.75+detail*0.25);
    return 1.0-density*frame.cloud_state.y;
}
// The compact seven-light table and the extended table share one accessor
// so continuation vertices can sample either with the same selection.
uint lamp_count() {return frame.local_state.w<0.5?7u:min(uint(frame.local_state.x),64u);}
float4 lamp_position(uint i) {return frame.local_state.w<0.5?frame.point_position[i]:frame.local_position[i];}
float4 lamp_colour(uint i) {return frame.local_state.w<0.5?frame.point_colour[i]:frame.local_colour[i];}
float local_weight(Surface s,uint i) {
    float4 lamp=lamp_position(i);
    float distance2=dot(lamp.xyz-s.position,lamp.xyz-s.position);
    if(lamp.w<=0.0||distance2<0.000025)return 0.0;
    return dot(lamp_colour(i).rgb,float3(0.2126,0.7152,0.0722))*max(1.0-distance2/(lamp.w*lamp.w),0.0);
}
void point_light(Surface s,float3 v,float4 lamp,float4 colour,float2 u,float weight,inout float3 diffuse,inout float3 specular,inout float4 diffuse_moment) {
    float3 delta=lamp.xyz-s.position;float distance=length(delta);
    if(lamp.w<=0.0||distance>=lamp.w||distance<0.005)return;
    float3 direction=area_ray(delta/distance,abs(colour.w)/distance,u);
    float3 d,sp;float pdf;bsdf(s,v,direction,d,sp,pdf);
    if(colour.w<0.0)sp=0.0;
    if(!any(d+sp>0.0))return;
    float3 incoming=colour.rgb*(weight*PI*abs(dot(s.normal,direction))*
        max(1.0-distance*distance/(lamp.w*lamp.w),0.0)*visibility(s,direction,distance,false));
    diffuse+=d*incoming;specular+=sp*incoming;
    add_direction(d*incoming,direction,diffuse_moment);
}
void sun_light(Surface s,float3 v,PathSampler sampler,out float3 diffuse,out float3 specular) {
    diffuse=0.0;specular=0.0;
    if(!any(frame.sun.rgb>0.0))return;
    float3 direction=area_ray(frame.sun_direction.xyz,frame.sun_direction.w,path_random(sampler,0u));
    Surface sunlight_surface=s;
    if(s.cone>0.0)sunlight_surface.geometric_normal=s.normal;
    float3 d,sp;float pdf;bsdf(sunlight_surface,v,direction,d,sp,pdf);
    if(!any(d+sp>0.0))return;
    float3 incoming=frame.sun.rgb*(PI*abs(dot(s.normal,direction))*cloud_visibility(s.position)*terrain_sun_visibility(s,direction));
    diffuse=d*incoming;specular=sp*incoming;
}
// Continuation vertices trace one local shadow ray. The light is drawn in
// proportion to its unshadowed reach at the vertex and divided by that
// probability, so every source keeps its full expected energy while a path
// no longer pays one visibility ray per in-range light at every bounce. The
// primary vertex keeps the exact sum, which the reconstruction sees directly.
void direct_light_bounce(Surface s,float3 v,PathSampler sampler,out float3 diffuse,out float3 specular) {
    sun_light(s,v,sampler,diffuse,specular);
    float4 unused_moment=0.0;
    uint count=lamp_count();
    float total=0.0;
    for(uint i=0;i<count;i++)total+=local_weight(s,i);
    if(total<=0.0)return;
    float threshold=path_random(sampler,13u).x*total;
    float cumulative=0.0;
    for(uint i=0;i<count;i++) {
        float weight=local_weight(s,i);cumulative+=weight;
        if(weight>0.0&&threshold<cumulative) {
            point_light(s,v,lamp_position(i),lamp_colour(i),path_random(sampler,1u),total/weight,diffuse,specular,unused_moment);
            return;
        }
    }
}
void direct_light(Surface s,float3 v,PathSampler sampler,out float3 diffuse,out float3 specular,out float3 sunlight,out float4 diffuse_moment,bool sample_local) {
    diffuse_moment=0.0;
    sun_light(s,v,sampler,diffuse,specular);
    sunlight=diffuse;
    if(!sample_local)return;
    if(frame.local_state.w<0.5) {
        for(uint i=0;i<7;i++)point_light(s,v,frame.point_position[i],frame.point_colour[i],path_random(sampler,i+1u),1.0,diffuse,specular,diffuse_moment);
        return;
    }
    uint count=min(uint(frame.local_state.x),64u);
    if(count<=4u) {
        for(uint i=0;i<count;i++)point_light(s,v,frame.local_position[i],frame.local_colour[i],path_random(sampler,i+1u),1.0,diffuse,specular,diffuse_moment);
        return;
    }
    // Four stratified importance samples keep lit scenes at a fixed shadow-ray
    // budget at the visible surface: five to seven sources now share the
    // estimator that crowded fire/spell scenes already used above seven.
    // Divide by the selection probability so every admitted source
    // contributes its full energy, including late spell lights.
    // https://pbr-book.org/4ed/Light_Sources/Light_Sampling
    float total=0.0;
    for(uint i=0;i<count;i++)total+=local_weight(s,i);
    if(total<=0.0)return;
    float4 jitter=float4(path_random(sampler,13u),path_random(sampler,14u));
    float4 thresholds=(float4(0,1,2,3)+jitter)*(total*0.25);
    float cumulative=0.0;uint draw=0u;
    for(uint i=0;i<count&&draw<4u;i++) {
        float weight=local_weight(s,i);cumulative+=weight;
        while(draw<4u&&thresholds[draw]<cumulative&&weight>0.0) {
            point_light(s,v,frame.local_position[i],frame.local_colour[i],path_random(sampler,draw+1u),total/(4.0*weight),diffuse,specular,diffuse_moment);
            draw++;
        }
    }
}
void direct_light(Surface s,float3 v,PathSampler sampler,out float3 diffuse,out float3 specular,out float3 sunlight,out float4 diffuse_moment) {
    direct_light(s,v,sampler,diffuse,specular,sunlight,diffuse_moment,true);
}
void direct_light(Surface s,float3 v,PathSampler sampler,out float3 diffuse,out float3 specular,out float3 sunlight) {
    float4 unused;direct_light(s,v,sampler,diffuse,specular,sunlight,unused);
}
#ifndef PATH_NO_EMITTERS
// One light sample and one BSDF sample use the power heuristic. Selection
// probability is part of the light PDF, including when the bounded proposal
// omits an emitter (zero light PDF => full weight for the BSDF hit).
// https://pbr-book.org/4ed/Light_Transport_I_Surface_Reflection/A_Better_Path_Tracer
float mis_weight(float p,float q) {
    float scale=max(max(p,q),1e-30);p/=scale;q/=scale;
    return p*p/max(p*p+q*q,1e-30);
}
float triangle_pdf(uint index,float3 origin,float3 light_position) {
    uint offset=16u+index*64u;
    float4 a=asfloat(emitters.Load4(offset)),b=asfloat(emitters.Load4(offset+16u));
    float3 c=asfloat(emitters.Load3(offset+32u));
    float3 delta=light_position-origin;float distance2=dot(delta,delta);
    float cosine=abs(dot(normalize(cross(b.xyz-a.xyz,c-a.xyz)),normalize(delta)));
    // Emission is two-sided, matching closest-hit's face-forward surfaces.
    return cosine>1e-8?b.w*distance2/(a.w*cosine):0.0;
}
float emitter_hit_pdf(Surface hit,float3 origin) {
    if(emitters.Load(0)==0u||!any(hit.emission>0.0))return 0.0;
    uint mask=emitters.Load(4),h=(hit.instance_id+1u)*0x9e3779b9u ^ hit.primitive_id*0x85ebca6bu;
    uint slot=(h^(h>>16u))&mask;
    for(uint probe=0;probe<=mask;probe++) {
        uint3 entry=emitter_lookup.Load3(slot*16u);
        if(entry.x==0u)return 0.0;
        if(entry.x==hit.instance_id+1u&&entry.y==hit.primitive_id)return triangle_pdf(entry.z,origin,hit.position);
        slot=(slot+1u)&mask;
    }
    return 0.0;
}
void emissive_light(Surface s,float3 v,PathSampler sampler,out float3 diffuse,out float3 specular,out float3 light_direction) {
    diffuse=0.0;specular=0.0;
    light_direction=0.0;
    uint count=emitters.Load(0);if(count==0u)return;
    float choice=path_random(sampler,8u).x;uint low=0u,high=count;
    while(low<high) {
        uint mid=low+(high-low)/2u;
        if(choice<asfloat(emitters.Load(16u+mid*64u+44u)))high=mid;else low=mid+1u;
    }
    uint offset=16u+min(low,count-1u)*64u;
    float3 pa=asfloat(emitters.Load3(offset)),pb=asfloat(emitters.Load3(offset+16u)),pc=asfloat(emitters.Load3(offset+32u));
    uint4 light=emitters.Load4(offset+48u);
    float2 uv_light=path_random(sampler,9u);
    float r=sqrt(uv_light.x),u=uv_light.y;float3 w=float3(1.0-r,r*(1.0-u),r*u);
    float3 light_position=pa*w.x+pb*w.y+pc*w.z;
    // Use the same offset origin as BSDF continuations for both proposals.
    float3 origin=surface_origin(s,light_position-s.position),delta=light_position-origin;
    float distance=length(delta);if(distance<=0.004||distance>frame.camera.w)return;
    float3 direction=delta/distance,d,sp;float bsdf_pdf;bsdf(s,v,direction,d,sp,bsdf_pdf);
    if(bsdf_pdf<=0.0)return;
    float pdf=triangle_pdf(min(low,count-1u),origin,light_position);if(pdf<=0.0||!isfinite(pdf))return;
    uint4 material=geometry.Load4(light.z*16u);uint i=material.x+light.y*3u;
    Vertex a=vertex_at(i),b=vertex_at(i+1),c=vertex_at(i+2);
    float3 uv=float3(hit_uv(a,b,c,w),a.emission_layer.w);
    // Alpha testing uses mip zero just like any-hit. Rejected samples remain
    // zero contributions; resampling them would bias cutout emitters brighter.
    if(light.w==0u&&colours.SampleLevel(colour_sampler,uv,0.0).a*a.diffuse.a<asfloat(material.z))return;
    float density=max(length(float2(b.position_u.w-a.position_u.w,b.normal_v.w-a.normal_v.w))/max(length(pb-pa),0.001),
                      length(float2(c.position_u.w-a.position_u.w,c.normal_v.w-a.normal_v.w))/max(length(pc-pa),0.001));
    uint width,height,layers,levels;colours.GetDimensions(0,width,height,layers,levels);
    float lod=max(log2(max(max(0.002,s.roughness*0.02)*distance*density*float(width),1.0)),0.0);
    float3 emission=(material.y&1u)!=0u?a.emission_layer.rgb:linear_colour(colours.SampleLevel(colour_sampler,uv,lod).rgb*a.emission_layer.rgb);
    if(!any(emission>0.0))return;
    Surface visible=(Surface)0;visible.cone=shadow_cone;
    // Emissive target exclusion still uses the existing endpoint margin;
    // the receiver no longer discards nearby blockers through a fixed TMin.
    RayDesc ray={origin,0.0,direction,distance-0.002};
    // Match indirect geometry visibility, including non-shadow-casting walls.
    TraceRay(scene,RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH|RAY_FLAG_SKIP_CLOSEST_HIT_SHADER,4,0,0,0,ray,visible);
    float3 incoming=emission*(abs(dot(s.normal,direction))*visible.visible*mis_weight(pdf,bsdf_pdf)/pdf);
    diffuse=d*incoming;specular=sp*incoming;
    light_direction=direction;
}
void emissive_light(Surface s,float3 v,PathSampler sampler,out float3 diffuse,out float3 specular) {
    float3 unused;emissive_light(s,v,sampler,diffuse,specular,unused);
}
#endif
#ifdef PATH_RTXDI
#include "path_trace_rtxdi.hlsli"
#endif
// A refracted camera path reaches its first opaque surface through an
// interface, like a reflected continuation does. That vertex then draws one
// local light in proportion to its reach instead of summing every source,
// matching the budget of the bounce vertices; the expected energy is the same.
#ifdef PATH_TRANSMISSION
static bool refracted_vertex=false;
#endif
void path_sample(Surface primary,float3 view,PathSampler sampler,out float3 diffuse,out float3 specular,out float2 hit_distance,out float3 direct_specular,out float3 sunlight,out float4 diffuse_moment,out float4 specular_moment) {
    shadow_cone=0.0;
#ifdef PATH_RTXDI
    direct_light(primary,view,sampler,diffuse,specular,sunlight,diffuse_moment,false);
#elif defined(PATH_TRANSMISSION)
    if(refracted_vertex){direct_light_bounce(primary,view,sampler,diffuse,specular);sunlight=0.0;diffuse_moment=0.0;}
    else direct_light(primary,view,sampler,diffuse,specular,sunlight,diffuse_moment);
#else
    direct_light(primary,view,sampler,diffuse,specular,sunlight,diffuse_moment);
#endif
    specular_moment=0.0;
    direct_specular=specular;
    hit_distance=0.0;
    Surface current=primary;
#ifdef PATH_ROULETTE
    // Smooth metals expose deep-path noise directly in reflections. Retain
    // more of their tail while allowing diffuse receivers the larger saving.
    float roulette_floor=lerp(0.25,0.75,primary.metalness*(1.0-primary.roughness));
#endif
    float3 v=view,weight_d=1.0,weight_s=1.0,first_direction=0.0;
    uint bounces=clamp(uint(frame.path.x),1u,4u);
    for(uint depth=0;depth<bounces;depth++) {
        sampler.vertex=depth;
#ifndef PATH_NO_EMITTERS
        float3 emitter_d=0.0,emitter_s=0.0,emitter_direction=0.0;
#ifdef PATH_RTXDI
        if(depth>0u)
#endif
            emissive_light(current,v,sampler,emitter_d,emitter_s,emitter_direction);
        if(depth==0) {
            diffuse+=emitter_d;specular+=emitter_s;
            add_direction(emitter_d,emitter_direction,diffuse_moment);add_direction(emitter_s,emitter_direction,specular_moment);
        }
        else {
            float3 incoming=emitter_d*current.albedo+emitter_s;
            diffuse+=weight_d*incoming;specular+=weight_s*incoming;
            add_direction(weight_d*incoming,first_direction,diffuse_moment);add_direction(weight_s*incoming,first_direction,specular_moment);
        }
#endif
        float3 direction=sample_bsdf(current,v,sampler),d,sp;float pdf;
        bsdf(current,v,direction,d,sp,pdf);
        float cosine=abs(dot(current.normal,direction));
        if(pdf<=1e-8||cosine<=0.0)break;
        if(depth==0) {
            first_direction=direction;
            weight_d=d*(cosine/pdf);weight_s=sp*(cosine/pdf);
        } else {
            float3 weight=(d*current.albedo+sp)*(cosine/pdf);
            weight_d*=weight;weight_s*=weight;
        }
        if(max(max(weight_d.r,max(weight_d.g,weight_d.b)),max(weight_s.r,max(weight_s.g,weight_s.b)))<1e-6)break;
#ifdef PATH_ROULETTE
        // Keep roulette out of the first two continuation bounces. For the
        // optional deeper tail, compensate surviving paths rather than
        // dropping dim energy. A 25% floor bounds the added sample variance;
        // both demodulated signals use the same independent purpose slot.
        if(depth>=2u) {
            float survival=clamp(max(max(weight_d.r,max(weight_d.g,weight_d.b)),
                max(weight_s.r,max(weight_s.g,weight_s.b))),roulette_floor,1.0);
            if(path_random(sampler,12u).x>=survival)break;
            weight_d/=survival;weight_s/=survival;
        }
#endif
        Surface hit=(Surface)0;hit.cone=bounce_cone(current,v);
        RayDesc ray={surface_origin(current,direction),0.0,direction,frame.camera.w};
        TraceRay(scene,RAY_FLAG_NONE,4,0,0,0,ray,hit);
        float segment=hit.hit>0.5?length(hit.position-current.position):60000.0;
        // NRD reconstructs the first secondary surface, not total path length.
        // A later sky escape must not turn a nearby diffuse hit into infinity.
        if(depth==0)hit_distance=float2(segment,segment);
        if(hit.hit<0.5) {
            float3 environment=sky_radiance(direction);
            diffuse+=weight_d*environment;specular+=weight_s*environment;
            add_direction(weight_d*environment,first_direction,diffuse_moment);add_direction(weight_s*environment,first_direction,specular_moment);break;
        }
        float emission_weight=1.0;
#ifndef PATH_NO_EMITTERS
        float emitter_pdf=emitter_hit_pdf(hit,ray.Origin);
#ifdef PATH_RTXDI
        // Partition first-bounce registered-emitter paths into ReSTIR NEE.
        // Omitted emitters retain BSDF support; later bounces keep original MIS.
        emission_weight=depth==0u?(emitter_pdf>0.0?0.0:1.0):mis_weight(pdf,emitter_pdf);
#else
        emission_weight=mis_weight(pdf,emitter_pdf);
#endif
#endif
#if defined(PATH_SHARC) && !defined(PATH_SHARC_UPDATE)
        // Keep the primary direct signal and sharp/leaf transport exact. A
        // nearby hit smaller than its cache voxel is not a safe lookup.
        if(current.roughness>=0.6 && current.metalness<0.1 && hit.roughness>=0.6
            && hit.metalness<0.1 && hit.visible==0.0) {
            SharcParameters cache=sharc_parameters();
            float voxel=HashGridGetVoxelSize(HashGridGetLevel(hit.position,cache.hashGridParameters),cache.hashGridParameters);
            if(segment>voxel) {
                sharc_count(1u);
                float3 cached;
                if(SharcGetCachedRadiance(cache,sharc_hit(hit),cached,false) && all(isfinite(cached))) {
                    sharc_count(2u);
                    float3 incoming=hit.emission*emission_weight+max(cached,0.0);
                    diffuse+=weight_d*incoming;specular+=weight_s*incoming;
                    add_direction(weight_d*incoming,first_direction,diffuse_moment);add_direction(weight_s*incoming,first_direction,specular_moment);break;
                }
            }
        }
        sharc_count(3u);
#endif
        float3 direct_d,direct_s;
        sampler.vertex=depth+1u;
        shadow_cone=0.15;
        direct_light_bounce(hit,-direction,sampler,direct_d,direct_s);
        float3 incoming=hit.emission*emission_weight+hit.albedo*direct_d+direct_s;
        diffuse+=weight_d*incoming;specular+=weight_s*incoming;
        add_direction(weight_d*incoming,first_direction,diffuse_moment);add_direction(weight_s*incoming,first_direction,specular_moment);
        current=hit;v=-direction;
    }
}
#ifdef PATH_SHARC_UPDATE
[shader("raygeneration")]
void main() {
    uint2 tile=DispatchRaysIndex().xy;
    uint jitter=sample_hash(tile.x+tile.y*DispatchRaysDimensions().x+sharc_frame.dimensions.y*0x9e3779b9u);
    uint2 pixel=tile*4u+uint2(jitter&3u,(jitter>>2u)&3u);
    uint2 size=sharc_frame.dimensions.zw;if(any(pixel>=size))return;
    float2 uv=(float2(pixel)+0.5)/float2(size);
    float4 p=mul(frame.inv_projection,float4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0));p/=p.w;
    float3 eye=mul(frame.camera_world,float4(0,0,0,1)).xyz;
    float3 forward=-mul(frame.camera_world,float4(0,0,1,0)).xyz;
    float3 origin=eye,direction=normalize(mul(frame.camera_world,float4(p.xyz,0)).xyz);
    if(frame.camera.x>0.5){origin=mul(frame.camera_world,float4(p.xyz,1)).xyz;direction=forward;}
    Surface current=(Surface)0;
    RayDesc ray={origin,frame.camera.x>0.5?0.001:frame.settings.w/max(dot(direction,forward),0.001),direction,frame.camera.y};
    TraceRay(scene,RAY_FLAG_NONE,1,0,0,0,ray,current);
    if(current.hit<0.5)return;
    current.position+=asfloat(lighting_offsets.Load3(current.instance_id*16u));
    SharcParameters cache=sharc_parameters();SharcState state;SharcInit(state);
    PathSampler sampler=path_sampler(sharc_frame.dimensions.y,pixel.x+pixel.y*size.x);
    float3 view=-direction;float emission_weight=1.0;
    sharc_count(0u);
    shadow_cone=0.0;
    for(uint depth=0;depth<8u;depth++) {
        sampler.vertex=depth;
        float3 d,sp,sunlight;
        if(depth==0u)direct_light(current,view,sampler,d,sp,sunlight);
        else {shadow_cone=0.15;direct_light_bounce(current,view,sampler,d,sp);}
#ifndef PATH_NO_EMITTERS
        float3 ed,es;emissive_light(current,view,sampler,ed,es);d+=ed;sp+=es;
#endif
        SharcHitData h=sharc_hit(current);h.emissive=current.emission*emission_weight;
        if(!SharcUpdateHit(cache,state,h,d*current.albedo+sp,path_random(sampler,15u).x))break;
        direction=sample_bsdf(current,view,sampler);float pdf;
        bsdf(current,view,direction,d,sp,pdf);
        float cosine=abs(dot(current.normal,direction));if(pdf<=1e-8||cosine<=0.0)break;
        SharcSetThroughput(state,(d*current.albedo+sp)*(cosine/pdf));
        ray.Origin=surface_origin(current,direction);ray.Direction=direction;ray.TMin=0;ray.TMax=frame.camera.w;
        Surface hit=(Surface)0;hit.cone=bounce_cone(current,view);
        TraceRay(scene,RAY_FLAG_NONE,4,0,0,0,ray,hit);
        if(hit.hit<0.5){SharcUpdateMiss(cache,state,sky_radiance(direction));break;}
        emission_weight=1.0;
#ifndef PATH_NO_EMITTERS
        emission_weight=mis_weight(pdf,emitter_hit_pdf(hit,ray.Origin));
#endif
        current=hit;view=-direction;
    }
}
#elif defined(PATH_TRANSMISSION)
#include "path_trace_transmission.hlsli"
#elif defined(PATH_WATER_REFLECTION)
[shader("raygeneration")]
void main() {
    uint2 pixel=DispatchRaysIndex().xy;float2 size=float2(DispatchRaysDimensions().xy);
    float3 eye=mul(frame.camera_world,float4(0,0,0,1)).xyz;
    float3 forward=-mul(frame.camera_world,float4(0,0,1,0)).xyz;
    Surface guide=(Surface)0;
    float3 diffuse_colour=0.0,specular=0.0,sun_colour=0.0,direct_specular=0.0;
    float3 albedo=0.0,emission=0.0,edge_colour=0.0;
    float4 diffuse_moment=0.0,specular_moment=0.0;
    float diffuse_distance=0.0,specular_distance=65504.0,coverage=0.0;
    uint hits=0u;bool mixed=false;
    uint samples=clamp(uint(frame.settings.y),1u,16u);
    // Preserve the existing four fixed spatial samples. Mixed silhouettes
    // publish their exact premultiplied average, bypassing denoiser guesses
    // across different surfaces. Interior pixels retain full PT/NRD history.
    for(uint tap=0u;tap<4u;tap++) {
        float2 uv=(float2(pixel)+(float2(tap&1u,tap>>1u)+0.5)*0.5)/size;
        float4 p=mul(frame.inv_projection,float4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0));p/=p.w;
        float3 origin=eye,direction=normalize(mul(frame.camera_world,float4(p.xyz,0)).xyz);
        if(frame.camera.x>0.5){origin=mul(frame.camera_world,float4(p.xyz,1)).xyz;direction=forward;}
        Surface primary=(Surface)0;
        if(direction.y>0.00001) {
            float entry=(water_frame.plane_fog.x-origin.y)/direction.y;
            if(entry>0.0&&entry<frame.camera.y) {
                RayDesc ray={origin+direction*(entry+0.025),0.001,direction,max(frame.camera.y-entry-0.025,0.001)};
                TraceRay(scene,RAY_FLAG_NONE,1,0,0,0,ray,primary);
            }
        }
        if(primary.hit<0.5){mixed=true;continue;}
        if(hits==0u)guide=primary;
        else if(primary.instance_id!=guide.instance_id||dot(primary.normal,guide.normal)<0.98||
                abs(primary.roughness-guide.roughness)>0.05||abs(primary.metalness-guide.metalness)>0.05)mixed=true;
        hits++;
        float3 d=0.0,s=0.0,sun=0.0,ds=0.0;
        float4 dm=0.0,sm=0.0;
        for(uint i=0u;i<samples;i++) {
            PathSampler sampler=path_sampler(uint(frame.settings.x)*samples+i,(pixel.x+pixel.y*uint(size.x))*4u+tap);
            float3 one_d,one_s,one_ds,one_sun;float2 distance;float4 one_dm,one_sm;
            path_sample(primary,-direction,sampler,one_d,one_s,distance,one_ds,one_sun,one_dm,one_sm);
            d+=one_d;s+=one_s;ds+=one_ds;sun+=one_sun;dm+=one_dm;sm+=one_sm;
            diffuse_distance+=distance.x/float(samples);
            if(distance.y>0.0)specular_distance=min(specular_distance,distance.y);
        }
        float3 ambient=float3(frame.sky_zenith.w,frame.sky_horizon.w,frame.sky_ground.w);
        d=max(d/float(samples),ambient*(1.0-primary.metalness)*(1.0-f0(primary)));
        s/=float(samples);sun/=float(samples);ds/=float(samples);
        diffuse_colour+=d*primary.albedo;specular+=s;sun_colour+=sun*primary.albedo;direct_specular+=ds;
        diffuse_moment+=dm/float(samples);specular_moment+=sm/float(samples);
        albedo+=primary.albedo;emission+=primary.emission;
        float fade=frame.center_radius.w>0.0?1.0-smoothstep(frame.center_radius.w-12.0,frame.center_radius.w,length(primary.position-frame.center_radius.xyz)):1.0;
        float fog=saturate((dot(primary.position-eye,forward)-water_frame.plane_fog.y)/max(water_frame.plane_fog.z-water_frame.plane_fog.y,0.001));
        edge_colour+=lerp(d*primary.albedo+s+primary.emission,water_frame.sky.rgb,fog)*fade*0.25;
        coverage+=fade*0.25;
    }
    guide_image[pixel]=float4(guide.normal,hits>0u?dot(guide.position-eye,forward):0.0);
    indirect_image[pixel]=0.0;shadow_image0[pixel]=0.0;shadow_image1[pixel]=0.0;
    path_distance[pixel]=0.0;path_direct_specular[pixel]=0.0;path_direct_sun[pixel]=0.0;
    path_diffuse_direction[pixel]=0.0;path_specular_direction[pixel]=0.0;
    water_emission_coverage[pixel]=0.0;water_edge_colour[pixel]=0.0;
    if(hits==0u)return;
    // Demodulate only after averaging shaded samples; composing with this
    // same average albedo preserves their colour and energy before filtering.
    float3 diffuse=diffuse_colour/max(albedo,1e-6);
    float3 sunlight=sun_colour/max(albedo,1e-6);
    specular/=float(hits);direct_specular/=float(hits);albedo/=float(hits);
    indirect_image[pixel]=float4(min(diffuse,60000.0),f16tof32(0x3c00u+guide.instance_id));
    shadow_image0[pixel]=float4(min(specular,60000.0),1.0);
    path_direct_specular[pixel]=float4(min(direct_specular,60000.0),0.0);
    path_direct_sun[pixel]=float4(min(sunlight,60000.0),0.0);
    path_diffuse_direction[pixel]=mean_direction(diffuse_moment/float(hits),max(diffuse-sunlight,0.0));
    path_specular_direction[pixel]=mean_direction(specular_moment/float(hits),max(specular-direct_specular,0.0));
    uint surface=uint(round(saturate(guide.roughness)*63.0))|(uint(round(saturate(guide.metalness)*31.0))<<6u);
    shadow_image1[pixel]=float4(albedo,float(surface));
    path_distance[pixel]=float2(diffuse_distance/float(hits),specular_distance==65504.0?0.0:specular_distance);
    water_emission_coverage[pixel]=float4(min(emission/float(hits),60000.0),coverage);
    water_edge_colour[pixel]=float4(min(edge_colour,60000.0),float(mixed));
}
#else
[shader("raygeneration")]
void main() {
    uint2 pixel=DispatchRaysIndex().xy;float2 size=float2(DispatchRaysDimensions().xy);
    float2 uv=(float2(pixel)+0.5)/size;
    float4 p=mul(frame.inv_projection,float4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0));p/=p.w;
    float3 eye=mul(frame.camera_world,float4(0,0,0,1)).xyz;
    float3 forward=-mul(frame.camera_world,float4(0,0,1,0)).xyz;
    float3 origin=eye,direction=normalize(mul(frame.camera_world,float4(p.xyz,0)).xyz);
    if(frame.camera.x>0.5){origin=mul(frame.camera_world,float4(p.xyz,1)).xyz;direction=forward;}
    Surface primary=(Surface)0;
    RayDesc ray={origin,frame.camera.x>0.5?0.001:frame.settings.w/max(dot(direction,forward),0.001),direction,frame.camera.y};
    TraceRay(scene,RAY_FLAG_NONE,1,0,0,0,ray,primary);
    guide_image[pixel]=float4(primary.normal,primary.hit>0.5?dot(primary.position-eye,forward):0.0);
    indirect_image[pixel]=0.0;shadow_image0[pixel]=0.0;shadow_image1[pixel]=0.0;path_distance[pixel]=0.0;path_direct_specular[pixel]=0.0;path_direct_sun[pixel]=0.0;
    path_diffuse_direction[pixel]=0.0;path_specular_direction[pixel]=0.0;
#ifdef PATH_RTXDI
    di_clear(pixel);
#endif
    if(primary.hit<0.5)return;
    // Camera clearance moves only the first-person presentation mesh. Trace
    // its illumination at the matching authored surface, where the complete
    // shadow/GI body lives. Otherwise that overlapping copy encloses parts of
    // the shifted receiver and blacks out its sunlight and bounce lighting.
    // Keep guide/depth and reprojection at the displayed position above.
    primary.position+=asfloat(lighting_offsets.Load3(primary.instance_id*16u));
    float3 diffuse=0.0,specular=0.0,direct_specular=0.0,sunlight=0.0;
    float4 diffuse_moment=0.0,specular_moment=0.0;
    float diffuse_distance=0.0,specular_distance=65504.0;
    uint samples=clamp(uint(frame.settings.y),1u,16u);
    for(uint i=0;i<samples;i++) {
        PathSampler sampler=path_sampler(uint(frame.settings.x)*samples+i,pixel.x+pixel.y*uint(size.x));
        float3 d,s,direct_s,direct_sun;float2 distance;float4 dm,sm;
        path_sample(primary,-direction,sampler,d,s,distance,direct_s,direct_sun,dm,sm);
        diffuse+=d;specular+=s;direct_specular+=direct_s;sunlight+=direct_sun;diffuse_moment+=dm;specular_moment+=sm;
        diffuse_distance+=distance.x;
        // NRD's specular tracking uses the minimum valid first-bounce distance
        // across samples. The primary camera hit must never enter this value.
        if(distance.y>0.0)specular_distance=min(specular_distance,distance.y);
    }
#ifdef PATH_RTXDI
    float3 di_d,di_s,di_direct;float4 di_dm,di_sm;
    di_lighting(primary,-direction,pixel,guide_image[pixel].w,di_d,di_s,di_direct,di_dm,di_sm);
    diffuse+=di_d*float(samples);specular+=di_s*float(samples);direct_specular+=di_direct*float(samples);
    diffuse_moment+=di_dm*float(samples);specular_moment+=di_sm*float(samples);
#endif
    // Raw diffuse alpha is unused by lighting. Encode the stable placement ID
    // in normal FP16 bit patterns: all 4096 instances remain exact, unlike
    // storing integers above 2048 directly. The filter carries identity onward.
    // Cave artwork relies on an authored ambient floor even in passages
    // without lamps. Preserve that diffuse minimum, rather than importing
    // outdoor sky or adding the full ambient term on top of traced light.
    // It is applied once at the receiver, never recursively at each bounce.
    float3 ambient=float3(frame.sky_zenith.w,frame.sky_horizon.w,frame.sky_ground.w);
    diffuse=max(diffuse/float(samples),ambient*(1.0-primary.metalness)*(1.0-f0(primary)));
    indirect_image[pixel]=float4(diffuse,f16tof32(0x3c00u+primary.instance_id));
    shadow_image0[pixel]=float4(specular/float(samples),1.0);
    path_direct_specular[pixel]=float4(direct_specular/float(samples),primary.specular);
    path_direct_sun[pixel]=float4(sunlight/float(samples),0.0);
    path_diffuse_direction[pixel]=mean_direction(diffuse_moment/float(samples),max(diffuse-sunlight/float(samples),0.0));
    path_specular_direction[pixel]=mean_direction(specular_moment/float(samples),max((specular-direct_specular)/float(samples),0.0));
    // Every integer up to 2047 is exact in the RGBA16F guide. Separate 6/5-bit
    // fields avoid aliases such as (roughness .2, metalness .4) and (.6, .2).
    uint surface=uint(round(saturate(primary.roughness)*63.0))|
        (uint(round(saturate(primary.metalness)*31.0))<<6u);
    shadow_image1[pixel]=float4(primary.albedo,float(surface));
    path_distance[pixel]=float2(diffuse_distance/float(samples),specular_distance==65504.0?0.0:specular_distance);
}
#endif // PATH_SHARC_UPDATE
#elif defined(PATH_MISS)
[shader("miss")]
void main(inout Surface result) {result.visible=1.0;}
#elif defined(PATH_ANY_HIT)
[shader("anyhit")]
void main(inout Surface result,Attributes attributes) {
    uint4 material=geometry.Load4(instance_geometry.Load(InstanceID()*4u)*16u); uint i=material.x+3*PrimitiveIndex();
    // Negative cone belongs only to the exact foreign-terrain shadow ray.
    // Its instance_id word carries a component key, not a camera placement.
    if(result.cone<0.0 && terrain_component(InstanceID(),PrimitiveIndex())==result.instance_id) {
        IgnoreHit();return;
    }
    Vertex a=vertex_at(i),b=vertex_at(i+1),c=vertex_at(i+2);
    float3 w=float3(1.0-attributes.bary.x-attributes.bary.y,attributes.bary);
    // Camera and shadow rays test the exact cutout at mip zero, matching the
    // raster scissor. Continuation rays carry a footprint: testing the
    // averaged coverage at that mip removes the per-sample alias noise of
    // distant leaves in bounce light and keeps their texels cache resident.
    float lod=0.0;
    if(result.cone>0.0) {
        float3x4 to_world=ObjectToWorld3x4();
        float3 edge1=mul((float3x3)to_world,b.position_u.xyz-a.position_u.xyz);
        float3 edge2=mul((float3x3)to_world,c.position_u.xyz-a.position_u.xyz);
        float density=max(length(float2(b.position_u.w-a.position_u.w,b.normal_v.w-a.normal_v.w))/max(length(edge1),0.001),
                          length(float2(c.position_u.w-a.position_u.w,c.normal_v.w-a.normal_v.w))/max(length(edge2),0.001));
        float3 facet=normalize(cross(edge1,edge2));
        float grazing=max(abs(dot(facet,WorldRayDirection())),0.1);
        uint width,height,layers,levels;colours.GetDimensions(0,width,height,layers,levels);
        lod=log2(max(result.cone*RayTCurrent()*density*float(width)/grazing,1.0));
    }
    if(colours.SampleLevel(colour_sampler,float3(hit_uv(a,b,c,w),a.emission_layer.w),lod).a*a.diffuse.a<asfloat(material.z))IgnoreHit();
}
#elif defined(PATH_CLOSEST_HIT)
// Static terrain material evaluation mirrors GroundSurfaceShader and
// TerrainCliffShader. The padded sRGB atlas is shared with raster rendering.
// Continuation hits (incoming cone above zero) keep the authored owner tile
// of each cell and skip the edge, transition, junction and cliff-neighbour
// blends that hide seams at the visible surface. Bounce lighting averages
// those seams over its cone, and each skipped blend saves two to six taps.
static bool continuation_hit=false;
uint4 land_layout() { return terrain_data.Load4(0); }
float4 land_sampling() { return asfloat(terrain_data.Load4(16)); }
uint4 land_detail() { return terrain_data.Load4(32); }
uint4 land_extra() { return terrain_data.Load4(48); }
#if defined(PATH_TERRAIN_SURFACE_MAPS)
// Derived-map strength: relief gain, ripple gain, ripple reach, roughness contrast.
float4 land_tuning() { return asfloat(terrain_data.Load4(64)); }
#endif
uint land_tile(int2 cell) {
    uint4 layout=land_layout();
    cell=clamp(cell,int2(0,0),int2(layout.xy)-1);
    return terrain_data.Load(layout.z+4u*(uint(cell.y)*layout.x+uint(cell.x)));
}
float4 tile_info(int2 cell) { uint tile=land_tile(cell);return float4(float(tile&65535u),float((tile>>16u)&255u),0,0); }
float2 tile_turn(float2 p,int rotation) {
    if(rotation==1)return float2(-p.y,p.x);
    if(rotation==2)return -p;
    if(rotation==3)return float2(p.y,-p.x);
    return p;
}
float4 tile_traits(float type) {
    int g=int(type+0.5);
    return float4(g==2||g==4||g==15,g==3||g==9||g==12,g==0||g==5||g==11,g==10);
}
// Avoid variable integer division in every atlas tap. Tile indices are in
// [0,63]. The half-integer bias keeps row
// division away from rounding boundaries for any positive integer tile count.
float2 tile_origin(uint tile,float per_row) {
    float row=floor((float(tile)+0.5)/per_row);
    return float2(float(tile)-row*per_row,per_row-1.0-row);
}
// Atlas gradients are isotropic. Quarter turns and donor mirroring cannot
// change their length, so all taps in a projection share one mip choice.
float tile_lod(float footprint) {
    float4 sampling=land_sampling();float per_row=sampling.x,padding=sampling.y;
    float border=8.0*sampling.z*per_row,scale=1.0/(per_row*(1.0+2.0*padding));
    uint width,height,layers,levels;terrain_colours.GetDimensions(0,width,height,layers,levels);
    float gutter=(padding>0.0?padding:border)*scale;
    float span=min(abs(footprint*(1.0-2.0*border)*scale),max(gutter,0.5/float(width)));
    return max(log2(max(span*float(width),1.0)),0.0);
}
#if defined(PATH_TERRAIN_SURFACE_MAPS)
// Colour and derived surface lookups share these texels and mip choices.
float4 tile_coord(float packed,float2 p,float atlas_lod) {
#else
float3 tile_sample(float packed,float2 p,float atlas_lod) {
#endif
    int code=int(packed+0.5),tile=code&63,rotation=(code>>14)&3;
    float4 sampling=land_sampling();float per_row=sampling.x;
    float border=8.0*sampling.z*per_row,interior=1.0-2.0*border,padding=sampling.y,span=1.0+2.0*padding;
    float2 local=border+(0.5+tile_turn(p-0.5,rotation))*interior;
    local=saturate(float2(local.x,1.0-local.y));
    float2 uv=(tile_origin(uint(tile),per_row)+(local+padding)/span)/per_row;
    // Real terrain uses padded tiles. Keep the edge-limited fallback for
    // unpadded atlases, where the safe mip also depends on this tap's UV.
    [branch] if(padding<=0.0) {
        uint width,height,layers,levels;terrain_colours.GetDimensions(0,width,height,layers,levels);
        float margin=min(min(local.x,1.0-local.x),min(local.y,1.0-local.y))/(per_row*span);
        atlas_lod=min(atlas_lod,max(log2(max(margin*float(width),1.0)),0.0));
    }
#if defined(PATH_TERRAIN_SURFACE_MAPS)
    return float4(uv,float((code>>6)&255),atlas_lod);
}
float3 tile_sample(float packed,float2 p,float atlas_lod) {
    float4 at=tile_coord(packed,p,atlas_lod);
    return terrain_colours.SampleLevel(colour_sampler,at.xyz,at.w).rgb;
}
// GroundSurfaceShader.SURFACE_FUNCTIONS: slope from atlas pixel axes to the
// tile's local p axes, at the colour tap's coordinates and footprint.
float4 surface_texel(float packed,float4 at) {
    float4 s=terrain_surface.SampleLevel(colour_sampler,at.xyz,at.w);
    float2 slope=(s.rg*2.0-1.0)*0.6; // TerrainSurfaceMaps.SLOPE_RANGE
    int rotation=(int(packed+0.5)>>14)&3;
    return float4(tile_turn(float2(slope.x,-slope.y),(4-rotation)%4),s.b,s.a);
}
float3 tile_texels(float packed,float2 p,float atlas_lod,bool mapped,inout float4 surface) {
    float4 at=tile_coord(packed,p,atlas_lod);
    [branch] if(mapped)surface=surface_texel(packed,at);
    return terrain_colours.SampleLevel(colour_sampler,at.xyz,at.w).rgb;
}
// The authored owner walk. With mapped, the derived map shares each owner's
// coordinates, footprint and edge weight instead of walking them again.
float3 original_walk(int2 cell,float2 p,float atlas_lod,bool mapped,out float4 traits,out float4 surface) {
    int2 shift=int2(floor(p));cell+=shift;p-=float2(shift);
    surface=float4(0,0,1,0);
    float4 info=tile_info(cell);float3 colour=tile_texels(info.r,p,atlas_lod,mapped,surface);traits=tile_traits(info.g);
#else
    return terrain_colours.SampleLevel(colour_sampler,float3(uv,float((code>>6)&255)),atlas_lod).rgb;
}
float3 transition_original_sample(int2 cell,float2 p,float atlas_lod,out float4 traits) {
    int2 shift=int2(floor(p));cell+=shift;p-=float2(shift);
    float4 info=tile_info(cell);float3 colour=tile_sample(info.r,p,atlas_lod);traits=tile_traits(info.g);
#endif
    if(land_sampling().w<0.5||continuation_hit)return colour;
    float2 weight=0.5*(1.0-smoothstep(0.0,0.12,min(p,1.0-p)));
    int2 step_cell=int2(p.x<0.5?-1:1,p.y<0.5?-1:1);
    if(weight.x>0.0) {
#if defined(PATH_TERRAIN_SURFACE_MAPS)
        info=tile_info(cell+int2(step_cell.x,0));float4 side=surface;
        colour=lerp(colour,tile_texels(info.r,p-float2(step_cell.x,0),atlas_lod,mapped,side),weight.x);
        surface=lerp(surface,side,weight.x);traits=lerp(traits,tile_traits(info.g),weight.x);
    }
    if(weight.y>0.0) {
        info=tile_info(cell+int2(0,step_cell.y));float4 other_surface=surface;
        float3 other=tile_texels(info.r,p-float2(0,step_cell.y),atlas_lod,mapped,other_surface);float4 other_traits=tile_traits(info.g);
        if(weight.x>0.0) {
            info=tile_info(cell+step_cell);float4 side=other_surface;
            other=lerp(other,tile_texels(info.r,p-float2(step_cell),atlas_lod,mapped,side),weight.x);
            other_surface=lerp(other_surface,side,weight.x);other_traits=lerp(other_traits,tile_traits(info.g),weight.x);
        }
        colour=lerp(colour,other,weight.y);surface=lerp(surface,other_surface,weight.y);traits=lerp(traits,other_traits,weight.y);
#else
        info=tile_info(cell+int2(step_cell.x,0));
        colour=lerp(colour,tile_sample(info.r,p-float2(step_cell.x,0),atlas_lod),weight.x);
        traits=lerp(traits,tile_traits(info.g),weight.x);
    }
    if(weight.y>0.0) {
        info=tile_info(cell+int2(0,step_cell.y));
        float3 other=tile_sample(info.r,p-float2(0,step_cell.y),atlas_lod);float4 other_traits=tile_traits(info.g);
        if(weight.x>0.0) {
            info=tile_info(cell+step_cell);
            other=lerp(other,tile_sample(info.r,p-float2(step_cell),atlas_lod),weight.x);
            other_traits=lerp(other_traits,tile_traits(info.g),weight.x);
        }
        colour=lerp(colour,other,weight.y);traits=lerp(traits,other_traits,weight.y);
#endif
    }
    return colour;
}
float4 transition_row(int2 cell) {
    uint4 layout=land_layout();uint offset=land_extra().z;
    if(offset==0u||any(cell<0)||any(cell>=int2(layout.xy)))return 0.0;
    return asfloat(terrain_data.Load4(offset+16u*(uint(cell.y)*layout.x+uint(cell.x))));
}
float4 transition_junction_row(int2 cell) {
    uint4 layout=land_layout();uint offset=land_extra().w;
    if(offset==0u||any(cell<0)||any(cell>=int2(layout.xy)))return 0.0;
    return asfloat(terrain_data.Load4(offset+16u*(uint(cell.y)*layout.x+uint(cell.x))));
}
#if defined(PATH_TERRAIN_SURFACE_MAPS)
float surface_owned(int2 cell) {
    float4 row=transition_row(cell);
    return (row.a<0.5||row.r==row.g)?1.0:0.0;
}
// Synthesized transition colour keeps its painted relief; fade over a tile.
float surface_coverage(int2 cell,float2 p) {
    if(land_extra().z==0u)return 1.0;
    float2 g=float2(cell)+p-0.5;int2 b=int2(floor(g));float2 f=g-float2(b);
    return lerp(lerp(surface_owned(b),surface_owned(b+int2(1,0)),f.x),
                lerp(surface_owned(b+int2(0,1)),surface_owned(b+int2(1,1)),f.x),f.y);
}
#endif
float cliff_eligible(int2 cell) {
    uint4 layout=land_layout();
    if(land_detail().z==0u||any(cell<0)||any(cell>=int2(layout.xy)))return 0.0;
    return float((land_tile(cell)>>24u)&1u);
}
float cliff_vertex(int2 p) {
    uint at=uint(p.y)*land_extra().x+uint(p.x);
    return float((terrain_data.Load(land_detail().z+(at&~3u))>>((at&3u)*8u))&255u)/255.0;
}
float cliff_guard(float2 grid) {
    int2 a=clamp(int2(floor(grid)),int2(0,0),int2(land_extra().xy)-2);float2 p=saturate(grid-float2(a));
    float ne=cliff_vertex(a+int2(1,0)),sw=cliff_vertex(a+int2(0,1));
    return p.x+p.y>1.0?ne*(1.0-p.y)+sw*(1.0-p.x)+cliff_vertex(a+int2(1,1))*(p.x+p.y-1.0):
        cliff_vertex(a)*(1.0-p.x-p.y)+ne*p.x+sw*p.y;
}
float3 cliff_weights(int2 cell,float2 p,float3 normal,float distance_to_eye) {
    if(cliff_eligible(cell)<0.5)return 0.0;
    float3 n=abs(normalize(normal));float side=(1.0-smoothstep(0.57357644,0.76604444,n.y))*(1.0-smoothstep(80.0,140.0,distance_to_eye));
    if(side<=0.0)return 0.0;
    side*=1.0-smoothstep(0.72,0.95,min(cliff_guard((float2(cell)+p)*2.0),n.y));
    float2 weight=0.5*(1.0-smoothstep(0.0,0.15,min(p,1.0-p)));
    int2 step_cell=int2(p.x<0.5?-1:1,p.y<0.5?-1:1);
    if(cliff_eligible(cell+int2(step_cell.x,0))<0.5)side*=1.0-2.0*weight.x;
    if(cliff_eligible(cell+int2(0,step_cell.y))<0.5)side*=1.0-2.0*weight.y;
    if(cliff_eligible(cell+step_cell)<0.5)side*=1.0-4.0*weight.x*weight.y;
    float2 axes=n.xz*n.xz;axes/=max(axes.x+axes.y,1e-8);axes=max(axes-0.02,0.0);axes/=max(axes.x+axes.y,1e-8);
    return float3(axes.x*side,side,axes.y*side);
}
// Keep the projection and integer hash identical to TerrainCliffShader.
float cliff_hash(int2 cell) {
    uint h=uint(cell.x)*73856093u ^ uint(cell.y)*19349663u;
    h^=h>>16u;h*=0x7feb352du;h^=h>>15u;h*=0x846ca68bu;h^=h>>16u;
    return float(h&16777215u)/16777215.0;
}
float3 cliff_noise(float2 p) {
    int2 cell=int2(floor(p));float2 f=frac(p),u=f*f*(3.0-2.0*f),d=6.0*f*(1.0-f);
    float a=cliff_hash(cell),b=cliff_hash(cell+int2(1,0)),c=cliff_hash(cell+int2(0,1)),e=cliff_hash(cell+int2(1,1));
    return float3(lerp(lerp(a,b,u.x),lerp(c,e,u.x),u.y),lerp(b-a,e-c,u.y)*d.x,lerp(c-a,e-b,u.x)*d.y);
}
// Broad rock relief is measured on the wall, not on its stretched land UVs.
// Rounded ridges avoid a hard normal discontinuity at each noise zero.
float2 cliff_rock_slope(float2 p,float footprint) {
 float3 a=cliff_noise(p*0.85+float2(3.1,-7.9));
 float3 b=cliff_noise(p*2.3+float2(-12.7,9.2));
 float ridge=(a.x-0.5)/sqrt((a.x-0.5)*(a.x-0.5)+0.02);
 return a.yz*(0.85*ridge)*(1.0-smoothstep(0.2,0.6,footprint))
      +b.yz*0.34*(1.0-smoothstep(0.06,0.2,footprint));
}
float3 cliff_relief_normal(float3 world,float3 normal,float3 geometric,float3 to_eye,float3 planes,float distance_to_eye,float footprint) {
 float fade=1.0-smoothstep(25.0,70.0,distance_to_eye);
 if (planes.y<=0.0 || fade<=0.0 || footprint>=0.6) { return normal; }
 float3 slope=0.0;
 if (planes.x>0.0) { float2 q=cliff_rock_slope(float2(-world.z,world.y),footprint); slope+=float3(0.0,q.y,-q.x)*planes.x; }
 if (planes.z>0.0) { float2 q=cliff_rock_slope(world.xy,footprint); slope+=float3(q,0.0)*planes.z; }
 float3 perturbation=-(slope-normal*dot(normal,slope))*fade;
 // Keep relief shallow and inside both the face and viewing hemispheres.
 perturbation*=min(1.0,0.6/max(length(perturbation),1e-6));
 if (dot(geometric,normal)<0.0) { geometric=-geometric; }
 float limit=1.0,a=-dot(perturbation,geometric),b=-dot(perturbation,to_eye);
 if (a>0.0) { limit=min(limit,0.8*max(dot(normal,geometric),0.0)/a); }
 if (b>0.0) { limit=min(limit,0.8*max(dot(normal,to_eye),0.0)/b); }
 float3 result=normalize(normal+perturbation*limit);
 return dot(result,geometric)>0.05 && dot(result,to_eye)>0.0 ? result : normal;
}
float2 cliff_turn(float2 p) { return float2(0.8*p.x-0.6*p.y,0.6*p.x+0.8*p.y); }
struct CliffProjection { float4 uv; float2 filter; };
CliffProjection cliff_project(float2 p,float atlas_lod) {
    float3 noise=cliff_noise(p*0.43+float2(7.1,-3.7));
    float2 warp=float2(0.55,-0.385),q=p+warp*(noise.x-0.5);
    // Ray cones have no anisotropic screen gradients. Bound the two Jacobian
    // columns, then reapply the atlas gutter cap after increasing the mip.
    float scale=max(length(float2(1,0)+warp*noise.y*0.43),length(float2(0,1)+warp*noise.z*0.43));
    CliffProjection result;
    result.filter.x=min(max(atlas_lod+log2(max(scale,1e-6)),0.0),tile_lod(1e6));
    result.filter.y=0.15+0.7*smoothstep(0.15,0.85,cliff_noise(p*0.63+float2(-11.3,4.9)).x);
    result.uv=1.0-abs(frac(float4(q,cliff_turn(q)+float2(0.37,0.83))*0.5)*2.0-1.0);
    return result;
}
float3 cliff_sample(float code,CliffProjection projection) {
    return lerp(tile_sample(code,projection.uv.xy,projection.filter.x),tile_sample(code,projection.uv.zw,projection.filter.x),projection.filter.y);
}
float3 cliff_projected_tile(float code,float3 planes,CliffProjection x,CliffProjection z) {
    float3 colour=0.0;
    [branch] if(planes.x>0.0)colour+=cliff_sample(code,x)*planes.x;
    [branch] if(planes.z>0.0)colour+=cliff_sample(code,z)*planes.z;
    return colour;
}
// One projected colour per tile code per hit. The edge blend evaluates the
// own cell and up to three neighbours with the same world projection, and
// uniform rock gives them the same code; a repeated code costs no new taps.
static float cliff_memo_code[4];
static float3 cliff_memo_colour[4];
static uint cliff_memo_used=0u;
float3 cliff_projected_tile_memo(float code,float3 planes,CliffProjection x,CliffProjection z) {
    [unroll] for(uint k=0u;k<4u;k++) {
        if(k<cliff_memo_used&&cliff_memo_code[k]==code)return cliff_memo_colour[k];
    }
    float3 colour=cliff_projected_tile(code,planes,x,z);
    if(cliff_memo_used<4u){cliff_memo_code[cliff_memo_used]=code;cliff_memo_colour[cliff_memo_used]=colour;cliff_memo_used++;}
    return colour;
}
float3 cliff_projected_surface(int2 cell,float2 p,float3 planes,CliffProjection x,CliffProjection z) {
    [branch] if((land_tile(cell)&(1u<<25u))==0u)return cliff_projected_tile_memo(tile_info(cell).r,planes,x,z);
    // Corner donor codes follow the aligned vertex guard array. Only flagged
    // tiles read this payload; plain snapshots retain their original layout.
    uint offset=land_detail().z+((land_extra().x*land_extra().y+3u)&~3u);
    float4 row=asfloat(terrain_data.Load4(offset+16u*(uint(cell.y)*land_layout().x+uint(cell.x))));
    p=smoothstep(0.2,0.8,saturate(p));
    float4 weights=float4((1.0-p.x)*(1.0-p.y),p.x*(1.0-p.y),(1.0-p.x)*p.y,p.x*p.y);
    float3 colour=0.0;
    // Fixed lanes avoid the Vulkan driver's failure on dynamic vector writes.
    if(row.x==row.y) { weights.x+=weights.y;weights.y=0.0; }
    if(row.x==row.z) { weights.x+=weights.z;weights.z=0.0; }
    if(row.x==row.w) { weights.x+=weights.w;weights.w=0.0; }
    if(row.y==row.z) { weights.y+=weights.z;weights.z=0.0; }
    if(row.y==row.w) { weights.y+=weights.w;weights.w=0.0; }
    if(row.z==row.w) { weights.z+=weights.w;weights.w=0.0; }
    [branch] if(weights.x>0.0)colour+=cliff_projected_tile_memo(row.x-1.0,planes,x,z)*weights.x;
    [branch] if(weights.y>0.0)colour+=cliff_projected_tile_memo(row.y-1.0,planes,x,z)*weights.y;
    [branch] if(weights.z>0.0)colour+=cliff_projected_tile_memo(row.z-1.0,planes,x,z)*weights.z;
    [branch] if(weights.w>0.0)colour+=cliff_projected_tile_memo(row.w-1.0,planes,x,z)*weights.w;
    return colour;
}
float3 cliff_albedo(float3 original,int2 cell,float2 p,float3 world,float3 planes,float atlas_lod) {
    if(planes.y<=0.0)return original;
    cliff_memo_used=0u;
    // Reuse the same world projection across all corner donors/neighbours.
    CliffProjection x=(CliffProjection)0,z=(CliffProjection)0;
    [branch] if(planes.x>0.0)x=cliff_project(float2(-world.z,world.y)*0.5,atlas_lod);
    [branch] if(planes.z>0.0)z=cliff_project(world.xy*0.5,atlas_lod);
    float3 own=cliff_projected_surface(cell,p,planes,x,z),colour=own;
    if(continuation_hit)return original*(1.0-planes.y)+own;
    float2 weight=0.5*(1.0-smoothstep(0.0,0.15,min(p,1.0-p)));
    int2 step_cell=int2(p.x<0.5?-1:1,p.y<0.5?-1:1);
    if(weight.x>0.0&&cliff_eligible(cell+int2(step_cell.x,0))>0.5)colour=lerp(colour,cliff_projected_surface(cell+int2(step_cell.x,0),p-float2(int2(step_cell.x,0)),planes,x,z),weight.x);
    if(weight.y>0.0) {
        float3 other=cliff_eligible(cell+int2(0,step_cell.y))>0.5?cliff_projected_surface(cell+int2(0,step_cell.y),p-float2(int2(0,step_cell.y)),planes,x,z):own;
        if(weight.x>0.0&&cliff_eligible(cell+step_cell)>0.5)other=lerp(other,cliff_projected_surface(cell+step_cell,p-float2(step_cell),planes,x,z),weight.x);
        colour=lerp(colour,other,weight.y);
    }
    return original*(1.0-planes.y)+colour;
}
// Keep a perturbed shading normal continuously inside both valid hemispheres.
float3 land_normal(float3 n,float3 perturbation,float3 geometric) {
    float limit=1.0;float projected=-dot(perturbation,geometric);
    if(projected>0.0)limit=min(limit,0.8*max(dot(n,geometric),0.0)/projected);
    projected=dot(perturbation,WorldRayDirection());
    if(projected>0.0)limit=min(limit,0.8*max(dot(n,-WorldRayDirection()),0.0)/projected);
    float3 detailed=normalize(n+perturbation*limit);
    return dot(detailed,geometric)>0.05&&dot(detailed,WorldRayDirection())<0.0?detailed:n;
}

#if defined(PATH_TERRAIN_TRANSITIONS)
// Natural-transition donor selection, guards and junction weights match
// TerrainTransitionShader.FUNCTIONS and JUNCTION_FUNCTIONS.
float transition_noise(float2 p) {
	float2 cell=floor(p); float2 f=frac(p); f=f*f*(3.0-2.0*f);
	float4 q=float4(dot(cell,float2(127.1,311.7)),dot(cell+float2(1.0,0.0),float2(127.1,311.7)),
		dot(cell+float2(0.0,1.0),float2(127.1,311.7)),dot(cell+(float2)1.0,float2(127.1,311.7)));
	float4 h=frac(sin(q)*43758.5453);
	return lerp(lerp(h.x,h.y,f.x),lerp(h.z,h.w,f.x),f.y);
}
float transition_weight(float4 row,float2 p,int family_b) {
	int pair=int(row.a+0.5); int a=pair&63; int b=pair>>6;
	if (a==b) { return b==family_b ? 1.0 : 0.0; }
	int bits=int(row.b)&15;
	float4 w=float4(float(bits&1),float((bits>>1)&1),float((bits>>2)&1),float((bits>>3)&1));
	float weight=lerp(lerp(w.x,w.y,p.x),lerp(w.z,w.w,p.x),p.y);
	return b==family_b ? weight : 1.0-weight;
}
bool transition_pair(float4 row,int pair) {
	int other=int(row.a+0.5); int family=other&63;
	return other==pair || (family>0 && family==(other>>6) && (family==(pair&63) || family==(pair>>6)));
}
float3 transition_fill(float slot,float2 grid,float atlas_lod) {
	// Mirror at each whole-tile boundary: continuous original donor texels,
	// using the shared analytic footprint so wrapping cannot change the mip.
	float2 phase=frac(grid*0.5); float2 p=1.0-abs(phase*2.0-1.0);
	return tile_sample(slot-1.0,p,atlas_lod);
}
#if defined(PATH_TERRAIN_SURFACE_MAPS)
// traits enters as the original's traits.
float3 transition_pair_from(int2 cell,float2 p,float atlas_lod,float3 original,inout float4 traits) {
#else
float3 transition_pair_sample(int2 cell,float2 p,float atlas_lod,out float4 traits) {
	float3 original=transition_original_sample(cell,p,atlas_lod,traits);
#endif
	int2 shift=int2(floor(p)); cell+=shift; p-=float2(shift);
	float4 row=transition_row(cell);
	if (row.a<0.5 || row.r==row.g) { return original; }
	int packed=int(row.b); int pair=int(row.a+0.5);
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
	float2 grid=float2(cell)+p;
	float2 q=grid+0.28*(float2(transition_noise(grid*0.72+float2(3.1,-1.7)),transition_noise(grid*0.72+float2(-9.2,7.3)))*2.0-1.0);
	float4 other=transition_row(int2(floor(q)));
	float weight=transition_weight(row,p,pair>>6);
	amount*=1.0-smoothstep(0.82,1.0,max(weight,1.0-weight));
	if (transition_pair(other,pair)) { weight=transition_weight(other,frac(q),pair>>6); }
	// Keep authored material endpoints, including tiny isolated corner paint.
	amount*=1.0-smoothstep(0.82,1.0,max(weight,1.0-weight));
	float3 a=transition_fill(row.r,grid,atlas_lod); float3 b=transition_fill(row.g,grid,atlas_lod);
	float noise=transition_noise(grid*2.6+float2(17.7,4.3))-0.5;
	float height=clamp(dot(b-a,float3(0.2126,0.7152,0.0722)),-0.25,0.25);
	int type_a=(packed>>12)&15; int type_b=(packed>>16)&15;
	bool soft=type_a==9 || type_a==12 || type_b==9 || type_b==12 || type_a==3 || type_b==3;
	float width=soft ? 0.42 : 0.28;
	float score=weight+0.16*noise+0.22*height;
	float blend=smoothstep(0.5-width,0.5+width,score);
	traits=lerp(traits,lerp(tile_traits(float(type_a)),tile_traits(float(type_b)),blend),amount);
	return lerp(original,lerp(a,b,blend),amount);
}

float transition_junction_lattice(int2 cell) {
	// Integer coordinates must give the same shared corner from either cell.
	// Floating sin/dot hashes can be reassociated differently at that boundary.
	uint h=uint(cell.x)*73856093u ^ uint(cell.y)*19349663u;
	h^=h>>16u; h*=0x7feb352du; h^=h>>15u; h*=0x846ca68bu; h^=h>>16u;
	return float(h&16777215u)/16777215.0;
}
float transition_junction_noise(float2 p) {
	int2 cell=int2(floor(p)); float2 f=frac(p); f=f*f*(3.0-2.0*f);
	return lerp(lerp(transition_junction_lattice(cell),transition_junction_lattice(cell+int2(1,0)),f.x),
		lerp(transition_junction_lattice(cell+int2(0,1)),transition_junction_lattice(cell+int2(1,1)),f.x),f.y);
}
float4 transition_junction_weights(float4 metadata,float2 p) {
	// Metadata contains exact integer-valued float32 channels. Adding 0.5
	// would corrupt odd 24-bit integers above 2^23 before conversion to int.
	uint packed=uint(metadata.g);
	uint4 corners=(packed>>uint4(0,2,4,6))&3u;
	float4 kernel=float4((1.0-p.x)*(1.0-p.y),p.x*(1.0-p.y),(1.0-p.x)*p.y,p.x*p.y);
	// Fixed component reductions avoid dynamic vector scatter in the native
	// Vulkan compiler while preserving the four authored corner weights.
	return float4(dot(kernel,float4(corners==0u)),dot(kernel,float4(corners==1u)),
	              dot(kernel,float4(corners==2u)),dot(kernel,float4(corners==3u)));
}
float transition_junction_dominance(float4 weights) {
	return 1.0-smoothstep(0.82,1.0,max(max(weights.x,weights.y),max(weights.z,weights.w)));
}
float transition_junction_guard(int packed,float2 p) {
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
float3 transition_junction_sample(int2 cell,float2 p,float atlas_lod,float4 row,float4 metadata,
		float3 original,float4 original_traits,out float4 traits) {
	traits=original_traits;
	float4 weights=transition_junction_weights(metadata,p);
	float guard=transition_junction_guard((int(metadata.g)>>8)&255,p);
	float amount=guard*transition_junction_dominance(weights);
	if (amount<=0.0) { return original; }
	float2 grid=float2(cell)+p;
	// The shared guard also damps the warp before an unsupported tile. Its
	// maximum displacement stays below the distance to that tile, avoiding
	// a discontinuous valid-field -> unwarped fallback inside the art fade.
	float2 q=grid+0.28*guard*(float2(transition_junction_noise(grid*0.72+float2(3.1,-1.7)),transition_junction_noise(grid*0.72+float2(-9.2,7.3)))*2.0-1.0);
	float4 other=transition_junction_row(int2(floor(q)));
	// Both sides of a shared edge consume the entire same warped field,
	// including its additional families. Never project it onto a local pair.
	if (other.r>0.0) {
		metadata=other; row=transition_row(int2(floor(q)));
		weights=transition_junction_weights(metadata,frac(q));
	}
	amount*=transition_junction_dominance(weights);
	if (amount<=0.0) { return original; }
	int families=int(metadata.r); int packed=int(row.b);
	int4 ids=int4(families&63,(families>>6)&63,(families>>12)&63,(families>>18)&63);
	float4 slots=float4(row.r,row.g,float(int(metadata.b)&32767),float(int(metadata.a)&32767));
	int4 types=int4((packed>>12)&15,(packed>>16)&15,(int(metadata.b)>>15)&15,(int(metadata.a)>>15)&15);
	float3 colors[4]; float4 scores=(float4)-9.0; float mean=0.0;
	float3 luma=float3(0.2126,0.7152,0.0722);
	const int material_count=4;
	[unroll] for (int i=0;i<material_count;i++) {
		colors[i]=(float3)0.0;
		if (weights[i]>0.0) {
			colors[i]=transition_fill(slots[i],grid,atlas_lod);
			mean+=weights[i]*dot(colors[i],luma);
		}
	}
	float strongest=max(max(weights.x,weights.y),max(weights.z,weights.w));
	float contested=min(3.0*(1.0-strongest),1.0);
	[unroll] for (int i=0;i<material_count;i++) {
		if (weights[i]>0.0) {
			float2 seed=float2(float(ids[i])*17.31,float(ids[i])*29.17);
			float noise=transition_junction_noise(grid*2.6+seed)-0.5;
			float height=clamp(dot(colors[i],luma)-mean,-0.25,0.25);
			scores[i]=weights[i]+contested*min(3.0*weights[i],1.0)*(0.16*noise+0.22*height);
		}
	}
	float best_score=max(max(scores.x,scores.y),max(scores.z,scores.w));
	// A hard/soft runner-up tie must not switch the width discontinuously.
	// Weight the softness field continuously; absent materials contribute zero.
	float soft=0.0;
	[unroll] for (int i=0;i<material_count;i++) {
		if (types[i]==3 || types[i]==9 || types[i]==12) { soft+=weights[i]; }
	}
	float depth=lerp(0.28,0.42,smoothstep(0.0,0.5,soft));
	// Every active material competes. No pair reduction drops a third/fourth
	// family at the centre. An absent family has score -9 and exactly no share.
	float4 shares=max(scores-(float4)(best_score-depth),(float4)0.0); shares*=shares;
	shares/=dot(shares,(float4)1.0);
	float3 color=(float3)0.0; float4 surface=(float4)0.0;
	[unroll] for (int i=0;i<material_count;i++) {
		color+=colors[i]*shares[i];
		surface+=tile_traits(float(types[i]))*shares[i];
	}
	traits=lerp(original_traits,surface,amount);
	return lerp(original,color,amount);
}
#if defined(PATH_TERRAIN_SURFACE_MAPS)
float3 ground_sample_from(int2 cell,float2 p,float atlas_lod,float3 original,float4 original_traits,out float4 traits) {
#else
float3 ground_sample(int2 cell,float2 p,float atlas_lod,out float4 traits) {
#endif
#if defined(PATH_TERRAIN_SURFACE_MAPS)
	if(continuation_hit){traits=original_traits;return original;}
#else
	if(continuation_hit)return transition_original_sample(cell,p,atlas_lod,traits);
#endif
	int2 shift=int2(floor(p)); cell+=shift; p-=float2(shift);
	float4 row=transition_row(cell);
	// All pure tiles remain authored, even inside the junction halo.
	int influence=(int(row.b)>>20)&15;
	float blend=0.0; float4 metadata=(float4)0.0;
	if (row.a!=0.0 && !(row.a>0.0 && row.r==row.g) && influence!=0) {
		float4 flags=float4(float(influence&1),float((influence>>1)&1),float((influence>>2)&1),float((influence>>3)&1));
		blend=smoothstep(0.0,1.0,lerp(lerp(flags.x,flags.y,p.x),lerp(flags.z,flags.w,p.x),p.y));
		if (blend>0.0) {
			metadata=transition_junction_row(cell);
			if (metadata.r<=0.0) { blend=0.0; }
		}
	}
	// One call site avoids expanding the entire legacy program for each
	// mutually exclusive fallback. Zero influence returns it exactly.
	float4 legacy_traits=(float4)0.0; float3 legacy=(float3)0.0;
	if (blend<1.0) {
#if defined(PATH_TERRAIN_SURFACE_MAPS)
		legacy_traits=original_traits;legacy=transition_pair_from(cell,p,atlas_lod,original,legacy_traits);
		if (blend<=0.0) { traits=legacy_traits; return legacy; }
	}
#else
		legacy=transition_pair_sample(cell,p,atlas_lod,legacy_traits);
		if (blend<=0.0) { traits=legacy_traits; return legacy; }
	}
	float4 original_traits;
	float3 original=transition_original_sample(cell,p,atlas_lod,original_traits);
#endif
	float3 junction=transition_junction_sample(cell,p,atlas_lod,row,metadata,original,original_traits,traits);
	if (blend>=1.0) { return junction; }
	traits=lerp(legacy_traits,traits,blend);
	return lerp(legacy,junction,blend);
}

#else
#if defined(PATH_TERRAIN_SURFACE_MAPS)
float3 ground_sample_from(int2 cell,float2 p,float atlas_lod,float3 original,float4 original_traits,out float4 traits) {
    traits=original_traits;return original;
#else
float3 ground_sample(int2 cell,float2 p,float atlas_lod,out float4 traits) {
    return transition_original_sample(cell,p,atlas_lod,traits);
#endif
}
#endif
#if defined(PATH_TERRAIN_SURFACE_MAPS)
// Ground colour and, when mapped, the derived map from one owner walk.
float3 ground_sample(int2 cell,float2 p,float atlas_lod,bool mapped,out float4 traits,out float4 surface) {
    float4 original_traits;float3 original=original_walk(cell,p,atlas_lod,mapped,original_traits,surface);
    return ground_sample_from(cell,p,atlas_lod,original,original_traits,traits);
}
// Returns linear albedo and evaluates the same detail normal/material fields
// for primary and secondary rays. Vertex-to-tile identity survives XY jitter.
// Sand wind ripples, as GroundSurfaceShader.SURFACE_FUNCTIONS sand_ripple.
float2 sand_ripple(float2 xz,float span) {
    float4 tuning=land_tuning();
    float fade=1.0-smoothstep(tuning.z*0.45,tuning.z,span);
    if(fade<=0.0)return 0.0;
    uint normal_layer=land_detail().x,macro_layer=land_detail().y;
    float2 warp=normal_layer>0u?colours.SampleLevel(colour_sampler,float3(xz*0.031,normal_layer-1u),0.0).rg*2.0-1.0:0.0;
    float2 dir=normalize(float2(0.8,0.6)+0.45*warp);
    float macro=macro_layer>0u?colours.SampleLevel(colour_sampler,float3(xz*0.09,macro_layer-1u),0.0).r:0.0;
    float phase=dot(xz,dir)*(6.2831853/0.42)+3.0*macro;
    float dh=cos(phase)+0.5*cos(2.0*phase);
    return -dir*dh*0.9*tuning.y*fade;
}
// surface_relief: derived slope in hit-UV axes (XY), coverage (Z), sand (W).
bool terrain_material(uint vertex,float2 uv,float uv_density,inout Surface s,float footprint,float distance,out float3 albedo,out float painted_scale,out float4 surface_relief) {
    albedo=0.0;painted_scale=1.0;surface_relief=0.0;uint4 layout=land_layout();
#else
// Returns linear albedo and evaluates the same detail normal/material fields
// for primary and secondary rays. Vertex-to-tile identity survives XY jitter.
bool terrain_material(uint vertex,float2 uv,float uv_density,inout Surface s,float footprint,float distance,out float3 albedo,out float painted_scale) {
    albedo=0.0;painted_scale=1.0;uint4 layout=land_layout();
#endif
    if(layout.x==0u)return false;
    uint id=terrain_data.Load(layout.w+(vertex/3u)*4u);
    if(id==0u||id>layout.x*layout.y)return false;
    uint tile=id-1u;
    int2 cell;
    if((layout.x&(layout.x-1u))==0u)cell=int2(tile&(layout.x-1u),tile>>firstbithigh(layout.x));
    else cell=int2(tile%layout.x,tile/layout.x);
    uint code=land_tile(cell)&65535u;float4 sampling=land_sampling();
    float per_row=sampling.x,border=8.0*sampling.z*per_row,interior=1.0-2.0*border;
    float2 origin=tile_origin(code&63u,per_row);
    float2 local=(uv*per_row-origin-border)/interior;
    int rotation=(4-int(code>>14u))%4;
    local=0.5+tile_turn(float2(local.x,1.0-local.y)-0.5,rotation);
    // Quarter turns and V inversion preserve length. Reuse the world-space
    // UV density already needed by the base material and painted relief.
    float density=uv_density*per_row/interior;
    // World-space texture derivatives depend on the intersected triangle,
    // not its bent lighting normal. Using the latter overfilters cliff
    // relief and makes detail LOD change as smooth normals approach the eye.
    float grazing=max(abs(dot(s.geometric_normal,WorldRayDirection())),0.1);
    float span=footprint*density/grazing;
    float ground_lod=tile_lod(span);
#if defined(PATH_TERRAIN_SURFACE_MAPS)
    bool mapped=(land_detail().w&2u)!=0u;float coverage=0.0;float4 surface;
    float4 traits;float3 colour=ground_sample(cell,clamp(local,0.0,0.99999),ground_lod,mapped,traits,surface);
    [branch] if(mapped)coverage=surface_coverage(cell,clamp(local,0.0,0.99999));
    float sand=surface.a*coverage;
    surface.xy*=land_tuning().x;
    // Back from local p to hit-UV axes: the tile's quarter turn, then V flip.
    float2 turned=tile_turn(surface.xy,int(code>>14u)&3);
    surface_relief=float4(turned.x,-turned.y,coverage,sand);
#else
    float4 traits;float3 colour=ground_sample(cell,clamp(local,0.0,0.99999),ground_lod,traits);
#endif
    float3 planes=cliff_weights(cell,saturate(local),s.geometric_normal,distance);
    float cliff_lod=planes.y>0.0?tile_lod(footprint/grazing*0.5):0.0;
    // Continuation hits keep the tile colour, cliff projection and material
    // response, but not the detail, painted and cliff relief normals: their
    // per-pixel footprint belongs to the visible surface, and the integrator
    // averages bounce shading over the cone anyway. Each saved normal costs
    // up to ten atlas taps per terrain hit.
    bool continuation=s.cone>0.0;
    float fade=continuation?0.0:1.0-smoothstep(25.0,70.0,distance);
    float3 n=s.normal;
    // Preserve the established bounded painted relief on ordinary terrain.
    // Its four compact atlas taps run below, once, instead of evaluating the
    // complete neighbouring transition field four additional times per hit.
#if defined(PATH_TERRAIN_SURFACE_MAPS)
    painted_scale=(1.0-planes.y)*lerp(lerp(lerp(1.0,1.15,traits.x),0.45,traits.y),1.0,sand)*(1.0-0.8*traits.w);
#else
    painted_scale=(1.0-planes.y)*lerp(lerp(1.0,1.15,traits.x),0.45,traits.y)*(1.0-0.8*traits.w);
#endif
    [branch] if(fade>0.0) {
        uint normal_layer=land_detail().x;
        [branch] if(normal_layer>0u) {
            uint width,height,layers,levels;colours.GetDimensions(0,width,height,layers,levels);
            float lod=max(log2(max(footprint*0.45*float(width)/grazing,1.0)),0.0);
            float fine_lod=max(log2(max(footprint*1.7*float(width)/grazing,1.0)),0.0);
            float3 weights=n*n;weights*=weights;
            // n^4 weights are rarely exactly zero: a 2% floor skips the two
            // near-vertical planes on ordinary ground without a visible step.
            weights=select(weights>0.02*dot(weights,float3(1,1,1)),weights,float3(0,0,0));
            weights/=max(dot(weights,float3(1,1,1)),1e-8);
            float2 x=0.0,y=0.0,z=0.0,fine=0.0;
            [branch] if(weights.x>0.0)x=colours.SampleLevel(colour_sampler,float3(s.position.zy*0.45,normal_layer-1u),lod).rg*2.0-1.0;
            [branch] if(weights.y>0.0) {
                y=colours.SampleLevel(colour_sampler,float3(s.position.xz*0.45,normal_layer-1u),lod).rg*2.0-1.0;
#if defined(PATH_TERRAIN_SURFACE_MAPS)
                fine=(colours.SampleLevel(colour_sampler,float3(s.position.xz*1.7+0.37,normal_layer-1u),fine_lod).rg*2.0-1.0)*lerp(lerp(0.25,0.85,traits.z),0.6,sand);
                if(sand>0.0)fine+=sand_ripple(s.position.xz,footprint)*sand;
#else
                fine=(colours.SampleLevel(colour_sampler,float3(s.position.xz*1.7+0.37,normal_layer-1u),fine_lod).rg*2.0-1.0)*lerp(0.25,0.85,traits.z);
#endif
            }
            [branch] if(weights.z>0.0)z=colours.SampleLevel(colour_sampler,float3(s.position.xy*0.45,normal_layer-1u),lod).rg*2.0-1.0;
            float3 perturbation=float3(0,x.y,x.x)*weights.x+float3(y.x+fine.x,0,y.y+fine.y)*weights.y+float3(z.x,z.y,0)*weights.z;
            perturbation-=n*dot(n,perturbation);
#if defined(PATH_TERRAIN_SURFACE_MAPS)
            float relief=lerp(lerp(lerp(lerp(0.13,0.10,traits.x),0.055,traits.y),0.025,traits.w),0.09,sand);
#else
            float relief=lerp(lerp(lerp(0.13,0.10,traits.x),0.055,traits.y),0.025,traits.w);
#endif
            n=land_normal(n,perturbation*relief*fade,s.geometric_normal);
        }
    }
    // Match the visible wall relief without four full donor-field samples.
    if(!continuation)n=cliff_relief_normal(s.position,n,s.geometric_normal,-WorldRayDirection(),planes,distance,footprint/grazing);
    else painted_scale=0.0;
    colour=cliff_albedo(colour,cell,saturate(local),s.position,planes,cliff_lod);
    uint macro_layer=land_detail().y;
    [branch] if(macro_layer>0u) {
        uint width,height,layers,levels;colours.GetDimensions(0,width,height,layers,levels);
        float lod=max(log2(max(footprint*0.012*float(width)/grazing,1.0)),0.0);
        float macro=colours.SampleLevel(colour_sampler,float3(s.position.xz*0.012,macro_layer-1u),lod).r;
        colour*=lerp(1.0,0.92+0.16*macro,1.0-traits.y*0.6);
    }
    s.normal=n;albedo=saturate(colour);
    // Terrain types supply a restrained dielectric response. Colour brightness
    // never classifies a surface as metal, ice or polished stone.
    if((land_detail().w&1u)!=0u) {
#if defined(PATH_TERRAIN_SURFACE_MAPS)
        float base_rough=lerp(lerp(lerp(lerp(0.94,0.84,traits.x),0.98,traits.y),0.96,traits.z),0.25,traits.w);
        float map_rough=clamp(base_rough+(surface.z-base_rough)*land_tuning().w,0.05,1.0);
        s.roughness=lerp(base_rough,map_rough,coverage*(1.0-planes.y));
#else
        s.roughness=lerp(lerp(lerp(lerp(0.94,0.84,traits.x),0.98,traits.y),0.96,traits.z),0.25,traits.w);
#endif
        s.metalness=0.0;s.specular=0.5;
    }
    return true;
}

#if defined(PATH_TERRAIN_SURFACE_MAPS)
// surface: derived terrain slope in hit-UV axes and its coverage (XY, Z).
// Full coverage needs no colour taps: the map already holds the relief.
float3 relief_normal(float3 n,float3 geometric,float3 edge1,float3 edge2,float2 uv1,float2 uv2,
                     float3 texel,float2 step_uv,float lod,float strength,bool terrain,float3 surface) {
#else
float3 relief_normal(float3 n,float3 geometric,float3 edge1,float3 edge2,float2 uv1,float2 uv2,
                     float3 texel,float2 step_uv,float lod,float strength,bool terrain) {
#endif
    float3 r1=cross(edge2,n),r2=cross(n,edge1);
    float3 u=r1*uv1.x+r2*uv2.x,v=r1*uv1.y+r2*uv2.y;
    // The oriented triangle area can reverse under mirrored placement or
    // a back-face hit. UV reflection itself must retain its handedness.
    float area=dot(cross(edge1,edge2),n);
    if(abs(area)<1e-10||abs(uv1.x*uv2.y-uv1.y*uv2.x)<1e-10)return n;
    float scale=sign(area)*rsqrt(max(max(dot(u,u),dot(v,v)),1e-12));
#if defined(PATH_TERRAIN_SURFACE_MAPS)
    float bound=terrain?0.30:0.12;
    // The map holds perceptual-brightness differences; these taps use doubled
    // linear luminance differences. 2.5 is their ratio for typical ground.
    float2 slope=clamp(surface.xy*2.5,-bound,bound);
    [branch] if(surface.z<0.999) {
        const float3 lum=float3(0.2126,0.7152,0.0722);
        float left=dot(colours.SampleLevel(colour_sampler,texel-float3(step_uv.x,0,0),lod).rgb,lum);
        float right=dot(colours.SampleLevel(colour_sampler,texel+float3(step_uv.x,0,0),lod).rgb,lum);
        float above=dot(colours.SampleLevel(colour_sampler,texel-float3(0,step_uv.y,0),lod).rgb,lum);
        float below=dot(colours.SampleLevel(colour_sampler,texel+float3(0,step_uv.y,0),lod).rgb,lum);
        slope=lerp(clamp(float2(right-left,below-above)*2.0,-bound,bound),slope,surface.z);
    }
#else
    const float3 lum=float3(0.2126,0.7152,0.0722);
    float left=dot(colours.SampleLevel(colour_sampler,texel-float3(step_uv.x,0,0),lod).rgb,lum);
    float right=dot(colours.SampleLevel(colour_sampler,texel+float3(step_uv.x,0,0),lod).rgb,lum);
    float above=dot(colours.SampleLevel(colour_sampler,texel-float3(0,step_uv.y,0),lod).rgb,lum);
    float below=dot(colours.SampleLevel(colour_sampler,texel+float3(0,step_uv.y,0),lod).rgb,lum);
    float bound=terrain?0.30:0.12;
    float2 slope=clamp(float2(right-left,below-above)*2.0,-bound,bound);
#endif
    float3 perturbation=(u*slope.x+v*slope.y)*scale*strength;
    // Limit the displacement continuously as either valid hemisphere is
    // approached. A hard return to n makes relief pop at grazing angles.
    float limit=1.0;
    float projected=dot(perturbation,geometric);
    if(projected>0.0)limit=min(limit,0.8*max(dot(n,geometric),0.0)/projected);
    projected=dot(perturbation,-WorldRayDirection());
    if(projected>0.0)limit=min(limit,0.8*max(dot(n,-WorldRayDirection()),0.0)/projected);
    float3 detailed=normalize(n-perturbation*limit);
    // Relief changes shading only; never point a ray into the actual facet.
    return dot(detailed,geometric)>0.05&&dot(detailed,WorldRayDirection())<0.0?detailed:n;
}
// Match SurfaceDetail's raster UV basis, including mirrored UVs, transformed
// geometry and back faces. Authored tangent normals never move the ray origin.
float3 surface_detail_normal(float2 encoded,float3 n,float3 geometric,float3 view,
                            float3 edge1,float3 edge2,float2 uv1,float2 uv2,float strength) {
    float det=uv1.x*uv2.y-uv1.y*uv2.x;
    if(abs(det)<1e-10)return n;
    float3 t=(edge1*uv2.y-edge2*uv1.y)/det;
    float3 b=(edge2*uv1.x-edge1*uv2.x)/det;
    t-=n*dot(n,t);
    if(dot(t,t)<1e-12)return n;
    t=normalize(t);
    b=cross(n,t)*(dot(cross(n,t),b)<0.0?-1.0:1.0);
    float2 xy=clamp(encoded*2.0-1.0,-1.0,1.0)*strength;
    float z=sqrt(max(1.0-dot(xy,xy),0.0));
    float3 delta=t*xy.x+b*xy.y+n*(z-1.0);
    float bound=1.0;
    float facing=dot(delta,geometric);
    if(facing<0.0)bound=min(bound,0.8*max(dot(n,geometric),0.0)/-facing);
    facing=dot(delta,view);
    if(facing<0.0)bound=min(bound,0.8*max(dot(n,view),0.0)/-facing);
    return normalize(n+delta*bound);
}
[shader("closesthit")]
void main(inout Surface result,Attributes attributes) {
    uint4 material=geometry.Load4(instance_geometry.Load(InstanceID()*4u)*16u); uint i=material.x+3*PrimitiveIndex();
    Vertex a=vertex_at(i),b=vertex_at(i+1),c=vertex_at(i+2);
    float3 w=float3(1.0-attributes.bary.x-attributes.bary.y,attributes.bary);
    float3 n=a.normal_v.xyz*w.x+b.normal_v.xyz*w.y+c.normal_v.xyz*w.z;
    result.normal=normalize(mul(n,(float3x3)WorldToObject3x4()));
    // Reconstruct on the triangle, not along the incoming ray. Base vertex
    // and instance translation are added last, limiting cancellation error.
    precise float3 edge1=b.position_u.xyz-a.position_u.xyz;
    precise float3 edge2=c.position_u.xyz-a.position_u.xyz;
    precise float3 object_position=a.position_u.xyz+mad(attributes.bary.x,edge1,attributes.bary.y*edge2);
    float3x4 to_world=ObjectToWorld3x4(),to_object=WorldToObject3x4();
    precise float3 position;
    position.x=to_world._m03+mad(to_world._m00,object_position.x,mad(to_world._m01,object_position.y,to_world._m02*object_position.z));
    position.y=to_world._m13+mad(to_world._m10,object_position.x,mad(to_world._m11,object_position.y,to_world._m12*object_position.z));
    position.z=to_world._m23+mad(to_world._m20,object_position.x,mad(to_world._m21,object_position.y,to_world._m22*object_position.z));
    result.position=position;result.hit=1.0;
#ifdef PATH_TRANSMISSION_HIT
    result.hit=dot(result.normal,WorldRayDirection())<0.0?1.0:2.0;
#endif
    result.instance_id=InstanceID();result.primitive_id=PrimitiveIndex();
    // Transform the object-space triangle normal with the inverse transpose.
    // Subtracting translated world vertices loses small facets far from zero.
    float3 object_normal=cross(edge1,edge2);
    float3 world_normal=mul(object_normal,(float3x3)to_object);
    float normal_scale=rsqrt(dot(world_normal,world_normal));
    result.geometric_normal=world_normal*normal_scale;
    if(dot(result.geometric_normal,WorldRayDirection())>0.0)result.geometric_normal=-result.geometric_normal;
    // Floating-point error bounds following NVIDIA's DXR analysis:
    // https://developer.nvidia.com/blog/solving-self-intersection-artifacts-in-directx-raytracing/
    // Constants cover float reconstruction/intersection and both transforms.
    // Project the uncertainty onto the actual face normal, including scale
    // and shear. Keep the payload at 96 bytes by replacing its unused distance.
    const float roundoff=5.9604644775390625e-8;
    const float intersection_error=1.7881398e-7,transform_error=1.1920932e-7;
    float3 extent=max(abs(edge1),abs(edge2))*2.0;
    float3 object_error=roundoff*abs(a.position_u.xyz)+intersection_error*max(extent.x,max(extent.y,extent.z));
    object_error+=transform_error*mul(abs(to_object),float4(abs(position),1.0));
    float3 world_error=intersection_error*mul(abs((float3x3)to_world),abs(object_position))+
        transform_error*abs(float3(to_world._m03,to_world._m13,to_world._m23));
    result.offset=dot(object_error,abs(object_normal))*normal_scale+dot(world_error,abs(result.geometric_normal));
    // Interpolated normals can point through a steep terrain facet. Offset
    // rays along the actual triangle and keep the shading hemisphere outside
    // it, rather than flipping the smooth normal beneath the triangle.
    if((material.y&2u)!=0u) {
        // MPR lighting normals can straddle a steep facet's tangent plane.
        // Negating one turns the entire upward lighting field downward and
        // creates black triangular wedges. Project terrain continuously into
        // the face hemisphere; two-sided objects retain their facing rule.
        result.normal=normalize(result.normal+result.geometric_normal*
            max(0.05-dot(result.normal,result.geometric_normal),0.0));
    } else if(dot(result.normal,result.geometric_normal)<0.0)result.normal=-result.normal;
    // Smooth hill/branch normals can cross the view horizon while the actual
    // facet stays visible. Replacing them with the face normal at zero causes
    // a large lighting jump during a tiny camera turn. Project continuously
    // into the visible hemisphere; the geometric hemisphere stays positive.
    float3 view=-WorldRayDirection();
    result.normal=normalize(result.normal+view*max(0.05-dot(result.normal,view),0.0));
    float density=max(length(float2(b.position_u.w-a.position_u.w,b.normal_v.w-a.normal_v.w))/max(length(mul((float3x3)to_world,edge1)),0.001),
                      length(float2(c.position_u.w-a.position_u.w,c.normal_v.w-a.normal_v.w))/max(length(mul((float3x3)to_world,edge2)),0.001));
    uint width,height,layers,levels; colours.GetDimensions(0,width,height,layers,levels);
    float footprint=result.cone*RayTCurrent();
    if(result.cone==0.0) {
        // Primary rays have no continuation cone. Their material footprint
        // comes from the actual trace grid, including reduced-resolution PT
        // under temporal upscaling. LOD 0 here made fine equipment masks and
        // reflected texture colour alternate as the camera/actor moved.
        footprint=2.0*abs(frame.inv_projection[0][0])/float(DispatchRaysDimensions().x);
        if(frame.camera.x<0.5) {
            float3 eye=mul(frame.camera_world,float4(0,0,0,1)).xyz;
            float3 forward=-mul(frame.camera_world,float4(0,0,1,0)).xyz;
            footprint*=max(dot(position-eye,forward),0.0);
        }
    }
    footprint/=max(abs(dot(result.geometric_normal,WorldRayDirection())),0.1);
    float base_texels=max(footprint*density*float(width),1.0);
    float lod=log2(base_texels);
    float3 texel=float3(hit_uv(a,b,c,w),a.emission_layer.w);
    float3 colour=0.0;
    bool terrain=(material.y&2u)!=0u;
    float strength=float((material.w>>24u)&127u)/127.0;
    uint plant_layer=(material.y>>8u)&255u;
    result.visible=0.0;
    if(plant_layer>0u) {
        float2 plant=colours.SampleLevel(colour_sampler,float3(texel.xy,float(plant_layer-1u)),lod).rg;
        if((material.y&4u)!=0u)result.visible=saturate(plant.r)*0.40;
        if((material.y&8u)!=0u)strength=max(strength,saturate(plant.g)*0.45);
    }
    result.roughness=max(float(material.w&255u)/255.0,0.08);
    result.metalness=float((material.w>>8u)&255u)/255.0;
    result.specular=float((material.w>>16u)&255u)/255.0;
    uint surface_layer=(material.y>>16u)&255u;
    [branch] if(surface_layer>0u) {
        // Legacy redress map: R highlight, G perceptual roughness, B metalness.
        // It is linear data, not albedo or ORM. Keep the calibrated dielectric
        // F0; legacy highlight gain is not a physical specular parameter.
        float2 surface=colours.SampleLevel(colour_sampler,float3(texel.xy,float(surface_layer-1u)),lod).gb;
        result.roughness=clamp(surface.x,0.08,1.0);
        result.metalness=saturate(surface.y);
    }
    uint detail_layer=(material.y>>24u)&255u;
    [branch] if(detail_layer>0u) {
        float3 eye=mul(frame.camera_world,float4(0,0,0,1)).xyz;
        float distance=length(position-eye);
        float footprint=2.0*abs(frame.inv_projection[0][0])/float(DispatchRaysDimensions().x);
        if(frame.camera.x<0.5)footprint*=distance;
        footprint=max(footprint,result.cone*RayTCurrent());
        float texels=footprint*density*float(width)/max(abs(dot(result.normal,WorldRayDirection())),0.1);
        float detail_lod=log2(max(max(base_texels,texels),1.0));
        float4 detail=colours.SampleLevel(colour_sampler,float3(texel.xy,float(detail_layer-1u)),detail_lod);
        float visible_detail=(1.0-smoothstep(2.0,8.0,texels))*(1.0-smoothstep(24.0,60.0,distance));
        result.roughness=clamp(lerp(max(detail.b,0.65),detail.b,visible_detail),0.08,1.0);
        result.metalness=saturate(detail.a);
        if(result.cone<=0.0)result.normal=surface_detail_normal(detail.rg,result.normal,result.geometric_normal,-WorldRayDirection(),
            mul((float3x3)to_world,edge1),mul((float3x3)to_world,edge2),
            float2(b.position_u.w-a.position_u.w,b.normal_v.w-a.normal_v.w),
            float2(c.position_u.w-a.position_u.w,c.normal_v.w-a.normal_v.w),visible_detail);
        // This authored map replaces brightness-derived relief, avoiding
        // double normals and four extra colour fetches on mapped props.
        strength=0.0;
    }
#if defined(PATH_TERRAIN_SURFACE_MAPS)
    float3 terrain_albedo=0.0;float painted_scale=1.0;bool detailed_terrain=false;float4 surface_relief=0.0;
#else
    float3 terrain_albedo=0.0;float painted_scale=1.0;bool detailed_terrain=false;
#endif
    continuation_hit=result.cone>0.0;
    #if defined(PATH_TERRAIN_MATERIALS)
    [branch] if(terrain&&land_layout().x>0u) {
        float3 eye=mul(frame.camera_world,float4(0,0,0,1)).xyz;
        float distance=length(position-eye);
        float footprint=2.0*abs(frame.inv_projection[0][0])/float(DispatchRaysDimensions().x);
        if(frame.camera.x<0.5)footprint*=distance;
        footprint=max(footprint,result.cone*RayTCurrent());
#if defined(PATH_TERRAIN_SURFACE_MAPS)
        detailed_terrain=terrain_material(i,texel.xy,density,result,footprint,distance,terrain_albedo,painted_scale,surface_relief);
#else
        detailed_terrain=terrain_material(i,texel.xy,density,result,footprint,distance,terrain_albedo,painted_scale);
#endif
        strength*=painted_scale;
    }
    #endif
    // Painted relief is a visible-surface detail; see terrain_material.
    if(result.cone>0.0)strength=0.0;
    [branch] if(strength>0.0) {
        float3 eye=mul(frame.camera_world,float4(0,0,0,1)).xyz;
        float distance=length(position-eye);
        float footprint=2.0*abs(frame.inv_projection[0][0])/float(DispatchRaysDimensions().x);
        if(frame.camera.x<0.5)footprint*=distance;
        footprint=max(footprint,result.cone*RayTCurrent());
        float texels=footprint*density*float(width)/max(abs(dot(result.normal,WorldRayDirection())),0.1);
        float relief_texels=max(base_texels,texels);
        float relief_lod=log2(relief_texels);
        // Land has broad painted ridges as well as texel detail. Widen the
        // finite difference with the mip footprint, then fade it before the
        // receiver range ends. Object relief keeps its tighter bounds.
        float step_scale=terrain?1.5*relief_texels:1.0;
        strength*=terrain?1.5*(1.0-smoothstep(25.0,65.0,distance))*(1.0-smoothstep(2.0,8.0,texels)):
            (1.0-smoothstep(14.0,40.0,distance))*(1.0-smoothstep(1.2,4.0,texels));
        [branch] if(strength>0.0)result.normal=relief_normal(result.normal,result.geometric_normal,
            mul((float3x3)to_world,edge1),mul((float3x3)to_world,edge2),
            float2(b.position_u.w-a.position_u.w,b.normal_v.w-a.normal_v.w),
            float2(c.position_u.w-a.position_u.w,c.normal_v.w-a.normal_v.w),
#if defined(PATH_TERRAIN_SURFACE_MAPS)
            texel,step_scale/float2(width,height),relief_lod,strength,terrain,surface_relief.xyz);
#else
            texel,step_scale/float2(width,height),relief_lod,strength,terrain);
#endif
    }
    // Detailed terrain already sampled its colour from the shared raster atlas.
    [branch] if(!detailed_terrain||any(a.emission_layer.rgb>0.0))colour=colours.SampleLevel(colour_sampler,texel,lod).rgb;
    result.albedo=saturate((detailed_terrain?terrain_albedo:linear_colour(colour))*saturate(a.diffuse.rgb));
    result.emission=0.0;
    [branch] if(any(a.emission_layer.rgb!=0.0))
        result.emission=(material.y&1u)!=0u?a.emission_layer.rgb:linear_colour(colour*a.emission_layer.rgb);
    result.cone=0.0;
    if(terrain) {
        uint4 layout=terrain_sun_samples.Load4(0);
        uint base=terrain_sun_samples.Load(32u+InstanceID()*4u);
        if(base!=0xffffffffu) {
            uint corner=layout.y+(base+PrimitiveIndex()*3u)*4u;
            uint3 indices=terrain_sun_samples.Load3(corner);
            float3 sun=float3(asfloat(terrain_sun_values.Load(indices.x*4u)),
                asfloat(terrain_sun_values.Load(indices.y*4u)),asfloat(terrain_sun_values.Load(indices.z*4u)));
            result.cone=1.0+saturate(dot(sun,w));
        }
    }
}
#endif
