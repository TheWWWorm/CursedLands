#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform readonly image2D raw_diffuse;
layout(rgba16f,set=0,binding=1) uniform readonly image2D raw_guide;
layout(rgba16f,set=0,binding=2) uniform readonly image2D raw_specular;
layout(rgba16f,set=0,binding=3) uniform readonly image2D raw_material;
layout(rgba16f,set=0,binding=4) uniform readonly image2D previous_diffuse;
layout(rgba16f,set=0,binding=5) uniform readonly image2D previous_guide;
layout(rgba16f,set=0,binding=6) uniform readonly image2D previous_specular;
layout(rgba16f,set=0,binding=7) uniform readonly image2D previous_material;
layout(rgba16f,set=0,binding=8) uniform writeonly image2D result_diffuse;
layout(rgba16f,set=0,binding=9) uniform writeonly image2D result_guide;
layout(rgba16f,set=0,binding=10) uniform writeonly image2D result_specular;
layout(rgba16f,set=0,binding=11) uniform writeonly image2D result_material;
// Standard deviations, not squared moments: HDR variance can exceed FP16.
// A negative sign records a fully dark, well-supported current neighbourhood.
layout(rg16f,set=0,binding=13) uniform readonly image2D previous_noise;
layout(rg16f,set=0,binding=14) uniform writeonly image2D result_noise;
layout(r16f,set=0,binding=15) uniform readonly image2D previous_identity;
layout(r16f,set=0,binding=16) uniform writeonly image2D result_identity;
struct Motion {vec4 position[3];vec4 normal[3];};
layout(std430,set=0,binding=17) readonly buffer MotionBuffer {Motion motion[];};
layout(std140,set=0,binding=12) uniform Frame {
    mat4 inv_projection;mat4 camera_world;mat4 previous_view_projection;mat4 previous_view;
    vec4 sun;vec4 sun_direction;vec4 sky;vec4 settings;vec4 camera;vec4 center_radius;
    vec4 point_position[7];vec4 point_colour[7];vec4 path;
    mat4 previous_inverse_view_projection;
} frame;

// An 8x8 group shares its 2-pixel spatial halo. Keep the same 25-tap filter
// while fetching each input and reconstructing each position once per tile.
// Progressive accumulation has no spatial kernel and bypasses this cache.
shared vec4 tile_guide[144];
shared vec4 tile_material[144];
shared vec3 tile_diffuse[144];
shared vec3 tile_specular[144];
shared vec3 tile_world[144];

