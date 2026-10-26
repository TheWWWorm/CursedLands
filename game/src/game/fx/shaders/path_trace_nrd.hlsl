// Application/NRD boundary. Compile against the pinned SDK; use its actual
// packing and material-factor helpers for both ends of the denoiser.
#include "NRD.hlsli"
// Keep the application boundary on the same unmodified SPIR-V path as the
// SDK passes; Godot's re-optimization can corrupt the dynamic light table.
[[vk::constant_id(0)]] const bool ei_nrd_dispatch = true;
[[vk::binding(0,0)]] Texture2D<float4> raw_diffuse : register(t0);
[[vk::binding(1,0)]] Texture2D<float4> raw_guide : register(t1);
[[vk::binding(2,0)]] Texture2D<float4> raw_specular : register(t2);
[[vk::binding(3,0)]] Texture2D<float4> raw_material : register(t3);
[[vk::binding(4,0)]] Texture2D<float2> raw_distance : register(t4);
[[vk::binding(5,0)]] ByteAddressBuffer motions : register(t5);
// Analytic direct highlights have known lighting directions, not a secondary
// hit distance. Preserve them outside NRD's indirect specular reconstruction.
[[vk::binding(13,0)]] Texture2D<float4> direct_specular : register(t13);
// Sun visibility follows the caster, not the receiver's secondary hit.
// Reconstruct it separately so long indirect history cannot leave an old
// animal shadow behind or erase a newly arriving shadow.
[[vk::binding(14,0)]] Texture2D<float4> direct_sun : register(t14);
#ifdef NRD_DIRECTIONAL
[[vk::binding(15,0)]] Texture2D<float4> diffuse_direction : register(t15);
[[vk::binding(16,0)]] Texture2D<float4> specular_direction : register(t16);
#endif
struct Frame {
    column_major float4x4 inv_projection;
    column_major float4x4 camera_world;
    column_major float4x4 previous_view_projection;
    column_major float4x4 previous_view;
    float4 sun;float4 sun_direction;float4 sky;float4 settings;float4 camera;float4 center_radius;
    float4 point_position[7];float4 point_colour[7];float4 path;
    column_major float4x4 previous_inverse_view_projection;
    float4 sky_zenith;float4 sky_horizon;float4 sky_ground;
    float4 cloud_state;float4 cloud_phases;float4 cloud_domain;
    float4 local_state;
    float4 local_position[64];float4 local_colour[64];
};
[[vk::binding(6,0)]] ConstantBuffer<Frame> frame : register(b6);

float3 world_at(uint2 pixel,float depth,uint2 size) {
    float2 uv=(float2(pixel)+0.5)/float2(size);
    float4 p=mul(frame.inv_projection,float4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0));p/=p.w;
    float3 view=frame.camera.x>0.5?float3(p.xy,-depth):p.xyz*(depth/-p.z);
    return mul(frame.camera_world,float4(view,1.0)).xyz;
}
float3 view_at(float3 world) {
    float3 eye=mul(frame.camera_world,float4(0,0,0,1)).xyz;
    return frame.camera.x>0.5?mul(frame.camera_world,float4(0,0,1,0)).xyz:normalize(eye-world);
}
void factors(uint2 pixel,float3 world,float3 normal,out float roughness,out float3 diffuse,out float3 specular) {
    float4 material=raw_material[pixel];uint packed=uint(round(material.w));
    roughness=float(packed&63u)/63.0;float metalness=float(packed>>6u)/31.0;
    float3 view=view_at(world);
    // Diffuse has already been divided by base colour in the integrator. Use
    // white here so material texture detail stays in the raster receiver.
    NRD_MaterialFactors(normal,view,1.0,lerp(0.04.xxx,material.rgb,metalness),roughness,diffuse,specular);
    diffuse*=max(1.0-metalness,0.05);
}

