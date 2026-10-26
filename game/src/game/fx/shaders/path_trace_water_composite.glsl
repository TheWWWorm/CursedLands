#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform readonly image2D diffuse;
layout(rgba16f,set=0,binding=1) uniform readonly image2D specular;
layout(rgba16f,set=0,binding=2) uniform readonly image2D albedo;
layout(rgba16f,set=0,binding=3) uniform readonly image2D guide;
layout(rgba16f,set=0,binding=4) uniform readonly image2D emission_coverage;
layout(rgba16f,set=0,binding=5) uniform readonly image2D edge_colour;
layout(rgba16f,set=0,binding=6) uniform writeonly image2D reflection;
// Same 2816-byte PT frame prefix, followed by two water-specific vectors.
layout(std140,set=0,binding=7) uniform Frame { vec4 data[178]; } frame;
void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy);
    if(any(greaterThanEqual(p,imageSize(reflection))))return;
    vec4 e=imageLoad(emission_coverage,p),edge=imageLoad(edge_colour,p);
    vec3 radiance=imageLoad(diffuse,p).rgb*imageLoad(albedo,p).rgb+imageLoad(specular,p).rgb+e.rgb;
    float fog=clamp((imageLoad(guide,p).w-frame.data[176].y)/max(frame.data[176].z-frame.data[176].y,0.001),0.0,1.0);
    radiance=mix(radiance,frame.data[177].rgb,fog)*e.a;
    if(edge.a>0.5)radiance=edge.rgb;
    // Transparent sky, premultiplied coverage, scene-linear HDR. Water's
    // existing compositor performs the same unpremultiply as Mirror mode.
    imageStore(reflection,p,vec4(clamp(radiance,0.0,60000.0),e.a));
}
