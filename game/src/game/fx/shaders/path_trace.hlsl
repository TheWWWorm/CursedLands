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
};
[[vk::binding(4,0)]] ConstantBuffer<Frame> frame : register(b400000);
struct Vertex { float4 position_u; float4 normal_v; float4 diffuse; float4 emission_layer; };
struct Surface { float3 position; float offset; float3 normal; float hit; float3 albedo; float visible; float3 emission; float cone; float roughness; float metalness; float specular; uint instance_id; float3 geometric_normal; uint primitive_id; };
struct Attributes { float2 bary; };
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
static const float PI=3.14159265359;
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
float3 surface_origin(Surface s) {
    // closest-hit bounds reconstruction, intersection and instance transforms.
    // Preserve the final FMA so rounding cannot erase the small normal offset.
    precise float3 origin=mad(s.geometric_normal,s.offset,s.position);
    return origin;
}
float visibility(Surface s,float3 direction,float reach,bool directional) {
    Surface result=(Surface)0;
    float3 origin=surface_origin(s);
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
    TraceRay(scene,RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH|RAY_FLAG_SKIP_CLOSEST_HIT_SHADER,2,0,0,0,ray,result);
    return result.visible;
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
void bsdf(Surface s,float3 v,float3 l,out float3 diffuse,out float3 specular,out float pdf) {
    diffuse=0.0;specular=0.0;pdf=0.0;
    float nv=dot(s.normal,v),nl=dot(s.normal,l);
    if(nv<=0.0||nl<=0.0||dot(s.geometric_normal,l)<=0.0)return;
    float3 h=normalize(v+l);
    float nh=saturate(dot(s.normal,h)),vh=saturate(dot(v,h));
    float a=s.roughness*s.roughness,a2=a*a;
    float3 reflectance=f0(s),f=reflectance+(1.0-reflectance)*pow(1.0-vh,5.0);
    float d=ggx_d(nh,a2);
    diffuse=(1.0-s.metalness)*(1.0-f)/PI;
    specular=f*d*smith_g1(nv,a2)*smith_g1(nl,a2)/max(4.0*nv*nl,1e-6);
    float chance=specular_chance(s,nv);
    // Visible-normal GGX density, transformed from half vectors to outgoing
    // directions. This must match sample_bsdf, including its mixture weight.
    pdf=(1.0-chance)*nl/PI+chance*d*smith_g1(nv,a2)/max(4.0*nv,1e-6);
}
float3 sample_bsdf(Surface s,float3 v,PathSampler sampler) {
    float chance=specular_chance(s,dot(s.normal,v));
    float2 u=path_random(sampler,11u);
    if(path_random(sampler,10u).x>=chance)return cosine_ray(s.normal,u);
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
    return reflect(-v,h);
}
void direct_light(Surface s,float3 v,PathSampler sampler,out float3 diffuse,out float3 specular) {
    diffuse=0.0;specular=0.0;
    for(uint i=0;i<8;i++) {
        float3 direction,colour;float reach;
        if(i==0) {
            if(!any(frame.sun.rgb>0.0))continue;
            direction=area_ray(frame.sun_direction.xyz,frame.sun_direction.w,path_random(sampler,i));
            colour=frame.sun.rgb;reach=frame.camera.w;
        } else {
            float4 lamp=frame.point_position[i-1];
            float3 delta=lamp.xyz-s.position;float distance=length(delta);
            if(lamp.w<=0.0||distance>=lamp.w||distance<0.005)continue;
            direction=area_ray(delta/distance,frame.point_colour[i-1].w/distance,path_random(sampler,i));
            colour=frame.point_colour[i-1].rgb*max(1.0-distance*distance/(lamp.w*lamp.w),0.0);
            reach=distance;
        }
        float cosine=dot(s.normal,direction);
        if(cosine<=0.0)continue;
        float3 d,sp;float pdf;bsdf(s,v,direction,d,sp,pdf);
        // Authored game light values are diffuse irradiance / pi. Convert
        // them to the radiance scale used by the normalized BRDF.
        float3 incoming=colour*(PI*cosine*visibility(s,direction,reach,i==0));
        diffuse+=d*incoming;specular+=sp*incoming;
    }
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
void emissive_light(Surface s,float3 v,PathSampler sampler,out float3 diffuse,out float3 specular) {
    diffuse=0.0;specular=0.0;
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
    float3 origin=surface_origin(s),delta=light_position-origin;
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
    Surface visible=(Surface)0;
    // Emissive target exclusion still uses the existing endpoint margin;
    // the receiver no longer discards nearby blockers through a fixed TMin.
    RayDesc ray={origin,0.0,direction,distance-0.002};
    // Match indirect geometry visibility, including non-shadow-casting walls.
    TraceRay(scene,RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH|RAY_FLAG_SKIP_CLOSEST_HIT_SHADER,4,0,0,0,ray,visible);
    float3 incoming=emission*(max(dot(s.normal,direction),0.0)*visible.visible*mis_weight(pdf,bsdf_pdf)/pdf);
    diffuse=d*incoming;specular=sp*incoming;
}
#endif
void path_sample(Surface primary,float3 view,PathSampler sampler,out float3 diffuse,out float3 specular) {
    direct_light(primary,view,sampler,diffuse,specular);
    Surface current=primary;
    float3 v=view,weight_d=1.0,weight_s=1.0;
    uint bounces=clamp(uint(frame.path.x),1u,4u);
    for(uint depth=0;depth<bounces;depth++) {
        sampler.vertex=depth;
#ifndef PATH_NO_EMITTERS
        float3 emitter_d,emitter_s;emissive_light(current,v,sampler,emitter_d,emitter_s);
        if(depth==0) {diffuse+=emitter_d;specular+=emitter_s;}
        else {
            float3 incoming=emitter_d*current.albedo+emitter_s;
            diffuse+=weight_d*incoming;specular+=weight_s*incoming;
        }
#endif
        float3 direction=sample_bsdf(current,v,sampler),d,sp;float pdf;
        bsdf(current,v,direction,d,sp,pdf);
        float cosine=max(dot(current.normal,direction),0.0);
        if(pdf<=1e-8||cosine<=0.0)break;
        if(depth==0) {
            weight_d=d*(cosine/pdf);weight_s=sp*(cosine/pdf);
        } else {
            float3 weight=(d*current.albedo+sp)*(cosine/pdf);
            weight_d*=weight;weight_s*=weight;
        }
        if(max(max(weight_d.r,max(weight_d.g,weight_d.b)),max(weight_s.r,max(weight_s.g,weight_s.b)))<1e-6)break;
        Surface hit=(Surface)0;hit.cone=max(0.002,current.roughness*0.02);
        RayDesc ray={surface_origin(current),0.0,direction,frame.camera.w};
        TraceRay(scene,RAY_FLAG_NONE,4,0,0,0,ray,hit);
        if(hit.hit<0.5) {
            float3 environment=sky_radiance(direction);
            diffuse+=weight_d*environment;specular+=weight_s*environment;break;
        }
        float3 direct_d,direct_s;
        sampler.vertex=depth+1u;
        direct_light(hit,-direction,sampler,direct_d,direct_s);
        float emission_weight=1.0;
#ifndef PATH_NO_EMITTERS
        emission_weight=mis_weight(pdf,emitter_hit_pdf(hit,ray.Origin));
#endif
        float3 incoming=hit.emission*emission_weight+hit.albedo*direct_d+direct_s;
        diffuse+=weight_d*incoming;specular+=weight_s*incoming;
        current=hit;v=-direction;
    }
}
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
    indirect_image[pixel]=0.0;shadow_image0[pixel]=0.0;shadow_image1[pixel]=0.0;
    if(primary.hit<0.5)return;
    float3 diffuse=0.0,specular=0.0;
    uint samples=clamp(uint(frame.settings.y),1u,16u);
    for(uint i=0;i<samples;i++) {
        PathSampler sampler=path_sampler(uint(frame.settings.x)*samples+i,pixel.x+pixel.y*uint(size.x));
        float3 d,s;path_sample(primary,-direction,sampler,d,s);diffuse+=d;specular+=s;
    }
    indirect_image[pixel]=float4(diffuse/float(samples),1.0);
    shadow_image0[pixel]=float4(specular/float(samples),1.0);
    // Every integer up to 2047 is exact in the RGBA16F guide. Separate 6/5-bit
    // fields avoid aliases such as (roughness .2, metalness .4) and (.6, .2).
    uint surface=uint(round(saturate(primary.roughness)*63.0))|
        (uint(round(saturate(primary.metalness)*31.0))<<6u);
    shadow_image1[pixel]=float4(primary.albedo,float(surface));
}
#elif defined(PATH_MISS)
[shader("miss")]
void main(inout Surface result) {result.visible=1.0;}
#elif defined(PATH_ANY_HIT)
[shader("anyhit")]
void main(inout Surface result,Attributes attributes) {
    uint4 material=geometry.Load4(instance_geometry.Load(InstanceID()*4u)*16u); uint i=material.x+3*PrimitiveIndex();
    Vertex a=vertex_at(i),b=vertex_at(i+1),c=vertex_at(i+2);
    float3 w=float3(1.0-attributes.bary.x-attributes.bary.y,attributes.bary);
    if(colours.SampleLevel(colour_sampler,float3(hit_uv(a,b,c,w),a.emission_layer.w),0.0).a*a.diffuse.a<asfloat(material.z))IgnoreHit();
}
#elif defined(PATH_CLOSEST_HIT)
float3 relief_normal(float3 n,float3 geometric,float3 edge1,float3 edge2,float2 uv1,float2 uv2,
                     float3 texel,float2 step_uv,float lod,float strength) {
    float3 r1=cross(edge2,n),r2=cross(n,edge1);
    float3 u=r1*uv1.x+r2*uv2.x,v=r1*uv1.y+r2*uv2.y;
    // The oriented triangle area can reverse under mirrored placement or
    // a back-face hit. UV reflection itself must retain its handedness.
    float area=dot(cross(edge1,edge2),n);
    if(abs(area)<1e-10||abs(uv1.x*uv2.y-uv1.y*uv2.x)<1e-10)return n;
    float scale=sign(area)*rsqrt(max(max(dot(u,u),dot(v,v)),1e-12));
    const float3 lum=float3(0.2126,0.7152,0.0722);
    float left=dot(colours.SampleLevel(colour_sampler,texel-float3(step_uv.x,0,0),lod).rgb,lum);
    float right=dot(colours.SampleLevel(colour_sampler,texel+float3(step_uv.x,0,0),lod).rgb,lum);
    float above=dot(colours.SampleLevel(colour_sampler,texel-float3(0,step_uv.y,0),lod).rgb,lum);
    float below=dot(colours.SampleLevel(colour_sampler,texel+float3(0,step_uv.y,0),lod).rgb,lum);
    float2 slope=clamp(float2(right-left,below-above)*2.0,-0.12,0.12);
    float3 detailed=normalize(n-(u*slope.x+v*slope.y)*scale*strength);
    // Relief changes shading only; never point a ray into the actual facet.
    return dot(detailed,geometric)>0.05&&dot(detailed,WorldRayDirection())<0.0?detailed:n;
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
    if(dot(result.normal,result.geometric_normal)<0.0)result.normal=-result.normal;
    if(dot(result.normal,WorldRayDirection())>=0.0)result.normal=result.geometric_normal;
    float density=max(length(float2(b.position_u.w-a.position_u.w,b.normal_v.w-a.normal_v.w))/max(length(mul((float3x3)to_world,edge1)),0.001),
                      length(float2(c.position_u.w-a.position_u.w,c.normal_v.w-a.normal_v.w))/max(length(mul((float3x3)to_world,edge2)),0.001));
    uint width,height,layers,levels; colours.GetDimensions(0,width,height,layers,levels);
    float lod=max(log2(max(result.cone*RayTCurrent()*density*float(width),1.0)),0.0);
    float3 texel=float3(hit_uv(a,b,c,w),a.emission_layer.w);
    float3 colour=colours.SampleLevel(colour_sampler,texel,lod).rgb;
    float strength=float((material.w>>24u)&127u)/127.0;
    if(strength>0.0) {
        float3 eye=mul(frame.camera_world,float4(0,0,0,1)).xyz;
        float distance=length(position-eye);
        float footprint=2.0*abs(frame.inv_projection[0][0])/float(DispatchRaysDimensions().x);
        if(frame.camera.x<0.5)footprint*=distance;
        footprint=max(footprint,result.cone*RayTCurrent());
        float texels=footprint*density*float(width)/max(abs(dot(result.normal,WorldRayDirection())),0.1);
        strength*=(1.0-smoothstep(14.0,40.0,distance))*(1.0-smoothstep(1.2,4.0,texels));
        if(strength>0.0)result.normal=relief_normal(result.normal,result.geometric_normal,
            mul((float3x3)to_world,edge1),mul((float3x3)to_world,edge2),
            float2(b.position_u.w-a.position_u.w,b.normal_v.w-a.normal_v.w),
            float2(c.position_u.w-a.position_u.w,c.normal_v.w-a.normal_v.w),
            texel,1.0/float2(width,height),max(lod,log2(max(texels,1.0))),strength);
    }
    result.albedo=saturate(linear_colour(colour)*saturate(a.diffuse.rgb));
    result.roughness=max(float(material.w&255u)/255.0,0.08);
    result.metalness=float((material.w>>8u)&255u)/255.0;
    result.specular=float((material.w>>16u)&255u)/255.0;
    result.emission=(material.y&1u)!=0u?a.emission_layer.rgb:linear_colour(colour*a.emission_layer.rgb);
}
#endif
