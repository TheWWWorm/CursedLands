// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <algorithm>
#include <vector>

namespace godot {
// Stateless sole geometry. The existing caller owns authored bounds, vertex
// acquisition, terrain admission and contact history. Keep float vector and
// double scalar operations in the same order as GroundMarks._sole_geometry.
class GroundContactKernel : public RefCounted {
    GDCLASS(GroundContactKernel, RefCounted)
    const StringName weld_key = "weld_mesh";
    const String point_field = "p", extent_field = "extent", angle_field = "angle", height_field = "height";
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("sole_geometry", "part", "vertices", "part_script"), &GroundContactKernel::sole_geometry);
    }
public:
    Variant sole_geometry(Node3D *part, const Callable &vertices, const Ref<Script> &part_script) const {
        if (!part || !vertices.is_valid()) return {};
        const Ref<Script> attached = part->get_script();
        if (attached.is_valid() && attached != part_script) return {};
        const TypedArray<Node> children = part->get_children();
        // Decline custom node methods before invoking the vertex provider.
        for (int64_t i = 0; i < children.size(); ++i) {
            auto *mesh = Object::cast_to<MeshInstance3D>(Variant(children[i]).get_validated_object());
            if (mesh && mesh->get_script().get_validated_object()) return {};
        }
        Ref<Mesh> welded;
        if (part->has_meta(weld_key) && part->is_visible_in_tree()) {
            const Variant stored = part->get_meta(weld_key);
            if (stored.get_type() != Variant::ARRAY) return {};
            const Array row = stored;
            if (row.is_empty()) return {};
            welded = Ref<Mesh>(row[0]);
            if (welded.is_null() || !welded->is_class("ArrayMesh")) return {};
        }
        std::vector<Vector3> points;
        double bottom = INFINITY;
        const auto append = [&](const Ref<Mesh> &mesh, const Transform3D &transform) {
            const PackedVector3Array local = vertices.call(mesh);
            const Vector3 *data = local.ptr();
            points.reserve(points.size() + local.size());
            for (int64_t i = 0; i < local.size(); ++i) {
                const Vector3 p = transform.xform(data[i]);
                points.push_back(p);
                bottom = std::min(bottom, double(p.y));
            }
        };
        if (welded.is_valid()) append(welded, part->get_global_transform());
        for (int64_t i = 0; i < children.size(); ++i) {
            auto *mesh = Object::cast_to<MeshInstance3D>(Variant(children[i]).get_validated_object());
            if (!mesh || mesh->get_mesh().is_null() || !mesh->is_visible()) continue;
            append(mesh->get_mesh(), mesh->get_global_transform());
        }
        if (points.empty()) return Dictionary();
        const Basis basis = part->get_global_transform().basis;
        Vector2 forward = Vector2(basis.get_column(2).x, -basis.get_column(2).z).normalized();
        if (forward.length_squared() < .1) forward = Vector2(0, -1);
        const Vector2 across(forward.y, -forward.x);
        Vector2 lo(INFINITY, INFINITY), hi = -lo;
        for (const Vector3 &p : points) {
            if (p.y > bottom + .035) continue;
            const Vector2 xy(p.x, -p.z), local(xy.dot(across), xy.dot(forward));
            lo = lo.min(local); hi = hi.max(local);
        }
        const Vector2 middle = (lo + hi) * .5;
        Dictionary result;
        result[point_field] = across * middle.x + forward * middle.y;
        result[extent_field] = ((hi - lo) * .5).clamp(Vector2(.025, .045), Vector2(.32, .46));
        result[angle_field] = double(forward.angle()) - 3.14159265358979323846 * .5;
        result[height_field] = bottom;
        return result;
    }
};
}
