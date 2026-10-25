// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {
// Scan the live registry in its original order. Nearby-unit animation/audio
// work and custom-unit behavior remain synchronous script callbacks. No
// positions, admission results, actor references or sound state are retained.
class UnitSoundScanKernel : public RefCounted {
    GDCLASS(UnitSoundScanKernel, RefCounted)
    const StringName states_name="_units",stamp_name="_stamp",pos_name="pos";
    const String seen_name="seen",far_name="far";
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("scan", "collector", "units", "listener", "radius_squared", "unit_script", "near", "fallback"), &UnitSoundScanKernel::scan);
    }
public:
    int64_t scan(RefCounted *collector, const Array &units, Vector2 listener, double radius_squared,
            const Ref<Script> &unit_script, const Callable &near, const Callable &fallback) const {
        Dictionary states=collector->get(states_name);
        int64_t stamp=collector->get(stamp_name), count=0;
        const Dictionary empty;
        for (int64_t i=0;i<units.size();++i) {
            Node *unit=Object::cast_to<Node>(units[i].get_validated_object());
            if (!unit) continue;
            if (Ref<Script>(unit->get_script())!=unit_script) {
                count+=int64_t(fallback.call(unit,listener));
            } else {
                const int64_t id=unit->get_instance_id();
                const Variant value=states.get(id,empty);
                if (value.get_type()!=Variant::DICTIONARY) {
                    count+=int64_t(fallback.call(unit,listener));
                } else {
                    Dictionary state=value;
                    const Vector2 position=unit->get(pos_name);
                    if (position.distance_squared_to(listener)>radius_squared) {
                        if (!state.is_empty()) {
                            ++count;state[seen_name]=stamp;state[far_name]=true;
                        }
                        continue;
                    }
                    count+=int64_t(near.call(unit,id,state));
                }
            }
            // A wake/audio/custom callback may synchronously replace state
            // or reenter tick(). Subsequent units observe those current fields.
            states=collector->get(states_name);stamp=collector->get(stamp_name);
        }
        return count;
    }
};
}
