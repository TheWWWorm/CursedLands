// Bounded dielectric camera transport. All rays use the shared scene; opaque
// primary lighting and NRD/RR remain unchanged. Smooth surfaces, RGB absorption.
[[vk::binding(39,0)]] ByteAddressBuffer dielectric_data : register(t3900000);
struct TransmissionControl { float4 state; };
[[vk::binding(40,0)]] ConstantBuffer<TransmissionControl> transmission_control : register(b4000000);
struct Dielectric { float3 sigma; float ior; uint kind; float thickness; };
Dielectric optical(Surface s) {
    uint at=instance_geometry.Load(s.instance_id*4u)*32u;
    float4 a=asfloat(dielectric_data.Load4(at)),b=asfloat(dielectric_data.Load4(at+16));
    Dielectric m;m.sigma=max(a.xyz,0.0);m.ior=max(a.w,1.0);m.kind=uint(b.x);m.thickness=max(b.y,0.0);return m;
}
float fresnel_dielectric(float cosine,float eta) {
    float c=saturate(cosine),s2=eta*eta*max(0.0,1.0-c*c);
    if(s2>=1.0)return 1.0;
    float t=sqrt(1.0-s2);
    float rs=(eta*c-t)/max(eta*c+t,1e-8),rp=(c-eta*t)/max(c+eta*t,1e-8);
    return .5*(rs*rs+rp*rp);
}
float3 opaque_radiance(Surface s,float3 direction,PathSampler sampler) {
    float3 d,sp,ds,sun;float2 distance;float4 dm,sm;
    path_sample(s,-direction,sampler,d,sp,distance,ds,sun,dm,sm);
    float3 ambient=float3(frame.sky_zenith.w,frame.sky_horizon.w,frame.sky_ground.w);
    return max(d,ambient*(1.0-s.metalness)*(1.0-f0(s)))*s.albedo+sp+s.emission;
}
float3 dielectric_path(Surface first,float3 direction,float3 eye,PathSampler sampler,out float3 terminal,out bool valid) {
    Surface hit=first;float3 weight=1.0;terminal=first.position;valid=true;
    float iors[4];float3 absorption[4];uint ids[4];uint stack=0u;
    // A back-facing first interface means the eye is inside this volume.
    Dielectric initial=optical(first);
    if(first.hit>1.5&&initial.kind!=3u) {
        iors[0]=initial.ior;absorption[0]=initial.sigma;ids[0]=first.instance_id;stack=1u;
        weight*=exp(-initial.sigma*length(first.position-eye));
    }
    for(uint crossing=0u;crossing<16u;crossing++) {
        Dielectric m=optical(hit);
        if(m.kind==0u){terminal=hit.position;return weight*opaque_radiance(hit,direction,sampler);}
        sampler.vertex=8u+crossing;
        float3 n=hit.normal; // Facing the incident ray, bounded by geometric face.
        float incoming=stack>0u?iors[stack-1u]:1.0;
        bool entering=hit.hit<1.5;
        float outgoing=entering?m.ior:(stack>1u?iors[stack-2u]:1.0);
        if(!entering&&m.kind!=3u&&(stack==0u||ids[stack-1u]!=hit.instance_id)){valid=false;return 0.0;}
        float eta=incoming/outgoing;
        float F=fresnel_dielectric(dot(-direction,n),eta);
        float3 bent=refract(direction,n,eta);
        float3 origin=hit.position;
        if(m.kind==3u) {
            // Parallel thin pane: both interfaces and the infinite internal
            // reflection series, with Beer attenuation for its actual oblique
            // interior distance. Net exiting direction stays parallel.
            eta=incoming/m.ior;F=fresnel_dielectric(dot(-direction,n),eta);
            bent=refract(direction,n,eta);
            float inside=m.thickness/max(abs(dot(bent,n)),1e-5);
            float3 A=exp(-m.sigma*inside);
            float3 T=(1.0-F)*(1.0-F)*A/max(1.0-F*F*A*A,1e-6);
            float3 R=F+(1.0-F)*(1.0-F)*F*A*A/max(1.0-F*F*A*A,1e-6);
            float chance=clamp(dot(R,float3(.2126,.7152,.0722)),.001,.999);
            if(path_random(sampler,14u).x<chance){weight*=R/chance;direction=reflect(direction,n);origin=surface_origin(hit,direction);}
            else {weight*=T/(1.0-chance);origin=surface_origin(hit,bent)+bent*inside;}
        } else if(F>=1.0||((m.kind!=1u||crossing>0u)&&path_random(sampler,14u).x<F)) {
            direction=reflect(direction,n);origin=surface_origin(hit,direction);
        } else {
            // Water's first Fresnel split is composed by the water shader;
            // subsequent interfaces and glass use the sampled split above.
            weight*=eta*eta;
            direction=normalize(bent);origin=surface_origin(hit,direction);
            if(entering) {
                if(stack>=4u){valid=false;return 0.0;}
                iors[stack]=m.ior;absorption[stack]=m.sigma;ids[stack]=hit.instance_id;stack++;
            } else stack--;
        }
        RayDesc ray={origin,0.0,direction,frame.camera.w};
        hit=(Surface)0;hit.cone=.002;
        TraceRay(scene,RAY_FLAG_NONE,9,0,0,0,ray,hit);
        float length_in_medium=hit.hit>.5?length(hit.position-origin):frame.camera.w;
        if(stack>0u)weight*=exp(-absorption[stack-1u]*length_in_medium);
        if(hit.hit<.5) {
            // Missing closed-glass exit is invalid geometry, not an infinitely
            // tinted world. Water is a surface bounding an open half volume.
            if(stack>0u&&initial.kind!=1u){valid=false;return 0.0;}
            terminal=origin+direction*frame.camera.w;
            return weight*sky_radiance(direction);
        }
    }
    // Limit exhaustion (e.g. repeated TIR) contributes zero to this bounded
    // path, never teleports through the object or returns unattenuated sky.
    return 0.0;
}
[shader("raygeneration")]
void main() {
    uint2 pixel=DispatchRaysIndex().xy;float2 size=float2(DispatchRaysDimensions().xy);
    float2 uv=(float2(pixel)+.5)/size;
    float4 p=mul(frame.inv_projection,float4(uv.x*2-1,1-uv.y*2,-1,1));p/=p.w;
    float3 eye=mul(frame.camera_world,float4(0,0,0,1)).xyz;
    float3 forward=-mul(frame.camera_world,float4(0,0,1,0)).xyz;
    float3 origin=eye,direction=normalize(mul(frame.camera_world,float4(p.xyz,0)).xyz);
    if(frame.camera.x>.5){origin=mul(frame.camera_world,float4(p.xyz,1)).xyz;direction=forward;}
    Surface first=(Surface)0;
    RayDesc ray={origin,frame.camera.x>.5?.001:frame.settings.w/max(dot(direction,forward),.001),direction,frame.camera.y};
    TraceRay(scene,RAY_FLAG_NONE,9,0,0,0,ray,first);
    if(first.hit<.5||optical(first).kind==0u) {indirect_image[pixel]=0;guide_image[pixel]=0;shadow_image0[pixel]=0;return;}
    float3 sum=0,terminal=0;bool all_valid=true;
    for(uint i=0u;i<2u;i++) {
        PathSampler sampler=path_sampler(uint(frame.settings.x)*2u+i,pixel.x+pixel.y*uint(size.x));
        bool valid;float3 endpoint;
        sum+=dielectric_path(first,direction,eye,sampler,endpoint,valid)*.5;
        terminal+=endpoint*.5;all_valid=all_valid&&valid;
    }
    if(!all_valid){indirect_image[pixel]=0;guide_image[pixel]=0;shadow_image0[pixel]=0;return;}
    float previous=transmission_control.state.x;
    if(previous>0.0)sum=lerp(sum,indirect_image[pixel].rgb,previous/(previous+1.0));
    indirect_image[pixel]=float4(min(max(sum,0.0),60000.0),optical(first).kind==1u?1.0:2.0);
    guide_image[pixel]=float4(first.normal,dot(first.position-eye,forward));
    shadow_image0[pixel]=float4(terminal,optical(first).kind);
}
