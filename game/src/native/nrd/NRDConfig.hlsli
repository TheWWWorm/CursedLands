// Shared by the CPU dispatch planner and every compiled shader.
#define NRD_NORMAL_ENCODING 4
#define NRD_ROUGHNESS_ENCODING 1
#define NRD_SUPPORTS_VIEWPORT_OFFSET 0
#define NRD_SUPPORTS_CHECKERBOARD 0
#define NRD_SUPPORTS_HISTORY_CONFIDENCE 1
#define NRD_SUPPORTS_DISOCCLUSION_THRESHOLD_MIX 0
#define NRD_SUPPORTS_ANTIFIREFLY 1
// Keep the same pipeline on qualified Vulkan and D3D12 devices. Compute
// derivatives are optional in Vulkan and are not needed by the fallback path.
#define NRD_SUPPORTS_QUAD_INTRINSICS 0
#define REBLUR_PERFORMANCE_MODE 0
