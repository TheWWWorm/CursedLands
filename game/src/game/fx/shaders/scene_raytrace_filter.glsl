#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform readonly image2D raw_gi;
layout(rgba16f,set=0,binding=1) uniform readonly image2D raw_guide;
layout(rgba16f,set=0,binding=2) uniform readonly image2D raw_shadow0;
layout(rgba16f,set=0,binding=3) uniform readonly image2D raw_shadow1;
layout(rgba16f,set=0,binding=4) uniform readonly image2D previous_gi;
layout(rgba16f,set=0,binding=5) uniform readonly image2D previous_guide;
layout(rgba16f,set=0,binding=6) uniform readonly image2D previous_shadow0;
layout(rgba16f,set=0,binding=7) uniform readonly image2D previous_shadow1;
layout(rgba16f,set=0,binding=8) uniform writeonly image2D result_gi;
layout(rgba16f,set=0,binding=9) uniform writeonly image2D result_guide;
layout(rgba16f,set=0,binding=10) uniform writeonly image2D result_shadow0;
layout(rgba16f,set=0,binding=11) uniform writeonly image2D result_shadow1;
layout(std140,set=0,binding=12) uniform Frame {
    mat4 inv_projection;
    mat4 camera_world;
    mat4 previous_view_projection;
    mat4 previous_view;
    vec4 sun;
    vec4 sun_direction;
    vec4 sky;
    vec4 settings;
    vec4 camera;
    vec4 center_radius;
    vec4 point_position[7];
    vec4 point_colour[7];
} frame;

vec3 position_at(ivec2 pixel,float depth,ivec2 size) {
    vec2 uv=(vec2(pixel)+0.5)/vec2(size);
    vec4 near=frame.inv_projection*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0);
    near/=near.w;
    vec3 view=frame.camera.x>0.5?vec3(near.xy,-depth):near.xyz*(depth/-near.z);
    return (frame.camera_world*vec4(view,1.0)).xyz;
}

void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy),size=imageSize(raw_gi);
    if(any(greaterThanEqual(p,size)))return;
    vec4 guide=imageLoad(raw_guide,p);
    imageStore(result_guide,p,guide);
    if(guide.w<=0.0) {
        imageStore(result_gi,p,vec4(0.0));
        imageStore(result_shadow0,p,vec4(1.0));
        imageStore(result_shadow1,p,vec4(1.0));
        return;
    }
    vec3 world=position_at(p,guide.w,size);
    float footprint=frame.camera.x>0.5?abs(frame.inv_projection[1][1])*2.0/float(size.y):
        abs(frame.inv_projection[1][1])*2.0*guide.w/float(size.y);
    float plane_tolerance=max(0.025,footprint*0.5);
    vec3 sum=vec3(0.0),lo=vec3(1e20),hi=vec3(0.0);
    vec4 shadows0=vec4(0.0),shadows1=vec4(0.0);
    vec4 shadow_min0=vec4(1.0),shadow_max0=vec4(0.0),shadow_min1=vec4(1.0),shadow_max1=vec4(0.0);
    float total=0.0,shadow_total=0.0;
    // A small cross-bilateral reconstruction. The plane test also rejects
    // parallel surfaces separated by a wall or a foreground silhouette.
    for(int y=-2;y<=2;y++)for(int x=-2;x<=2;x++) {
        ivec2 q=p+ivec2(x,y);
        if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,size)))continue;
        vec4 g=imageLoad(raw_guide,q);
        if(g.w<=0.0||dot(guide.xyz,g.xyz)<0.9)continue;
        vec3 delta=position_at(q,g.w,size)-world;
        float plane=abs(dot(delta,guide.xyz));
        if(plane>plane_tolerance||length(delta)>max(0.15,footprint*5.0))continue;
        float weight=exp(-float(x*x+y*y)*0.32)*exp(-plane/max(plane_tolerance,0.001));
        vec3 sample_gi=imageLoad(raw_gi,q).rgb;
        sum+=sample_gi*weight;total+=weight;
        lo=min(lo,sample_gi);hi=max(hi,sample_gi);
        if(abs(x)<=1&&abs(y)<=1) {
            vec4 s0=imageLoad(raw_shadow0,q),s1=imageLoad(raw_shadow1,q);
            shadows0+=s0*weight;shadows1+=s1*weight;
            shadow_min0=min(shadow_min0,s0);shadow_max0=max(shadow_max0,s0);
            shadow_min1=min(shadow_min1,s1);shadow_max1=max(shadow_max1,s1);
            shadow_total+=weight;
        }
    }
    vec3 gi=sum/max(total,0.0001);
    shadows0/=max(shadow_total,0.0001);shadows1/=max(shadow_total,0.0001);
    float age=1.0;
    vec4 previous=frame.previous_view_projection*vec4(world,1.0);
    vec2 uv=vec2(previous.x,-previous.y)/previous.w*0.5+0.5;
    if(frame.camera.z>0.5&&previous.w>0.0&&all(greaterThanEqual(uv,vec2(0.0)))&&all(lessThan(uv,vec2(1.0)))) {
        ivec2 q=ivec2(uv*vec2(size));
        vec4 g=imageLoad(previous_guide,q);
        float expected=-(frame.previous_view*vec4(world,1.0)).z;
        // Do not keep lighting on disoccluded/moving surfaces. History is
        // deliberately short so a moving caster does not leave a long trail.
        if(g.w>0.0&&abs(g.w-expected)<max(0.035,footprint*0.75)&&dot(g.xyz,guide.xyz)>0.94) {
            vec4 old=imageLoad(previous_gi,q);
            age=min(old.a+1.0,8.0);
            vec3 tolerance=(hi-lo)*0.15+vec3(0.01);
            gi=mix(gi,clamp(old.rgb,lo-tolerance,hi+tolerance),1.0-1.0/age);
            shadows0=mix(shadows0,clamp(imageLoad(previous_shadow0,q),shadow_min0,shadow_max0),0.5);
            shadows1=mix(shadows1,clamp(imageLoad(previous_shadow1,q),shadow_min1,shadow_max1),0.5);
        }
    }
    imageStore(result_gi,p,vec4(max(gi,vec3(0.0)),age));
    imageStore(result_shadow0,p,clamp(shadows0,0.0,1.0));
    imageStore(result_shadow1,p,clamp(shadows1,0.0,1.0));
}
