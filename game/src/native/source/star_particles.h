// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <algorithm>

namespace godot {
// Exit and wisp particle updates share the original ordered interpolation /
// removal pass. Spawning stays in script: exits sample authored floor planes,
// while wisps read live carrier bounds, gait and death. Only exit emitters run
// on workers, exactly as before; a wisp still owns its main-thread lifecycle.
class StarParticleKernel : public RefCounted {
    GDCLASS(StarParticleKernel, RefCounted)
    static constexpr int exit_alpha[16] = {0,80,176,255,255,255,255,255,255,255,255,255,255,255,128,64};
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("advance", "emitter"), &StarParticleKernel::advance);
        ClassDB::bind_method(D_METHOD("supports_type", "type"), &StarParticleKernel::supports_type);
    }
public:
    bool supports_type(int64_t type) const { return type == 0x2038 || type == 0x204d; }
    bool advance(Object *emitter) const {
        if (!emitter) return false;
        const int64_t type = emitter->get("type");
        if (!supports_type(type)) return false;
        Ref<RandomNumberGenerator> rng = emitter->get("rng");
        if (rng.is_null()) return false;
        const double size = emitter->get("s");
        const bool carrier = emitter->get("has_carrier");
        Array parts = emitter->get("parts");
        const int64_t count = parts.size();
        int64_t live = 0;
        for (int64_t i = 0; i < count; ++i) {
            Array p = parts[i];
            if (bool(p[0x18])) continue;
            p[4] = p[0]; p[5] = p[1]; p[6] = p[2]; p[7] = p[3];
            p[0x12] = p[0x11]; p[0x17] = p[0x16];
            const int64_t life = p[0x14];
            if (type == 0x2038) {
                p[0x16] = (int64_t(exit_alpha[std::clamp<int64_t>(life, 0, 15)]) << 24) | (int64_t(p[0x16]) & 0xffffff);
            }
            p[0x14] = life - 1;
            if (life < 1) {
                p[0x18] = int64_t(1);
                // A newly dead row survives for one interpolation tick with
                // its previous visible state. Remove it on the next call.
                p[0] = p[4]; p[1] = p[5]; p[2] = p[6]; p[3] = p[7];
                p[0x11] = p[0x12]; p[0x16] = p[0x17];
            } else if (type == 0x2038) {
                const int64_t frame = p[0x11];
                p[2] = double(p[2]) + .05;
                p[0x11] = ((frame + 1) & 3) | (frame & ~int64_t(3));
                p[3] = p[0xb];
            } else {
                p[0x16] = int64_t(0xffffffff);
                // Godot's decimal parser stores the script's 9.313226580990458e-11
                // one ULP below the C++ literal. Preserve that exact constant.
                p[3] = (double(rng->randi()) * 0x1.99999c0199999p-34 + 0.800000011920929) * size * double(p[8]);
                if (!carrier) {
                    emitter->call("stop");
                    emitter->call("attach", Variant());
                }
            }
            if (live != i) parts[live] = p;
            ++live;
        }
        if (live != count) parts.resize(live);
        return true;
    }
};
}
