// Main-view direct visibility and diffuse one-bounce global illumination.
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
};
[[vk::binding(4,0)]] ConstantBuffer<Frame> frame : register(b400000);
struct Vertex { float4 position_u; float4 normal_v; float4 diffuse; float4 emission_layer; };
struct Surface { float3 position; float distance; float3 normal; float hit; float3 albedo; float visible; float3 emission; float cone; };
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
#if defined(SCENE_RAYGEN)
static const float PI=3.14159265359;
float random(inout uint seed) {
    seed=seed*747796405u+2891336453u;
    uint x=((seed>>((seed>>28u)+4u))^seed)*277803737u;
    return float((x>>22u)^x)*(1.0/4294967296.0);
}
void basis(float3 n,out float3 t,out float3 b) {
    t=normalize(cross(abs(n.z)<0.99?float3(0,0,1):float3(0,1,0),n)); b=cross(n,t);
}
float3 cosine_ray(float3 n,inout uint seed) {
    float r=sqrt(random(seed)),phi=2.0*PI*random(seed);
    float3 t,b; basis(n,t,b);
    return normalize(t*(r*cos(phi))+b*(r*sin(phi))+n*sqrt(max(1.0-r*r,0.0)));
}
float3 area_ray(float3 direction,float angular_radius,inout uint seed) {
    if(angular_radius<=0.0)return direction;
    float3 t,b; basis(direction,t,b);
    float r=sqrt(random(seed))*angular_radius,phi=random(seed)*2.0*PI;
    return normalize(direction+t*(r*cos(phi))+b*(r*sin(phi)));
}
float visibility(float3 p,float3 n,float3 direction,float reach) {
    Surface result=(Surface)0;
    float3 offset=n*(dot(n,direction)>=0.0?0.015:-0.015);
    RayDesc ray={p+offset,0.002,direction,max(reach-0.025,0.003)};
    TraceRay(scene,RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH|RAY_FLAG_SKIP_CLOSEST_HIT_SHADER,2,0,0,0,ray,result);
    return result.visible;
}
float3 illumination(Surface s) {
    float3 light=0.0;
    float facing=max(dot(s.normal,frame.sun_direction.xyz),0.0);
    if(facing>0.0 && any(frame.sun.rgb>0.0))
        light+=frame.sun.rgb*facing*visibility(s.position,s.normal,frame.sun_direction.xyz,frame.camera.w);
    for(uint i=0;i<7;i++) {
        float4 lamp=frame.point_position[i];
        float3 delta=lamp.xyz-s.position; float distance=length(delta);
        if(lamp.w<=0.0 || distance>=lamp.w || distance<0.005)continue;
        float3 direction=delta/distance;
        float cosine=max(dot(s.normal,direction),0.0);
        if(cosine>0.0) {
            float attenuation=max(1.0-distance*distance/(lamp.w*lamp.w),0.0);
            light+=frame.point_colour[i].rgb*cosine*attenuation*visibility(s.position,s.normal,direction,distance);
        }
    }
    return s.albedo*light+s.emission;
}
[shader("raygeneration")]
void main() {
    uint2 pixel=DispatchRaysIndex().xy; float2 size=float2(DispatchRaysDimensions().xy);
    float2 uv=(float2(pixel)+0.5)/size;
    float4 p=mul(frame.inv_projection,float4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0)); p/=p.w;
    float3 eye=mul(frame.camera_world,float4(0,0,0,1)).xyz;
    float3 forward=-mul(frame.camera_world,float4(0,0,1,0)).xyz;
    float3 origin=eye,direction=normalize(mul(frame.camera_world,float4(p.xyz,0)).xyz);
    if(frame.camera.x>0.5) {origin=mul(frame.camera_world,float4(p.xyz,1)).xyz; direction=forward;}
    Surface primary=(Surface)0;
    RayDesc ray={origin,frame.camera.x>0.5?0.001:frame.settings.w/max(dot(direction,forward),0.001),direction,frame.camera.y};
    TraceRay(scene,RAY_FLAG_NONE,1,0,0,0,ray,primary);
    guide_image[pixel]=float4(primary.normal,primary.hit>0.5?dot(primary.position-eye,forward):0.0);
    indirect_image[pixel]=0.0; shadow_image0[pixel]=1.0; shadow_image1[pixel]=1.0;
    if(primary.hit<0.5)return;
    uint seed=pixel.x+pixel.y*uint(size.x)+uint(frame.settings.x)*1442695041u+1u;
    if(frame.sun.w>0.5) {
        float shadows[8];
        for(uint l=0;l<8;l++)shadows[l]=1.0;
        uint samples=clamp(uint(frame.settings.z),1u,4u);
        if(any(frame.sun.rgb>0.0) && dot(primary.normal,frame.sun_direction.xyz)>0.0) {
            shadows[0]=0.0;
            for(uint s=0;s<samples;s++)
                shadows[0]+=visibility(primary.position,primary.normal,area_ray(frame.sun_direction.xyz,frame.sun_direction.w,seed),frame.camera.w)/float(samples);
        }
        for(uint l=0;l<7;l++) {
            float3 delta=frame.point_position[l].xyz-primary.position; float distance=length(delta);
            if(frame.point_position[l].w<=0.0 || distance>=frame.point_position[l].w || distance<0.005)continue;
            if(dot(primary.normal,delta)<=0.0)continue;
            shadows[l+1]=0.0;
            for(uint s=0;s<samples;s++)
                shadows[l+1]+=visibility(primary.position,primary.normal,area_ray(delta/distance,frame.point_colour[l].w/distance,seed),distance)/float(samples);
        }
        shadow_image0[pixel]=float4(shadows[0],shadows[1],shadows[2],shadows[3]);
        shadow_image1[pixel]=float4(shadows[4],shadows[5],shadows[6],shadows[7]);
    }
    if(frame.sky.w>0.5) {
        float3 sum=0.0; uint samples=clamp(uint(frame.settings.y),1u,16u);
        for(uint s=0;s<samples;s++) {
            Surface bounce=(Surface)0;
            // Diffuse radiance needs a broad footprint; mip filtering also
            // bounds high-frequency texture variance before reconstruction.
            bounce.cone=0.02;
            float3 bounce_direction=cosine_ray(primary.normal,seed);
            RayDesc bounce_ray={primary.position+primary.normal*0.015,0.002,bounce_direction,frame.camera.w};
            TraceRay(scene,RAY_FLAG_NONE,4,0,0,0,bounce_ray,bounce);
            sum+=bounce.hit>0.5?illumination(bounce):frame.sky.rgb;
        }
        // Cosine-weighted hemisphere integration: E/pi is mean radiance.
        indirect_image[pixel]=float4(sum/float(samples),1.0);
    }
}
#elif defined(SCENE_MISS)
[shader("miss")]
void main(inout Surface result) {result.visible=1.0;}
#elif defined(SCENE_ANY_HIT)
[shader("anyhit")]
void main(inout Surface result,Attributes attributes) {
    uint4 material=geometry.Load4(InstanceID()*16); uint i=material.x+3*PrimitiveIndex();
    Vertex a=vertex_at(i),b=vertex_at(i+1),c=vertex_at(i+2);
    float3 w=float3(1.0-attributes.bary.x-attributes.bary.y,attributes.bary);
    if(colours.SampleLevel(colour_sampler,float3(hit_uv(a,b,c,w),a.emission_layer.w),0.0).a*a.diffuse.a<asfloat(material.z))IgnoreHit();
}
#elif defined(SCENE_CLOSEST_HIT)
[shader("closesthit")]
void main(inout Surface result,Attributes attributes) {
    uint4 material=geometry.Load4(InstanceID()*16); uint i=material.x+3*PrimitiveIndex();
    Vertex a=vertex_at(i),b=vertex_at(i+1),c=vertex_at(i+2);
    float3 w=float3(1.0-attributes.bary.x-attributes.bary.y,attributes.bary);
    float3 n=a.normal_v.xyz*w.x+b.normal_v.xyz*w.y+c.normal_v.xyz*w.z;
    result.normal=normalize(mul(n,(float3x3)WorldToObject3x4()));
    if(dot(result.normal,WorldRayDirection())>0.0)result.normal=-result.normal;
    result.position=WorldRayOrigin()+WorldRayDirection()*RayTCurrent();
    result.distance=RayTCurrent(); result.hit=1.0;
    float3 pa=mul(ObjectToWorld3x4(),float4(a.position_u.xyz,1)).xyz;
    float3 pb=mul(ObjectToWorld3x4(),float4(b.position_u.xyz,1)).xyz;
    float3 pc=mul(ObjectToWorld3x4(),float4(c.position_u.xyz,1)).xyz;
    float density=max(length(float2(b.position_u.w-a.position_u.w,b.normal_v.w-a.normal_v.w))/max(length(pb-pa),0.001),
                      length(float2(c.position_u.w-a.position_u.w,c.normal_v.w-a.normal_v.w))/max(length(pc-pa),0.001));
    uint width,height,layers,levels; colours.GetDimensions(0,width,height,layers,levels);
    float lod=max(log2(max(result.cone*result.distance*density*float(width),1.0)),0.0);
    float3 colour=colours.SampleLevel(colour_sampler,float3(hit_uv(a,b,c,w),a.emission_layer.w),lod).rgb;
    result.albedo=linear_colour(colour)*saturate(a.diffuse.rgb);
    result.emission=(material.y&1u)!=0u?a.emission_layer.rgb:linear_colour(colour*a.emission_layer.rgb);
}
#endif
