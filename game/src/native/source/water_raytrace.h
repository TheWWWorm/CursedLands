// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector4.hpp>
#include <algorithm>
#include <cmath>
#include <map>
#include <vector>

namespace godot {
// Main-thread scene inspection and CPU geometry packing only. No renderer
// resources, retained node pointers, gameplay state changes or worker access.
class WaterRaytraceKernel : public RefCounted {
    GDCLASS(WaterRaytraceKernel, RefCounted)
    struct Instance {
        uint64_t node = 0, mesh = 0;
        int index = 0, mask = -1;
        bool terrain = false;
        Transform3D transform;
    };
    struct Group {
        uint64_t node = 0;
        bool unit = false;
        int visible = -1;
        std::vector<Instance> instances;
    };
    std::vector<Group> groups;
    const StringName invisible_method = "is_invisible";
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("atlas_layers", "arrays", "transform", "center", "radius", "plane"), &WaterRaytraceKernel::atlas_layers);
        ClassDB::bind_method(D_METHOD("pack", "arrays", "transform", "settings"), &WaterRaytraceKernel::pack);
        ClassDB::bind_method(D_METHOD("clear_instances"), &WaterRaytraceKernel::clear_instances);
        ClassDB::bind_method(D_METHOD("add_group", "node", "unit"), &WaterRaytraceKernel::add_group);
        ClassDB::bind_method(D_METHOD("add_instance", "group", "node", "mesh", "terrain", "index", "transform", "mask"), &WaterRaytraceKernel::add_instance);
        ClassDB::bind_method(D_METHOD("updates", "force"), &WaterRaytraceKernel::updates);
    }
