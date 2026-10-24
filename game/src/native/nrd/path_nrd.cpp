// CPU-only NRD dispatch adapter. All RD resources and GPU work belong to the
// renderer, on its render thread; no native device or command queue is borrowed.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <NRD.h>
#include <algorithm>
#include <cmath>
#include <cstring>
using namespace godot;

class PathNrd : public RefCounted {
    GDCLASS(PathNrd, RefCounted)
    nrd::Instance *instance = nullptr;
    bool first = true;
    float smoothed_ms = 16.667f;
    static Array pool(const nrd::TextureDesc *textures, uint32_t count) {
        Array result;
        for (uint32_t i = 0; i < count; ++i) {
            Dictionary t; t["format"] = int(textures[i].format);
            t["scale"] = textures[i].downsampleFactor; result.append(t);
        }
        return result;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("describe"), &PathNrd::describe);
        ClassDB::bind_method(D_METHOD("dispatches", "matrices", "size", "frame_index", "reset", "milliseconds", "lighting_limit"), &PathNrd::dispatches);
    }
public:
    ~PathNrd() { if (instance) nrd::DestroyInstance(*instance); }
    Dictionary describe() {
        if (!instance) {
            nrd::DenoiserDesc denoiser{0, nrd::Denoiser::REBLUR_DIFFUSE_SPECULAR};
            nrd::InstanceCreationDesc creation{};
            creation.denoisers = &denoiser; creation.denoisersNum = 1;
            if (nrd::CreateInstance(creation, instance) != nrd::Result::SUCCESS) return {};
        }
        const auto &d = *nrd::GetInstanceDesc(*instance);
        Dictionary result; Array pipelines;
        for (uint32_t i = 0; i < d.pipelinesNum; ++i) {
            const auto &p = d.pipelines[i]; Dictionary entry;
            entry["shader"] = String(p.shaderIdentifier); entry["constants"] = p.hasConstantData;
            pipelines.append(entry);
        }
        result["pipelines"] = pipelines;
        result["permanent"] = pool(d.permanentPool, d.permanentPoolSize);
        result["transient"] = pool(d.transientPool, d.transientPoolSize);
        result["constant_bytes"] = int(d.constantBufferMaxDataSize);
        result["version"] = "4.18.0";
        Dictionary resources;
        resources["motion"] = int(nrd::ResourceType::IN_MV);
        resources["normal"] = int(nrd::ResourceType::IN_NORMAL_ROUGHNESS);
        resources["depth"] = int(nrd::ResourceType::IN_VIEWZ);
        resources["diffuse"] = int(nrd::ResourceType::IN_DIFF_RADIANCE_HITDIST);
        resources["specular"] = int(nrd::ResourceType::IN_SPEC_RADIANCE_HITDIST);
        resources["confidence_diffuse"] = int(nrd::ResourceType::IN_DIFF_CONFIDENCE);
        resources["confidence_specular"] = int(nrd::ResourceType::IN_SPEC_CONFIDENCE);
        resources["out_diffuse"] = int(nrd::ResourceType::OUT_DIFF_RADIANCE_HITDIST);
        resources["out_specular"] = int(nrd::ResourceType::OUT_SPEC_RADIANCE_HITDIST);
        resources["permanent"] = int(nrd::ResourceType::PERMANENT_POOL);
        resources["transient"] = int(nrd::ResourceType::TRANSIENT_POOL);
        result["resources"] = resources;
        return result;
    }
    Array dispatches(PackedFloat32Array matrices, Vector2i size, int64_t frame_index,
                     bool reset, double milliseconds, double lighting_limit) {
        if (!instance || matrices.size() != 64 || size.x < 2 || size.y < 2 || size.x > 16384 || size.y > 16384) return {};
        for (int i = 0; i < 64; ++i) if (!std::isfinite(matrices[i])) return {};
        nrd::CommonSettings c{};
        memcpy(c.viewToClipMatrix, matrices.ptr(), 16 * sizeof(float));
        memcpy(c.viewToClipMatrixPrev, matrices.ptr() + 16, 16 * sizeof(float));
        memcpy(c.worldToViewMatrix, matrices.ptr() + 32, 16 * sizeof(float));
        memcpy(c.worldToViewMatrixPrev, matrices.ptr() + 48, 16 * sizeof(float));
        c.resourceSize[0] = c.resourceSizePrev[0] = c.rectSize[0] = c.rectSizePrev[0] = size.x;
        c.resourceSize[1] = c.resourceSizePrev[1] = c.rectSize[1] = c.rectSizePrev[1] = size.y;
        c.denoisingRange = 65500.0f;
        c.frameIndex = uint32_t(frame_index);
        c.isMotionVectorInWorldSpace = true; c.motionVectorScale[2] = 1.0f;
        c.isHistoryConfidenceAvailable = true;
        c.timeDeltaBetweenFrames = std::clamp(float(milliseconds), 1.0f, 1000.0f);
        c.accumulationMode = first ? nrd::AccumulationMode::CLEAR_AND_RESTART :
            reset ? nrd::AccumulationMode::RESTART : nrd::AccumulationMode::CONTINUE;
        smoothed_ms += (c.timeDeltaBetweenFrames - smoothed_ms) / (1.0f + 200.0f / smoothed_ms);
        nrd::ReblurSettings settings{};
        settings.maxAccumulatedFrameNum = std::clamp(nrd::GetMaxAccumulatedFrameNum(0.35f, 1000.0f / smoothed_ms), 8u, 30u);
        // Fire flutter and rain transitions already supply a shorter response
        // budget. Apply it to both slow and stabilized NRD history as well.
        if (lighting_limit < 8.0) settings.maxAccumulatedFrameNum = uint32_t(std::max(1.0, lighting_limit));
        settings.maxFastAccumulatedFrameNum = std::min(6u, settings.maxAccumulatedFrameNum);
        settings.maxStabilizedFrameNum = settings.maxAccumulatedFrameNum;
        settings.historyFixFrameNum = std::min(3u, settings.maxFastAccumulatedFrameNum - 1);
        settings.returnHistoryLengthInsteadOfOcclusion = true;
        if (nrd::SetCommonSettings(*instance, c) != nrd::Result::SUCCESS ||
            nrd::SetDenoiserSettings(*instance, 0, &settings) != nrd::Result::SUCCESS) return {};
        const nrd::DispatchDesc *dispatches = nullptr; uint32_t count = 0; const nrd::Identifier id = 0;
        if (nrd::GetComputeDispatches(*instance, &id, 1, dispatches, count) != nrd::Result::SUCCESS) return {};
        Array result;
        for (uint32_t i = 0; i < count; ++i) {
            const auto &d = dispatches[i]; Dictionary entry; Array resources;
            for (uint32_t j = 0; j < d.resourcesNum; ++j) {
                const auto &r = d.resources[j]; Dictionary resource;
                resource["type"] = int(r.type); resource["pool"] = r.indexInPool;
                resource["storage"] = r.descriptorType == nrd::DescriptorType::STORAGE_TEXTURE;
                resources.append(resource);
            }
            PackedByteArray constants; constants.resize(d.constantBufferDataSize);
            if (d.constantBufferDataSize) memcpy(constants.ptrw(), d.constantBufferData, d.constantBufferDataSize);
            entry["pipeline"] = d.pipelineIndex; entry["resources"] = resources;
            entry["constants"] = constants; entry["grid"] = Vector2i(d.gridWidth, d.gridHeight);
            result.append(entry);
        }
        first = false;
        return result;
    }
};
static void initialize(ModuleInitializationLevel level) { if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<PathNrd>(); }
static void uninitialize(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT path_nrd_init(GDExtensionInterfaceGetProcAddress address, GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
    GDExtensionBinding::InitObject object(address, library, init);
    object.register_initializer(initialize); object.register_terminator(uninitialize);
    object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE); return object.init();
}
