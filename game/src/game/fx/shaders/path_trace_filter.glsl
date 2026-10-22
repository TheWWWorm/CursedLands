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
layout(std140,set=0,binding=12) uniform Frame {
    mat4 inv_projection;mat4 camera_world;mat4 previous_view_projection;mat4 previous_view;
    vec4 sun;vec4 sun_direction;vec4 sky;vec4 settings;vec4 camera;vec4 center_radius;
    vec4 point_position[7];vec4 point_colour[7];vec4 path;
} frame;

vec3 position_at(ivec2 pixel,float depth,ivec2 size) {
    vec2 uv=(vec2(pixel)+0.5)/vec2(size);
    vec4 near=frame.inv_projection*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0);near/=near.w;
    vec3 view=frame.camera.x>0.5?vec3(near.xy,-depth):near.xyz*(depth/-near.z);
    return (frame.camera_world*vec4(view,1.0)).xyz;
}
vec3 finite_signal(vec3 c) {
    return any(isnan(c))||any(isinf(c))?vec3(0.0):clamp(c,0.0,60000.0);
}
void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy),size=imageSize(raw_diffuse);
    if(any(greaterThanEqual(p,size)))return;
    vec4 guide=imageLoad(raw_guide,p),material=imageLoad(raw_material,p);
    imageStore(result_guide,p,guide);imageStore(result_material,p,material);
    if(guide.w<=0.0) {
        imageStore(result_diffuse,p,vec4(0.0));imageStore(result_specular,p,vec4(0.0));return;
    }
    vec3 world=position_at(p,guide.w,size);
    float footprint=frame.camera.x>0.5?abs(frame.inv_projection[1][1])*2.0/float(size.y):
        abs(frame.inv_projection[1][1])*2.0*guide.w/float(size.y);
    float plane_tolerance=max(0.025,footprint*0.5);
    bool progressive=frame.path.y>8.0;
    int radius=progressive?0:2;
    vec3 diffuse=vec3(0.0),specular=vec3(0.0),dlo=vec3(1e20),dhi=vec3(0.0),slo=vec3(1e20),shi=vec3(0.0);
    float dw=0.0,sw=0.0;
    for(int y=-radius;y<=radius;y++)for(int x=-radius;x<=radius;x++) {
        ivec2 q=p+ivec2(x,y);
        if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,size)))continue;
        vec4 g=imageLoad(raw_guide,q),m=imageLoad(raw_material,q);
        if(g.w<=0.0||dot(guide.xyz,g.xyz)<0.94||abs(m.w-material.w)>0.15)continue;
        vec3 delta=position_at(q,g.w,size)-world;
        float plane=abs(dot(delta,guide.xyz));
        if(plane>plane_tolerance||length(delta)>max(0.15,footprint*5.0))continue;
        float weight=exp(-float(x*x+y*y)*0.5)*exp(-plane/max(plane_tolerance,0.001));
        vec3 d=finite_signal(imageLoad(raw_diffuse,q).rgb),s=finite_signal(imageLoad(raw_specular,q).rgb);
        diffuse+=d*weight;dw+=weight;dlo=min(dlo,d);dhi=max(dhi,d);
        // Glossy radiance must not smear across different material colours.
        if(abs(x)<=1&&abs(y)<=1&&length(m.rgb-material.rgb)<0.25) {
            specular+=s*weight;sw+=weight;slo=min(slo,s);shi=max(shi,s);
        }
    }
    diffuse/=max(dw,0.0001);specular/=max(sw,0.0001);
    float age=1.0;
    vec4 previous=frame.previous_view_projection*vec4(world,1.0);
    vec2 uv=vec2(previous.x,-previous.y)/previous.w*0.5+0.5;
    if(frame.camera.z>0.5&&(!progressive||frame.path.z>0.5)&&previous.w>0.0&&
        all(greaterThanEqual(uv,vec2(0.0)))&&all(lessThan(uv,vec2(1.0)))) {
        ivec2 q=ivec2(uv*vec2(size));
        vec4 g=imageLoad(previous_guide,q),m=imageLoad(previous_material,q);
        float expected=-(frame.previous_view*vec4(world,1.0)).z;
        if(g.w>0.0&&abs(g.w-expected)<max(0.035,footprint*0.75)&&dot(g.xyz,guide.xyz)>0.96&&
            abs(m.w-material.w)<0.05&&length(m.rgb-material.rgb)<0.15) {
            vec4 old=imageLoad(previous_diffuse,q);
            vec3 old_specular=imageLoad(previous_specular,q).rgb;
            age=min(old.a+1.0,frame.path.y);
            if(!progressive) {
                old.rgb=clamp(old.rgb,dlo-(dhi-dlo)*0.15-0.01,dhi+(dhi-dlo)*0.15+0.01);
                old_specular=clamp(old_specular,slo-(shi-slo)*0.1-0.01,shi+(shi-slo)*0.1+0.01);
            }
            diffuse=mix(diffuse,old.rgb,1.0-1.0/age);
            specular=mix(specular,old_specular,1.0-1.0/age);
        }
    }
    imageStore(result_diffuse,p,vec4(finite_signal(diffuse),age));
    imageStore(result_specular,p,vec4(finite_signal(specular),age));
}
