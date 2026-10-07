// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <algorithm>
#include <cmath>
#include <limits>
#include <vector>

namespace godot {
// An immutable route owns typed motion records. Evaluation keeps the scalar
// subtraction order and double intermediates used by GDScript, including its
// float Vector2 coefficient rounding. Backward seeks need no mutable cursor.
class MotionSplineKernel : public RefCounted {
    GDCLASS(MotionSplineKernel, RefCounted)
    struct Node { Vector2 p, d; double v; Vector2i cell; };
    struct Segment { double length, interval; Vector2 cx, cy; };
    std::vector<Node> nodes;
    std::vector<Segment> segments;
    Vector2 start;
    double heading = 0., initial_turn = 0., turn_rate = 0., turning_time = 0.;
    static Dictionary result(Vector2 p, Vector2 d, double v, Vector2i cell, int index, bool turning, bool active) {
        Dictionary out;
        out["p"] = p; out["d"] = d; out["v"] = v; out["cell"] = cell;
        out["index"] = index; out["turning"] = turning; out["active"] = active;
        return out;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure", "nodes", "lengths", "intervals", "x_coefficients", "y_coefficients", "start", "heading", "initial_turn", "turn_rate"), &MotionSplineKernel::configure);
        ClassDB::bind_method(D_METHOD("sample", "tick"), &MotionSplineKernel::sample);
    }
public:
    bool configure(const Array &input, const PackedFloat64Array &lengths, const PackedFloat64Array &intervals,
            const PackedVector2Array &xs, const PackedVector2Array &ys, Vector2 p_start,
            double p_heading, double p_initial_turn, double p_turn_rate) {
        nodes.clear(); segments.clear();
        start = p_start; heading = p_heading; initial_turn = p_initial_turn; turn_rate = p_turn_rate;
        turning_time = turn_rate > 0. ? std::abs(initial_turn) / turn_rate :
            (initial_turn != 0. ? std::numeric_limits<double>::infinity() : 0.);
        const int64_t count = std::max(int64_t(0), input.size() - 1);
        if (lengths.size() != count || intervals.size() != count || xs.size() != count || ys.size() != count) return false;
        for (int64_t i = 0; i < input.size(); ++i) {
            if (input[i].get_type() != Variant::DICTIONARY) { nodes.clear(); return false; }
            const Dictionary row = input[i];
            const Variant p = row.get("p", Variant()), d = row.get("d", Variant()),
                v = row.get("v", Variant()), cell = row.get("cell", Variant());
            if (p.get_type() != Variant::VECTOR2 || d.get_type() != Variant::VECTOR2 ||
                (v.get_type() != Variant::FLOAT && v.get_type() != Variant::INT) || cell.get_type() != Variant::VECTOR2I) {
                nodes.clear(); return false;
            }
            nodes.push_back({p, d, double(v), cell});
        }
        for (int64_t i = 0; i < count; ++i) segments.push_back({lengths[i], intervals[i], xs[i], ys[i]});
        return true;
    }
    Dictionary sample(double tick) const {
        if (nodes.empty()) return result(start * .5f, Vector2::from_angle(heading), 0., Vector2i(), 0, false, false);
        if (tick <= turning_time) {
            const double sign = initial_turn > 0. ? 1. : (initial_turn < 0. ? -1. : 0.);
            const double angle = heading + sign * std::max(tick, 0.) * turn_rate;
            return result(start * .5f, Vector2::from_angle(angle), 0., nodes[0].cell, 0, true, true);
        }
        double t = tick - turning_time;
        for (size_t i = 0; i < segments.size(); ++i) {
            const Segment &seg = segments[i];
            if (t <= seg.interval) {
                const Node &a = nodes[i], &b = nodes[i+1];
                const double s = std::min(t * a.v, seg.length);
                const Vector2 p(((s * double(seg.cx.y) + double(seg.cx.x)) * s + double(a.d.x)) * s + double(a.p.x),
                    ((s * double(seg.cy.y) + double(seg.cy.x)) * s + double(a.d.y)) * s + double(a.p.y));
                const Vector2 d((2. * double(seg.cx.x) + s * double(seg.cx.y) * 3.) * s + double(a.d.x),
                    (2. * double(seg.cy.x) + s * double(seg.cy.y) * 3.) * s + double(a.d.y));
                return result(p * .5f, d, a.v, b.cell, int(i+1), false, true);
            }
            t -= seg.interval;
        }
        const Node &last = nodes.back();
        return result(last.p * .5f, last.d, 0., last.cell, int(nodes.size()-1), false, false);
    }
};
} // namespace godot
