// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/plane.hpp>
#include <godot_cpp/variant/projection.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

namespace godot {
// Pure geometry; no retained scene references or alternative picking rules.
// Inputs have already received the same morph/skin and world transforms as
// MeshScreenRect's script path. Keep its float32 vector arithmetic and its
// double scalar arithmetic (clipping ratios and pixel mapping) in that order.
class ScreenRectKernel : public RefCounted {
    GDCLASS(ScreenRectKernel, RefCounted)
    static int32_t pixel(double value) {
        if (!std::isfinite(value) || value <= -0x1p63 || value >= 0x1p63) return 0;
        const double f = std::floor(value), d = value - f;
        const int64_t whole = int64_t(f);
        return int32_t(whole + (d > .5 || (d == .5 && whole % 2 != 0)));
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("bounds", "surfaces", "planes", "projection", "inverse_basis", "origin", "size"), &ScreenRectKernel::bounds);
    }
public:
    Rect2i bounds(const Array &surfaces, const TypedArray<Plane> &input_planes,
                 const Projection &projection, const Basis &inverse_basis,
                 Vector3 origin, Vector2 size) const {
        if (input_planes.size() != 6) return Rect2i();
        std::array<Plane, 6> planes;
        for (int i = 0; i < 6; ++i) planes[i] = input_planes[i];
        Vector2 lo(INFINITY, INFINITY), hi(-INFINITY, -INFINITY);
        bool any = false;
        auto project = [&](const Vector3 &point) {
            const Vector3 local = inverse_basis.xform(point - origin);
            const Vector4 p = projection.xform(Vector4(local.x, local.y, local.z, 1.f));
            Vector2 screen;
            if (p.w != 0.f) {
                const Vector3 normal = Vector3(p.x, p.y, p.z) / p.w;
                screen = Vector2((double(normal.x) * .5 + .5) * size.x,
                                 (-double(normal.y) * .5 + .5) * size.y);
            }
            lo = lo.min(screen); hi = hi.max(screen); any = true;
        };
        std::vector<Vector3> poly, next;
        poly.reserve(12); next.reserve(12);
        for (int64_t si = 0; si < surfaces.size(); ++si) {
            const Array surface = surfaces[si];
            if (surface.size() != 3) continue;
            const PackedVector3Array vertices = surface[0];
            const PackedInt32Array indices = surface[1];
            const int64_t primitive = surface[2], count = vertices.size();
            const Vector3 *vs = vertices.ptr();
            int outside = 0, common = 63;
            for (int64_t i = 0; i < count; ++i) {
                int code = 0;
                for (int j = 0; j < 6; ++j) if (planes[j].is_point_over(vs[i])) code |= 1 << j;
                outside |= code; common &= code;
            }
            if (common != 0) continue;
            if (outside == 0) {
                for (int64_t i = 0; i < count; ++i) project(vs[i]);
                continue;
            }
            // Godot Mesh::PRIMITIVE_TRIANGLES / TRIANGLE_STRIP. Other
            // primitives follow the existing script's wholly-inside rule.
            if (primitive != 3 && primitive != 4) continue;
            const bool indexed = !indices.is_empty();
            const int64_t index_count = indexed ? indices.size() : count;
            const int32_t *ids = indices.ptr();
            for (int64_t i = 0; i + 2 < index_count; i += primitive == 3 ? 3 : 1) {
                poly.clear();
                for (int j = 0; j < 3; ++j) {
                    const int64_t index = indexed ? ids[i + j] : i + j;
                    if (index < 0 || index >= count) { poly.clear(); break; }
                    poly.push_back(vs[index]);
                }
                for (const Plane &plane : planes) {
                    if (poly.empty()) break;
                    next.clear();
                    Vector3 prev = poly.back();
                    double dp = plane.distance_to(prev);
                    for (const Vector3 &point : poly) {
                        const double d = plane.distance_to(point);
                        if ((d <= 0.) != (dp <= 0.)) next.push_back(prev.lerp(point, real_t(dp / (dp - d))));
                        if (d <= 0.) next.push_back(point);
                        prev = point; dp = d;
                    }
                    poly.swap(next);
                }
                for (const Vector3 &point : poly) project(point);
            }
        }
        if (!any) return Rect2i();
        const Vector2i start(pixel(lo.x), pixel(lo.y)), end(pixel(hi.x), pixel(hi.y));
        return end.x > start.x && end.y > start.y ? Rect2i(start, end - start) : Rect2i();
    }
};
}
