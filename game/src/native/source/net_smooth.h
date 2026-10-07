// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <algorithm>
#include <cmath>

namespace godot {
// Replica interpolation is ordinary numeric state. The native placement pass
// can read it directly, instead of reflecting through a GDScript object for
// each scalar on each rendered frame. All access remains on the main thread.
class NetSmoothKernel : public RefCounted {
    GDCLASS(NetSmoothKernel, RefCounted)
public:
    Vector2 view = Vector2(INFINITY, INFINITY);
    double yaw = INFINITY, speed = 0.0, yaw_speed = 0.0, interval = 0.1;
    int64_t last_ms = 0;
    struct Placement {
        bool valid = false;
        uint64_t unit = 0, world = 0;
        int64_t revision = -1, terrain = -1, surface = 0, floor = -1;
        Vector2 point = Vector2(INFINITY, INFINITY);
        double yaw = 0.0;
        Transform3D transform;
    } placement;

    void got_at(Vector2 target, int64_t now, bool quiet, double facing) {
        if (last_ms > 0) interval = Math::clamp(Math::lerp(interval, double(now - last_ms) / 1000.0, 0.25), 0.05, 0.4);
        last_ms = now;
        if (quiet || view == Vector2(INFINITY, INFINITY) || view.distance_to(target) > 6.0) {
            view = target; speed = 0.0;
            if (facing != INFINITY) yaw = facing;
            yaw_speed = 0.0;
            return;
        }
        speed = view.distance_to(target) / interval;
        if (facing != INFINITY && yaw != INFINITY) yaw_speed = std::abs(Math::angle_difference(yaw, facing)) / interval;
    }
    void got(Vector2 target, bool quiet, double facing) { got_at(target, Time::get_singleton()->get_ticks_msec(), quiet, facing); }
    Vector2 step(Vector2 target, double dt) {
        if (view == Vector2(INFINITY, INFINITY) || view.distance_to(target) > 6.0) {
            view = target; yaw = INFINITY;
        } else view = view.move_toward(target, std::max(speed, 0.5) * std::max(dt, 0.0));
        return view;
    }
    double step_yaw(double facing, double dt) {
        yaw = yaw == INFINITY ? facing : Math::rotate_toward(yaw, facing, std::max(yaw_speed, 2.0) * std::max(dt, 0.0));
        return yaw;
    }
    void set_view(Vector2 value) { view = value; }
    Vector2 get_view() const { return view; }
    void set_yaw(double value) { yaw = value; }
    double get_yaw() const { return yaw; }
    void set_speed(double value) { speed = value; }
    double get_speed() const { return speed; }
    void set_yaw_speed(double value) { yaw_speed = value; }
    double get_yaw_speed() const { return yaw_speed; }
    void set_interval(double value) { interval = value; }
    double get_interval() const { return interval; }
    void set_last_ms(int64_t value) { last_ms = value; }
    int64_t get_last_ms() const { return last_ms; }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("got", "target", "quiet", "facing"), &NetSmoothKernel::got, DEFVAL(false), DEFVAL(INFINITY));
        ClassDB::bind_method(D_METHOD("got_at", "target", "now", "quiet", "facing"), &NetSmoothKernel::got_at);
        ClassDB::bind_method(D_METHOD("step", "target", "delta"), &NetSmoothKernel::step);
        ClassDB::bind_method(D_METHOD("step_yaw", "facing", "delta"), &NetSmoothKernel::step_yaw);
#define SMOOTH_FIELD(name, field, type) \
        ClassDB::bind_method(D_METHOD("set_" #field, "value"), &NetSmoothKernel::set_##field); \
        ClassDB::bind_method(D_METHOD("get_" #field), &NetSmoothKernel::get_##field); \
        ADD_PROPERTY(PropertyInfo(type, name), "set_" #field, "get_" #field)
        SMOOTH_FIELD("view", view, Variant::VECTOR2);
        SMOOTH_FIELD("yaw", yaw, Variant::FLOAT);
        SMOOTH_FIELD("_speed", speed, Variant::FLOAT);
        SMOOTH_FIELD("_yaw_speed", yaw_speed, Variant::FLOAT);
        SMOOTH_FIELD("_interval", interval, Variant::FLOAT);
        SMOOTH_FIELD("_last_ms", last_ms, Variant::INT);
#undef SMOOTH_FIELD
    }
};
} // namespace godot
