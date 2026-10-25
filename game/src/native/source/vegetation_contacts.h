// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <algorithm>
#include <cmath>
#include <vector>

namespace godot {
// Presentation-thread query. No actor, visibility, transform or contact result
// survives the call. Terrain admission remains in the existing script methods.
class VegetationContactKernel : public RefCounted {
    GDCLASS(VegetationContactKernel, RefCounted)
    const StringName hidden_key = "hidden", fogged_key = "fogged", dead_key = "dead";
    const StringName model_key = "model", near_screen_method = "near_screen", meshes_key = "_geoms";
    const StringName allowed_method = "vegetation_allowed", surface_method = "surface_sample";
    const StringName radius_key = "figure_radius", stance_key = "stance", facing_key = "facing";
    const String id_field = "id", point_field = "p", extent_field = "extent", angle_field = "angle", height_field = "height";
    struct Candidate {
        Node3D *unit;
        Vector3 root;
        real_t distance;
        int64_t id;
        Array meshes;
    };
    static bool exact_script(Object *object, const Ref<Script> &script) {
        return object && Ref<Script>(object->get_script()) == script;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("contacts", "units", "details", "focus", "unit_script", "model_script", "details_script", "width", "limit", "crawl_stance"), &VegetationContactKernel::contacts);
    }
public:
    Variant contacts(const Array &units, Object *details, Vector2 focus,
            const Ref<Script> &unit_script, const Ref<Script> &model_script,
            const Ref<Script> &details_script, double width, int64_t limit, int64_t crawl_stance) const {
        if (unit_script.is_null() || model_script.is_null() || details_script.is_null() ||
                !exact_script(details, details_script) || !focus.is_finite() ||
                !std::isfinite(width) || width <= 6.0 || limit < 0 || limit > 32) return {};
        std::vector<Candidate> nearby;
        for (int64_t i = 0; i < units.size(); ++i) {
            Object *object = units[i].get_validated_object();
            if (!object) continue;
            Node3D *unit = Object::cast_to<Node3D>(object);
            if (!exact_script(unit, unit_script)) return {};
            if (!unit->is_inside_tree() || !unit->is_visible_in_tree() ||
                    bool(unit->get(hidden_key)) || bool(unit->get(fogged_key)) || bool(unit->get(dead_key))) continue;
            Node3D *model = Object::cast_to<Node3D>(unit->get(model_key).get_validated_object());
            if (!model) continue;
            if (!exact_script(model, model_script)) return {};
            if (!model->is_visible_in_tree() || !bool(unit->call(near_screen_method))) continue;
            const Vector3 root = unit->get_global_transform_interpolated().origin;
            if (!root.is_finite()) return {};
            const Vector2 p(root.x, root.z), offset = (p - focus).abs();
            if (offset.x > width * .5 - 3.0 || offset.y > width * .5 - 3.0) continue;
            nearby.push_back({unit, root, p.distance_squared_to(focus), int64_t(unit->get_instance_id()), {}});
        }
        std::sort(nearby.begin(), nearby.end(), [](const Candidate &a, const Candidate &b) {
            return a.distance != b.distance ? a.distance < b.distance : a.id < b.id;
        });
        const size_t count = std::min(size_t(limit), nearby.size());
        // Decline custom mesh methods before any terrain callback. Ordinary
        // geometry keeps the same ordered bounds, including invalid/hidden rows.
        for (size_t i = 0; i < count; ++i) {
            Candidate &row = nearby[i];
            row.meshes = row.unit->get(meshes_key);
            for (int64_t j = 0; j < row.meshes.size(); ++j) {
                MeshInstance3D *mesh = Object::cast_to<MeshInstance3D>(row.meshes[j].get_validated_object());
                if (mesh && mesh->get_script().get_validated_object()) return {};
            }
        }
        TypedArray<Dictionary> result;
        for (size_t i = 0; i < count; ++i) {
            const Candidate &row = nearby[i];
            const Vector2 p(row.root.x, -row.root.z);
            if (!bool(details->call(allowed_method, p))) continue;
            const Dictionary surface = details->call(surface_method, p);
            const double height = surface[height_field];
            AABB box(Vector3(INFINITY, INFINITY, INFINITY), Vector3());
            for (int64_t j = 0; j < row.meshes.size(); ++j) {
                MeshInstance3D *mesh = Object::cast_to<MeshInstance3D>(row.meshes[j].get_validated_object());
                if (!mesh || !mesh->is_visible_in_tree() || mesh->get_mesh().is_null()) continue;
                const AABB current = mesh->get_global_transform_interpolated().xform(mesh->get_aabb());
                box = box.position.is_finite() ? box.merge(current) : current;
            }
            if (!box.position.is_finite() || box.position.y > height + .22 || box.get_end().y < height) continue;
            const double radius = std::clamp(double(row.unit->get(radius_key)) * .7, .18, .8);
            double length = radius;
            Vector2 centre(row.root.x, row.root.z);
            if (int64_t(row.unit->get(stance_key)) == crawl_stance) {
                length = std::clamp(std::max(double(box.size.x), double(box.size.z)) * .45, radius, 1.2);
                const Vector3 middle = box.get_center();
                centre = Vector2(middle.x, middle.z);
            }
            Dictionary contact;
            contact[id_field] = row.id;
            contact[point_field] = centre;
            contact[extent_field] = Vector2(length, radius);
            contact[angle_field] = -double(row.unit->get(facing_key));
            result.push_back(contact);
        }
        return result;
    }
};
}
