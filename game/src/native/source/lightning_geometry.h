// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/projection.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <array>
#include <vector>
#include <cmath>
#include <algorithm>
#include <cstring>

namespace godot {
// Pure lightning geometry. The caller owns noise-key/RNG advancement, camera
// state, materials and mesh installation. No scene or rendering calls per point.
class LightningGeometryKernel : public RefCounted {
    GDCLASS(LightningGeometryKernel, RefCounted)
    static Array noise_key(const Ref<RandomNumberGenerator> &rng, double amplitude) {
        // Keep the script's draw order explicit; C++ function-argument
        // evaluation order must never reorder the shared random stream.
        const double x = double(rng->randi()) * 4.656613e-10;
        const double y = double(rng->randi()) * 4.656613e-10;
        Vector2 w(x - 1.0, y - 1.0);
        w = w.length() > .0001 ? w.normalized() * real_t(amplitude) : Vector2(amplitude, 0);
        const int first = rng->randi() % 16, second = rng->randi() % 16;
        Array key; key.push_back(first); key.push_back(second); key.push_back(double(w.x)); key.push_back(double(w.y)); return key;
    }
    static Dictionary noise_bolt(double f, Vector3 shift, double width, double amplitude, const Ref<RandomNumberGenerator> &rng) {
        Dictionary bolt; bolt["f"] = f; bolt["shift"] = shift; bolt["width"] = width;
        bolt["band"] = (rng->randi() & 3) * .25;
        Array axes;
        for (int axis = 0; axis < 2; ++axis) {
            Array keys; for (int k = 0; k < 3; ++k) keys.push_back(noise_key(rng, amplitude)); axes.push_back(keys);
        }
        bolt["keys"] = axes; return bolt;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("points","a","b","bolt","tick","fraction","tables","fine"), &LightningGeometryKernel::points);
        ClassDB::bind_method(D_METHOD("strip","camera","depth_inverse","projection","viewport_size","points","width","repeat","band"), &LightningGeometryKernel::strip);
        ClassDB::bind_method(D_METHOD("surface_data","vertices","uvs","colors"), &LightningGeometryKernel::surface_data);
        ClassDB::bind_method(D_METHOD("new_bolts","a","b","parameter","rng"), &LightningGeometryKernel::new_bolts);
        ClassDB::bind_method(D_METHOD("advance_keys","bolts","amplitude","rng"), &LightningGeometryKernel::advance_keys);
        ClassDB::bind_method(D_METHOD("glows","ends","origin","eye","basis","size","world_tick"), &LightningGeometryKernel::glows);
    }
public:
    Array new_bolts(Vector3 a, Vector3 b, double parameter, const Ref<RandomNumberGenerator> &rng) const {
        if (rng.is_null()) return {};
        const double amplitude = parameter > 0 ? 1.5 : parameter == 0 ? 2.0 : 1.0;
        const double width = parameter == 0 ? 4.0 : std::abs(parameter) * (parameter < 0 ? 1.5 : 1.0);
        Array bolts; bolts.push_back(noise_bolt(0, Vector3(), width, amplitude, rng));
        const double length = (b - a).length();
        const double fractions[6] = {.2, .3, .5, .8, .9, .9};
        for (int i = 0; i < 6; ++i) {
            if (parameter == 0) {
                const double x = double(rng->randi()) * 4.656613e-10 - 1;
                const double y = double(rng->randi()) * 4.656613e-10 - 1;
                const double z = double(rng->randi()) * 4.656613e-10 - 1;
                const Vector3 shift = Vector3(x, y, z) * real_t(.05) * real_t(length);
                const double w = 2.45 + double(rng->randi()) * 2.3283064e-10 * 2.8;
                bolts.push_back(noise_bolt(0, shift, w, amplitude, rng));
            } else {
                const double w = (.7 + double(rng->randi()) * 2.3283064e-10 * .8) * std::abs(parameter) * .5;
                bolts.push_back(noise_bolt(fractions[i], Vector3(), w, amplitude, rng));
            }
        }
        return bolts;
    }
    void advance_keys(Array bolts, double amplitude, const Ref<RandomNumberGenerator> &rng) const {
        if (rng.is_null()) return;
        for (int i = 0; i < bolts.size(); ++i) {
            const Dictionary bolt = bolts[i]; const Array axes = bolt["keys"];
            for (int axis = 0; axis < axes.size(); ++axis) {
                Array keys = axes[axis]; keys.pop_front(); keys.push_back(noise_key(rng, amplitude));
            }
        }
    }
    Array glows(const PackedVector3Array &ends, Vector3 origin, Vector3 eye, Basis basis, double size, int64_t world_tick) const {
        if (ends.size() > 64 || !origin.is_finite() || !eye.is_finite() || !std::isfinite(size)) return {};
        PackedVector3Array vertices; PackedVector2Array uvs; PackedColorArray colors;
        const int count = ends.size() * 8 * 6;
        vertices.resize(count); uvs.resize(count); colors.resize(count);
        auto *vs = vertices.ptrw(); auto *us = uvs.ptrw(); auto *cs = colors.ptrw();
        int at = 0;
        for (int end = 0; end < ends.size(); ++end) {
            const Vector3 point = ends[end] + origin;
            if (!point.is_finite()) return {};
            Vector3 direction = eye - point;
            if (direction.length() > 0) direction /= direction.length();
            const double value = float(double(point.x) * 15.0), floor = std::floor(value), rest = value - floor;
            if (!std::isfinite(value) || value < -0x1p63 || value >= 0x1p63) return {};
            const int64_t whole = int64_t(floor);
            const int64_t rounded = whole + (rest > .5 || (rest == .5 && whole % 2 != 0));
            const int64_t phase = world_tick % 15 + rounded % 15;
            for (int i = 0; i < 8; ++i) {
                const double f = i * .125;
                const Vector3 p = point + direction * real_t(f) * real_t(size);
                const float extent = std::sqrt(1.0 - f*f) * size;
                const Vector3 centre(p.x, p.z, -p.y);
                const double half = double(extent) / std::cos(3.14159265358979323846 / 7.0);
                const Vector3 right = basis.get_column(0) * real_t(half), up = basis.get_column(1) * real_t(half);
                const int frame = int(((phase + i*2) % 15 + 15) % 15);
                const float x = (frame & 3) * .25, y = .75 - (frame >> 2) * .25;
                const Vector3 positions[6] = {centre-right+up, centre+right+up, centre-right-up, centre-right-up, centre+right+up, centre+right-up};
                const Vector2 tex[6] = {Vector2(x,y),Vector2(x+.25,y),Vector2(x,y+.25),Vector2(x,y+.25),Vector2(x+.25,y),Vector2(x+.25,y+.25)};
                for (int j=0; j<6; ++j) { vs[at]=positions[j]; us[at]=tex[j]; cs[at++]=Color(1,1,1,160.0/255.0); }
            }
        }
        Array out; out.push_back(vertices); out.push_back(uvs); out.push_back(colors); return out;
    }

