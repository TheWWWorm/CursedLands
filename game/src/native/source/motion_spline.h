// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/core/math.hpp>
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
    struct Control { Vector2 p; int n; };
    struct Node { Vector2 p, d; double v; Vector2i cell; };
    std::vector<Control> controls;
    struct Segment { double length, interval; Vector2 cx, cy; };
    std::vector<Node> nodes;
    std::vector<Segment> segments;
    Vector2 start;
    double heading = 0., initial_turn = 0., turn_rate = 0., turning_time = 0., duration = 0.;
    static constexpr double pi = 3.14159265358979323846;
    static int direction(Vector2i d) {
        static const Vector2i dirs[] = {{0,0},{0,-1},{-1,-1},{-1,0},{-1,1},{0,1},{1,1},{1,0},{1,-1}};
        for (int i = 0; i < 9; ++i) if (d == dirs[i]) return i;
        return -1;
    }
    static int bend(int a, int b) { const int n = std::abs(a-b); return std::min(n,8-n); }
    static Vector2 coefficients(double a, double da, double b, double db, double length) {
        if (length <= .00000001) return Vector2();
        const double f = ((b-a)-da*length)/length*2.;
        const double cubic = ((db-da)-f)/(length*length);
        const double quadratic = (f-cubic*length*length*2.)/length*.5;
        return Vector2(quadratic,cubic);
    }
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
        ClassDB::bind_method(D_METHOD("build", "from", "to", "cells", "values", "base", "turn", "facing"), &MotionSplineKernel::build);
        ClassDB::bind_method(D_METHOD("records"), &MotionSplineKernel::records);
    }
