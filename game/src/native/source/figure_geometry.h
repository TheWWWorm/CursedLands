// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/weak_ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <cmath>

namespace godot {
// Read authored part bounds at their current origins. This deliberately keeps
// no pose cache: effects, collision consumers and same-frame edits see the
// same transforms as EIFigureGeometry's script implementation.
class FigureGeometryKernel : public RefCounted {
    GDCLASS(FigureGeometryKernel, RefCounted)
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("measure", "model"), &FigureGeometryKernel::measure);
    }
public:
    Dictionary measure(Node3D *model) const {
        const StringName parts_key("ei_figure_parts"), geometry_key("ei_figure_geometry");
        if (!model || !model->has_meta(parts_key)) return {};
        const Array parts = model->get_meta(parts_key);
        const bool inside = model->is_inside_tree();
        const Transform3D inverse = inside ? model->get_global_transform().affine_inverse() : Transform3D();
        Vector3 lo(3.402823466e38, 3.402823466e38, 3.402823466e38), hi = -lo;
        int count = 0;
        for (int64_t i = 0; i < parts.size(); ++i) {
            const Ref<WeakRef> reference = parts[i];
            if (reference.is_null()) continue;
            Node3D *node = Object::cast_to<Node3D>(reference->get_ref());
            if (!node || !model->is_ancestor_of(node)) continue;
            ++count;
            Vector3 position;
            if (inside) {
                position = inverse.xform(node->get_global_position());
            } else {
                Transform3D relative = node->get_transform();
                Node3D *parent = node->get_parent_node_3d();
                while (parent && parent != model) {
                    relative = parent->get_transform() * relative;
                    parent = parent->get_parent_node_3d();
                }
                position = relative.origin;
            }
            const Vector3 p(position.x, -position.z, position.y);
            if (double(p.x)*p.x + double(p.y)*p.y + double(p.z)*p.z > 1.0e9) continue;
            const Dictionary geometry = node->get_meta(geometry_key);
            const Vector3 centre = geometry["centre"], minimum = geometry["min"], maximum = geometry["max"];
            // Native/GDScript scalar sums use double until stored in Vector3.
            const Vector3 a(double(minimum.x)+p.x+centre.x, double(minimum.y)+p.y+centre.y, double(minimum.z)+p.z+centre.z);
            const Vector3 b(double(maximum.x)+p.x+centre.x, double(maximum.y)+p.y+centre.y, double(maximum.z)+p.z+centre.z);
            lo = lo.min(a); hi = hi.max(b);
        }
        Dictionary result;
        const Vector3 centre = count ? (lo + hi) * real_t(.5) : Vector3();
        lo = count ? lo - centre : Vector3();
        hi = count ? hi - centre : Vector3();
        result["centre"] = centre; result["min"] = lo; result["max"] = hi;
        result["radius"] = double(float(std::sqrt(double(lo.x)*lo.x + double(lo.y)*lo.y + double(lo.z)*lo.z)));
        result["flags"] = count ? 3 : 0;
        return result;
    }
};
}
