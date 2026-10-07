// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <cmath>

namespace godot {
// One call per emitter, rather than a script callback and repeated ObjectDB
// validation per particle. A particle worker owns this emitter for the whole
// call. Its arrays and RNG are never shared with another emitter; no scene
// nodes, global random stream, renderer or gameplay state are accessed here.
class FireParticleKernel : public RefCounted {
    GDCLASS(FireParticleKernel, RefCounted)
    struct State {
        int64_t type, ec, dc, e4, flags, chance, minimum, capacity;
        double size, lift, shrink, wind_scale, moved, spacing;
        Vector3 origin, vmin, vmax, wind;
        bool carrier;
        RandomNumberGenerator *rng;
        double random() const { return double(rng->randi()) * 2.3283064e-10; }
        double range(double a, double b) const { return a + (b - a) * random(); }
    };
    static void previous(Array &p) {
        p[4] = p[0]; p[5] = p[1]; p[6] = p[2]; p[7] = p[3];
        p[0x12] = p[0x11]; p[0x17] = p[0x16];
    }
    static bool update(const State &s, Array &p) {
        p[0x14] = int64_t(p[0x14]) - 1;
        if (int64_t(p[0x14]) == 0) return false;
        p[0x13] = int64_t(p[0x13]) - 1;
        if (int64_t(p[0x13]) == 0) {
            p[0x11] = int64_t(p[0x11]) + 1;
            if (int64_t(p[0x11]) >= s.dc) return false;
            p[0x13] = s.e4;
            if (int64_t(p[0x11]) > 7) {
                if (s.type == 0x2003 || s.type == 0x2010) return false;
                p[0x13] = s.e4 << 2;
                if ((s.rng->randi() & 3) == 0) return false;
            }
            if (int64_t(p[0x11]) == 8) p[0x10] = double(p[0x10]) * .5;
        }
        p[2] = double(p[2]) + double(p[0x10]);
        if (int64_t(p[0x11]) < 2) {
            p[0] = double(p[0]) + double(p[8]);
            p[1] = double(p[1]) + double(p[9]);
            p[2] = double(p[2]) + double(p[10]);
        }
        if (int64_t(p[0x11]) < 7) {
            p[3] = s.shrink * double(p[3]);
            return true;
        }
        p[3] = double(p[3]) * 1.06;
        const double w = double(p[3]) * s.wind_scale * .15;
        // Preserve the script's Vector3 rounding at both vector operations.
        const Vector3 at = Vector3(p[0], p[1], p[2]) + s.wind * real_t(w);
        p[0] = double(at.x); p[1] = double(at.y); p[2] = double(at.z);
        return true;
    }
    static void spawn(const State &s, Array &parts) {
        Array p; p.resize(25); p.fill(int64_t(0));
        for (int i = 0; i < 4; ++i) p[i] = 0.;
        for (int i = 8; i < 0x11; ++i) p[i] = 0.;
        p[0x16] = int64_t(0xffffffff);
        p[0x14] = s.ec; p[0x11] = int64_t(s.type == 0x2004 ? 8 : 0);
        p[0x13] = s.e4; p[3] = s.size;
        double k = 0.;
        if (s.rng->randi() % 100 + 1 <= 40) { p[3] = s.size * .5; k = s.size * .3; }
        const double vx = s.range(double(s.vmin.x) - k, double(s.vmax.x) + k);
        const double vy = s.range(double(s.vmin.y) - k, double(s.vmax.y) + k);
        const Vector3 velocity = Vector3(vx, vy, 0.) * real_t(.5);
        p[8] = double(velocity.x); p[9] = double(velocity.y); p[10] = double(velocity.z);
        p[0] = double(s.origin.x) + double(p[8]);
        p[1] = double(s.origin.y) + double(p[9]);
        p[2] = double(s.origin.z) + s.random() * s.lift;
        p[0xe] = 0.; p[0xf] = 0.; p[0x10] = s.lift;
        previous(p); parts.append(p);
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("step", "emitter"), &FireParticleKernel::step);
    }
public:
    bool step(Object *emitter) const {
        ERR_FAIL_NULL_V(emitter, false);
        static const StringName type("type"), ec("ec"), dc("dc"), e4("e4"), flags("flags"), cc("cc"),
            d0("d0"), d8("d8"), size("s"), a110("a110"), m114("m114"), wind_s("wind_s"),
            moved("moved"), d4("d4"), wp("wp"), vmin("vmin"), vmax("vmax"), wind("wind"),
            has_carrier("has_carrier"), rng("rng"), parts_key("parts");
        Ref<RandomNumberGenerator> random = emitter->get(rng);
        ERR_FAIL_COND_V(random.is_null(), false);
        const State s = { emitter->get(type), emitter->get(ec), emitter->get(dc), emitter->get(e4),
            emitter->get(flags), emitter->get(cc), emitter->get(d0), emitter->get(d8),
            emitter->get(size), emitter->get(a110), emitter->get(m114), emitter->get(wind_s),
            emitter->get(moved), emitter->get(d4), emitter->get(wp), emitter->get(vmin),
            emitter->get(vmax), emitter->get(wind), emitter->get(has_carrier), random.ptr() };
        Array parts = emitter->get(parts_key);
        const int64_t count = parts.size();
        int64_t live = 0;
        for (int64_t i = 0; i < count; ++i) {
            Array p = parts[i];
            if (bool(p[0x18])) continue;
            previous(p);
            if (!update(s, p)) {
                p[0x18] = int64_t(1);
                p[0] = p[4]; p[1] = p[5]; p[2] = p[6];
                p[0x11] = p[0x12]; p[3] = p[7]; p[0x16] = p[0x17];
            }
            // Stable compaction preserves interpolation of newly dead rows
            // and avoids repeatedly shifting all remaining array entries.
            if (live != i) parts[live] = p;
            ++live;
        }
        if (live != count) parts.resize(live);
        int64_t attempts = s.spacing != 0. ? int64_t(std::round(s.moved / s.spacing)) : 0;
        if (attempts <= s.minimum) attempts = s.minimum;
        if ((s.flags & 1) && (!(s.flags & 2) || s.carrier)) {
            int64_t spawned = 0;
            for (int64_t i = 0; i < attempts && parts.size() < s.capacity; ++i) {
                if (int64_t(s.rng->randi() % 100) < s.chance) { ++spawned; spawn(s, parts); }
            }
            if (!spawned && s.chance > 50 && attempts > 0 && parts.size() < s.capacity) spawn(s, parts);
        }
        if (!s.carrier && !(s.flags & 4)) return !parts.is_empty();
        if (s.carrier && !(s.flags & 1) && parts.is_empty()) return false;
        return true;
    }
};
} // namespace godot
