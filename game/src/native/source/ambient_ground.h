// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <cmath>

namespace godot {
// AmbientHabitat's ordered highest-triangle query, not GrassFieldKernel's
// first-hit query. Borrow current arrays for this call; retain no terrain or
// result. Optional visible-ground displacement remains with its script owner.
class AmbientGroundKernel : public RefCounted {
    GDCLASS(AmbientGroundKernel, RefCounted)
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("sample", "point", "size", "stride", "heights",
            "xy", "tiles", "types", "per_atlas", "elevation"), &AmbientGroundKernel::sample);
    }
public:
    Variant sample(Vector2 p, Vector2i size, int64_t stride, const PackedFloat32Array &heights,
            const PackedVector2Array &xy, const PackedInt32Array &tiles,
            const PackedInt32Array &types, int64_t per_atlas, const Callable &elevation) const {
        const int width = size.x, height = size.y;
        if (width <= 0 || height <= 0 || width > 8192 || height > 8192 || (width & 1) || (height & 1) ||
                stride != width + 1 || per_atlas <= 0 || per_atlas > 256) return Variant();
        const int64_t vertices = stride * (height + 1), tile_count = int64_t(width / 2) * (height / 2);
        if (heights.size() < vertices || xy.size() < vertices || tiles.size() < tile_count) return Variant();
        Dictionary best;
        if (!p.is_finite() || p.x < 0 || p.y < 0 || p.x >= width || p.y >= height) return best;
        const Vector2i cell(int(std::floor(p.x)), int(std::floor(p.y)));
        const bool drawn = elevation.is_valid();
        static constexpr int triangles[2][3] = {{2,1,0},{1,2,3}};
        double best_height = 0.;
        for (int dy = -1; dy <= 1; ++dy) {
            for (int dx = -1; dx <= 1; ++dx) {
                const Vector2i q = cell + Vector2i(dx, dy);
                if (q.x < 0 || q.y < 0 || q.x >= width || q.y >= height) continue;
                const Vector2i corners[4] = {q, q + Vector2i(1,0), q + Vector2i(0,1), q + Vector2i(1,1)};
                Vector3 points[4];
                for (int j = 0; j < 4; ++j) {
                    const int64_t at = corners[j].y * stride + corners[j].x;
                    const Vector2 jitter = xy[at];
                    points[j] = Vector3(double(corners[j].x) + jitter.x, heights[at], -double(corners[j].y) - jitter.y);
                }
                for (const auto &tri : triangles) {
                    const Vector3 a = points[tri[0]], b = points[tri[1]], c = points[tri[2]];
                    const Vector2 ab(double(b.x) - a.x, -double(b.z) + a.z);
                    const Vector2 ac(double(c.x) - a.x, -double(c.z) + a.z);
                    const double det = ab.cross(ac);
                    if (std::abs(det) < .000001) continue;
                    const Vector2 ap = p - Vector2(a.x, -a.z);
                    const double u = double(ap.cross(ac)) / det, v = double(ab.cross(ap)) / det;
                    if (u < -.00001 || v < -.00001 || u + v > 1.00001) continue;
                    // GDScript Vector components become double scalars. Keep
                    // this evaluation order, including float Vector3 weights
                    // when calling the existing drawn-ground interpolation.
                    double hit_height = double(a.y) + (double(b.y) - a.y) * u + (double(c.y) - a.y) * v;
                    if (drawn) hit_height = double(elevation.call(a, b, c, Vector3(1. - u - v, u, v), q));
                    if (best.is_empty() || hit_height > best_height) {
                        const int code = tiles[(q.y / 2) * (width / 2) + q.x / 2];
                        const int64_t type_index = ((code >> 6) & 255) * per_atlas * per_atlas + (code & 63);
                        best_height = hit_height;
                        best["height"] = hit_height;
                        best["normal"] = (c - a).cross(b - a).normalized();
                        best["type"] = type_index < types.size() ? int(types[type_index]) : 8;
                        best["code"] = code;
                    }
                }
            }
        }
        return best;
    }
};
}