vec3 position_at(ivec2 pixel,float depth,ivec2 size) {
    vec2 uv=(vec2(pixel)+0.5)/vec2(size);
    vec4 near=frame.inv_projection*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0);near/=near.w;
    vec3 view=frame.camera.x>0.5?vec3(near.xy,-depth):near.xyz*(depth/-near.z);
    return (frame.camera_world*vec4(view,1.0)).xyz;
}
vec3 finite_signal(vec3 c) {
    return any(isnan(c))||any(isinf(c))?vec3(0.0):clamp(c,0.0,60000.0);
}
vec2 surface_at(float packed) {
    uint bits=uint(round(packed));
    return vec2(float(bits&63u)/63.0,float(bits>>6u)/31.0);
}
vec3 reflection_at(vec3 position,vec3 normal,vec3 eye,vec3 parallel_view) {
    vec3 view=frame.camera.x>0.5?parallel_view:normalize(eye-position);
    return reflect(-view,normalize(normal));
}
float glossy_compatibility(vec3 current,vec3 other,float roughness) {
    // A GGX-shaped angular confidence, not a second BRDF evaluation. The
    // reflection lobe scales with 2*alpha, where alpha=roughness^2. Narrow lobes
    // cannot reuse the same surface's radiance after its viewing angle changes.
    float alpha=max(roughness,0.08);alpha*=alpha;
    vec3 delta=current-other;
    float overlap=1.0/(1.0+dot(delta,delta)/(4.0*alpha*alpha));
    return overlap*overlap;
}
float spatial_variance(vec3 sum,vec3 squares,float weight,float weight_squared) {
    // Centred moments avoid cancellation on a constant, bright HDR surface.
    // Correct for unequal weights; an isolated sample has no spatial estimate.
    float divisor=weight-weight_squared/max(weight,0.0001);
    if(divisor<0.0001)return 0.0;
    vec3 variance=max((squares-sum*sum/max(weight,0.0001))/divisor,vec3(0.0));
    return max(variance.x,max(variance.y,variance.z));
}
float finite_sigma(float sigma) {
    return isnan(sigma)||isinf(sigma)?0.0:clamp(abs(sigma),0.0,60000.0);
}
vec3 previous_position(ivec2 p,float depth,ivec2 size) {
    vec2 uv=(vec2(p)+0.5)/vec2(size);
    vec4 near=frame.previous_inverse_view_projection*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0);
    near/=near.w;
    vec3 eye=-(transpose(mat3(frame.previous_view))*frame.previous_view[3].xyz);
    vec3 forward=-vec3(frame.previous_view[0][2],frame.previous_view[1][2],frame.previous_view[2][2]);
    float near_depth=dot(near.xyz-eye,forward);
    return frame.camera.x>0.5?near.xyz+forward*(depth-near_depth):eye+(near.xyz-eye)*(depth/near_depth);
}
void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy),size=imageSize(raw_diffuse);
    bool progressive=frame.path.y>8.0;
    if(!progressive) {
        ivec2 origin=ivec2(gl_WorkGroupID.xy)*8-2;
        for(uint i=gl_LocalInvocationIndex;i<144u;i+=64u) {
            ivec2 q=origin+ivec2(i%12u,i/12u);
            vec4 g=vec4(0),m=vec4(0);vec3 d=vec3(0),s=vec3(0),w=vec3(0);
            if(all(greaterThanEqual(q,ivec2(0)))&&all(lessThan(q,size))) {
                g=imageLoad(raw_guide,q);m=imageLoad(raw_material,q);
                d=finite_signal(imageLoad(raw_diffuse,q).rgb);s=finite_signal(imageLoad(raw_specular,q).rgb);
                if(g.w>0.0)w=position_at(q,g.w,size);
            }
            tile_guide[i]=g;tile_material[i]=m;tile_diffuse[i]=d;tile_specular[i]=s;tile_world[i]=w;
        }
        // Out-of-bounds lanes still populate the halo and reach this barrier.
        barrier();
    }
    if(any(greaterThanEqual(p,size)))return;
    int centre=(int(gl_LocalInvocationID.y)+2)*12+int(gl_LocalInvocationID.x)+2;
    vec4 guide=progressive?imageLoad(raw_guide,p):tile_guide[centre];
    vec4 material=progressive?imageLoad(raw_material,p):tile_material[centre];
    float identity=imageLoad(raw_diffuse,p).a;
    imageStore(result_identity,p,vec4(identity,0.0,0.0,0.0));
    imageStore(result_guide,p,guide);imageStore(result_material,p,material);
    if(guide.w<=0.0) {
        imageStore(result_diffuse,p,vec4(0.0));imageStore(result_specular,p,vec4(0.0));
        imageStore(result_noise,p,vec4(0.0));return;
    }
    vec3 world=progressive?position_at(p,guide.w,size):tile_world[centre];
    vec2 surface=surface_at(material.w);
    vec3 eye=frame.camera_world[3].xyz,parallel_view=frame.camera_world[2].xyz;
    vec3 reflection=reflection_at(world,guide.xyz,eye,parallel_view);
    float footprint=frame.camera.x>0.5?abs(frame.inv_projection[1][1])*2.0/float(size.y):
        abs(frame.inv_projection[1][1])*2.0*guide.w/float(size.y);
    float plane_tolerance=max(0.025,footprint*0.5);
    int radius=progressive?0:2;
    vec3 dlo=vec3(1e20),dhi=vec3(0.0),slo=vec3(1e20),shi=vec3(0.0);
    vec3 centre_d=progressive?finite_signal(imageLoad(raw_diffuse,p).rgb):tile_diffuse[centre];
    vec3 centre_s=progressive?finite_signal(imageLoad(raw_specular,p).rgb):tile_specular[centre];
    vec3 dsum=vec3(0.0),ssum=vec3(0.0),dsquares=vec3(0.0),ssquares=vec3(0.0);
    float dw=0.0,sw=0.0,dw2=0.0,sw2=0.0;
    int dcount=0,scount=0;float dpeak=0.0,speak=0.0;
    for(int y=-radius;y<=radius;y++)for(int x=-radius;x<=radius;x++) {
        ivec2 q=p+ivec2(x,y);
        if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,size)))continue;
        int at=centre+y*12+x;
        vec4 g=progressive?imageLoad(raw_guide,q):tile_guide[at],m=progressive?imageLoad(raw_material,q):tile_material[at];
        vec2 other_surface=surface_at(m.w);
        if(g.w<=0.0||dot(guide.xyz,g.xyz)<0.94||any(greaterThan(abs(other_surface-surface),vec2(0.15))))continue;
        vec3 other_world=progressive?position_at(q,g.w,size):tile_world[at],delta=other_world-world;
        float plane=abs(dot(delta,guide.xyz));
        if(plane>plane_tolerance||length(delta)>max(0.15,footprint*5.0))continue;
        float weight=exp(-float(x*x+y*y)*0.5)*exp(-plane/max(plane_tolerance,0.001));
        vec3 d=progressive?finite_signal(imageLoad(raw_diffuse,q).rgb):tile_diffuse[at];
        vec3 s=progressive?finite_signal(imageLoad(raw_specular,q).rgb):tile_specular[at];
        dcount++;dpeak=max(dpeak,max(d.x,max(d.y,d.z)));
        if(length(m.rgb-material.rgb)<0.25) {scount++;speak=max(speak,max(s.x,max(s.y,s.z)));}
        dw+=weight;dlo=min(dlo,d);dhi=max(dhi,d);
        vec3 dd=d-centre_d;dsum+=dd*weight;dsquares+=dd*dd*weight;dw2+=weight*weight;
        // Glossy radiance must not smear across different material colours.
        if(abs(x)<=1&&abs(y)<=1&&length(m.rgb-material.rgb)<0.25) {
            float glossy_weight=weight*glossy_compatibility(reflection,
                reflection_at(other_world,g.xyz,eye,parallel_view),min(surface.x,other_surface.x));
            sw+=glossy_weight;slo=min(slo,s);shi=max(shi,s);
            vec3 sd=s-centre_s;ssum+=sd*glossy_weight;ssquares+=sd*sd*glossy_weight;sw2+=glossy_weight*glossy_weight;
        }
    }
    // Reuse the centred first moments for the estimate too: a constant HDR
    // field stays exact instead of accumulating weighted-sum roundoff.
    vec3 diffuse=dw>0.0001?centre_d+dsum/dw:vec3(0.0);
    vec3 specular=sw>0.0001?centre_s+ssum/sw:vec3(0.0);
    float dvariance=spatial_variance(dsum,dsquares,dw,dw2),svariance=spatial_variance(ssum,ssquares,sw,sw2);
    // Two consecutive dark neighbourhoods provide stronger evidence of a
    // lighting change than one missing Monte Carlo sample. Small/edge kernels
    // cannot trigger this, and the previous sign travels through guide checks.
    bool ddark=dcount>=20&&dpeak<0.00001,sdark=scount>=20&&speak<0.00001;
    float age=1.0,specular_age=1.0;
    uint instance=(packHalf2x16(vec2(identity,0.0))&65535u)-0x3c00u;
    bool valid_instance=identity>=1.0&&instance<uint(motion.length());
    vec3 old_position=world,old_normal=guide.xyz;
    bool valid_motion=false;
    if(valid_instance) {
        valid_motion=motion[instance].normal[0].w>0.5;
        if(motion[instance].normal[1].w>0.5) {
            vec4 position=vec4(world,1.0);
            old_position=vec3(dot(motion[instance].position[0],position),
                dot(motion[instance].position[1],position),dot(motion[instance].position[2],position));
            // Inverse transpose of current->previous, prepared once per
            // placement. Rotation, nonuniform scale and shear remain valid.
            old_normal=normalize(vec3(dot(motion[instance].normal[0].xyz,guide.xyz),
                dot(motion[instance].normal[1].xyz,guide.xyz),dot(motion[instance].normal[2].xyz,guide.xyz)));
        }
    }
    vec4 previous=frame.previous_view_projection*vec4(old_position,1.0);
    vec2 uv=vec2(previous.x,-previous.y)/previous.w*0.5+0.5;
    if(valid_motion&&frame.camera.z>0.5&&(!progressive||frame.path.z>0.5)&&previous.w>0.0&&
        all(greaterThanEqual(uv,vec2(0.0)))&&all(lessThan(uv,vec2(1.0)))) {
        // An unchanged progressive camera uses the identical pixel exactly;
        // repeated subpixel interpolation would blur a converging still image.
        vec2 pixel=progressive?vec2(p):uv*vec2(size)-0.5;
        ivec2 base=ivec2(floor(pixel));vec2 blend=fract(pixel);
        vec4 old=vec4(0.0);vec3 old_specular=vec3(0.0);float total=0.0,specular_weight=0.0;
        float specular_confidence=0.0,specular_new_weight=0.0;
        float old_dvariance=0.0,old_svariance=0.0;
        float old_ddark=0.0,old_sdark=0.0;
        vec3 view_normal=(mat3(frame.previous_view)*old_normal);
        vec3 old_eye=-(transpose(mat3(frame.previous_view))*frame.previous_view[3].xyz);
        vec3 old_parallel_view=vec3(frame.previous_view[0][2],frame.previous_view[1][2],frame.previous_view[2][2]);
        float reach=max(0.1,footprint*2.5/max(abs(view_normal.z),0.1));
        for(int y=0;y<2;y++)for(int x=0;x<2;x++) {
            ivec2 q=base+ivec2(x,y);
            if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,size)))continue;
            float w=(x==0?1.0-blend.x:blend.x)*(y==0?1.0-blend.y:blend.y);
            if(w<=0.0)continue;
            if(imageLoad(previous_identity,q).r!=identity)continue;
            vec4 g=imageLoad(previous_guide,q),m=imageLoad(previous_material,q);
            vec2 old_surface=surface_at(m.w);
            if(g.w<=0.0||dot(g.xyz,old_normal)<=0.96||any(greaterThanEqual(abs(old_surface-surface),vec2(0.05)))||length(m.rgb-material.rgb)>=0.15)continue;
            vec3 old_world=previous_position(q,g.w,size),delta=old_world-old_position;
            // Compare surfaces in world space. Adjacent pixels on a slope
            // legitimately have different depths; unrelated layers still fail.
            if(abs(dot(delta,old_normal))>plane_tolerance||length(delta)>reach)continue;
            vec2 sigma=imageLoad(previous_noise,q).rg;
            bvec2 was_dark=lessThan(sigma,vec2(0.0));
            sigma=vec2(finite_sigma(sigma.x),finite_sigma(sigma.y));
            vec4 history=imageLoad(previous_diffuse,q);
            if(history.a>=1.0) {
                old+=vec4(finite_signal(history.rgb),history.a)*w;total+=w;
                old_dvariance+=sigma.x*sigma.x*w;
                if(was_dark.x)old_ddark+=w;
            }
            vec4 glossy_history=imageLoad(previous_specular,q);
            if(glossy_history.a>=1.0) {
                float confidence=progressive?1.0:glossy_compatibility(reflection,
                    reflection_at(old_world,g.xyz,old_eye,old_parallel_view),min(surface.x,old_surface.x));
                // Variance-aware colour bounds are deliberately less aggressive.
                // Use a narrower temporal lobe to retain moving highlight detail
                // without clamping away legitimate Monte Carlo fluctuations.
                confidence=confidence*confidence*confidence;
                float new_weight=w*confidence/min(1.0+glossy_history.a,frame.path.y);
                float history_weight=w*confidence-new_weight;
                specular_confidence+=w*confidence;specular_new_weight+=new_weight;
                old_specular+=finite_signal(glossy_history.rgb)*history_weight;specular_weight+=history_weight;
                old_svariance+=sigma.y*sigma.y*history_weight;
                if(was_dark.y)old_sdark+=history_weight;
            }
        }
        if(total>0.01) {
            // Partially disoccluded pixels get less historical confidence.
            age=min(1.0+old.a,frame.path.y);
            if(ddark&&old_ddark>total*0.9)age=min(age,2.0);
            old.rgb/=total;
            old_dvariance/=total;
            if(!progressive) {
                float margin=3.0*sqrt(max(dvariance,old_dvariance)*dw2/max(dw*dw,0.0001));
                old.rgb=clamp(old.rgb,dlo-(dhi-dlo)*0.15-0.01-margin,dhi+(dhi-dlo)*0.15+0.01+margin);
            }
            diffuse=mix(diffuse,old.rgb,1.0-1.0/age);
            dvariance=mix(dvariance,old_dvariance,1.0-1.0/age);
        }
        if(specular_weight>0.0) {
            old_specular/=specular_weight;
            old_svariance/=specular_weight;
            if(!progressive) {
                float margin=3.0*sqrt(max(svariance,old_svariance)*sw2/max(sw*sw,0.0001));
                old_specular=clamp(old_specular,slo-(shi-slo)*0.1-0.01-margin,shi+(shi-slo)*0.1+0.01+margin);
            }
            // Store effective confidence independently. Multiplying the blend
            // itself prevents an eight-frame diffuse age from restoring stale
            // glossy history immediately after a view-dependent rejection.
            // Keep the small new-sample weight explicit. Recovering it by
            // subtracting a nearly-one history weight loses precision during
            // long progressive accumulation on the DX12 compute path.
            float current_weight=max(1.0-specular_confidence,0.0)+specular_new_weight;
            specular_age=min(1.0/current_weight,frame.path.y);
            if(sdark&&old_sdark>specular_weight*0.9)specular_age=min(specular_age,2.0);
            specular=mix(specular,old_specular,1.0-1.0/specular_age);
            svariance=mix(svariance,old_svariance,1.0-1.0/specular_age);
        }
    }
    imageStore(result_diffuse,p,vec4(finite_signal(diffuse),age));
    imageStore(result_specular,p,vec4(finite_signal(specular),specular_age));
    vec2 sigma=vec2(finite_sigma(sqrt(max(dvariance,0.0))),finite_sigma(sqrt(max(svariance,0.0))));
    imageStore(result_noise,p,vec4(ddark?-sigma.x:sigma.x,sdark?-sigma.y:sigma.y,0.0,0.0));
}
