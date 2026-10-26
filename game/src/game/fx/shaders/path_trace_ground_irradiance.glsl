#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform readonly image2D raw_diffuse;
layout(rgba16f,set=0,binding=1) uniform readonly image2D raw_guide;
layout(rgba16f,set=0,binding=2) uniform readonly image2D raw_sun;
layout(rgba16f,set=0,binding=3) uniform readonly image2D previous_indirect;
layout(rgba16f,set=0,binding=4) uniform readonly image2D previous_guide;
layout(rgba16f,set=0,binding=5) uniform writeonly image2D result_indirect;
layout(rgba16f,set=0,binding=7) uniform readonly image2D previous_sun;
layout(rgba16f,set=0,binding=8) uniform writeonly image2D result_sun;
layout(std140,set=0,binding=6) uniform Frame {
    mat4 inv_projection;mat4 camera_world;mat4 previous_view_projection;
    mat4 previous_view;mat4 previous_inverse_view_projection;
    vec4 settings; // reusable history, indirect cap, orthographic, direct cap
} frame;
shared vec4 tile_guide[144];
shared vec4 tile_indirect[144];
shared vec3 tile_sun[144];
shared vec3 tile_world[144];

vec3 finite_signal(vec3 value) {
    return any(isnan(value))||any(isinf(value))?vec3(0.0):clamp(value,0.0,60000.0);
}
vec3 position_at(ivec2 p,float depth,ivec2 size) {
    vec2 uv=(vec2(p)+.5)/vec2(size);
    vec4 near=frame.inv_projection*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0);near/=near.w;
    vec3 view=frame.settings.z>.5?vec3(near.xy,-depth):near.xyz*(depth/-near.z);
    return (frame.camera_world*vec4(view,1.0)).xyz;
}
vec3 old_position(ivec2 p,float depth,ivec2 size) {
    vec2 uv=(vec2(p)+.5)/vec2(size);
    vec4 near=frame.previous_inverse_view_projection*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0);near/=near.w;
    vec3 eye=-(transpose(mat3(frame.previous_view))*frame.previous_view[3].xyz);
    vec3 forward=-vec3(frame.previous_view[0][2],frame.previous_view[1][2],frame.previous_view[2][2]);
    float near_depth=dot(near.xyz-eye,forward);
    return frame.settings.z>.5?near.xyz+forward*(depth-near_depth):eye+(near.xyz-eye)*(depth/near_depth);
}
// Use depth geometry for plane rejection: painted shading relief is not the
// plane of the terrain. The shorter valid side avoids crossing silhouettes.
vec3 surface_plane(int centre,vec3 world,vec3 normal) {
    vec3 tangent[2];
    for(int axis=0;axis<2;axis++) {
        int step_=axis==0?1:12,a=centre-step_,b=centre+step_;
        vec3 da=world-tile_world[a],db=tile_world[b]-world;
        bool va=tile_guide[a].w>0.0,vb=tile_guide[b].w>0.0;
        if(!va&&!vb)return normal;
        tangent[axis]=va&&(!vb||dot(da,da)<dot(db,db))?da:db;
    }
    vec3 plane=cross(tangent[0],tangent[1]);
    if(dot(plane,plane)<1e-16)return normal;
    plane=normalize(plane);return dot(plane,normal)<0.0?-plane:plane;
}
void main() {
    ivec2 size=imageSize(result_indirect),p=ivec2(gl_GlobalInvocationID.xy);
    ivec2 origin=ivec2(gl_WorkGroupID.xy)*8-2;
    for(uint i=gl_LocalInvocationIndex;i<144u;i+=64u) {
        ivec2 q=origin+ivec2(i%12u,i/12u);
        vec4 g=vec4(0),light=vec4(0);vec3 world=vec3(0),sun=vec3(0);
        if(all(greaterThanEqual(q,ivec2(0)))&&all(lessThan(q,size))) {
            g=imageLoad(raw_guide,q);light=imageLoad(raw_diffuse,q);
            sun=finite_signal(imageLoad(raw_sun,q).rgb);
            light.rgb=finite_signal(light.rgb-sun);
            if(g.w>0.0)world=position_at(q,g.w,size);
        }
        tile_guide[i]=g;tile_indirect[i]=light;tile_sun[i]=sun;tile_world[i]=world;
    }
    barrier();
    if(any(greaterThanEqual(p,size)))return;
    int centre=(int(gl_LocalInvocationID.y)+2)*12+int(gl_LocalInvocationID.x)+2;
    vec4 guide=tile_guide[centre],light=tile_indirect[centre];
    // This helper has no owner outside planted upward-facing receivers.
    if(guide.w<=0.0||guide.y<.35) {
        imageStore(result_indirect,p,vec4(0));imageStore(result_sun,p,vec4(0));return;
    }
    vec3 world=tile_world[centre],normal=normalize(guide.xyz);
    vec3 plane=surface_plane(centre,world,normal);
    float footprint=abs(frame.inv_projection[1][1])*2.0/float(size.y)*(frame.settings.z>.5?1.0:guide.w);
    float tolerance=max(max(.01,footprint*.5),guide.w*.00075);
    float reach=max(.1,footprint*5.0);
    vec3 sum=vec3(0),low=vec3(60000),high=vec3(0);float weight=0.0;
    vec3 sun_sum=vec3(0),sun_low=vec3(60000),sun_high=vec3(0);
    for(int y=-2;y<=2;y++)for(int x=-2;x<=2;x++) {
        int at=centre+y*12+x;vec4 g=tile_guide[at];
        float agreement=dot(normal,g.xyz);
        if(g.w<=0.0||g.y<.35||agreement<.8||tile_indirect[at].a!=light.a)continue;
        vec3 delta=tile_world[at]-world;float error=abs(dot(delta,plane));
        if(error>tolerance||length(delta)>reach)continue;
        float w=exp(-float(x*x+y*y)*.125)*pow(max(agreement,0.0),4.0)*exp(-error/max(tolerance,.001));
        vec3 sample_=tile_indirect[at].rgb;sum+=sample_*w;weight+=w;
        low=min(low,sample_);high=max(high,sample_);
        sun_sum+=tile_sun[at]*w;sun_low=min(sun_low,tile_sun[at]);sun_high=max(sun_high,tile_sun[at]);
    }
    vec3 value=weight>0.0?sum/weight:light.rgb;float age=1.0;
    vec3 sun_value=weight>0.0?sun_sum/weight:tile_sun[centre];float sun_age=1.0;
    if(frame.settings.x>.5) {
        vec4 clip=frame.previous_view_projection*vec4(world,1.0);
        vec2 uv=vec2(clip.x,-clip.y)/clip.w*.5+.5;
        if(clip.w>0.0&&all(greaterThanEqual(uv,vec2(0)))&&all(lessThan(uv,vec2(1)))) {
            vec2 pixel=uv*vec2(size)-.5,blend=fract(pixel);ivec2 base=ivec2(floor(pixel));
            vec3 previous=vec3(0);float total=0.0,previous_age=0.0;
            vec3 old_sun_sum=vec3(0);float sun_total=0.0,old_sun_age=0.0;
            for(int y=0;y<2;y++)for(int x=0;x<2;x++) {
                ivec2 q=base+ivec2(x,y);
                if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,size)))continue;
                vec4 g=imageLoad(previous_guide,q),old=imageLoad(previous_indirect,q);
                if(g.w<=0.0||g.y<.35||old.a<.5||dot(normal,g.xyz)<.8)continue;
                vec3 delta=old_position(q,g.w,size)-world;
                if(abs(dot(delta,plane))>tolerance||length(delta)>reach)continue;
                float w=(x==0?1.0-blend.x:blend.x)*(y==0?1.0-blend.y:blend.y);
                previous+=old.rgb*w;previous_age+=old.a*w;total+=w;
                vec4 old_sun=imageLoad(previous_sun,q);
                if(old_sun.a>.5) {old_sun_sum+=old_sun.rgb*w;old_sun_age+=old_sun.a*w;sun_total+=w;}
            }
            if(total>.01) {
                // Fresh current samples bound old indirect after an occluder or
                // light changes. In particular a newly dark region cannot retain
                // a bright cache merely because its receiving plane is unchanged.
                previous=clamp(previous/total,low,high);
                age=min(previous_age/total+1.0,max(frame.settings.y,1.0));
                value=mix(value,previous,1.0-1.0/age);
            }
            if(sun_total>.01) {
                // Current visibility bounds the separate short direct history.
                // A newly blocked/open neighbourhood drops its old light/shadow
                // immediately; native blade shadow ATTENUATION remains current.
                vec3 previous_sun_value=clamp(old_sun_sum/sun_total,sun_low,sun_high);
                sun_age=min(old_sun_age/sun_total+1.0,max(frame.settings.w,1.0));
                sun_value=mix(sun_value,previous_sun_value,1.0-1.0/sun_age);
            }
        }
    }
    imageStore(result_indirect,p,vec4(finite_signal(value),age));
    imageStore(result_sun,p,vec4(finite_signal(sun_value),sun_age));
}
