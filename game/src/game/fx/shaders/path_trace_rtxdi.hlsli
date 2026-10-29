// Application bridge for the unmodified NVIDIA RTXDI 3.1.0 shader library.
// SDK headers are external build inputs; see RTXDI_NOTICES.txt and the manifest.
#include <Rtxdi/DI/ReSTIRDIParameters.h>
#include <Rtxdi/DI/Reservoir.hlsli>
#include <Rtxdi/Utils/RandomSamplerState.hlsli>
struct DIStoredSurface { float3 position; float depth; uint normal; uint geometric; uint albedo; uint material; };
struct DIControl {
    column_major float4x4 previous_view_projection;
    column_major float4x4 previous_view;
    uint4 layout; // width, height, previous array, current array
    uint4 state; // history valid, initial samples, RR, frame sequence
};
[[vk::binding(33,0)]] RWStructuredBuffer<RTXDI_PackedDIReservoir> di_reservoirs : register(u3300000);
[[vk::binding(34,0)]] RWStructuredBuffer<DIStoredSurface> di_surfaces : register(u3400000);
[[vk::binding(35,0)]] StructuredBuffer<float2> di_neighbors : register(t3500000);
[[vk::binding(36,0)]] ConstantBuffer<DIControl> di_control : register(b3600000);
[[vk::binding(37,0)]] ConstantBuffer<Frame> di_previous_frame : register(b3700000);
[[vk::binding(38,0)]] ByteAddressBuffer di_motion : register(t3800000);
#define RTXDI_LIGHT_RESERVOIR_BUFFER di_reservoirs
#define RTXDI_NEIGHBOR_OFFSETS_BUFFER di_neighbors
// Keep candidate densities independent of visibility; shade with a fresh ray.
// BASIC has the SDK's documented visibility-related bias, not an unbiased claim.
#define RTXDI_ALLOWED_BIAS_CORRECTION RTXDI_BIAS_CORRECTION_BASIC
struct RAB_Surface { Surface hit; float3 view; float depth; };
struct RAB_LightInfo { uint index; bool previous; };
struct RAB_LightSample { float3 diffuse; float3 specular; float3 direction; float distance; uint kind; };
RTXDI_ReservoirBufferParameters di_buffer_parameters() {
    RTXDI_ReservoirBufferParameters p=(RTXDI_ReservoirBufferParameters)0;
    p.reservoirBlockRowPitch=((di_control.layout.x+15u)/16u)*256u;
    p.reservoirArrayPitch=p.reservoirBlockRowPitch*((di_control.layout.y+15u)/16u);return p;
}
uint di_surface_address(uint2 pixel,uint array) {
    return array*di_buffer_parameters().reservoirArrayPitch+pixel.y*di_control.layout.x+pixel.x;
}
uint di_pack_normal(float3 n) {
    n/=max(dot(abs(n),1.0.xxx),1e-8);float2 p=n.xy;
    if(n.z<0.0)p=(1.0-abs(p.yx))*float2(p.x>=0.0?1.0:-1.0,p.y>=0.0?1.0:-1.0);
    uint2 q=uint2(round(saturate(p*.5+.5)*65535.0));return q.x|(q.y<<16u);
}
float3 di_unpack_normal(uint value) {
    float2 p=float2(value&65535u,value>>16u)/65535.0*2.0-1.0;
    float3 n=float3(p,1.0-abs(p.x)-abs(p.y));
    if(n.z<0.0)n.xy=(1.0-abs(p.yx))*float2(p.x>=0.0?1.0:-1.0,p.y>=0.0?1.0:-1.0);
    return normalize(n);
}
uint di_pack4(float4 value) {uint4 q=uint4(round(saturate(value)*255.0));return q.x|(q.y<<8u)|(q.z<<16u)|(q.w<<24u);}
float4 di_unpack4(uint value) {return float4(value&255u,(value>>8u)&255u,(value>>16u)&255u,value>>24u)/255.0;}
void di_store_surface(uint2 pixel,RAB_Surface s) {
    DIStoredSurface p;p.position=s.hit.position;p.depth=s.depth;
    p.normal=di_pack_normal(s.hit.normal);p.geometric=di_pack_normal(s.hit.geometric_normal);
    p.albedo=di_pack4(float4(s.hit.albedo,0));
    p.material=di_pack4(float4(s.hit.roughness,s.hit.metalness,s.hit.specular,s.hit.visible));
    di_surfaces[di_surface_address(pixel,di_control.layout.w)]=p;
}
RAB_Surface RAB_EmptySurface() {return (RAB_Surface)0;}
bool RAB_IsSurfaceValid(RAB_Surface s) {return s.depth>0.0;}
float3 RAB_GetSurfaceNormal(RAB_Surface s) {return s.hit.normal;}
float RAB_GetSurfaceLinearDepth(RAB_Surface s) {return s.depth;}
Surface RAB_GetMaterial(RAB_Surface s) {return s.hit;}
bool RAB_AreMaterialsSimilar(Surface a,Surface b) {
    return abs(a.roughness-b.roughness)<.15 && abs(a.metalness-b.metalness)<.1 && all(abs(a.albedo-b.albedo)<.25);
}
int2 RAB_ClampSamplePositionIntoView(int2 p,bool previous) {return clamp(p,int2(0,0),int2(di_control.layout.xy)-1);}
RAB_Surface RAB_GetGBufferSurface(int2 pixel,bool previous) {
    RAB_Surface s=RAB_EmptySurface();
    if(any(pixel<0)||any(pixel>=int2(di_control.layout.xy))||di_control.state.x==0u)return s;
    // The fused pass only reads the previous array. No cross-pixel write/read race.
    DIStoredSurface p=di_surfaces[di_surface_address(pixel,di_control.layout.z)];
    if(p.depth<=0.0)return s;
    s.hit.position=p.position;s.depth=p.depth;s.hit.hit=1.0;
    s.hit.normal=di_unpack_normal(p.normal);s.hit.geometric_normal=di_unpack_normal(p.geometric);
    s.hit.albedo=di_unpack4(p.albedo).rgb;float4 m=di_unpack4(p.material);
    s.hit.roughness=max(m.x,.02);s.hit.metalness=m.y;s.hit.specular=m.z;s.hit.visible=m.w;
    float3 eye=mul(di_previous_frame.camera_world,float4(0,0,0,1)).xyz;
    s.view=di_previous_frame.camera.x>.5?mul(di_previous_frame.camera_world,float4(0,0,1,0)).xyz:normalize(eye-p.position);
    return s;
}
uint di_local_count(bool previous) {
    return previous?(di_previous_frame.local_state.w>.5?min(uint(di_previous_frame.local_state.x),64u):7u):
        (frame.local_state.w>.5?min(uint(frame.local_state.x),64u):7u);
}
void di_local(uint i,bool previous,out float4 position,out float4 colour) {
    if(previous) {
        position=di_previous_frame.local_state.w>.5?di_previous_frame.local_position[i]:di_previous_frame.point_position[min(i,6u)];
        colour=di_previous_frame.local_state.w>.5?di_previous_frame.local_colour[i]:di_previous_frame.point_colour[min(i,6u)];
    } else {
        position=frame.local_state.w>.5?frame.local_position[i]:frame.point_position[min(i,6u)];
        colour=frame.local_state.w>.5?frame.local_colour[i]:frame.point_colour[min(i,6u)];
    }
}
RAB_LightInfo RAB_EmptyLightInfo() {return (RAB_LightInfo)0;}
RAB_LightSample RAB_EmptyLightSample() {return (RAB_LightSample)0;}
RAB_LightInfo RAB_LoadLightInfo(uint index,bool previous) {RAB_LightInfo l;l.index=index;l.previous=previous;return l;}
int RAB_TranslateLightIndex(uint index,bool previous) {
    // Local IDs are stable-sorted by the controller. Membership/order changes
    // and emitter-table revisions explicitly reset this history.
    if(index<64u)return index<di_local_count(previous)?int(index):-1;
#ifndef PATH_NO_EMITTERS
    return index-64u<emitters.Load(0)?int(index):-1;
#else
    return -1;
#endif
}
// Exact textured emitter evaluation is reserved for the final shading of
// the selected sample; every resampling stage uses the same cheap target.
static bool di_exact=false;
RAB_LightSample RAB_SamplePolymorphicLight(RAB_LightInfo light,RAB_Surface receiver,float2 uv) {
    RAB_LightSample sample=RAB_EmptyLightSample();Surface s=receiver.hit;
    float3 incoming=0.0;float pdf;
    if(light.index<64u) {
        if(light.index>=di_local_count(light.previous))return sample;
        float4 lamp,colour;di_local(light.index,light.previous,lamp,colour);
        float3 delta=lamp.xyz-s.position;float distance=length(delta);
        if(lamp.w<=0.0||distance>=lamp.w||distance<.005)return sample;
        sample.direction=area_ray(delta/distance,abs(colour.w)/distance,uv);
        sample.distance=distance;sample.kind=1u;
        bsdf(s,receiver.view,sample.direction,sample.diffuse,sample.specular,pdf);
        if(colour.w<0.0)sample.specular=0.0;
        incoming=colour.rgb*(PI*abs(dot(s.normal,sample.direction))*max(1.0-distance*distance/(lamp.w*lamp.w),0.0));
    }
#ifndef PATH_NO_EMITTERS
    else {
        uint index=light.index-64u;if(index>=emitters.Load(0))return sample;
        uint offset=16u+index*64u;
        float4 pa=asfloat(emitters.Load4(offset));float3 pb=asfloat(emitters.Load3(offset+16u)),pc=asfloat(emitters.Load3(offset+32u));
        uint4 source=emitters.Load4(offset+48u);
        float r=sqrt(uv.x);float3 w=float3(1.0-r,r*(1.0-uv.y),r*uv.y);
        float3 light_position=pa.xyz*w.x+pb*w.y+pc*w.z;
        float3 origin=surface_origin(s,light_position-s.position),delta=light_position-origin;float distance=length(delta);
        if(distance<=.004||distance>frame.camera.w)return sample;
        sample.direction=delta/distance;sample.distance=distance;sample.kind=2u;
        bsdf(s,receiver.view,sample.direction,sample.diffuse,sample.specular,pdf);
        uint4 material=geometry.Load4(source.z*16u);uint i=material.x+source.y*3u;
        float3 emission;
        if(!di_exact) {
            // Candidate and reuse weights only need a consistent target
            // function. The material's constant emission, without its texture
            // or cutout, costs two loads instead of three vertices and two
            // taps; final shading below evaluates the exact sample, so the
            // resampled estimate stays unbiased.
            float3 constant=asfloat(vertices.Load3(i*64+48));
            emission=(material.y&1u)!=0u?constant:linear_colour(constant);
        } else {
            Vertex a=vertex_at(i),b=vertex_at(i+1),c=vertex_at(i+2);
            float3 tex=float3(hit_uv(a,b,c,w),a.emission_layer.w);
            if(source.w==0u&&colours.SampleLevel(colour_sampler,tex,0).a*a.diffuse.a<asfloat(material.z))return RAB_EmptyLightSample();
            float density=max(length(float2(b.position_u.w-a.position_u.w,b.normal_v.w-a.normal_v.w))/max(length(pb-pa.xyz),.001),
                              length(float2(c.position_u.w-a.position_u.w,c.normal_v.w-a.normal_v.w))/max(length(pc-pa.xyz),.001));
            uint width,height,layers,levels;colours.GetDimensions(0,width,height,layers,levels);
            float lod=max(log2(max(max(.002,s.roughness*.02)*distance*density*float(width),1.0)),0.0);
            emission=(material.y&1u)!=0u?a.emission_layer.rgb:linear_colour(colours.SampleLevel(colour_sampler,tex,lod).rgb*a.emission_layer.rgb);
        }
        // Density is over the shared light/UV domain, including the area's
        // solid-angle Jacobian. Reconnection reevaluates it at every receiver.
        float cosine=abs(dot(normalize(cross(pb-pa.xyz,pc-pa.xyz)),sample.direction));
        incoming=emission*(abs(dot(s.normal,sample.direction))*pa.w*cosine/max(distance*distance,1e-12));
    }
#endif
    sample.diffuse*=incoming;sample.specular*=incoming;return sample;
}
float RAB_GetLightSampleTargetPdfForSurface(RAB_LightSample sample,RAB_Surface s) {
    float value=dot(max(sample.diffuse*s.hit.albedo+sample.specular,0.0),float3(.2126,.7152,.0722));
    return isfinite(value)?value:0.0;
}
#include <Rtxdi/DI/SpatioTemporalResampling.hlsli>
void di_clear(uint2 pixel) {
    di_surfaces[di_surface_address(pixel,di_control.layout.w)]=(DIStoredSurface)0;
    RTXDI_StoreDIReservoir(RTXDI_EmptyDIReservoir(),di_buffer_parameters(),pixel,di_control.layout.w);
}
void di_lighting(Surface primary,float3 view,uint2 pixel,float depth,out float3 diffuse,out float3 specular,out float3 direct_specular,out float4 dm,out float4 sm) {
    RAB_Surface surface;surface.hit=primary;surface.view=view;surface.depth=depth;
    di_store_surface(pixel,surface);
    RTXDI_RandomSamplerState rng=RTXDI_InitRandomSampler(pixel,di_control.state.w,7u);
    RTXDI_DIReservoir initial=RTXDI_EmptyDIReservoir();
    uint locals=di_local_count(false),triangles=0;
#ifndef PATH_NO_EMITTERS
    triangles=emitters.Load(0);
#endif
    float local_probability=locals>0u?(triangles>0u?.5:1.0):0.0;
    for(uint i=0;i<di_control.state.y;i++) {
        uint index=0;float probability=0.0;
        if(RTXDI_GetNextRandom(rng)<local_probability) {
            index=min(uint(RTXDI_GetNextRandom(rng)*locals),locals-1u);probability=local_probability/float(locals);
        }
#ifndef PATH_NO_EMITTERS
        else if(triangles>0u) {
            float choice=RTXDI_GetNextRandom(rng);uint low=0,high=triangles;
            while(low<high) {uint mid=low+(high-low)/2u;if(choice<asfloat(emitters.Load(16u+mid*64u+44u)))high=mid;else low=mid+1u;}
            index=64u+min(low,triangles-1u);probability=(1.0-local_probability)*asfloat(emitters.Load(16u+(index-64u)*64u+28u));
        }
#endif
        if(probability<=0.0)continue;
        float2 uv=float2(RTXDI_GetNextRandom(rng),RTXDI_GetNextRandom(rng));uv=floor(uv*65535.0)/65535.0;
        RAB_LightSample sample=RAB_SamplePolymorphicLight(RAB_LoadLightInfo(index,false),surface,uv);
        RTXDI_StreamSample(initial,index,uv,RTXDI_GetNextRandom(rng),RAB_GetLightSampleTargetPdfForSurface(sample,surface),1.0/probability);
    }
    RTXDI_FinalizeResampling(initial,1.0,max(initial.M,1.0));
    RTXDI_DIReservoir reservoir=initial;
    float4 displayed=float4(primary.position-asfloat(lighting_offsets.Load3(primary.instance_id*16u)),1.0);
    uint motion_offset=primary.instance_id*96u;float valid=asfloat(di_motion.Load(motion_offset+60u));
    float3 previous_position=displayed.xyz;
    if(asfloat(di_motion.Load(motion_offset+76u))>.5)previous_position=float3(dot(asfloat(di_motion.Load4(motion_offset)),displayed),
        dot(asfloat(di_motion.Load4(motion_offset+16u)),displayed),dot(asfloat(di_motion.Load4(motion_offset+32u)),displayed));
    float4 clip=mul(di_control.previous_view_projection,float4(previous_position,1));
    if(di_control.state.x!=0u&&valid>.5&&clip.w>0.0) {
        float2 previous_pixel=(float2(clip.x,-clip.y)/clip.w*.5+.5)*float2(di_control.layout.xy)-.5;
        float previous_depth=-mul(di_control.previous_view,float4(previous_position,1)).z;
        RTXDI_RuntimeParameters runtime=(RTXDI_RuntimeParameters)0;runtime.neighborOffsetMask=255u;runtime.frameIndex=di_control.state.w;
        RTXDI_DISpatioTemporalResamplingParameters settings=(RTXDI_DISpatioTemporalResamplingParameters)0;
        settings.depthThreshold=.01;settings.normalThreshold=.95;settings.biasCorrectionMode=RTXDI_BIAS_CORRECTION_BASIC;
        settings.maxHistoryLength=di_control.state.z!=0u?4u:8u;settings.enablePermutationSampling=1u;
        settings.uniformRandomNumber=sample_hash(di_control.state.w);settings.numSamples=5u;settings.numDisocclusionBoostSamples=8u;
        // A bounded 8-pixel neighborhood avoids noisy MIS normalization when
        // nearby surfaces see substantially different local-light distributions.
        settings.samplingRadius=8.0;settings.enableMaterialSimilarityTest=1u;
        int2 temporal;RAB_LightSample selected=RAB_EmptyLightSample();
        reservoir=RTXDI_DISpatioTemporalResampling(pixel,surface,initial,rng,float3(previous_pixel-float2(pixel),previous_depth-depth),
            di_control.layout.z,runtime,di_buffer_parameters(),settings,temporal,selected);
    }
    RTXDI_StoreDIReservoir(reservoir,di_buffer_parameters(),pixel,di_control.layout.w);
    // RR prefers temporally independent noise. Mix in the fresh estimator at
    // final shading without corrupting the reservoir used for future reuse.
    if(di_control.state.z!=0u&&RTXDI_GetNextRandom(rng)<.25)reservoir=initial;
    diffuse=0.0;specular=0.0;direct_specular=0.0;dm=0.0;sm=0.0;
    if(!RTXDI_IsValidDIReservoir(reservoir))return;
    di_exact=true;
    RAB_LightSample sample=RAB_SamplePolymorphicLight(RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(reservoir),false),surface,RTXDI_GetDIReservoirSampleUV(reservoir));
    di_exact=false;
    float visible=0.0;
    if(sample.kind==1u)visible=visibility(primary,sample.direction,sample.distance,false);
    else if(sample.kind==2u) {
        Surface result=(Surface)0;RayDesc ray={surface_origin(primary,sample.direction),0.0,sample.direction,max(sample.distance-.002,0.0)};
        TraceRay(scene,RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH|RAY_FLAG_SKIP_CLOSEST_HIT_SHADER,4,0,0,0,ray,result);visible=result.visible;
    }
    float weight=RTXDI_GetDIReservoirInvPdf(reservoir)*visible;
    if(!isfinite(weight)||weight<0.0)return;
    diffuse=sample.diffuse*weight;specular=sample.specular*weight;
    add_direction(diffuse,sample.direction,dm);
    if(sample.kind==1u)direct_specular=specular;else add_direction(specular,sample.direction,sm);
}
