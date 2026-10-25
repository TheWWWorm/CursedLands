#include "path_trace_sharc.hlsli"
// As with NRD, preserve DXC SPIR-V through Godot 4.7 re-spirv.
// Its optimizer cannot correctly rewrite this structured-buffer program.
#ifdef SHARC_VULKAN
[[vk::constant_id(0)]] const bool sharc_dispatch = true;
#endif
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID) {
#ifdef SHARC_VULKAN
    if(!sharc_dispatch)return;
#endif
    SharcResolveParameters p;
    p.cameraPositionPrev=sharc_frame.previous_camera.xyz;
    p.accumulationFrameNum=uint(sharc_frame.temporal.x);
    p.responsiveFrameNum=1;
    p.staleFrameNumMax=uint(sharc_frame.temporal.y);
    p.frameIndex=sharc_frame.dimensions.y;
    SharcResolveEntry(id.x,sharc_parameters(),p);
}
