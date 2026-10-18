// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <algorithm>
#include <cmath>

namespace godot {
// One call per emitter, rather than a script callback and repeated ObjectDB
// validation per particle. A particle worker owns this emitter for the whole
// call. Its arrays and RNG are never shared with another emitter; no scene
// nodes, global random stream, renderer or gameplay state are accessed here.
class FireParticleKernel : public RefCounted {
    GDCLASS(FireParticleKernel, RefCounted)
    struct Ground {
        Object *script = nullptr;
        PackedFloat32Array heights, surface;
        Dictionary floors;
        int64_t width = 0, cells_x = 0, cells_y = 0;
        bool native = false, valid = false;
        double at(double x, double y) const {
            if (!script) return 0.;
            // Authored floor buckets and custom snapshots retain their script
            // query. The common terrain-only case reads this tick's immutable
            // arrays, avoiding a script call for every new flame.
            const Vector2 p(x, y);
            if (!native || floors.has(Vector2i(std::floor(p.x / 4.), std::floor(p.y / 4.))))
                return script->call("at", x, y);
            if (!valid) return 0.;
            const double xc = std::clamp(x, 0., double(width) - 1.001);
            const double yc = std::clamp(y, 0., double(cells_y + 1) - 1.001);
            const int64_t ix = int64_t(xc), iy = int64_t(yc), i = iy * width + ix;
            const double fx = xc - double(ix), fy = yc - double(iy);
            const float *h = heights.ptr();
            const double a = double(h[i]) + (double(h[i + 1]) - double(h[i])) * fx;
            const double b = double(h[i + width]) + (double(h[i + width + 1]) - double(h[i + width])) * fx;
            double value = a + (b - a) * fy;
            const int64_t cx = int64_t(x), cy = int64_t(y);
            if (cx >= 0 && cy >= 0 && cx < cells_x && cy < cells_y)
                value = std::max(value, double(surface[cy * cells_x + cx]));
            return value;
        }
    };
    struct State {
        int64_t type, ec, dc, e4, flags, chance, minimum, capacity;
        double size, lift, shrink, wind_scale, moved, spacing;
        Vector3 origin, vmin, vmax, wind;
        bool carrier;
        RandomNumberGenerator *rng;
        Vector3 delta, side, up, wall;
        Ground ground;
        double random() const { return double(rng->randi()) * 2.3283064e-10; }
        double range(double a, double b) const { return a + (b - a) * random(); }
    };
    static void set_vector(Array &p, int i, Vector3 value) {
        p[i] = double(value.x); p[i + 1] = double(value.y); p[i + 2] = double(value.z);
    }
    static Vector3 vector(const Array &p, int i) { return Vector3(p[i], p[i + 1], p[i + 2]); }
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
            if (s.type != 0x2000) {
                if (int64_t(p[0x11]) > 7) {
                    if (s.type == 0x2003 || s.type == 0x2010) return false;
                    p[0x13] = s.e4 << 2;
                    if ((s.rng->randi() & 3) == 0) return false;
                }
                if (int64_t(p[0x11]) == 8) p[0x10] = double(p[0x10]) * .5;
            }
        }
        if (s.type == 0x2000) {
            p[3] = s.shrink * double(p[3]);
            if (int64_t(p[0x15]) == 0) set_vector(p, 0, vector(p, 0) - vector(p, 8));
            else { p[0x15] = int64_t(0); p[3] = double(p[3]) * .5; }
            set_vector(p, 8, vector(p, 8) * real_t(.95));
            set_vector(p, 0, vector(p, 0) + vector(p, 8));
            return true;
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
    static void spawn(const State &s, Array &parts, int64_t index) {
        Array p; p.resize(25); p.fill(int64_t(0));
        for (int i = 0; i < 4; ++i) p[i] = 0.;
        for (int i = 8; i < 0x11; ++i) p[i] = 0.;
        p[0x16] = int64_t(0xffffffff);
        p[0x14] = s.ec; p[0x11] = int64_t(s.type == 0x2004 ? 8 : 0);
        p[0x13] = s.e4; p[3] = s.size;
        if (s.type == 0x2000) {
            set_vector(p, 0, s.origin);
            const double h = s.size * .5;
            double t = 0.;
            if (index == 0) { p[0x15] = int64_t(1); p[3] = s.size * 1.2; }
            else { p[3] = h; p[0x15] = int64_t(0); t = s.random() - 1.; }
            if (s.moved > 1e-5) {
                set_vector(p, 0, vector(p, 0) + s.delta * real_t(t));
                const double a = s.range(double(s.vmin.x) - h, double(s.vmax.x) + h);
                const double b = s.range(double(s.vmin.y) - h, double(s.vmax.y) + h);
                const Vector3 v = s.side * real_t(a) + s.up * real_t(b);
                set_vector(p, 8, v);
                if (int64_t(p[0x15]) == 0) set_vector(p, 0, vector(p, 0) + v);
            }
            previous(p); parts.append(p); return;
        }
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
        if (s.type == 0x2010) {
            const double t = double(s.rng->randi()) * 4.656613e-10 - 1.;
            p[0] = t * double(s.wall.x) + double(p[0]);
            p[1] = t * double(s.wall.y) + double(p[1]);
            // The same immutable tick snapshot used by the script emitter.
            const double ground = s.ground.at(p[0], p[1]);
            p[2] = double(p[2]) - double(s.origin.z) + ground;
        }
        previous(p); parts.append(p);
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("step", "emitter", "terrain_snapshot"), &FireParticleKernel::step, DEFVAL(false));
        ClassDB::bind_method(D_METHOD("supports_type", "type"), &FireParticleKernel::supports_type);
    }
public:
    bool supports_type(int64_t kind) const {
        return kind == 0x2000 || kind == 0x2001 || kind == 0x2003 || kind == 0x2004 || kind == 0x2010;
    }
    bool step(Object *emitter, bool terrain_snapshot = false) const {
        ERR_FAIL_NULL_V(emitter, false);
        static const StringName type("type"), ec("ec"), dc("dc"), e4("e4"), flags("flags"), cc("cc"),
            d0("d0"), d8("d8"), size("s"), a110("a110"), m114("m114"), wind_s("wind_s"),
            moved("moved"), d4("d4"), wp("wp"), vmin("vmin"), vmax("vmax"), wind("wind"),
            has_carrier("has_carrier"), rng("rng"), parts_key("parts"),
            dl("dl"), sd("sd"), upv("upv"), v130("v130"), ground_src("ground_src");
        Ref<RandomNumberGenerator> random = emitter->get(rng);
        ERR_FAIL_COND_V(random.is_null(), false);
        Ground ground;
        ground.script = emitter->get(ground_src);
        if (ground.script && terrain_snapshot) {
            ground.heights = ground.script->get("heights"); ground.surface = ground.script->get("surface");
            ground.floors = ground.script->get("floors"); ground.width = ground.script->get("grid_w");
            ground.cells_x = ground.script->get("cells_w"); ground.cells_y = ground.script->get("cells_h");
            ground.valid = ground.script->get("valid");
            ground.native = !ground.valid || (ground.width > 1 && ground.cells_x == ground.width - 1 && ground.cells_y > 0 &&
                ground.heights.size() >= ground.width * (ground.cells_y + 1) && ground.surface.size() >= ground.cells_x * ground.cells_y);
        }
        const State s = { emitter->get(type), emitter->get(ec), emitter->get(dc), emitter->get(e4),
            emitter->get(flags), emitter->get(cc), emitter->get(d0), emitter->get(d8),
            emitter->get(size), emitter->get(a110), emitter->get(m114), emitter->get(wind_s),
            emitter->get(moved), emitter->get(d4), emitter->get(wp), emitter->get(vmin),
            emitter->get(vmax), emitter->get(wind), emitter->get(has_carrier), random.ptr(),
            emitter->get(dl), emitter->get(sd), emitter->get(upv), emitter->get(v130), ground };
        ERR_FAIL_COND_V(!supports_type(s.type), false);
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
                if (int64_t(s.rng->randi() % 100) < s.chance) spawn(s, parts, spawned++);
            }
            if (!spawned && s.chance > 50 && attempts > 0 && parts.size() < s.capacity) spawn(s, parts, 0);
        }
        if (!s.carrier && !(s.flags & 4)) return !parts.is_empty();
        if (s.carrier && !(s.flags & 1) && parts.is_empty()) return false;
        return true;
    }
};
} // namespace godot