#ifdef NRD_PACK
// A distant flame must not shorten history across the whole view. Estimate
// its local contribution with the integrator's finite-range falloff. This
// controls history confidence only: it never adds unoccluded lighting.
float lighting_confidence(float3 world) {
    if(frame.path.y>=8.0)return 1.0;
    float affected=frame.local_state.y;
    if(affected<1.0) {
        float local=0.0;
        uint count=frame.local_state.w>0.5?min(uint(frame.local_state.x),64u):7u;
        for(uint i=0;i<count;i++) {
            float4 lamp=frame.local_state.w>0.5?frame.local_position[i]:frame.point_position[i];
            float3 colour=frame.local_state.w>0.5?frame.local_colour[i].rgb:frame.point_colour[i].rgb;
            float3 delta=lamp.xyz-world;
            if(lamp.w>0.0)local+=dot(colour,float3(0.2126,0.7152,0.0722))*max(1.0-dot(delta,delta)/(lamp.w*lamp.w),0.0);
        }
        float background=dot(frame.sun.rgb+frame.sky.rgb,float3(0.2126,0.7152,0.0722));
        affected=saturate(local/max(local+background,0.0001));
    }
    // REBLUR rounds history length twice. Two thirds retains two samples at
    // 60 Hz; lower frame rates need faster local response to flame flutter.
    // Weather fades are slower, so preserve two samples there at any rate.
    float response_confidence=frame.local_state.y>0.5?2.0/3.0:1.0-1.0/max(frame.path.y,2.0);
    return lerp(1.0,response_confidence,affected);
}
[[vk::binding(7,0),vk::image_format("rgba16f")]] RWTexture2D<float4> out_motion : register(u7);
[[vk::binding(8,0),vk::image_format("rgba16f")]] RWTexture2D<float4> out_normal : register(u8);
[[vk::binding(9,0),vk::image_format("r32f")]] RWTexture2D<float> out_depth : register(u9);
[[vk::binding(10,0),vk::image_format("rgba16f")]] RWTexture2D<float4> out_diffuse : register(u10);
[[vk::binding(11,0),vk::image_format("rgba16f")]] RWTexture2D<float4> out_specular : register(u11);
[[vk::binding(12,0),vk::image_format("r16f")]] RWTexture2D<float> out_confidence : register(u12);
#ifdef NRD_DIRECTIONAL
[[vk::binding(17,0),vk::image_format("rgba16f")]] RWTexture2D<float4> out_diffuse_sh1 : register(u17);
[[vk::binding(18,0),vk::image_format("rgba16f")]] RWTexture2D<float4> out_specular_sh1 : register(u18);
#endif
[numthreads(8,8,1)]
void main(uint2 pixel:SV_DispatchThreadID) {
    if(!ei_nrd_dispatch)return;
    uint2 size;raw_guide.GetDimensions(size.x,size.y);if(any(pixel>=size))return;
    float4 guide=raw_guide[pixel];
    if(guide.w<=0.0) {
        out_depth[pixel]=65504.0;out_motion[pixel]=0.0;out_normal[pixel]=float4(0,0,1,1);
        out_diffuse[pixel]=0.0;out_specular[pixel]=0.0;out_confidence[pixel]=0.0;
#ifdef NRD_DIRECTIONAL
        out_diffuse_sh1[pixel]=0.0;out_specular_sh1[pixel]=0.0;
#endif
        return;
    }
    float3 world=world_at(pixel,guide.w,size),normal=normalize(guide.xyz);
    float roughness;float3 df,sf;factors(pixel,world,normal,roughness,df,sf);
    uint placement=f32tof16(raw_diffuse[pixel].w)-0x3c00u;uint offset=placement*96u;
    float valid=asfloat(motions.Load(offset+60)),moving=asfloat(motions.Load(offset+76));
    float3 motion=0.0;
    if(valid>0.5&&moving>0.5) {
        float4 world_h=float4(world,1.0);
        float3 previous=float3(dot(asfloat(motions.Load4(offset)),world_h),dot(asfloat(motions.Load4(offset+16)),world_h),dot(asfloat(motions.Load4(offset+32)),world_h));
        motion=previous-world;
    }
    out_motion[pixel]=float4(motion,0.0);out_confidence[pixel]=valid*lighting_confidence(world);
    out_normal[pixel]=NRD_FrontEnd_PackNormalAndRoughness(normal,roughness,0.0);
    out_depth[pixel]=guide.w;
    float2 distance=raw_distance[pixel];
    float2 norm_distance=float2(REBLUR_FrontEnd_GetNormHitDist(distance.x,guide.w,float3(3,0.1,20),1.0),
        REBLUR_FrontEnd_GetNormHitDist(distance.y,guide.w,float3(3,0.1,20),roughness));
    float3 d=max(raw_diffuse[pixel].rgb-direct_sun[pixel].rgb,0.0)/df;
    float3 s=max(raw_specular[pixel].rgb-direct_specular[pixel].rgb,0.0)/sf;
#ifdef NRD_DIRECTIONAL
    float4 d1,s1;
    out_diffuse[pixel]=REBLUR_FrontEnd_PackSh(d,norm_distance.x,diffuse_direction[pixel].xyz,d1,true);
    out_specular[pixel]=REBLUR_FrontEnd_PackSh(s,norm_distance.y,specular_direction[pixel].xyz,s1,true);
    out_diffuse_sh1[pixel]=d1;out_specular_sh1[pixel]=s1;
#else
    out_diffuse[pixel]=REBLUR_FrontEnd_PackRadianceAndNormHitDist(d,norm_distance.x,true);
    out_specular[pixel]=REBLUR_FrontEnd_PackRadianceAndNormHitDist(s,norm_distance.y,true);
#endif
}
#else
[[vk::binding(7,0)]] Texture2D<float4> denoised_diffuse : register(t7);
[[vk::binding(8,0)]] Texture2D<float4> denoised_specular : register(t8);
[[vk::binding(9,0),vk::image_format("rgba16f")]] RWTexture2D<float4> out_diffuse : register(u9);
[[vk::binding(10,0),vk::image_format("rgba16f")]] RWTexture2D<float4> out_guide : register(u10);
[[vk::binding(11,0),vk::image_format("rgba16f")]] RWTexture2D<float4> out_specular : register(u11);
[[vk::binding(12,0),vk::image_format("rgba16f")]] RWTexture2D<float4> out_material : register(u12);
#ifdef NRD_DIRECTIONAL
[[vk::binding(17,0)]] Texture2D<float4> denoised_diffuse_sh1 : register(t17);
[[vk::binding(18,0)]] Texture2D<float4> denoised_specular_sh1 : register(t18);
#endif
[numthreads(8,8,1)]
void main(uint2 pixel:SV_DispatchThreadID) {
    if(!ei_nrd_dispatch)return;
    uint2 size;raw_guide.GetDimensions(size.x,size.y);if(any(pixel>=size))return;
    float4 guide=raw_guide[pixel];out_guide[pixel]=guide;out_material[pixel]=raw_material[pixel];
    // NRD deliberately doesn't touch out-of-range pixels; never present old
    // terrain lighting in newly exposed sky or an untraced receiver.
    if(guide.w<=0.0){out_diffuse[pixel]=0.0;out_specular[pixel]=0.0;return;}
    float3 world=world_at(pixel,guide.w,size),normal=normalize(guide.xyz);
    float roughness;float3 df,sf;factors(pixel,world,normal,roughness,df,sf);
#ifdef NRD_DIRECTIONAL
    NRD_SG diffuse_sg=REBLUR_BackEnd_UnpackSh(denoised_diffuse[pixel],denoised_diffuse_sh1[pixel].xyz);
    NRD_SG specular_sg=REBLUR_BackEnd_UnpackSh(denoised_specular[pixel],denoised_specular_sh1[pixel].xyz);
    float3 view=view_at(world);
    float4 d=float4(NRD_SG_ResolveDiffuse(diffuse_sg,normal,view,roughness),diffuse_sg.normHitDist);
    float4 s=float4(NRD_SG_ResolveSpecular(specular_sg,normal,view,roughness),specular_sg.normHitDist);
#else
    float4 d=REBLUR_BackEnd_UnpackRadianceAndNormHitDist(denoised_diffuse[pixel]);
    float4 s=REBLUR_BackEnd_UnpackRadianceAndNormHitDist(denoised_specular[pixel]);
#endif
    out_diffuse[pixel]=float4(clamp(d.rgb*df,0.0,60000.0),max(d.w,1.0));
    out_specular[pixel]=float4(clamp(s.rgb*sf+direct_specular[pixel].rgb,0.0,60000.0),max(s.w,1.0));
}
#endif
