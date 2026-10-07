// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "unit_simulation_state.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <algorithm>
#include <cmath>
#include <unordered_set>

namespace godot {
// One sequential perception query, not a tick-wide actor snapshot. Candidate
// membership/order, buffs, positions and deaths are read at the original AI
// decision point. Only actual occlusion tests cross back into the world.
class PerceptionKernel : public RefCounted {
    GDCLASS(PerceptionKernel, RefCounted)
    static constexpr double pi = 3.14159265358979323846;
    static bool detections(Object *unit, const UnitSimulationState *state, double &sight, double &life) {
        static const StringName proto_key("proto"), buffs_key("buffs");
        static const String detection_key("detection"), detect_key("detect");
        const Dictionary proto = state ? state->proto : Dictionary(unit->get(proto_key)), buffs = state ? state->buffs : Dictionary(unit->get(buffs_key));
        const Variant source = proto.get(detection_key, Array());
        double values[2] = {1., 1.};
        // Authored database float vectors are packed float32 arrays. Read
        // them directly; materializing an Array would allocate per target.
        if (source.get_type() == Variant::PACKED_FLOAT32_ARRAY) {
            const PackedFloat32Array base = source;
            if (base.size() > 0) values[0] = base[0];
            if (base.size() > 2) values[1] = base[2];
        } else if (source.get_type() == Variant::PACKED_FLOAT64_ARRAY) {
            const PackedFloat64Array base = source;
            if (base.size() > 0) values[0] = base[0];
            if (base.size() > 2) values[1] = base[2];
        } else if (source.get_type() == Variant::ARRAY) {
            const Array base = source;
            if (base.size() > 0) values[0] = base[0];
            if (base.size() > 2) values[1] = base[2];
        } else return false;
        double lo[2] = {}, hi[2] = {};
        const Array rows = buffs.is_empty() ? Array() : buffs.values();
        for (int64_t i = 0; i < rows.size(); ++i) {
            if (rows[i].get_type() != Variant::DICTIONARY) return false;
            const Dictionary b = rows[i];
            if (!b.has(detect_key)) continue;
            const Variant record = b[detect_key];
            if (record.get_type() != Variant::ARRAY) return false;
            const Array term = record;
            if (term.size() < 2) return false;
            const int64_t kind = term[0];
            if (kind != 0 && kind != 2) continue;
            const double amount = term[1];
            if (!std::isfinite(amount)) return false;
            const int index = kind == 0 ? 0 : 1;
            lo[index] = std::min(lo[index], amount);
            hi[index] = std::max(hi[index], amount);
        }
        if (!std::isfinite(values[0]) || !std::isfinite(values[1])) return false;
        sight = std::max(0., values[0] + lo[0] + hi[0]);
        life = std::max(0., values[1] + lo[1] + hi[1]);
        return true;
    }
    static bool visible(Object *observer, Object *target, Object *world, Object *ai,
            Vector2 from, double facing, const PackedFloat64Array &terms, const UnitSimulationState *state) {
        static const StringName pos_key("pos"), dead_key("dead"),
            stance_key("stance"), action_key("action"), ray_method("sight_ray"), scalar_method("can_notice_with");
        // Unusual legacy effect records retain the scalar conversions.
        double sight, life;
        if (!detections(target, state, sight, life))
            return bool(ai->call(scalar_method, observer, target, terms));
        const Vector2 to = state ? state->pos : Vector2(target->get(pos_key));
        if (!from.is_finite() || !to.is_finite() || !std::isfinite(facing))
            return bool(ai->call(scalar_method, observer, target, terms));
        const double distance = from.distance_to(to);
        const int64_t stance = state ? state->stance : int64_t(target->get(stance_key));
        const String action = state ? state->action : String(target->get(action_key));
        const double visibility = (stance == 2 ? .5 : stance == 1 ? .75 : 1.) * (action.begins_with("cast") ? 1.5 : 1.);
        const double range = terms[0] * visibility * terms[1] * sight;
        if (distance <= range || distance < terms[3]) {
            const double angle = std::abs(Math::wrapf(double((to - from).angle()) - facing, -pi, pi));
            double ray = -1.;
            if (distance <= range && angle <= terms[2]) {
                ray = world->call(ray_method, observer, target);
                if (distance < ray * range) return true;
            }
            if (angle <= pi * .5 && distance < terms[3]) {
                if (ray < 0.) ray = world->call(ray_method, observer, target);
                if (ray > .0001) return true;
            }
        }
        return !(state ? state->dead : bool(target->get(dead_key))) && distance < life * terms[4];
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("new_visible", "candidates", "unit_script", "observer", "world", "ai", "terms", "noticed", "corpses", "radius"), &PerceptionKernel::new_visible);
    }
public:
    Variant new_visible(const Array &candidates, const Ref<Script> &unit_script, Object *observer,
            Object *world, Object *ai, PackedFloat64Array terms, const Dictionary &noticed,
            const Dictionary &corpses, double radius) const {
        Array result;
        if (!observer || !world || !ai || unit_script.is_null()) return result;
        static const StringName dead_key("dead"), hidden_key("hidden"), terms_method("notice_terms"), scalar_method("can_notice_with"), pos_key("pos"), facing_key("facing");
        const Ref<UnitSimulationState> observer_state=UnitSimulationState::of(observer,unit_script);
        const Vector2 from = observer_state.is_valid() ? observer_state->pos : Vector2(observer->get(pos_key));
        const double facing = observer_state.is_valid() ? observer_state->facing : double(observer->get(facing_key));
        std::unordered_set<uint64_t> seen;
        for (int64_t i = 0; i < candidates.size(); ++i) {
            Object *target = candidates[i].get_validated_object();
            if (!target) continue;
            Ref<Script> script = target->get_script();
            const Ref<Script> actual = script;
            while (script.is_valid() && script != unit_script) script = script->get_base_script();
            if (script != unit_script) continue;
            // Custom target methods may observe the suspicion updates between
            // candidates. Return nil to keep the entire original script loop.
            if (actual != unit_script) return Variant();
            const Ref<UnitSimulationState> state=UnitSimulationState::of(target,unit_script);
            if (state.is_valid() ? state->hidden : bool(target->get(hidden_key))) continue;
            const uint64_t id = target->get_instance_id();
            if (((state.is_valid() ? state->dead : bool(target->get(dead_key))) ? corpses : noticed).has(int64_t(id)) || !seen.insert(id).second) continue;
            if (terms.is_empty()) terms = ai->call(terms_method, observer, radius);
            if (terms.size() != 5) return result;
            bool finite = true;
            for (int j = 0; j < 5; ++j) finite = finite && std::isfinite(terms[j]);
            const bool accepted = finite ? visible(observer, target, world, ai, from, facing, terms, state.ptr()) :
                bool(ai->call(scalar_method, observer, target, terms));
            if (accepted) result.append(candidates[i]);
        }
        return result;
    }
};
} // namespace godot
