// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <algorithm>
#include <cmath>

namespace godot {
// Modifier and orbit emitters retain their original scene-dependent initial
// creation in script. Once their control points exist, a whole tick operates
// on this emitter's owned arrays and random stream, without particle callbacks.
class SpellParticleKernel : public RefCounted {
    GDCLASS(SpellParticleKernel, RefCounted)
    struct State {
        int64_t type, ec, dc, e4, flags, chance, minimum, capacity;
        double size, moved, spacing;
        Vector3 origin, vmin, vmax;
        bool carrier, orbit;
        RandomNumberGenerator *rng;
        Array controls;
        double random() const { return double(rng->randi()) * 2.3283064e-10; }
        double range(double a, double b) const { return a + (b - a) * random(); }
    };
    static constexpr int mod_in[16] = {0,32,64,128,255,255,255,255,255,255,255,128,0,0,0,0};
    static constexpr int mod_out[16] = {0,128,255,255,255,255,255,255,192,128,64,32,0,0,0,0};
    static constexpr int orbit_alpha[8] = {0,0,32,64,112,160,208,255};
    static int64_t alpha(int64_t value) { return (std::clamp<int64_t>(value, 0, 255) << 24) | 0xffffff; }
    static void set_vector(Array &p, int index, Vector3 value) {
        p[index] = double(value.x); p[index + 1] = double(value.y); p[index + 2] = double(value.z);
    }
    static Vector3 vector(const Array &p, int index) { return Vector3(p[index], p[index + 1], p[index + 2]); }
    static void previous(Array &p) {
        p[4] = p[0]; p[5] = p[1]; p[6] = p[2]; p[7] = p[3];
        p[0x12] = p[0x11]; p[0x17] = p[0x16];
    }
    static void controls(State &s) {
        for (int64_t i = 0; i < s.controls.size(); ++i) {
            Array c = s.controls[i];
            if (s.orbit) {
                const double x = c[6];
                c[9] = c[0]; c[10] = c[1]; c[11] = c[2];
                c[6] = double(c[7]) * double(c[4]) + double(c[6]) * double(c[3]);
                c[7] = double(c[3]) * double(c[7]) - x * double(c[4]);
                c[0] = double(s.origin.x) + double(c[6]);
                c[1] = double(s.origin.y) + double(c[7]);
                c[2] = double(s.origin.z) + double(c[8]);
            } else {
                c[13] = int64_t(c[13]) + 1;
                if (int64_t(c[13]) > 10) { s.flags &= ~int64_t(1); continue; }
                c[3] = c[0]; c[4] = c[1]; c[5] = c[2];
                c[0] = double(s.origin.x) + double(c[6]);
                c[1] = double(s.origin.y) + double(c[7]);
                c[2] = double(s.origin.z) + double(c[8]) + double(s.vmin.x);
                const double k = s.size >= 0. ? 0.71428573 : 1.4;
                c[6] = double(c[6]) * k; c[7] = double(c[7]) * k; c[8] = double(c[8]) * k;
            }
        }
    }
    static bool update(const State &s, Array &p) {
        if (s.orbit) {
            if (int64_t(p[0x15]) < 0) {
                const Array c = s.controls[-1 - int64_t(p[0x15])];
                set_vector(p, 0, vector(c, 0));
                p[3] = (double(s.rng->randi()) * 9.313226e-11 + .8) * s.size * .4;
                if (!(s.flags & 1) || !s.carrier) {
                    const int64_t life = p[0x14];
                    if (life < 0) return false;
                    p[0x16] = alpha(orbit_alpha[std::clamp<int64_t>(life + 1, 0, 7)]);
                    p[0x14] = life - 1;
                }
                return true;
            }
            const int64_t life = int64_t(p[0x14]) - 1; p[0x14] = life;
            if (!life) return false;
            if (life < 7) p[0x16] = alpha(orbit_alpha[std::clamp<int64_t>(life, 0, 7)]);
            p[0x11] = int64_t(p[0x11]) + 1;
            if (int64_t(p[0x11]) == 16) p[0x11] = int64_t(12);
            set_vector(p, 0, vector(p, 8));
            p[3] = double(p[3]) * .97;
            p[10] = double(p[10]) + double(p[13]);
            p[13] = double(p[12]) * double(p[13]);
            return true;
        }
        p[0x14] = int64_t(p[0x14]) - 1;
        if (int64_t(p[0x14]) == 0) return false;
        if (int64_t(p[0x11]) < 12 && int64_t(p[0x15]) >= 0) {
            const Array c = s.controls[int64_t(p[0x15])];
            set_vector(p, 0, vector(c, 0));
            const int64_t index = std::clamp<int64_t>(c[13], 0, 15);
            p[3] = double(p[3]) * (s.size < 0. ? .9345794 : 1.07);
            p[0x16] = alpha(s.size < 0. ? mod_out[index] : mod_in[index]);
            return true;
        }
        p[0x13] = int64_t(p[0x13]) - 1;
        if (int64_t(p[0x13]) == 0) {
            p[0x11] = int64_t(p[0x11]) + 1;
            if (int64_t(p[0x11]) >= s.dc) p[0x11] = int64_t(12);
            p[0x13] = s.e4;
        }
        p[11] = double(p[11]) * .9; p[12] = double(p[12]) * .9; p[13] = double(p[13]) * .9;
        p[0] = double(p[11]) + double(p[8]);
        p[1] = double(p[12]) + double(p[9]);
        p[2] = double(p[13]) + double(p[10]);
        p[3] = double(p[3]) * .9;
        p[0x16] = alpha(((int64_t(p[0x16]) >> 24) & 255) - 48);
        return true;
    }
    static void spawn(const State &s, Array &parts, int64_t index) {
        Array p; p.resize(25); p.fill(int64_t(0));
        for (int i = 0; i < 4; ++i) p[i] = 0.;
        for (int i = 8; i < 17; ++i) p[i] = 0.;
        p[0x16] = int64_t(0xffffffff);
        if (s.orbit) {
            const int64_t ci = s.rng->randi() % s.ec;
            const Array c = s.controls[ci];
            p[0x11] = int64_t(12); p[0x14] = int64_t(28); p[0x13] = int64_t(1); p[0x15] = ci;
            const double f = s.random();
            p[12] = 1.03;
            p[13] = (double(s.rng->randi()) * 8.149073e-11 + .85) * double(c[5]) * .03;
            const double vx = s.range(s.vmin.x, s.vmax.x), vy = s.range(s.vmin.y, s.vmax.y), vz = s.range(s.vmin.z, s.vmax.z);
            const Vector3 v(vx, vy, vz), prev = vector(c, 9), cur = vector(c, 0);
            set_vector(p, 0, prev + v);
            set_vector(p, 8, cur * real_t(1. - f) + prev * real_t(f) + v);
            p[3] = (double(s.rng->randi()) * 1.862645e-10 + .6) * s.size * .2;
        } else {
            p[0x14] = s.ec; p[0x13] = s.e4;
            const Array first = s.controls[0];
            if (int64_t(first[13]) == 0 && index < s.controls.size()) {
                const Array c = s.controls[index];
                p[0x11] = s.type - 0x201b; p[0x15] = index;
                set_vector(p, 0, vector(c, 0)); p[3] = s.size >= 0. ? .125 : .2;
            } else {
                const Array c = s.controls[s.rng->randi() % s.controls.size()];
                const double t = s.random();
                set_vector(p, 8, vector(c, 0) * real_t(t) + vector(c, 3) * real_t(1. - t));
                p[11] = double(s.rng->randi()) * 1.8626451e-11 - .04;
                p[12] = double(s.rng->randi()) * 1.8626451e-11 - .04;
                p[13] = double(s.rng->randi()) * 1.8626451e-11 - .04;
                set_vector(p, 0, vector(p, 8)); p[3] = .06;
                p[0x11] = int64_t(12 + (s.rng->randi() & 3)); p[0x15] = int64_t(-1);
            }
        }
        previous(p); parts.append(p);
    }
protected:
    static void _bind_methods() { ClassDB::bind_method(D_METHOD("step", "emitter"), &SpellParticleKernel::step); }
public:
    bool step(Object *emitter) const {
        ERR_FAIL_NULL_V(emitter, false);
        static const StringName type("type"), ec("ec"), dc("dc"), e4("e4"), flags("flags"), cc("cc"),
            d0("d0"), d8("d8"), size("s"), moved("moved"), d4("d4"), wp("wp"), vmin("vmin"), vmax("vmax"),
            has_carrier("has_carrier"), rng("rng"), parts_key("parts"), cp("cp");
        Ref<RandomNumberGenerator> random = emitter->get(rng);
        ERR_FAIL_COND_V(random.is_null(), false);
        const int64_t kind = emitter->get(type);
        State s = {kind, emitter->get(ec), emitter->get(dc), emitter->get(e4), emitter->get(flags),
            emitter->get(cc), emitter->get(d0), emitter->get(d8), emitter->get(size), emitter->get(moved),
            emitter->get(d4), emitter->get(wp), emitter->get(vmin), emitter->get(vmax), emitter->get(has_carrier),
            kind >= 0x202b, random.ptr(), emitter->get(cp)};
        ERR_FAIL_COND_V(!((kind >= 0x201b && kind <= 0x2026) || (kind >= 0x202b && kind <= 0x202e)), false);
        ERR_FAIL_COND_V(s.controls.is_empty() || (s.orbit && (s.ec <= 0 || s.controls.size() < s.ec)), false);
        controls(s); emitter->set(flags, s.flags);
        Array parts = emitter->get(parts_key);
        const int64_t count = parts.size(); int64_t live = 0;
        for (int64_t i = 0; i < count; ++i) {
            Array p = parts[i];
            if (bool(p[0x18])) continue;
            previous(p);
            if (!update(s, p)) {
                p[0x18] = int64_t(1);
                p[0] = p[4]; p[1] = p[5]; p[2] = p[6];
                p[0x11] = p[0x12]; p[3] = p[7]; p[0x16] = p[0x17];
            }
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
