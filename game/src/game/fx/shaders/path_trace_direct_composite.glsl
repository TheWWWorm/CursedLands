#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform readonly image2D raw_direct;
layout(rgba16f,set=0,binding=1) uniform readonly image2D filtered_direct;
layout(rgba16f,set=0,binding=2) uniform image2D specular;
layout(rgba16f,set=0,binding=3) uniform readonly image2D filtered_sun;
layout(rgba16f,set=0,binding=4) uniform image2D diffuse;
void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy);
    if(any(greaterThanEqual(p,imageSize(specular))))return;
    vec4 value=imageLoad(specular,p);
    // NRD's resolve includes the original direct term. Replace that term
    // without applying another filter to its reconstructed indirect light.
    value.rgb=clamp(max(value.rgb-imageLoad(raw_direct,p).rgb,vec3(0.0))+
        imageLoad(filtered_direct,p).rgb,0.0,60000.0);
    imageStore(specular,p,value);
    // NRD receives only diffuse light other than the analytic sun term.
    // Publish the same reconstructed sun in the full signal and the terrain
    // AOV, so native grass occlusion cannot subtract a different history.
    vec4 light=imageLoad(diffuse,p);
    light.rgb=clamp(light.rgb+imageLoad(filtered_sun,p).rgb,0.0,60000.0);
    imageStore(diffuse,p,light);
}
