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
    float4 path;             // Continuation bounces, history limit, stationary, reserved.
};
[[vk::binding(4,0)]] ConstantBuffer<Frame> frame : register(b400000);
struct Vertex { float4 position_u; float4 normal_v; float4 diffuse; float4 emission_layer; };
struct Surface { float3 position; float distance; float3 normal; float hit; float3 albedo; float visible; float3 emission; float cone; float roughness; float metalness; float specular; float reserved; float3 geometric_normal; float padding; };
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
    RayDesc ray={p+n*0.015,0.002,direction,max(reach-0.025,0.003)};
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
    float chance=clamp(max(reflectance.x,max(reflectance.y,reflectance.z)),0.1,0.9);
    pdf=(1.0-chance)*nl/PI+chance*d*nh/max(4.0*vh,1e-6);
}
float3 sample_bsdf(Surface s,float3 v,inout uint seed) {
    float3 reflectance=f0(s);
    float chance=clamp(max(reflectance.x,max(reflectance.y,reflectance.z)),0.1,0.9);
    if(random(seed)>=chance)return cosine_ray(s.normal,seed);
    float a=s.roughness*s.roughness,u=random(seed),phi=random(seed)*2.0*PI;
    float c=sqrt((1.0-u)/max(1.0+(a*a-1.0)*u,1e-6));
    float r=sqrt(max(1.0-c*c,0.0));
    float3 t,b;basis(s.normal,t,b);
    float3 h=normalize(t*(r*cos(phi))+b*(r*sin(phi))+s.normal*c);
    return reflect(-v,h);
}
void direct_light(Surface s,float3 v,inout uint seed,out float3 diffuse,out float3 specular) {
    diffuse=0.0;specular=0.0;
    for(uint i=0;i<8;i++) {
        float3 direction,colour;float reach;
        if(i==0) {
            if(!any(frame.sun.rgb>0.0))continue;
            direction=area_ray(frame.sun_direction.xyz,frame.sun_direction.w,seed);
            colour=frame.sun.rgb;reach=frame.camera.w;
        } else {
            float4 lamp=frame.point_position[i-1];
            float3 delta=lamp.xyz-s.position;float distance=length(delta);
            if(lamp.w<=0.0||distance>=lamp.w||distance<0.005)continue;
            direction=area_ray(delta/distance,frame.point_colour[i-1].w/distance,seed);
            colour=frame.point_colour[i-1].rgb*max(1.0-distance*distance/(lamp.w*lamp.w),0.0);
            reach=distance;
        }
        float cosine=dot(s.normal,direction);
        if(cosine<=0.0)continue;
        float3 d,sp;float pdf;bsdf(s,v,direction,d,sp,pdf);
        // Authored game light values are diffuse irradiance / pi. Convert
        // them to the radiance scale used by the normalized BRDF.
        float3 incoming=colour*(PI*cosine*visibility(s.position,s.geometric_normal,direction,reach));
        diffuse+=d*incoming;specular+=sp*incoming;
    }
}
void path_sample(Surface primary,float3 view,inout uint seed,out float3 diffuse,out float3 specular) {
    direct_light(primary,view,seed,diffuse,specular);
    Surface current=primary;
    float3 v=view,weight_d=1.0,weight_s=1.0;
    uint bounces=clamp(uint(frame.path.x),1u,4u);
    for(uint depth=0;depth<bounces;depth++) {
        float3 direction=sample_bsdf(current,v,seed),d,sp;float pdf;
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
        RayDesc ray={current.position+current.geometric_normal*0.015,0.002,direction,frame.camera.w};
        TraceRay(scene,RAY_FLAG_NONE,4,0,0,0,ray,hit);
        if(hit.hit<0.5) {
            diffuse+=weight_d*frame.sky.rgb;specular+=weight_s*frame.sky.rgb;break;
        }
        float3 direct_d,direct_s;
        direct_light(hit,-direction,seed,direct_d,direct_s);
        float3 incoming=hit.emission+hit.albedo*direct_d+direct_s;
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
    uint seed=pixel.x+pixel.y*uint(size.x)+uint(frame.settings.x)*1442695041u+1u;
    float3 diffuse=0.0,specular=0.0;
    uint samples=clamp(uint(frame.settings.y),1u,16u);
    for(uint i=0;i<samples;i++) {
        float3 d,s;path_sample(primary,-direction,seed,d,s);diffuse+=d;specular+=s;
    }
    indirect_image[pixel]=float4(diffuse/float(samples),1.0);
    shadow_image0[pixel]=float4(specular/float(samples),1.0);
    shadow_image1[pixel]=float4(primary.albedo,primary.roughness+2.0*primary.metalness);
}
#elif defined(PATH_MISS)
[shader("miss")]
void main(inout Surface result) {result.visible=1.0;}
#elif defined(PATH_ANY_HIT)
[shader("anyhit")]
void main(inout Surface result,Attributes attributes) {
    uint4 material=geometry.Load4(InstanceID()*16); uint i=material.x+3*PrimitiveIndex();
    Vertex a=vertex_at(i),b=vertex_at(i+1),c=vertex_at(i+2);
    float3 w=float3(1.0-attributes.bary.x-attributes.bary.y,attributes.bary);
    if(colours.SampleLevel(colour_sampler,float3(hit_uv(a,b,c,w),a.emission_layer.w),0.0).a*a.diffuse.a<asfloat(material.z))IgnoreHit();
}
#elif defined(PATH_CLOSEST_HIT)
[shader("closesthit")]
void main(inout Surface result,Attributes attributes) {
    uint4 material=geometry.Load4(InstanceID()*16); uint i=material.x+3*PrimitiveIndex();
    Vertex a=vertex_at(i),b=vertex_at(i+1),c=vertex_at(i+2);
    float3 w=float3(1.0-attributes.bary.x-attributes.bary.y,attributes.bary);
    float3 n=a.normal_v.xyz*w.x+b.normal_v.xyz*w.y+c.normal_v.xyz*w.z;
    result.normal=normalize(mul(n,(float3x3)WorldToObject3x4()));
    result.position=WorldRayOrigin()+WorldRayDirection()*RayTCurrent();
    result.distance=RayTCurrent(); result.hit=1.0;
    float3 pa=mul(ObjectToWorld3x4(),float4(a.position_u.xyz,1)).xyz;
    float3 pb=mul(ObjectToWorld3x4(),float4(b.position_u.xyz,1)).xyz;
    float3 pc=mul(ObjectToWorld3x4(),float4(c.position_u.xyz,1)).xyz;
    result.geometric_normal=normalize(cross(pb-pa,pc-pa));
    if(dot(result.geometric_normal,WorldRayDirection())>0.0)result.geometric_normal=-result.geometric_normal;
    // Interpolated normals can point through a steep terrain facet. Offset
    // rays along the actual triangle and keep the shading hemisphere outside
    // it, rather than flipping the smooth normal beneath the triangle.
    if(dot(result.normal,result.geometric_normal)<0.0)result.normal=-result.normal;
    if(dot(result.normal,WorldRayDirection())>=0.0)result.normal=result.geometric_normal;
    float density=max(length(float2(b.position_u.w-a.position_u.w,b.normal_v.w-a.normal_v.w))/max(length(pb-pa),0.001),
                      length(float2(c.position_u.w-a.position_u.w,c.normal_v.w-a.normal_v.w))/max(length(pc-pa),0.001));
    uint width,height,layers,levels; colours.GetDimensions(0,width,height,layers,levels);
    float lod=max(log2(max(result.cone*result.distance*density*float(width),1.0)),0.0);
    float3 colour=colours.SampleLevel(colour_sampler,float3(hit_uv(a,b,c,w),a.emission_layer.w),lod).rgb;
    result.albedo=saturate(linear_colour(colour)*saturate(a.diffuse.rgb));
    result.roughness=max(float(material.w&255u)/255.0,0.08);
    result.metalness=float((material.w>>8u)&255u)/255.0;
    result.specular=float((material.w>>16u)&255u)/255.0;
    result.emission=(material.y&1u)!=0u?a.emission_layer.rgb:linear_colour(colour*a.emission_layer.rgb);
}
#endif