public:
    PackedInt32Array atlas_layers(const Array &arrays, const Transform3D &transform, Vector3 center, double radius, double plane) const {
        std::map<int, bool> seen;
        PackedInt32Array result;
        if (arrays.size() != Mesh::ARRAY_MAX) return result;
        const PackedVector3Array p = arrays[Mesh::ARRAY_VERTEX];
        const PackedVector2Array uv2 = arrays[Mesh::ARRAY_TEX_UV2];
        if (uv2.size() != p.size()) return result;
        const PackedInt32Array indices = arrays[Mesh::ARRAY_INDEX].get_type() == Variant::PACKED_INT32_ARRAY ? PackedInt32Array(arrays[Mesh::ARRAY_INDEX]) : PackedInt32Array();
        const int64_t count = indices.is_empty() ? p.size() : indices.size();
        for (int64_t at = 0; at + 2 < count; at += 3) {
            int v[3];
            for (int k = 0; k < 3; ++k) v[k] = indices.is_empty() ? int(at + k) : indices[at + k];
            if (v[0] < 0 || v[1] < 0 || v[2] < 0 || v[0] >= p.size() || v[1] >= p.size() || v[2] >= p.size()) continue;
            const Vector3 a = transform.xform(p[v[0]]), b = transform.xform(p[v[1]]), c = transform.xform(p[v[2]]);
            const Vector3 lo = a.min(b).min(c), hi = a.max(b).max(c);
            const Vector3 end = lo + (hi - lo); // Match the script AABB endpoint's float rounding.
            if (center.clamp(lo, end).distance_squared_to(center) > radius * radius || end.y < plane - .1) continue;
            const int layer = int(std::round(uv2[v[0]].x));
            if (seen.emplace(layer, true).second) result.push_back(layer);
        }
        return result;
    }

    Dictionary pack(const Array &arrays, const Transform3D &transform, const Dictionary &settings) const {
        Dictionary result;
        PackedFloat32Array data;
        PackedInt32Array used;
        result["failed"] = false;
        result["vertices"] = data; result["indices"] = used;
        if (arrays.size() != Mesh::ARRAY_MAX) return result;
        const PackedVector3Array p = arrays[Mesh::ARRAY_VERTEX], n = arrays[Mesh::ARRAY_NORMAL];
        const PackedVector2Array uv = arrays[Mesh::ARRAY_TEX_UV];
        if (p.is_empty() || n.size() != p.size() || uv.size() != p.size()) return result;
        const PackedInt32Array indices = arrays[Mesh::ARRAY_INDEX].get_type() == Variant::PACKED_INT32_ARRAY ? PackedInt32Array(arrays[Mesh::ARRAY_INDEX]) : PackedInt32Array();
        const PackedVector2Array uv2 = arrays[Mesh::ARRAY_TEX_UV2].get_type() == Variant::PACKED_VECTOR2_ARRAY ? PackedVector2Array(arrays[Mesh::ARRAY_TEX_UV2]) : PackedVector2Array();
        const bool land = settings["land"];
        const Vector3 center = settings["center"], emission = settings["emission"];
        const Vector4 diffuse = settings["diffuse"];
        const double radius = settings["radius"], plane = settings["plane"];
        const int limit = settings["limit"], base_layer = settings["layer"];
        const Dictionary atlas = settings["atlas"];
        std::map<int, int> layers;
        const Array keys = atlas.keys();
        for (int64_t i = 0; i < keys.size(); ++i) layers[int(keys[i])] = int(atlas[keys[i]]);
        const int64_t count = indices.is_empty() ? p.size() : indices.size();
        const int64_t capacity = std::min(count / 3, int64_t(std::max(limit, 0))) * 3;
        data.resize(capacity * 16); used.resize(capacity);
        float *out = data.ptrw(); int32_t *original = used.ptrw();
        const Basis normal = transform.basis.inverse().transposed();
        int64_t written = 0;
        for (int64_t at = 0; at + 2 < count; at += 3) {
            int v[3];
            for (int k = 0; k < 3; ++k) v[k] = indices.is_empty() ? int(at + k) : indices[at + k];
            if (v[0] < 0 || v[1] < 0 || v[2] < 0 || v[0] >= p.size() || v[1] >= p.size() || v[2] >= p.size()) continue;
            if (land) {
                const Vector3 a = transform.xform(p[v[0]]), b = transform.xform(p[v[1]]), c = transform.xform(p[v[2]]);
                const Vector3 lo = a.min(b).min(c), hi = a.max(b).max(c);
                const Vector3 end = lo + (hi - lo);
                if (center.clamp(lo, end).distance_squared_to(center) > radius * radius || end.y < plane - .1) continue;
            }
            int layer = base_layer;
            if (land && uv2.size() == p.size()) {
                const auto found = layers.find(int(std::round(uv2[v[0]].x)));
                layer = found == layers.end() ? -1 : found->second;
            }
            if (layer < 0) continue;
            if (written / 3 >= limit) { result["failed"] = true; break; }
            for (int k = 0; k < 3; ++k) {
                const int i = v[k];
                const Vector3 position = transform.xform(p[i]), nn = normal.xform(n[i]).normalized();
                float *dst = out + written * 16;
                dst[0]=position.x; dst[1]=position.y; dst[2]=position.z; dst[3]=uv[i].x;
                dst[4]=nn.x; dst[5]=nn.y; dst[6]=nn.z; dst[7]=uv[i].y;
                dst[8]=diffuse.x; dst[9]=diffuse.y; dst[10]=diffuse.z; dst[11]=diffuse.w;
                dst[12]=emission.x; dst[13]=emission.y; dst[14]=emission.z; dst[15]=float(layer);
                original[written++] = i;
            }
        }
        data.resize(written * 16); used.resize(written);
        result["vertices"] = data; result["indices"] = used;
        return result;
    }

    void clear_instances() { groups.clear(); }
    int add_group(Node3D *node, bool unit) {
        Group group; group.node = node ? node->get_instance_id() : 0; group.unit = unit;
        groups.push_back(group); return int(groups.size()) - 1;
    }
    void add_instance(int group, Node3D *node, const Ref<Mesh> &mesh, bool terrain, int index, const Transform3D &transform, int mask) {
        if (group < 0 || size_t(group) >= groups.size()) return;
        Instance entry; entry.node = node ? node->get_instance_id() : 0; entry.mesh = mesh.is_valid() ? mesh->get_instance_id() : 0;
        entry.terrain = terrain; entry.index = index; entry.transform = transform; entry.mask = mask;
        groups[group].instances.push_back(entry);
    }
    Array updates(bool force) {
        Array changes;
        for (Group &group : groups) {
            auto *root = Object::cast_to<Node3D>(ObjectDB::get_instance(group.node));
            bool visible = root && root->is_visible_in_tree();
            if (visible && group.unit && bool(root->call(invisible_method))) visible = false;
            if (!force && !visible && group.visible == 0) continue;
            group.visible = visible ? 1 : 0;
            for (Instance &entry : group.instances) {
                auto *node = Object::cast_to<Node3D>(ObjectDB::get_instance(entry.node));
                int mask = 0;
                Transform3D transform = entry.transform;
                if (visible && node && node->is_visible_in_tree()) {
                    auto *mesh = Object::cast_to<MeshInstance3D>(node);
                    if (entry.terrain) mask = 255;
                    else if (mesh && mesh->get_mesh().is_valid() && mesh->get_mesh()->get_instance_id() == entry.mesh) {
                        transform = node->get_global_transform();
                        mask = mesh->get_cast_shadows_setting() == GeometryInstance3D::SHADOW_CASTING_SETTING_SHADOWS_ONLY ? 2 :
                            mesh->get_cast_shadows_setting() == GeometryInstance3D::SHADOW_CASTING_SETTING_OFF ? 1 : 255;
                        // EIUnitModel.CLOSE_VIEW_LAYER: the sealed local torso
                        // has separate complete reflection/shadow copies.
                        if ((mesh->get_layer_mask() & ~(uint32_t(1) << 14)) == 0) mask = 0;
                    }
                }
                if (force || mask != entry.mask || transform != entry.transform) {
                    Dictionary change; change["index"] = entry.index; change["transform"] = transform; change["mask"] = mask;
                    changes.push_back(change); entry.mask = mask; entry.transform = transform;
                }
            }
        }
        return changes;
    }
};
} // namespace godot
