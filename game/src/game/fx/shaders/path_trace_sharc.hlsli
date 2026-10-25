// This software contains source code provided by NVIDIA Corporation.
// SDK headers are external build inputs; see SHARC_NOTICES.txt and the build manifest.
#define HASH_GRID_ENABLE_64_BIT_ATOMICS 0
#define SHARC_SEPARATE_EMISSIVE 1
#define SHARC_MATERIAL_DEMODULATION 1
// Trace a bounded fresh path for updates. Do not recursively reuse old light
// while a torch, occluder or scene generation is changing.
#define SHARC_ENABLE_CACHE_RESAMPLING 0
#define SHARC_PROPAGATION_DEPTH 8
#define SHARC_SAMPLE_NUM_THRESHOLD 1
#ifdef PATH_SHARC_UPDATE
#define SHARC_UPDATE 1
#else
#define SHARC_UPDATE 0
#endif
#include <SharcCommon.h>
[[vk::binding(22,0)]] RWStructuredBuffer<uint64_t> sharc_keys : register(u2200000);
[[vk::binding(23,0)]] RWStructuredBuffer<SharcAccumulationData> sharc_accumulation : register(u2300000);
[[vk::binding(24,0)]] RWStructuredBuffer<SharcPackedData> sharc_resolved : register(u2400000);
[[vk::binding(25,0)]] RWStructuredBuffer<uint> sharc_locks : register(u2500000);
struct SharcFrame {
    float4 camera_scale;
    float4 previous_camera;
    uint4 dimensions; // capacity, frame, full width, full height
    float4 temporal; // history, stale lifetime, debug counters, reserved
};
[[vk::binding(26,0)]] ConstantBuffer<SharcFrame> sharc_frame : register(b2600000);
[[vk::binding(27,0)]] RWStructuredBuffer<uint> sharc_stats : register(u2700000);
SharcParameters sharc_parameters() {
    SharcParameters p;
    p.hashGridParameters.cameraPosition=sharc_frame.camera_scale.xyz;
    p.hashGridParameters.logarithmBase=SHARC_GRID_LOGARITHM_BASE;
    p.hashGridParameters.sceneScale=sharc_frame.camera_scale.w;
    p.hashGridParameters.levelBias=0.0;
    p.hashGridData.capacity=sharc_frame.dimensions.x;
    p.hashGridData.hashEntriesBuffer=sharc_keys;
    p.hashGridData.lockBuffer=sharc_locks;
    p.accumulationBuffer=sharc_accumulation;
    p.resolvedBuffer=sharc_resolved;
    p.radianceScale=1000.0;
    return p;
}
void sharc_count(uint counter) {
    if(sharc_frame.temporal.z>0.5)InterlockedAdd(sharc_stats[counter],1u);
}
