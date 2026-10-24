#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform readonly image2D source_diffuse;
layout(rgba16f,set=0,binding=1) uniform readonly image2D source_specular;
layout(rgba16f,set=0,binding=2) uniform readonly image2D guide_image;
layout(rgba16f,set=0,binding=3) uniform readonly image2D material_image;
layout(rg16f,set=0,binding=4) uniform readonly image2D noise_image;
layout(rgba16f,set=0,binding=5) uniform writeonly image2D result_diffuse;
layout(rgba16f,set=0,binding=6) uniform writeonly image2D result_specular;
layout(std140,set=0,binding=7) uniform Frame {
    mat4 inv_projection;mat4 camera_world;mat4 previous_view_projection;mat4 previous_view;
    vec4 sun;vec4 sun_direction;vec4 sky;vec4 settings;vec4 camera;vec4 center_radius;
    vec4 point_position[7];vec4 point_colour[7];vec4 path;
    mat4 previous_inverse_view_projection;
} frame;
layout(push_constant,std430) uniform Params {int stride;int pad0;int pad1;int pad2;} params;

vec3 position_at(ivec2 p,float depth,ivec2 size) {
    vec2 uv=(vec2(p)+0.5)/vec2(size);
    vec4 near=frame.inv_projection*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,-1.0,1.0);near/=near.w;
    vec3 view=frame.camera.x>0.5?vec3(near.xy,-depth):near.xyz*(depth/-near.z);
    return (frame.camera_world*vec4(view,1.0)).xyz;
}
vec3 surface_plane(ivec2 p,vec3 world,vec3 fallback,ivec2 size) {
    vec3 tangent[2];
    for(int axis=0;axis<2;axis++) {
        ivec2 step_=axis==0?ivec2(1,0):ivec2(0,1);
        ivec2 a=clamp(p-step_,ivec2(0),size-1),b=clamp(p+step_,ivec2(0),size-1);
        float az=imageLoad(guide_image,a).w,bz=imageLoad(guide_image,b).w;
        vec3 da=world-position_at(a,az,size),db=position_at(b,bz,size)-world;
        bool va=az>0.0&&any(notEqual(a,p)),vb=bz>0.0&&any(notEqual(b,p));
        if(!va&&!vb)return fallback;
        tangent[axis]=va&&(!vb||dot(da,da)<dot(db,db))?da:db;
    }
    vec3 plane=cross(tangent[0],tangent[1]);
    if(dot(plane,plane)<1e-16)return fallback;
    plane=normalize(plane);return dot(plane,fallback)<0.0?-plane:plane;
}
vec2 surface(float packed) {
    uint bits=uint(round(packed));return vec2(float(bits&63u)/63.0,float(bits>>6u)/31.0);
}
float luminance(vec3 value) {return dot(value,vec3(0.2126,0.7152,0.0722));}
void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy),size=imageSize(source_diffuse);
    if(any(greaterThanEqual(p,size)))return;
    vec4 d=imageLoad(source_diffuse,p),s=imageLoad(source_specular,p),g=imageLoad(guide_image,p);
    if(g.w<=0.0){imageStore(result_diffuse,p,d);imageStore(result_specular,p,s);return;}
    vec4 m=imageLoad(material_image,p);vec2 rough=surface(m.w),sigma=abs(imageLoad(noise_image,p).rg);
    vec3 world=position_at(p,g.w,size);
    vec3 plane_normal=surface_plane(p,world,g.xyz,size);
    float footprint=abs(frame.inv_projection[1][1])*2.0/float(size.y)*(frame.camera.x>0.5?1.0:g.w);
    vec3 sum_d=d.rgb,sum_s=s.rgb;float wd=1.0,ws=1.0;
    const float kernel[3]=float[3](1.0,2.0/3.0,1.0/6.0);
    for(int y=-2;y<=2;y++)for(int x=-2;x<=2;x++) {
        if(x==0&&y==0)continue;
        ivec2 q=p+ivec2(x,y)*params.stride;
        if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,size)))continue;
        vec4 ng=imageLoad(guide_image,q),nm=imageLoad(material_image,q);
        float normal_match=max(dot(g.xyz,ng.xyz),0.0);
        if(ng.w<=0.0||normal_match<0.65)continue;
        vec2 nr=surface(nm.w);
        if(abs(nr.y-rough.y)>0.08)continue;
        vec3 delta=position_at(q,ng.w,size)-world;
        float tolerance=max(max(0.015,footprint*0.3),g.w*0.00075);
        float plane=abs(dot(delta,plane_normal));
        if(plane>tolerance||length(delta)>max(0.12,footprint*float(params.stride)*5.0))continue;
        vec4 nd=imageLoad(source_diffuse,q),ns=imageLoad(source_specular,q);
        vec2 noise=abs(imageLoad(noise_image,q).rg);
        // Filter lighting, not painted albedo. Confidence and local variance
        // leave established illumination boundaries and fine glossy lobes sharp.
        float dw=kernel[abs(x)]*kernel[abs(y)]*exp(-plane/tolerance)*pow(normal_match,4.0);
        float ds=2.0*sqrt(sigma.x*sigma.x/max(d.a,1.0)+noise.x*noise.x/max(nd.a,1.0))+0.01;
        float sw=dw;
        dw*=exp(-abs(luminance(nd.rgb)-luminance(d.rgb))/ds);
        sum_d+=nd.rgb*dw;wd+=dw;
        if(normal_match<0.94||abs(nr.x-rough.x)>0.08||length(nm.rgb-m.rgb)>0.15||rough.x<0.25)continue;
        float ss=2.0*sqrt(sigma.y*sigma.y/max(s.a,1.0)+noise.y*noise.y/max(ns.a,1.0))+0.005;
        sw*=exp(-abs(luminance(ns.rgb)-luminance(s.rgb))/ss);
        // Do not spread a narrow reflection over a wide spatial footprint.
        sw*=pow(max(dot(g.xyz,ng.xyz),0.0),mix(128.0,8.0,rough.x*rough.x));
        sum_s+=ns.rgb*sw;ws+=sw;
    }
    imageStore(result_diffuse,p,vec4(sum_d/wd,d.a));
    imageStore(result_specular,p,vec4(sum_s/ws,s.a));
}