    // Uncompressed position / RGBA8+UV buffers, matching RenderingServer's
    // surface packing. The caller verifies the format before updating a mesh.
    Array surface_data(const PackedVector3Array &vertices, const PackedVector2Array &uvs,
            const PackedColorArray &colors) const {
        const int64_t count = vertices.size();
        if (count == 0 || count > 1000000 || uvs.size() != count || colors.size() != count) return {};
        PackedByteArray positions, attributes;
        positions.resize(count * 12); attributes.resize(count * 12);
        auto *position = positions.ptrw(), *attribute = attributes.ptrw();
        const auto *points = vertices.ptr(); const auto *tex = uvs.ptr(); const auto *color = colors.ptr();
        Vector3 lo = points[0], hi = lo;
        for (int64_t i = 0; i < count; ++i) {
            if (!points[i].is_finite() || !tex[i].is_finite() || !std::isfinite(color[i].r) ||
                    !std::isfinite(color[i].g) || !std::isfinite(color[i].b) || !std::isfinite(color[i].a)) return {};
            lo = lo.min(points[i]); hi = hi.max(points[i]);
            const float xyz[3] = {float(points[i].x), float(points[i].y), float(points[i].z)};
            const float uv[2] = {float(tex[i].x), float(tex[i].y)};
            const uint8_t rgba[4] = {uint8_t(std::clamp(double(color[i].r) * 255., 0., 255.)),
                uint8_t(std::clamp(double(color[i].g) * 255., 0., 255.)),
                uint8_t(std::clamp(double(color[i].b) * 255., 0., 255.)),
                uint8_t(std::clamp(double(color[i].a) * 255., 0., 255.))};
            std::memcpy(position + i * 12, xyz, 12);
            std::memcpy(attribute + i * 12, rgba, 4);
            std::memcpy(attribute + i * 12 + 4, uv, 8);
        }
        Array out; out.push_back(positions); out.push_back(attributes); out.push_back(AABB(lo, hi - lo)); return out;
    }

