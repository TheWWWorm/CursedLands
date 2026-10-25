// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

namespace godot {
// Ordered subdivision and clipping only. The script supplies current terrain
// and floor triangles and retains material, visibility and lifetime ownership.
class GroundMarkProjectionKernel : public RefCounted {
    GDCLASS(GroundMarkProjectionKernel, RefCounted)
    struct Vertex { Vector3 point; Vector2 grid; Vector3 clip; };
    struct Output { Vector3 point; Vector3 normal; Vector2 uv; Vector2 grid; Color color; };
    struct Query {
        Vector2 centre, across, along, half;
        Rect2 bounds;
        double height, thickness;
        std::vector<Output> output;
        void triangle(const std::array<Vector3,3> &p, const std::array<Vector2,3> &grid, int depth, bool land) {
            Rect2 rect(Vector2(p[0].x,-p[0].z),Vector2());
            for (const Vector3 &v : p) rect = rect.expand(Vector2(v.x,-v.z));
            if (!rect.intersects(bounds)) return;
            if (std::min(double(p[0].y),std::min(double(p[1].y),double(p[2].y))) > height+thickness*.5 ||
                    std::max(double(p[0].y),std::max(double(p[1].y),double(p[2].y))) < height-thickness*.5) return;
            Vector3 normal = (p[2]-p[0]).cross(p[1]-p[0]).normalized();
            if (std::abs(double(normal.y)) < .01) return;
            if (normal.y < 0) normal = -normal;
            if (depth > 0) {
                const Vector3 ab=(p[0]+p[1])*.5, bc=(p[1]+p[2])*.5, ca=(p[2]+p[0])*.5;
                const Vector2 ga=(grid[0]+grid[1])*.5, gb=(grid[1]+grid[2])*.5, gc=(grid[2]+grid[0])*.5;
                triangle({p[0],ab,ca},{grid[0],ga,gc},depth-1,land);
                triangle({ab,p[1],bc},{ga,grid[1],gb},depth-1,land);
                triangle({ca,bc,p[2]},{gc,gb,grid[2]},depth-1,land);
                triangle({ab,bc,ca},{ga,gb,gc},depth-1,land);
                return;
            }
            std::vector<Vertex> poly; poly.reserve(12);
            for (int i=0; i<3; ++i) {
                const Vector2 delta=Vector2(p[i].x,-p[i].z)-centre;
                const Vector2 uv=Vector2(delta.dot(across),delta.dot(along))/half*.5+Vector2(.5,.5);
                poly.push_back({p[i],grid[i],Vector3(uv.x,uv.y,(double(p[i].y)-height)/thickness+.5)});
            }
            std::vector<Vertex> clipped; clipped.reserve(12);
            for (int axis=0; axis<3; ++axis) {
                for (double edge : {0.,1.}) {
                    if (poly.empty()) return;
                    clipped.clear();
                    Vertex previous=poly.back();
                    for (const Vertex &current : poly) {
                        const double a=previous.clip[axis], b=current.clip[axis];
                        const bool inside_a=edge==0. ? a>=edge : a<=edge;
                        const bool inside_b=edge==0. ? b>=edge : b<=edge;
                        if (inside_a!=inside_b) {
                            const double t=(edge-a)/(b-a);
                            clipped.push_back({previous.point.lerp(current.point,t),previous.grid.lerp(current.grid,t),previous.clip.lerp(current.clip,t)});
                        }
                        if (inside_b) clipped.push_back(current);
                        previous=current;
                    }
                    poly.swap(clipped);
                }
            }
            const Color color(land ? 1 : 0,0,0,1);
            for (size_t i=1; i+1<poly.size(); ++i) {
                for (size_t j : {size_t(0),i,i+1}) {
                    const Vertex &v=poly[j];
                    output.push_back({v.point,normal,Vector2(v.clip.x,v.clip.y),v.grid,color});
                }
            }
        }
    };
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("project", "triangles", "centre", "across", "along", "half", "bounds", "height", "thickness"), &GroundMarkProjectionKernel::project);
    }
public:
    Variant project(const Array &triangles, Vector2 centre, Vector2 across, Vector2 along,
            Vector2 half, Rect2 bounds, double height, double thickness) const {
        if (!centre.is_finite() || !across.is_finite() || !along.is_finite() || !half.is_finite() ||
                half.x<=0 || half.y<=0 || !bounds.position.is_finite() || !bounds.size.is_finite() ||
                !std::isfinite(height) || !std::isfinite(thickness) || thickness<=0) return {};
        // Validate the entire batch before emitting geometry. Unsupported
        // diagnostic inputs can retain the complete scalar calculation.
        for (int64_t i=0; i<triangles.size(); ++i) {
            if (triangles[i].get_type()!=Variant::ARRAY) return {};
            const Array row=triangles[i];
            if (row.size()!=4 || row[0].get_type()!=Variant::ARRAY || row[1].get_type()!=Variant::ARRAY ||
                    row[2].get_type()!=Variant::INT || row[3].get_type()!=Variant::BOOL) return {};
            const Array p=row[0], grid=row[1];
            if (p.size()!=3 || grid.size()!=3 || int64_t(row[2])<0 || int64_t(row[2])>4) return {};
            for (int j=0; j<3; ++j) {
                if (p[j].get_type()!=Variant::VECTOR3 || grid[j].get_type()!=Variant::VECTOR2 ||
                        !Vector3(p[j]).is_finite() || !Vector2(grid[j]).is_finite()) return {};
            }
        }
        Query query{centre,across,along,half,bounds,height,thickness,{}};
        for (int64_t i=0; i<triangles.size(); ++i) {
            const Array row=triangles[i], p=row[0], grid=row[1];
            query.triangle({p[0],p[1],p[2]},{grid[0],grid[1],grid[2]},int64_t(row[2]),bool(row[3]));
        }
        PackedVector3Array vertices,normals;
        PackedVector2Array uvs,grids;
        PackedColorArray colors;
        const int64_t size=query.output.size();
        vertices.resize(size);normals.resize(size);uvs.resize(size);grids.resize(size);colors.resize(size);
        Vector3 *v=vertices.ptrw(), *n=normals.ptrw();
        Vector2 *u=uvs.ptrw(), *g=grids.ptrw();
        Color *c=colors.ptrw();
        for (int64_t i=0; i<size; ++i) {
            const Output &row=query.output[i];v[i]=row.point;n[i]=row.normal;u[i]=row.uv;g[i]=row.grid;c[i]=row.color;
        }
        Array result;result.push_back(vertices);result.push_back(normals);result.push_back(uvs);result.push_back(grids);result.push_back(colors);
        return result;
    }
};
}
