// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/skin.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
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
    static int classify(const Vector3 *vertices, int64_t count, const std::array<Plane, 6> &planes) {
        if (count < 16) return 0;
        Vector3 lo = vertices[0], hi = lo;
        for (int64_t i = 1; i < count; ++i) { lo = lo.min(vertices[i]); hi = hi.max(vertices[i]); }
        if (!lo.is_finite() || !hi.is_finite()) return 0;
        const Vector3 magnitude = lo.abs().max(hi.abs());
        bool inside = true;
        for (const Plane &plane : planes) {
            real_t minimum = INFINITY, maximum = -INFINITY;
            for (int corner = 0; corner < 8; ++corner) {
                const Vector3 point(corner & 1 ? hi.x : lo.x, corner & 2 ? hi.y : lo.y, corner & 4 ? hi.z : lo.z);
                const real_t distance = plane.distance_to(point);
                minimum = std::min(minimum, distance); maximum = std::max(maximum, distance);
            }
            const double guard = (double(plane.normal.abs().dot(magnitude)) + std::abs(double(plane.d)) + 1.) * .0001;
            if (minimum > guard) return -1;
            if (maximum >= -guard) inside = false;
        }
        return inside ? 1 : 0;
    }
    static int32_t pixel(double value) {
        if (!std::isfinite(value) || value <= -0x1p63 || value >= 0x1p63) return 0;
        const double f = std::floor(value), d = value - f;
        const int64_t whole = int64_t(f);
        return int32_t(whole + (d > .5 || (d == .5 && whole % 2 != 0)));
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("bounds", "surfaces", "planes", "projection", "inverse_basis", "origin", "size"), &ScreenRectKernel::bounds);
        ClassDB::bind_method(D_METHOD("deform_vertices", "base", "shapes", "shape_weights", "normalized", "bones", "weights", "poses"), &ScreenRectKernel::deform_vertices);
        ClassDB::bind_method(D_METHOD("deformation_state", "instance"), &ScreenRectKernel::deformation_state);
        ClassDB::bind_method(D_METHOD("retained_bounds", "instance", "planes", "projection", "inverse_basis", "origin", "size"), &ScreenRectKernel::retained_bounds);
    }