    PackedVector3Array points(Vector3 a,Vector3 b,const Dictionary &bolt,int tick,double fraction,const Array &tables,const PackedInt32Array &fine) const {
        if (tables.size()!=32 || fine.size()!=2 || fine[0]<0 || fine[0]>=32 || fine[1]<0 || fine[1]>=32 ||
                !bolt.has("f") || !bolt.has("shift") || !bolt.has("keys")) return {};
        std::array<PackedFloat32Array,32> noise;
        for (int i=0;i<32;++i) { noise[i]=tables[i]; if(noise[i].size()<400)return {}; }
        const Array axes=bolt["keys"]; if(axes.size()!=2)return {};
        struct Key { int x,y;double a,b; } keys[2][3];
        for(int ax=0;ax<2;++ax) {
            const Array row=axes[ax];if(row.size()!=3)return {};
            for(int k=0;k<3;++k) {
                const Array v=row[k];if(v.size()!=4)return {};
                keys[ax][k]={int(v[0]),int(v[1]),double(v[2]),double(v[3])};
                if(keys[ax][k].x<0 || keys[ax][k].x>=32 || keys[ax][k].y<0 || keys[ax][k].y>=32)return {};
            }
        }
        const double f=bolt["f"];
        const Vector3 shift=bolt["shift"];
        const Vector3 pa=(f>0 ? b.lerp(a,f) : a)+shift,pb=b+shift,d=pb-pa;
        const double length=std::min(double(d.length()),15.0);
        const int n=length<10.0 ? 48 : std::clamp(int(std::round(5.0*length))&~3,4,400);
        const Vector3 p(d.y+0.0666*d.z,0.013*d.z-d.x,-0.0666*d.x-0.013*d.y);
        const Vector3 q=d.cross(p).normalized()*p.length();
        const double t=std::fmod(double(tick)+fraction,4.0)/4.0;
        const double bw[3]={0.5-t+t*t*0.5,t+0.5-t*t,t*t*0.5};
        const Vector3 step=d/double(n);
        PackedVector3Array out;out.resize(n+1);auto *dst=out.ptrw();
        for(int i=0;i<=n;++i) {
            double off[2]={};
            for(int ax=0;ax<2;++ax) {
                for(int k=0;k<3;++k) { const auto &key=keys[ax][k];off[ax]+=bw[k]*(key.a*noise[key.x][i]+key.b*noise[key.y][i]); }
                off[ax]+=noise[fine[ax]][i];
            }
            dst[i]=pa+step*i+p*off[0]+q*off[1];
        }
        return out;
    }

    Array strip(const Transform3D &camera,const Transform3D &depth_inverse,const Projection &projection,Vector2 size,const PackedVector3Array &points,double width,double repeat,double band) const {
        const int n=points.size();if(n<2 || n>4096 || size.x<=0 || size.y<=0)return {};
        std::vector<Vector4> projected;projected.reserve(n);
        for(int i=0;i<n;++i) {
            const Vector3 local=camera.xform_inv(points[i]);
            const Vector4 clip=projection.xform(Vector4(local.x,local.y,local.z,1));
            const double depth=-depth_inverse.xform(points[i]).z;
            if(clip.w==0 || depth==0 || !std::isfinite(depth))return {};
            const Vector3 normal=Vector3(clip.x,clip.y,clip.z)/clip.w;
            projected.emplace_back((double(normal.x)*.5+.5)*size.x,(-double(normal.y)*.5+.5)*size.y,depth,1.0/(0.4338837391175581*depth));
        }
        const Plane right=projection.get_projection_plane(Projection::PLANE_RIGHT);
        const Plane top=projection.get_projection_plane(Projection::PLANE_TOP);
        std::vector<Vector3> ribbon;ribbon.reserve(n*2);
        for(int i=0;i<n;++i) {
            const auto &p=projected[i], &first=projected[std::max(i-1,0)], &last=projected[std::min(i+1,n-1)];
            const Vector2 tangent(last.x-first.x,last.y-first.y);
            const float extent=width*p.w*15.0;
            const double k=tangent.length()>0 ? extent/double(tangent.length()) : 0.0;
            const Vector2 sides[2]={Vector2(p.x+tangent.y*k,p.y-tangent.x*k),Vector2(p.x-tangent.y*k,p.y+tangent.x*k)};
            Vector3 half;
            if(!Plane(Vector3(0,0,1),-p.z).intersect_3(right,top,&half))return {};
            for(const auto &s:sides) {
                Vector2 point((s.x/size.x)*2.0-1.0,(1.0-(s.y/size.y))*2.0-1.0);
                point*=Vector2(half.x,half.y);
                ribbon.push_back(camera.xform(Vector3(point.x,point.y,-p.z)));
            }
        }
        PackedVector3Array vertices;PackedVector2Array uvs;PackedColorArray colors;
        const int count=(n-1)*6;vertices.resize(count);uvs.resize(count);colors.resize(count);
        auto *vs=vertices.ptrw();auto *us=uvs.ptrw();auto *cs=colors.ptrw();
        const float step=repeat/double(n-1);double s0=repeat==0 ? .875 : 0;
        int at=0;
        for(int i=1;i<n;++i) {
            const float s1=s0+step;
            const int indices[6]={(i-1)*2,(i-1)*2+1,i*2,i*2,(i-1)*2+1,i*2+1};
            const Vector2 tex[6]={Vector2(s0,band),Vector2(s0,band+.25),Vector2(s1,band),Vector2(s1,band),Vector2(s0,band+.25),Vector2(s1,band+.25)};
            for(int j=0;j<6;++j) {
                vs[at]=ribbon[indices[j]];us[at]=tex[j];
                cs[at++]=Color(1,1,1, (j==0 || j==1 || j==4) ? (i==1?0:1) : (i==n-1?0:1));
            }
            s0=s1;
        }
        Array out;out.push_back(vertices);out.push_back(uvs);out.push_back(colors);return out;
    }
};
}
