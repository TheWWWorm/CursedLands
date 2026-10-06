// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "ai_activity_core.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace godot {
class AIActivityKernel : public RefCounted {
    GDCLASS(AIActivityKernel, RefCounted)
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("evaluate", "positions", "radii", "factions", "flags", "hostile_masks"), &AIActivityKernel::evaluate);
    }
public:
    PackedByteArray evaluate(const PackedVector2Array &positions, const PackedFloat64Array &radii,
                             const PackedInt64Array &factions, const PackedByteArray &flags, const PackedInt64Array &hostile_masks) const {
        const int64_t n = positions.size();
        PackedByteArray result; result.resize(n); result.fill(1);
        if (radii.size() != n || factions.size() != n || flags.size() != n || hostile_masks.size() != n) return result;
        std::vector<ei_activity::Actor> rows;
        rows.reserve(size_t(n));
        for (int64_t i = 0; i < n; ++i) {
            const Vector2 p = positions[i];
            rows.push_back({double(p.x), double(p.y), radii[i], factions[i], flags[i], uint32_t(hostile_masks[i])});
        }
        const auto active = ei_activity::evaluate(rows);
        for (int64_t i = 0; i < n; ++i) result[i] = active[size_t(i)];
        return result;
    }
};
}
