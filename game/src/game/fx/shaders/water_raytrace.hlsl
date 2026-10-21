// Shared DXR/Vulkan water-reflection shader. Build with tools/build_water_rt_shaders.py.
// The D3D12 registers match Godot's set * 100000000 + binding * 100000 ABI.
[[vk::binding(0, 0)]] RaytracingAccelerationStructure scene : register(t0);
[[vk::binding(1, 0), vk::image_format("rgba16f")]] RWTexture2D<float4> output_image : register(u100000);
[[vk::binding(2, 0)]] ByteAddressBuffer vertices : register(t200000);
[[vk::binding(3, 0)]] Texture2DArray<float4> colours : register(t300000);
[[vk::binding(5, 0)]] ByteAddressBuffer geometry : register(t500000);
[[vk::binding(6, 0)]] SamplerState colour_sampler : register(s600000);
struct Frame {
    column_major float4x4 inv_projection;
    column_major float4x4 camera_world;
    float4 ambient; // RGB lighting; W is the sample grid width (1, 2, or audit reference).
    float4 sun;
    float4 sun_plane;
    float4 fog;
    float4 sky;
    float4 center_radius;
    float4 point_position[4];
    float4 point_colour[4];
};
[[vk::binding(4, 0)]] ConstantBuffer<Frame> frame : register(b400000);
struct Vertex { float4 position_u; float4 normal_v; float4 diffuse; float4 emission_layer; };
struct Surface { float4 colour; float3 hit_point; float3 normal; float3 diffuse; float3 emission; float visible; float standard; };
struct Attributes { float2 bary; };

Vertex vertex_at(uint i) {
    Vertex v;
    v.position_u = asfloat(vertices.Load4(i * 64));
    v.normal_v = asfloat(vertices.Load4(i * 64 + 16));
    v.diffuse = asfloat(vertices.Load4(i * 64 + 32));
    v.emission_layer = asfloat(vertices.Load4(i * 64 + 48));
    return v;
}
float3 linear_colour(float3 c) {
    c = max(c, 0.0);
    return lerp(c / 12.92, pow((c + 0.055) / 1.055, 2.4), step(0.04045, c));
}
float2 hit_uv(Vertex a, Vertex c, Vertex d, float3 b) {
    return float2(dot(b, float3(a.position_u.w, c.position_u.w, d.position_u.w)),
                  dot(b, float3(a.normal_v.w, c.normal_v.w, d.normal_v.w)));
}