public:
    // Scenery mechanisms retain their uploaded vertex arrays. Fuse their
    // live morph, world transform and exact clipping in one native call.
    // Nil means unsupported: the existing general/cache path remains the
    // oracle for skins, third-party meshes and multi-surface figures.
    Variant retained_bounds(MeshInstance3D *instance, const TypedArray<Plane> &planes,
            const Projection &projection, const Basis &inverse_basis,
            const Vector3 &origin, const Vector2 &size) const {
        if (!instance || !instance->is_inside_tree() || !instance->is_visible_in_tree()) return Rect2i();
        const Ref<Mesh> mesh = instance->get_mesh();
        if (mesh.is_null()) return Rect2i();
        if (!mesh->is_class("ArrayMesh") || instance->get_skin().is_valid() || mesh->get_surface_count() != 1 ||
                mesh->has_meta("ei_cpu_surfaces") || !mesh->has_meta("ei_cpu_geometry")) return Variant();
        const Variant stored = mesh->get_meta("ei_cpu_geometry");
        if (stored.get_type() != Variant::ARRAY) return Variant();
        const Array geometry = stored;
        if (geometry.size() != 2 || geometry[0].get_type() != Variant::PACKED_VECTOR3_ARRAY ||
                (geometry[1].get_type() != Variant::NIL && geometry[1].get_type() != Variant::PACKED_INT32_ARRAY)) return Variant();
        PackedVector3Array vertices = geometry[0];
        // Large static mechanisms benefit more from the existing exact cache.
        if (vertices.size() > 2048) return Variant();
        const int count = instance->get_blend_shape_count();
        if (count > 0) {
            if (!mesh->has_meta("ei_cpu_shapes")) return Variant();
            const Variant stored_shapes = mesh->get_meta("ei_cpu_shapes");
            if (stored_shapes.get_type() != Variant::ARRAY) return Variant();
            const Array shapes = stored_shapes;
            if (shapes.size() != count) return Variant();
            PackedFloat64Array weights; weights.resize(count);
            for (int i = 0; i < count; ++i) weights.set(i, instance->get_blend_shape_value(i));
            vertices = deform_vertices(vertices, shapes, weights,
                int(mesh->get("blend_shape_mode")) == Mesh::BLEND_SHAPE_MODE_NORMALIZED,
                PackedInt32Array(), PackedFloat32Array(), TypedArray<Transform3D>());
        }
        const Transform3D transform = instance->get_global_transform_interpolated();
        Vector3 *out = vertices.ptrw();
        for (int64_t i = 0; i < vertices.size(); ++i) out[i] = transform.xform(out[i]);
        Array surface;
        surface.push_back(vertices);
        surface.push_back(geometry[1].get_type() == Variant::PACKED_INT32_ARRAY ? geometry[1] : Variant(PackedInt32Array()));
        surface.push_back(mesh->call("surface_get_primitive_type", 0));
        Array surfaces; surfaces.push_back(surface);
        return bounds(surfaces, planes, projection, inverse_basis, origin, size);
    }

    // Read the same current renderer inputs in one native call. Morph-heavy
    // creatures otherwise cross the script boundary hundreds of times merely
    // to validate an unchanged cached rectangle. No pose is cached here.
    Array deformation_state(MeshInstance3D *instance) const {
        PackedFloat64Array weights;
        TypedArray<Transform3D> poses;
        bool skinned = false;
        if (instance) {
            const Ref<Mesh> mesh = instance->get_mesh();
            if (mesh.is_valid()) {
                const int count = instance->get_blend_shape_count();
                weights.resize(count);
                double *out = weights.ptrw();
                for (int i = 0; i < count; ++i) out[i] = instance->get_blend_shape_value(i);
            }
            const Ref<Skin> skin = instance->get_skin();
            if (skin.is_valid()) {
                auto *skeleton = Object::cast_to<Skeleton3D>(instance->get_node_or_null(instance->get_skeleton_path()));
                if (skeleton) {
                    skinned = true;
                    const int count = skin->get_bind_count();
                    poses.resize(count);
                    for (int i = 0; i < count; ++i) {
                        const StringName name = skin->get_bind_name(i);
                        const int bone = name != StringName() ? skeleton->find_bone(name) : skin->get_bind_bone(i);
                        poses[i] = bone >= 0 ? skeleton->get_bone_global_pose(bone) * skin->get_bind_pose(i) : Transform3D();
                    }
                }
            }
        }
        Array out; out.push_back(weights); out.push_back(poses); out.push_back(skinned); return out;
    }

    // The script reference applies morphs in authored order, then skinning.
    // Keep each Vector3 intermediate at real_t precision, including weights.
    PackedVector3Array deform_vertices(const PackedVector3Array &base, const Array &shapes,
            const PackedFloat64Array &shape_weights, bool normalized,
            const PackedInt32Array &bones, const PackedFloat32Array &weights,
            const TypedArray<Transform3D> &input_poses) const {
        const int64_t count = base.size();
        if (count == 0 || shape_weights.size() < shapes.size()) return PackedVector3Array();
        if (!weights.is_empty() && (weights.size() % count != 0 || bones.size() != weights.size())) return PackedVector3Array();
        PackedVector3Array result = base;
        Vector3 *out = result.ptrw();
        const Vector3 *original = base.ptr();
        for (int64_t k = 0; k < shapes.size(); ++k) {
            const double weight = shape_weights[k];
            if (Math::is_zero_approx(weight)) continue;
            if (shapes[k].get_type() != Variant::PACKED_VECTOR3_ARRAY) return PackedVector3Array();
            const PackedVector3Array shape = shapes[k];
            if (shape.size() != count) continue;
            const Vector3 *target = shape.ptr();
            for (int64_t i = 0; i < count; ++i)
                out[i] += (normalized ? target[i] - original[i] : target[i]) * real_t(weight);
        }
        if (weights.is_empty()) return result;
        std::vector<Transform3D> poses;
        poses.reserve(input_poses.size());
        for (int64_t i = 0; i < input_poses.size(); ++i) poses.push_back(input_poses[i]);
        const int64_t stride = weights.size() / count;
        const int32_t *bone = bones.ptr();
        const float *influence = weights.ptr();
        for (int64_t i = 0; i < count; ++i) {
            Vector3 point;
            for (int64_t j = 0; j < stride; ++j) {
                const int64_t at = i * stride + j;
                const int32_t b = bone[at];
                if (b >= 0 && size_t(b) < poses.size()) point += poses[b].xform(out[i]) * real_t(influence[at]);
            }
            out[i] = point;
        }
        return result;
    }

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
            // Bounds only classify clipping. The returned rectangle still
            // projects every original posed vertex, never these box corners.
            const int classification = classify(vs, count, planes);
            if (classification < 0) continue;
            if (classification > 0) {
                for (int64_t i = 0; i < count; ++i) project(vs[i]);
                continue;
            }
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
