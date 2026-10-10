#pragma once
// Optional main-thread mean-water queries. One owner per cached sector; no
// scene, navigation, clock or GPU state. The script retains indexing and LRU.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <algorithm>
#include <cmath>
#include <limits>
#include <vector>

namespace godot {
class WaterSurfaceKernel : public RefCounted {
    GDCLASS(WaterSurfaceKernel, RefCounted)
    PackedVector3Array vertices;
    PackedInt32Array indices;
    std::vector<uint8_t> owners, ready;
    std::vector<Vector3> posed;
    int64_t frame = 0;
    bool valid = false, started = false;

    Vector3 vertex(int32_t index, const Transform3D &xf, const Dictionary &offsets) {
        if (!ready[index]) {
            Vector3 p = vertices[index];
            p.y = float(double(p.y) + double(offsets.get(int64_t(owners[index]), 0.0)));
            posed[index] = xf.xform(p);
            ready[index] = 1;
        }
        return posed[index];
    }

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("initialize", "vertices", "indices", "uv2"), &WaterSurfaceKernel::initialize);
        ClassDB::bind_method(D_METHOD("sample_mean", "point", "transform", "triangles", "offsets", "lava", "frame", "best"), &WaterSurfaceKernel::sample_mean);
        ClassDB::bind_method(D_METHOD("cache_bytes"), &WaterSurfaceKernel::cache_bytes);
    }

public:
    bool initialize(const PackedVector3Array &points, const PackedInt32Array &faces, const PackedVector2Array &uv2) {
        // Reject unsupported inputs before replacing the previous snapshot.
        if (points.is_empty() || points.size() != uv2.size() || faces.size() % 3 != 0) return false;
        for (int64_t i = 0; i < faces.size(); ++i) {
            if (faces[i] < 0 || faces[i] >= points.size()) return false;
        }
        for (int64_t i = 0; i < uv2.size(); ++i) {
            const double encoded = double(uv2[i].y) + .5;
            if (!std::isfinite(encoded) || encoded < double(std::numeric_limits<int64_t>::min()) ||
                    encoded >= -double(std::numeric_limits<int64_t>::min())) return false;
        }
        vertices = points; indices = faces;
        owners.resize(points.size()); ready.assign(points.size(), 0); posed.resize(points.size());
        for (int64_t i = 0; i < uv2.size(); ++i) {
            owners[i] = uint8_t(std::clamp(int64_t(double(uv2[i].y) + .5) % 64, int64_t(0), int64_t(63)));
        }
        started = false; valid = true;
        return true;
    }

    int64_t cache_bytes() const {
        // Geometry is shared packed input. Count only owned vector capacity.
        return int64_t(owners.capacity() + ready.capacity()) + int64_t(posed.capacity()) * sizeof(Vector3);
    }

    Dictionary sample_mean(Vector2 point, const Transform3D &xf, const PackedInt32Array &triangles,
            const Dictionary &offsets, const PackedFloat32Array &lava, int64_t epoch, Dictionary best) {
        if (!valid || !point.is_finite()) return best;
        // Validate the entire bucket before changing the lazy vertex cache.
        for (int64_t i = 0; i < triangles.size(); ++i) {
            const int64_t at = triangles[i];
            if (at < 0 || at % 3 != 0 || at + 2 >= indices.size()) return best;
        }
        if (!started || epoch != frame) {
            std::fill(ready.begin(), ready.end(), 0); frame = epoch; started = true;
        }
        for (int64_t i = 0; i < triangles.size(); ++i) {
            const int64_t at = triangles[i];
            const int32_t ia = indices[at], ib = indices[at + 1], ic = indices[at + 2];
            const Vector3 a = vertex(ia, xf, offsets), b = vertex(ib, xf, offsets), c = vertex(ic, xf, offsets);
            // GDScript scalar arithmetic is double; vector storage/cross is
            // float32. Preserve both boundaries and the original expression order.
            const Vector2 ab(double(b.x) - a.x, double(b.z) - a.z), ac(double(c.x) - a.x, double(c.z) - a.z);
            const Vector2 ap = point - Vector2(a.x, a.z);
            const double det = ab.cross(ac);
            if (std::abs(det) < 1e-8) continue;
            const double v = double(ap.cross(ac)) / det, w = double(ab.cross(ap)) / det;
            if (v < -.000001 || w < -.000001 || v + w > 1.000001) continue;
            const double by = b.y, cy = c.y;
            const double height = double(a.y) + v * (by - a.y) + w * (cy - a.y);
            if (!best.is_empty() && height <= double(best["height"])) continue;
            bool is_lava = false;
            for (uint8_t owner : {owners[ia], owners[ib], owners[ic]}) {
                is_lava = is_lava || (owner < lava.size() && lava[owner] > 0.0);
            }
            // Never mutate the caller's dictionary, including its unknown keys.
            Dictionary hit;
            hit["height"] = height; hit["lava"] = is_lava; hit["material"] = int64_t(owners[ia]);
            hit["slope"] = Vector2(((by - a.y) * ac.y - (cy - a.y) * ab.y) / det,
                (ab.x * (cy - a.y) - ac.x * (by - a.y)) / det);
            best = hit;
        }
        return best;
    }
};
} // namespace godot