public:
    bool configure(const Array &input, const PackedFloat64Array &lengths, const PackedFloat64Array &intervals,
            const PackedVector2Array &xs, const PackedVector2Array &ys, Vector2 p_start,
            double p_heading, double p_initial_turn, double p_turn_rate) {
        controls.clear(); nodes.clear(); segments.clear();
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
    // Route construction and sampling share owned typed storage. The normal
    // path never allocates per-control/per-node dictionaries; records() is a
    // lazy inspection/oracle boundary, not part of the movement loop.
    PackedFloat64Array build(Vector2 from, Vector2 to, const Array &input,
            const PackedInt32Array &values, double base, double turn, double facing) {
        PackedFloat64Array metadata;
        controls.clear(); nodes.clear(); segments.clear();
        if (!from.is_finite() || !to.is_finite() || !std::isfinite(base) ||
                !std::isfinite(turn) || !std::isfinite(facing) || input.size() > 1048576 ||
                from.abs().x > 1e7f || from.abs().y > 1e7f || to.abs().x > 1e7f || to.abs().y > 1e7f) return metadata;
        std::vector<Vector2i> cells; cells.reserve(size_t(input.size()));
        for (int64_t i = 0; i < input.size(); ++i) {
            if (input[i].get_type() != Variant::VECTOR2I) return metadata;
            const Vector2i cell = input[i];
            if (cell.x < -10000000 || cell.x > 10000000 || cell.y < -10000000 || cell.y > 10000000) return metadata;
            cells.push_back(cell);
        }
        start = from / .5f; heading = facing; turn_rate = turn;
        initial_turn = 0.; duration = 0.; turning_time = 0.;
        if (!cells.empty()) {
            controls.push_back({start,0});
            int previous = 0;
            for (size_t i = 0; i < cells.size(); ++i) {
                ++controls.back().n;
                if (i+1 == cells.size()) break;
                const int dir = direction(cells[i+1]-cells[i]);
                const Vector2 c(cells[i].x,cells[i].y);
                switch (dir) {
                    case 2: controls.push_back({c,0}); break;
                    case 4: controls.push_back({c+Vector2(0,1),0}); break;
                    case 6: controls.push_back({c+Vector2(1,1),0}); break;
                    case 8: controls.push_back({c+Vector2(1,0),0}); break;
                }
                bool bent = previous != 0 && bend(previous,dir) >= 2;
                if (i+2 < cells.size()) bent = bent || bend(dir,direction(cells[i+2]-cells[i+1])) >= 2;
                if (bent) switch (dir) {
                    case 1: controls.push_back({c+Vector2(.5,0),0}); break;
                    case 3: controls.push_back({c+Vector2(0,.5),0}); break;
                    case 5: controls.push_back({c+Vector2(.5,1),0}); break;
                    case 7: controls.push_back({c+Vector2(1,.5),0}); break;
                }
                previous = dir;
            }
            controls.push_back({to/.5f,0});
            size_t vi = 0;
            auto speed = [&]() { return double(vi < size_t(values.size()) ? values[int64_t(vi)] : 512)*base/512.; };
            for (size_t i = 0; i+1 < controls.size(); ++i) {
                const Vector2 a = controls[i].p, b = controls[i+1].p;
                const Vector2 tangent = (b-a)/real_t(std::max(double(a.distance_to(b)),.00001));
                const int n = controls[i].n;
                const double first = i == 0 ? -.5 : 0., last = i+2 == controls.size() ? .5 : 0.;
                if (n == 1 && first != 0. && last != 0.) {
                    const double v = speed(); const Vector2i cell = cells[std::min(vi,cells.size()-1)];
                    nodes.push_back({a,tangent,v,cell}); nodes.push_back({b,tangent,v,cell}); ++vi;
                    continue;
                }
                for (int j = 0; j < n; ++j) {
                    const double f = (double(j)+first+.5)/(double(n)+first-last);
                    nodes.push_back({a.lerp(b,real_t(f)),tangent,speed(),cells[std::min(vi,cells.size()-1)]});
                    ++vi;
                }
            }
            for (size_t i = 0; i+1 < nodes.size(); ++i) {
                Node &a = nodes[i]; const Node &b = nodes[i+1];
                const double delta = std::abs(Math::wrapf(double(a.d.angle())-double(b.d.angle()),-pi,pi));
                const double length = a.p.distance_to(b.p);
                if (delta > 0. && (turn <= 0. || length/std::max(a.v,.00000001) < delta/turn)) a.v = length*turn/delta;
            }
            if (!nodes.empty()) {
                const Vector2 first_direction = nodes[0].d;
                const double diff = Math::wrapf(double(first_direction.angle())-facing,-pi,pi);
                if (std::cos(diff) > .9) nodes[0].d = Vector2::from_angle(facing);
                else if (first_direction != Vector2()) initial_turn = diff;
                turning_time = turn_rate > 0. ? std::abs(initial_turn)/turn_rate :
                    (initial_turn != 0. ? std::numeric_limits<double>::infinity() : 0.);
                duration = turning_time;
                for (size_t i = 0; i+1 < nodes.size(); ++i) {
                    const Node &a = nodes[i], &b = nodes[i+1];
                    const double length = a.p.distance_to(b.p);
                    const double interval = a.v > 0. ? length/a.v : std::numeric_limits<double>::infinity();
                    segments.push_back({length,interval,coefficients(a.p.x,a.d.x,b.p.x,b.d.x,length),
                        coefficients(a.p.y,a.d.y,b.p.y,b.d.y,length)});
                    duration += interval;
                }
            }
        }
        metadata.push_back(initial_turn); metadata.push_back(duration); return metadata;
    }
    Dictionary records() const {
        Array control_records, node_records;
        PackedFloat64Array lengths, intervals;
        PackedVector2Array xs, ys;
        for (const Control &c : controls) { Dictionary r; r["p"]=c.p; r["n"]=c.n; control_records.append(r); }
        for (const Node &n : nodes) {
            Dictionary r; r["p"]=n.p; r["d"]=n.d; r["v"]=n.v; r["cell"]=n.cell; node_records.append(r);
        }
        for (const Segment &s : segments) {
            lengths.push_back(s.length); intervals.push_back(s.interval); xs.push_back(s.cx); ys.push_back(s.cy);
        }
        Dictionary out;
        out["controls"]=control_records; out["nodes"]=node_records; out["lengths"]=lengths; out["intervals"]=intervals;
        out["xs"]=xs; out["ys"]=ys; return out;
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
