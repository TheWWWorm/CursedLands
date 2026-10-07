// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <map>
#include <vector>

namespace godot {
// Configure on the main thread, then publish as an immutable field. Packed
// arrays keep their own COW references, and atlas images are private copies.
// Worker jobs never access terrain nodes, global loaders, textures or RIDs.
class GrassFieldKernel : public RefCounted {
    GDCLASS(GrassFieldKernel, RefCounted)
    int width = 0, height = 0, stride = 0, texture_size = 0, tile_size = 0;
    PackedFloat32Array heights, surface, water;
    PackedVector2Array xy;
    PackedInt32Array tiles;
    PackedByteArray ground;
    std::map<int, Ref<Image>> atlases;
    bool valid = false;
    static double lerp(double a, double b, double t) { return a + (b - a) * t; }
    Vector2 uv(int code, int dx, int dy) const {
        static constexpr int rotations[4][9] = {
            {0,1,2,3,4,5,6,7,8}, {2,5,8,1,4,7,0,3,6},
            {8,7,6,5,4,3,2,1,0}, {6,3,0,7,4,1,8,5,2}
        };
        const int k = rotations[(code >> 14) & 3][dy * 3 + dx];
        const int tile = code & 63, per_row = texture_size / tile_size;
        const double half = tile_size * .5;
        const double u = (tile % per_row) * tile_size + std::clamp((k % 3) * half, 8., tile_size - 8.);
        const double v = (tile / per_row) * tile_size + std::clamp((k / 3) * half, 8., tile_size - 8.);
        return Vector2(u / texture_size, 1. - v / texture_size);
    }
    double standing_height(Vector2 p) const {
        const double x = std::clamp(double(p.x), 0., stride - 1.001);
        const double y = std::clamp(double(p.y), 0., height - .001);
        const int ix = int(x), iy = int(y), i = iy * stride + ix;
        const double a = lerp(heights[i], heights[i + 1], x - ix);
        const double b = lerp(heights[i + stride], heights[i + stride + 1], x - ix);
        return std::max(lerp(a, b, y - iy), double(surface[int(p.y) * width + int(p.x)]));
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure", "data", "images"), &GrassFieldKernel::configure);
        ClassDB::bind_method(D_METHOD("sample", "point"), &GrassFieldKernel::sample);
    }
public:
    struct Sample { int code = 0; Vector2 uv; double height = 0.; Vector3 normal; };
    bool configure(const Dictionary &data, const Dictionary &images) {
        valid = false; atlases.clear();
        const Vector2i size = data.get("size", Vector2i());
        width = size.x; height = size.y; stride = int(data.get("grid_w", 0));
        texture_size = int(data.get("texture_size", 0)); tile_size = int(data.get("tile_size", 0));
        if (width <= 0 || height <= 0 || width > 8192 || height > 8192 || (width & 1) || (height & 1) ||
                stride != width + 1 || tile_size < 16 || texture_size < tile_size || texture_size % tile_size) return false;
        heights = data.get("heights", PackedFloat32Array()); surface = data.get("surface", PackedFloat32Array());
        water = data.get("water", PackedFloat32Array()); xy = data.get("land_xy", PackedVector2Array());
        tiles = data.get("land_tile", PackedInt32Array()); ground = data.get("ground", PackedByteArray());
        const int64_t cells = int64_t(width) * height, vertices = int64_t(stride) * (height + 1);
        if (heights.size() != vertices || xy.size() != vertices || surface.size() != cells || water.size() != cells ||
                ground.size() != cells || tiles.size() != cells / 4) return false;
        const Array keys = images.keys();
        for (int i = 0; i < keys.size(); ++i) {
            const Ref<Image> image = images[keys[i]];
            if (image.is_valid() && !image->is_empty() && !image->is_compressed()) {
                atlases[int(keys[i])] = Image::create_from_data(image->get_width(), image->get_height(),
                    image->has_mipmaps(), image->get_format(), image->get_data());
            }
        }
        valid = true; return true;
    }
    bool contains(Vector2 p) const {
        return valid && p.is_finite() && p.x >= 0 && p.y >= 0 && p.x < width && p.y < height;
    }
    bool surface_sample(Vector2 p, Sample &out) const {
        if (!contains(p)) return false;
        static constexpr int offsets[9][2] = {{0,0},{-1,0},{1,0},{0,-1},{0,1},{-1,-1},{1,-1},{-1,1},{1,1}};
        static constexpr int triangles[2][3] = {{2,1,0},{1,2,3}};
        const Vector2i cell(int(std::floor(p.x)), int(std::floor(p.y)));
        for (const auto &offset : offsets) {
            const Vector2i q = cell + Vector2i(offset[0], offset[1]);
            if (q.x < 0 || q.y < 0 || q.x >= width || q.y >= height) continue;
            const Vector2i corners[4] = {q, q + Vector2i(1,0), q + Vector2i(0,1), q + Vector2i(1,1)};
            Vector2 points[4]; double h[4];
            for (int j = 0; j < 4; ++j) {
                const int id = corners[j].y * stride + corners[j].x;
                points[j] = Vector2(corners[j]) + xy[id]; h[j] = heights[id];
            }
            for (const auto &tri : triangles) {
                const Vector2 a = points[tri[0]], b = points[tri[1]], c = points[tri[2]];
                const double determinant = (b - a).cross(c - a);
                if (std::abs(determinant) < 1e-7) continue;
                const double u = double((p - a).cross(c - a)) / determinant;
                const double v = double((b - a).cross(p - a)) / determinant;
                if (u < -1e-5 || v < -1e-5 || u + v > 1.00001) continue;
                out.code = tiles[(q.y / 2) * (width / 2) + q.x / 2];
                out.uv = Vector2(); out.height = 0.;
                const double weights[3] = {1. - u - v, u, v}; Vector3 vertices[3];
                for (int j = 0; j < 3; ++j) {
                    const int at = tri[j];
                    const Vector2i corner = corners[at] - Vector2i(q.x / 2, q.y / 2) * 2;
                    out.uv += uv(out.code, corner.x, corner.y) * real_t(weights[j]);
                    out.height += h[at] * weights[j];
                    vertices[j] = Vector3(points[at].x, h[at], -points[at].y);
                }
                out.normal = (vertices[2] - vertices[0]).cross(vertices[1] - vertices[0]).normalized();
                return true;
            }
        }
        return false;
    }
    Dictionary sample(Vector2 p) const {
        Dictionary d; Sample s;
        if (surface_sample(p, s)) { d["code"] = s.code; d["uv"] = s.uv; d["height"] = s.height; d["normal"] = s.normal; }
        return d;
    }
    bool allowed(Vector2 p, Sample &sample, Color &color) const {
        if (!contains(p)) return false;
        const int i = int(p.y) * width + int(p.x), type = ground[i];
        if ((type != 0 && type != 5 && type != 11) || !surface_sample(p, sample) || std::abs(sample.normal.y) < .80 ||
                standing_height(p) > sample.height + .08 || double(water[i]) > sample.height - .035) return false;
        const auto it = atlases.find((sample.code >> 6) & 255);
        if (it == atlases.end()) return false;
        const Ref<Image> &image = it->second;
        const Vector2 scaled = sample.uv * Vector2(image->get_width(), image->get_height());
        color = image->get_pixel(std::clamp(int(scaled.x), 0, image->get_width() - 1),
            std::clamp(int(scaled.y), 0, image->get_height() - 1));
        return color.g > .075 && color.g > double(color.r) * 1.035 + .008 && color.g > double(color.b) * 1.10 + .008;
    }
};

class GrassChunkJob : public RefCounted {
    GDCLASS(GrassChunkJob, RefCounted)
    Ref<GrassFieldKernel> field;
    Ref<RandomNumberGenerator> rng;
    Ref<FastNoiseLite> noise;
    Vector2i key;
    struct Obstacle { Transform3D inverse; AABB box; };
    std::vector<Obstacle> obstacles;
    Dictionary result;
    static double lerp(double a, double b, double t) { return a + (b - a) * t; }
    bool clear(Vector2 p, double height) const {
        for (const auto &obstacle : obstacles) {
            const Vector3 from = obstacle.inverse.xform(Vector3(p.x, height - .025, -p.y));
            const Vector3 to = obstacle.inverse.xform(Vector3(p.x, height + .88, -p.y));
            if (obstacle.box.intersects_segment(from, to)) return false;
        }
        return true;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure", "field", "key", "seed", "noise_seed", "obstacles"), &GrassChunkJob::configure);
        ClassDB::bind_method(D_METHOD("run"), &GrassChunkJob::run);
        ClassDB::bind_method(D_METHOD("read_result"), &GrassChunkJob::read_result);
        ClassDB::bind_method(D_METHOD("growth", "point"), &GrassChunkJob::growth);
    }
public:
    bool configure(const Ref<GrassFieldKernel> &p_field, Vector2i p_key, int64_t seed, int64_t noise_seed, const Array &boxes) {
        result.clear(); obstacles.clear(); field = p_field; key = p_key;
        if (field.is_null() || key.x < 0 || key.y < 0 || key.x > 1024 || key.y > 1024) return false;
        for (int i = 0; i < boxes.size(); ++i) {
            if (boxes[i].get_type() != Variant::DICTIONARY) return false;
            const Dictionary d = boxes[i];
            if (d.get("inverse", Variant()).get_type() != Variant::TRANSFORM3D ||
                    d.get("box", Variant()).get_type() != Variant::AABB) return false;
            obstacles.push_back({d["inverse"], d["box"]});
        }
        rng.instantiate(); rng->set_seed(uint64_t(seed));
        noise.instantiate(); noise->set_seed(int(noise_seed));
        noise->set_noise_type(FastNoiseLite::TYPE_SIMPLEX_SMOOTH);
        noise->set_frequency(.10); noise->set_fractal_type(FastNoiseLite::FRACTAL_FBM); noise->set_fractal_octaves(2);
        return true;
    }
    double growth(Vector2 point) const {
        if (noise.is_null()) return 0.;
        const double normalized = std::clamp((double(noise->get_noise_2d(point.x, point.y)) + .45) / 1., 0., 1.);
        return normalized * normalized * (3. - 2. * normalized);
    }
    void run() {
        if (field.is_null() || rng.is_null() || noise.is_null()) return;
        TypedArray<Transform3D> transforms; TypedArray<Color> colours, custom;
        PackedFloat32Array buffer;
        const Vector2 first = Vector2(key) * real_t(8.);
        for (int y = 0; y < 27; ++y) {
            for (int x = 0; x < 27; ++x) {
                // Keep every random draw and Vector/Color rounding boundary in
                // the scalar order. Obstacle rejection happens after variation.
                const double px = (x + double(rng->randf_range(.08, .92))) * .30;
                const double py = (y + double(rng->randf_range(.08, .92))) * .30;
                const Vector2 p = first + Vector2(px, py);
                const double lush = growth(p);
                if (rng->randf() > lerp(.78, 1., lush)) continue;
                GrassFieldKernel::Sample sample; Color color;
                if (p.x >= double(first.x) + 8. || p.y >= double(first.y) + 8. || !field->allowed(p, sample, color)) continue;
                color *= Color(lerp(1.20, .97, lush), lerp(1.02, 1.14, lush), .94);
                color *= real_t(rng->randf_range(.96, 1.14));
                color.r = std::min(double(color.r), .75); color.g = std::min(double(color.g), .80);
                color.b = std::min(double(color.b), .60); color.a = 1.;
                Basis basis(Vector3(0,1,0), real_t(rng->randf() * Math::TAU));
                const double width = rng->randf_range(.86, 1.22);
                const double height = rng->randf_range(.88, 1.12) * lerp(.80, 1.05, lush);
                basis = basis.scaled(Vector3(width, height, width));
                const Transform3D transform(basis, Vector3(p.x, sample.height - .008, -p.y));
                const double shape_seed = rng->randf();
                const double leaves = rng->randi_range(10, 14);
                const double lean = rng->randf_range(.04, .11);
                const double spread = rng->randf_range(.85, 1.15);
                const Color shape(shape_seed, leaves, lean, spread);
                if (!clear(p, double(transform.origin.y) + .008)) continue;
                transforms.append(transform); colours.append(color); custom.append(shape);
                const int start = buffer.size(); buffer.resize(start + 20);
                float *out = buffer.ptrw() + start;
                for (int row = 0; row < 3; ++row) {
                    for (int col = 0; col < 3; ++col) out[row * 4 + col] = basis[row][col];
                    out[row * 4 + 3] = transform.origin[row];
                }
                for (int component = 0; component < 4; ++component) {
                    out[12 + component] = color[component]; out[16 + component] = shape[component];
                }
            }
        }
        result["transforms"] = transforms; result["colours"] = colours;
        result["custom"] = custom; result["buffer"] = buffer;
    }
    Dictionary read_result() const { return result; }
};
} // namespace godot
