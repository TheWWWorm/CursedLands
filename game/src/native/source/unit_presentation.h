// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/array.hpp>
#include <algorithm>
#include <cmath>
#include "net_smooth.h"

namespace godot {
// A replica's placement pass, before animation/camera callbacks. Scene changes
// stay on the main thread; common terrain state is read once for the roster.
// The script path remains the independent fallback and correctness oracle.
class UnitPresentationKernel : public RefCounted {
    GDCLASS(UnitPresentationKernel, RefCounted)
    const StringName world_key = "world", terrain_key = "terrain", nav_key = "nav", authority_key = "authority";
    const StringName surface_key = "surface_rev", floor_key = "floor_rev", ground_method = "ground_at";
    const StringName pos_key = "pos", facing_key = "facing", net_key = "net_view";
    const StringName view_key = "view", yaw_key = "yaw", speed_key = "_speed", turn_key = "_yaw_speed";
    const StringName motion_key = "_move_speed", draw_motion_key = "_draw_move_speed", drawn_key = "_drawn";
    const StringName xf_pos_key = "_xf_pos", xf_yaw_key = "_xf_facing", xf_tid_key = "_xf_tid";
    const StringName xf_rev_key = "_xf_rev", xf_floor_key = "_xf_floor_rev", xf_key = "_xf";
    const StringName screen_key = "_screen", frame_key = "_placement_frame";
    const StringName placement_revision_key = "_placement_revision";
    struct Ground {
        Object *world = nullptr;
        int64_t terrain = 0, surface = 0, floor = 0;
    };
    Ground ground_state(Object *world) const {
        Ground state;
        if (!world || bool(world->get(authority_key))) return state;
        state.world = world;
        if (Object *terrain = world->get(terrain_key).get_validated_object()) {
            state.terrain = terrain->get_instance_id();
            state.surface = terrain->get(surface_key);
        }
        if (Object *nav = world->get(nav_key).get_validated_object()) state.floor = nav->get(floor_key);
        return state;
    }
    bool place(Node3D *unit, const Ground &state, double dt) const {
        if (!state.world || !unit || unit->get(world_key).get_validated_object() != state.world) return false;
        Object *smooth = unit->get(net_key).get_validated_object();
        if (!smooth) return false;
        const Vector2 target = unit->get(pos_key);
        const double facing = unit->get(facing_key);
        if (auto *record = Object::cast_to<NetSmoothKernel>(smooth)) {
            const Vector2 point = record->step(target, dt);
            const double yaw = record->step_yaw(facing, dt);
            unit->set(draw_motion_key, unit->get(motion_key));
            auto &cache = record->placement;
            const int64_t revision = unit->get(placement_revision_key);
            if (!cache.valid || cache.unit != unit->get_instance_id() || cache.world != state.world->get_instance_id() || cache.revision != revision) {
                cache.valid = true; cache.unit = unit->get_instance_id(); cache.world = state.world->get_instance_id(); cache.revision = revision;
                cache.point = unit->get(xf_pos_key); cache.yaw = unit->get(xf_yaw_key);
                cache.terrain = unit->get(xf_tid_key); cache.surface = unit->get(xf_rev_key); cache.floor = unit->get(xf_floor_key);
                cache.transform = unit->get(xf_key);
            }
            const Transform3D current = unit->get_transform();
            if (point == cache.point && yaw == cache.yaw && state.terrain == cache.terrain &&
                    state.surface == cache.surface && state.floor == cache.floor && current == cache.transform) return true;
            unit->set(drawn_key, point);
            const double height = state.world->call(ground_method, point.x, point.y);
            const Transform3D next(Basis(Vector3(0, 1, 0), yaw + Math::PI * 0.5), Vector3(point.x, height, -point.y));
            if (current != next) {
                const bool jump = current.origin.distance_squared_to(next.origin) > 4.0;
                unit->set_transform(next);
                if (jump) unit->reset_physics_interpolation();
            }
            cache.point = point; cache.yaw = yaw; cache.terrain = state.terrain;
            cache.surface = state.surface; cache.floor = state.floor; cache.transform = unit->get_transform();
            unit->set(xf_pos_key, point); unit->set(xf_yaw_key, yaw); unit->set(xf_tid_key, state.terrain);
            unit->set(xf_rev_key, state.surface); unit->set(xf_floor_key, state.floor); unit->set(xf_key, cache.transform);
            return true;
        }
        Vector2 point = smooth->get(view_key);
        double yaw = smooth->get(yaw_key);
        const Vector2 unplaced(INFINITY, INFINITY);
        if (point == unplaced || point.distance_to(target) > 6.0) {
            point = target;
            yaw = INFINITY;
        } else {
            point = point.move_toward(target, std::max(double(smooth->get(speed_key)), 0.5) * std::max(dt, 0.0));
        }
        yaw = yaw == INFINITY ? facing : Math::rotate_toward(yaw, facing,
            std::max(double(smooth->get(turn_key)), 2.0) * std::max(dt, 0.0));
        smooth->set(view_key, point);
        smooth->set(yaw_key, yaw);
        unit->set(draw_motion_key, unit->get(motion_key));
        const Transform3D current = unit->get_transform();
        if (point == Vector2(unit->get(xf_pos_key)) && yaw == double(unit->get(xf_yaw_key)) &&
                state.terrain == int64_t(unit->get(xf_tid_key)) && state.surface == int64_t(unit->get(xf_rev_key)) &&
                state.floor == int64_t(unit->get(xf_floor_key)) && current == Transform3D(unit->get(xf_key))) return true;
        unit->set(drawn_key, point);
        const double height = state.world->call(ground_method, point.x, point.y);
        const Transform3D next(Basis(Vector3(0, 1, 0), yaw + Math::PI * 0.5), Vector3(point.x, height, -point.y));
        if (current != next) {
            const bool jump = current.origin.distance_squared_to(next.origin) > 4.0;
            unit->set_transform(next);
            if (jump) unit->reset_physics_interpolation();
        }
        unit->set(xf_pos_key, point);
        unit->set(xf_yaw_key, yaw);
        unit->set(xf_tid_key, state.terrain);
        unit->set(xf_rev_key, state.surface);
        unit->set(xf_floor_key, state.floor);
        unit->set(xf_key, unit->get_transform());
        return true;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("sync_clients", "world", "units", "delta", "frame"), &UnitPresentationKernel::sync_clients);
        ClassDB::bind_method(D_METHOD("sync_client", "world", "unit", "delta"), &UnitPresentationKernel::sync_client);
    }
public:
    bool sync_client(Object *world, Node3D *unit, double dt) const {
        return place(unit, ground_state(world), dt);
    }
    int64_t sync_clients(Node *world, const Array &units, double dt, int64_t frame) const {
        const Ground state = ground_state(world);
        if (!state.world) return 0;
        int64_t count = 0;
        for (int64_t i = 0; i < units.size(); ++i) {
            Node3D *unit = Object::cast_to<Node3D>(units[i].get_validated_object());
            // A custom earlier callback keeps its own placement. Disabled,
            // detached and not-yet-built figures keep their original behavior.
            if (!unit || !unit->is_inside_tree() || !unit->is_processing() || !unit->can_process() ||
                    unit->get_process_priority() < world->get_process_priority() ||
                    !unit->get(screen_key).get_validated_object()) continue;
            if (place(unit, state, dt)) {
                unit->set(frame_key, frame);
                ++count;
            }
        }
        return count;
    }
};
} // namespace godot