#if defined(WATER_RAYGEN)
float visibility(float3 hit_point, float3 normal, float3 direction, float reach) {
    if (frame.sun.w < 0.5) { return 1.0; }
    Surface shadow = (Surface)0;
    float3 offset = normal * (dot(normal, direction) >= 0.0 ? 0.015 : -0.015);
    RayDesc ray = { hit_point + offset, 0.002, direction, max(reach - 0.02, 0.003) };
    TraceRay(scene, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH | RAY_FLAG_SKIP_CLOSEST_HIT_SHADER,
             2, 0, 0, 0, ray, shadow);
    return shadow.visible;
}
float4 trace_sample(float2 uv) {
    float4 p = mul(frame.inv_projection, float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, -1.0, 1.0));
    p /= p.w;
    float3 eye = mul(frame.camera_world, float4(0, 0, 0, 1)).xyz;
    float3 forward = -mul(frame.camera_world, float4(0, 0, 1, 0)).xyz;
    float3 origin = eye;
    float3 direction = normalize(mul(frame.camera_world, float4(p.xyz, 0.0)).xyz);
    if (frame.fog.w > 0.5) {
        origin = mul(frame.camera_world, float4(p.xyz, 1.0)).xyz;
        direction = forward;
    }
    Surface result = (Surface)0;
    if (direction.y > 0.00001) {
        float entry = (frame.sun_plane.w - origin.y) / direction.y;
        if (entry > 0.0 && entry < frame.fog.z) {
            RayDesc ray = { origin + direction * (entry + 0.025), 0.001, direction, frame.fog.z - entry };
            TraceRay(scene, RAY_FLAG_NONE, 1, 0, 0, 0, ray, result);
        }
    }
    float4 colour = result.colour;
    if (colour.a > 0.0) {
        float3 hit_point = result.hit_point, n = result.normal, diffuse = result.diffuse, emission = result.emission;
        float3 light = frame.ambient.rgb, spec = 0.0, extra = 0.0;
        float facing = max(dot(n, frame.sun_plane.xyz), 0.0);
        if (facing > 0.0) {
            light = max(light, frame.sun.rgb * diffuse * facing * visibility(hit_point, n, frame.sun_plane.xyz, frame.fog.z));
        }
        for (int i = 0; i < 4; i++) {
            float4 lamp = frame.point_position[i];
            float3 delta = lamp.xyz - hit_point;
            float distance = length(delta);
            if (lamp.w <= 0.0 || distance >= lamp.w || distance < 0.001) { continue; }
            float3 l = delta / distance;
            float facing = max(dot(n, l), 0.0);
            if (facing <= 0.0) { continue; }
            float attenuation = max(1.0 - distance * distance / (lamp.w * lamp.w), 0.0);
            float3 contribution = frame.point_colour[i].rgb * attenuation * facing * visibility(hit_point, n, l, distance);
            if (frame.point_colour[i].a > 1.5) { extra += linear_colour(contribution) * 0.75; }
            else {
                light = max(light, contribution * diffuse);
                if (frame.point_colour[i].a > 0.5) { spec = max(spec, contribution); }
            }
        }
        float3 shaded = linear_colour(saturate(colour.rgb * min(light + (result.standard < 0.5 ? emission : 0.0), 1.0) + spec));
        if (result.standard > 0.5) { shaded += emission; }
        shaded += linear_colour(colour.rgb) * extra;
        float depth = dot(hit_point - eye, forward);
        float fog = saturate((depth - frame.fog.x) / max(frame.fog.y - frame.fog.x, 0.001));
        colour.rgb = lerp(shaded, linear_colour(frame.sky.rgb), fog);
        if (frame.center_radius.w > 0.0) {
            colour.a *= 1.0 - smoothstep(frame.center_radius.w - 12.0, frame.center_radius.w, length(hit_point - frame.center_radius.xyz));
        }
    }
    // The water compositor unpremultiplies after bilinear filtering, just as
    // it does for the transparent Mirror viewport. Preserve edge coverage.
    return float4(colour.rgb * colour.a, colour.a);
}
[shader("raygeneration")]
void main() {
    uint2 pixel = DispatchRaysIndex().xy;
    float2 size = float2(DispatchRaysDimensions().xy);
    // A fixed spatial pattern has no history to ghost on moving creatures,
    // reveal stale banks after a camera cut, or flicker when FG is enabled.
    uint grid = clamp(uint(frame.ambient.w), 1u, 8u);
    float4 sum = 0.0;
    for (uint y = 0; y < grid; ++y) {
        for (uint x = 0; x < grid; ++x) {
            sum += trace_sample((float2(pixel) + (float2(x, y) + 0.5) / float(grid)) / size);
        }
    }
    output_image[pixel] = sum / float(grid * grid);
}
#elif defined(WATER_MISS)
[shader("miss")]
void main(inout Surface result) { result.visible = 1.0; }
#elif defined(WATER_ANY_HIT)
[shader("anyhit")]
void main(inout Surface result, Attributes attributes) {
    uint4 material = geometry.Load4(InstanceID() * 16);
    uint i = material.x + 3 * PrimitiveIndex();
    Vertex a = vertex_at(i), c = vertex_at(i + 1), d = vertex_at(i + 2);
    float3 b = float3(1.0 - attributes.bary.x - attributes.bary.y, attributes.bary);
    if (colours.SampleLevel(colour_sampler, float3(hit_uv(a, c, d, b), a.emission_layer.w), 0.0).a * a.diffuse.a < asfloat(material.z)) { IgnoreHit(); }
}
#elif defined(WATER_CLOSEST_HIT)
[shader("closesthit")]
void main(inout Surface result, Attributes attributes) {
    uint4 material = geometry.Load4(InstanceID() * 16);
    uint i = material.x + 3 * PrimitiveIndex();
    Vertex va = vertex_at(i), vc = vertex_at(i + 1), vd = vertex_at(i + 2);
    float3 b = float3(1.0 - attributes.bary.x - attributes.bary.y, attributes.bary);
    float3 n = va.normal_v.xyz * b.x + vc.normal_v.xyz * b.y + vd.normal_v.xyz * b.z;
    result.normal = normalize(mul(n, (float3x3)WorldToObject3x4()));
    result.hit_point = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
    result.diffuse = va.diffuse.rgb;
    result.emission = va.emission_layer.rgb;
    result.standard = float(material.y & 1);
    float3 a = mul(ObjectToWorld3x4(), float4(va.position_u.xyz, 1.0));
    float3 c = mul(ObjectToWorld3x4(), float4(vc.position_u.xyz, 1.0));
    float3 d = mul(ObjectToWorld3x4(), float4(vd.position_u.xyz, 1.0));
    float2 ua = float2(va.position_u.w, va.normal_v.w), uc = float2(vc.position_u.w, vc.normal_v.w), ud = float2(vd.position_u.w, vd.normal_v.w);
    float density = max(length(uc - ua) / max(length(c - a), 0.001), length(ud - ua) / max(length(d - a), 0.001));
    float3 eye = mul(frame.camera_world, float4(0, 0, 0, 1)).xyz;
    float distance = frame.fog.w > 0.5 ? 1.0 : length(result.hit_point - eye);
    uint width, height, layers, levels;
    colours.GetDimensions(0, width, height, layers, levels);
    float footprint = distance * frame.sky.w * density * float(width);
    float lod = max(log2(max(footprint, 1.0)), 0.0);
    result.colour = float4(colours.SampleLevel(colour_sampler, float3(hit_uv(va, vc, vd, b), va.emission_layer.w), lod).rgb, 1.0);
    if (result.standard > 0.5) { result.colour.rgb *= result.diffuse; result.diffuse = 1.0; }
}
#endif
