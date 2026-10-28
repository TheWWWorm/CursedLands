// Cached self-component sun visibility. Other terrain
// components and objects are tested exactly from the actual pixel receiver.
[[vk::binding(0,0)]] RaytracingAccelerationStructure scene : register(t0);
[[vk::binding(2,0)]] ByteAddressBuffer vertices : register(t200000);
[[vk::binding(5,0)]] ByteAddressBuffer geometry : register(t500000);
[[vk::binding(10,0)]] ByteAddressBuffer instance_geometry : register(t1000000);
[[vk::binding(42,0)]] ByteAddressBuffer terrain_sun_samples : register(t4200000);
[[vk::binding(43,0)]] RWByteAddressBuffer terrain_sun_values : register(u4300000);
struct Control { float4 sun_reach; float4 state; }; // state.x = solar angular radius
[[vk::binding(44,0)]] ConstantBuffer<Control> control : register(b4400000);
struct Payload { float visible; float hit; uint component; };
struct Attributes { float2 bary; };
uint terrain_component(uint instance,uint primitive) {
    uint base=terrain_sun_samples.Load(32u+instance*4u);
    if(base==0xffffffffu)return 0xffffffffu;
    uint component_start=terrain_sun_samples.Load(20u);
    return terrain_sun_samples.Load(component_start+(base/3u+primitive)*4u);
}
#if defined(PATH_RAYGEN)
float self_visibility(float4 sample,float3 direction,float support,uint component,uint flags) {
    precise float3 origin=mad(direction,sample.w,sample.xyz);
    RayDesc ray={origin,0.0,direction,max(control.sun_reach.w-sample.w,0.0)};
    [loop] for(uint step=0u;step<8u;++step) {
        Payload result=(Payload)0;result.hit=-1.0;result.component=component;
        TraceRay(scene,flags,32u,0,0,0,ray,result);
        if(result.hit<0.0)return 1.0;
        if(result.visible<=0.0||result.hit>=support)return 0.0;
        // Barycentric interpolation provides the spatial transition. An
        // arbitrary distance attenuation would darken otherwise open ridges.
        ray.TMin=asfloat(max(asuint(result.hit)+1u,0x00800000u));
        if(ray.TMin>=ray.TMax)return 1.0;
    }
    return 0.0;
}
[shader("raygeneration")]
void main() {
    uint index=DispatchRaysIndex().x;
    uint4 layout=terrain_sun_samples.Load4(0);
    if(index>=layout.w)return;
    // Inactive terrain neither shadows itself nor joins active components.
    if(terrain_sun_samples.Load(layout.z+index*32u+24u)==0u) {
        terrain_sun_values.Store(index*4u,asuint(1.0));return;
    }
    float4 sample=asfloat(terrain_sun_samples.Load4(layout.z+index*32u));
    float support=asfloat(terrain_sun_samples.Load(layout.z+index*32u+16u));
    uint component=terrain_sun_samples.Load(layout.z+index*32u+20u);
    uint flags=terrain_sun_samples.Load(24u)>1u?RAY_FLAG_FORCE_NON_OPAQUE:RAY_FLAG_FORCE_OPAQUE;
    float3 sun=normalize(control.sun_reach.xyz);
    float radius=max(control.state.x,0.0);
    float visibility;
    if(radius<=0.0) {
        visibility=self_visibility(sample,sun,support,component,flags);
    } else {
        // Positive seven-point disk cubature: center weight1/4, six regular
        // hexagon taps of weight1/8 at r=sqrt(2/3). Its smooth disk moments
        // are exact through degree5. Every shared vertex uses the same taps.
        float3 tangent=normalize(cross(abs(sun.z)<0.99?float3(0,0,1):float3(0,1,0),sun));
        float3 bitangent=cross(sun,tangent);
        static const float2 ring[6]={float2(1,0),float2(0.5,0.8660254037844386),
            float2(-0.5,0.8660254037844386),float2(-1,0),
            float2(-0.5,-0.8660254037844386),float2(0.5,-0.8660254037844386)};
        visibility=0.25*self_visibility(sample,sun,support,component,flags);
        [loop] for(uint tap=0u;tap<6u;++tap) {
            float2 offset=ring[tap]*(0.8164965809277260*radius);
            float3 direction=normalize(sun+tangent*offset.x+bitangent*offset.y);
            visibility+=0.125*self_visibility(sample,direction,support,component,flags);
        }
    }
    terrain_sun_values.Store(index*4u,asuint(visibility));
}
#elif defined(PATH_MISS)
[shader("miss")]
void main(inout Payload result) {result.visible=1.0;}
#elif defined(PATH_CLOSEST_HIT)
[shader("closesthit")]
void main(inout Payload result,Attributes attributes) {
    result.visible=0.0;result.hit=RayTCurrent();
    uint4 material=geometry.Load4(instance_geometry.Load(InstanceID()*4u)*16u);
    if((material.y&2u)!=0u) {
        uint i=material.x+PrimitiveIndex()*3u;
        float3 a=asfloat(vertices.Load3(i*64u));
        float3 b=asfloat(vertices.Load3((i+1u)*64u));
        float3 c=asfloat(vertices.Load3((i+2u)*64u));
        result.visible=dot(cross(b-a,c-a),ObjectRayDirection())<0.0?1.0:0.0;
    }
}
#elif defined(PATH_ANY_HIT)
[shader("anyhit")]
void main(inout Payload result,Attributes attributes) {
    if(terrain_component(InstanceID(),PrimitiveIndex())!=result.component)IgnoreHit();
}
#endif
