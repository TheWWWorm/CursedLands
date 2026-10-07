// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <algorithm>
#include <array>

using namespace godot;

// One immutable sector snapshot, owned by one WorkerThreadPool task. Only
// packed data crosses the boundary: no nodes, materials, textures or RIDs.
// Configure/read_result are called on the main thread, before/after joining.
class SoftGroundMeshJob : public RefCounted {
    GDCLASS(SoftGroundMeshJob, RefCounted)
    // Mesh.ArrayType. Keep this data-only extension independent of Mesh APIs.
    enum { VERTEX = 0, NORMAL = 1, COLOR = 3, UV = 4, UV2 = 5, INDEX = 12, MAX = 13 };
    static constexpr int subdiv = 16, tile_count = 256, tile_indices = 24;
    static constexpr int dense_vertices = 8 * (subdiv + 1) * (subdiv + 2) / 2;
    static constexpr int dense_indices = 8 * subdiv * subdiv * 3;
    struct Geometry {
        PackedVector3Array vertices, normals;
        PackedVector2Array uv, uv2;
        PackedColorArray colors;
        PackedInt32Array indices;

        bool read(const Array &a, int max_vertices, int expected_indices) {
            if (a.size() != MAX || a[VERTEX].get_type() != Variant::PACKED_VECTOR3_ARRAY ||
                    a[NORMAL].get_type() != Variant::PACKED_VECTOR3_ARRAY ||
                    a[UV].get_type() != Variant::PACKED_VECTOR2_ARRAY ||
                    a[UV2].get_type() != Variant::PACKED_VECTOR2_ARRAY ||
                    a[COLOR].get_type() != Variant::PACKED_COLOR_ARRAY ||
                    a[INDEX].get_type() != Variant::PACKED_INT32_ARRAY) return false;
            vertices = a[VERTEX]; normals = a[NORMAL]; uv = a[UV]; uv2 = a[UV2];
            colors = a[COLOR]; indices = a[INDEX];
            const int n = vertices.size();
            if (n <= 0 || n > max_vertices || normals.size() != n || uv.size() != n ||
                    uv2.size() != n || colors.size() != n || indices.size() != expected_indices) return false;
            const auto *ids = indices.ptr();
            for (int i = 0; i < expected_indices; ++i) if (ids[i] < 0 || ids[i] >= n) return false;
            return true;
        }
        void resize(int n, int ni) {
            vertices.resize(n); normals.resize(n); uv.resize(n); uv2.resize(n);
            colors.resize(n); indices.resize(ni);
        }
        Array arrays() const {
            Array a; a.resize(MAX);
            a[VERTEX] = vertices; a[NORMAL] = normals; a[UV] = uv; a[UV2] = uv2;
            a[COLOR] = colors; a[INDEX] = indices;
            return a;
        }
    };
    Geometry source;
    std::array<Geometry, tile_count> tiles;
    std::array<uint8_t, tile_count> state{}; // 0 original, 1 requested, 2 already dense.
    bool valid = false;
    Array result;

    Geometry subdivide_tile(int tile) const {
        Geometry out; out.resize(dense_vertices, dense_indices);
        auto *v = out.vertices.ptrw(); auto *n = out.normals.ptrw();
        auto *u = out.uv.ptrw(); auto *u2 = out.uv2.ptrw(); auto *c = out.colors.ptrw();
        auto *ids = out.indices.ptrw();
        const auto *sv = source.vertices.ptr(); const auto *sn = source.normals.ptr();
        const auto *su = source.uv.ptr(); const auto *su2 = source.uv2.ptr();
        const auto *sc = source.colors.ptr(); const auto *si = source.indices.ptr();
        int at = 0, index_at = 0;
        for (int triangle = 0; triangle < 8; ++triangle) {
            const int a = si[tile * tile_indices + triangle * 3];
            const int b = si[tile * tile_indices + triangle * 3 + 1];
            const int d = si[tile * tile_indices + triangle * 3 + 2];
            int rows[subdiv + 1];
            for (int y = 0; y <= subdiv; ++y) {
                rows[y] = at;
                for (int x = 0; x <= subdiv - y; ++x, ++at) {
                    const real_t wy = real_t(y) / subdiv, wx = real_t(x) / subdiv;
                    const real_t w = real_t(1) - wx - wy;
                    v[at] = sv[a] * w + sv[b] * wx + sv[d] * wy;
                    n[at] = sn[a] * w + sn[b] * wx + sn[d] * wy;
                    u[at] = su[a] * w + su[b] * wx + su[d] * wy;
                    u2[at] = su2[a] * w + su2[b] * wx + su2[d] * wy;
                    c[at] = sc[a] * w + sc[b] * wx + sc[d] * wy;
                }
            }
            for (int y = 0; y < subdiv; ++y) {
                for (int x = 0; x < subdiv - y; ++x) {
                    const int i = rows[y] + x, j = rows[y + 1] + x;
                    ids[index_at++] = i; ids[index_at++] = i + 1; ids[index_at++] = j;
                    if (x < subdiv - y - 1) {
                        ids[index_at++] = i + 1; ids[index_at++] = j + 1; ids[index_at++] = j;
                    }
                }
            }
        }
        return out;
    }

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure", "source", "tiles"), &SoftGroundMeshJob::configure);
        ClassDB::bind_method(D_METHOD("run"), &SoftGroundMeshJob::run);
        ClassDB::bind_method(D_METHOD("read_result"), &SoftGroundMeshJob::read_result);
    }
public:
    bool configure(const Array &p_source, const Dictionary &p_tiles) {
        valid = false; result.clear(); state.fill(0);
        source = Geometry(); tiles = {};
        if (p_tiles.size() > 128 || !source.read(p_source, 16384, tile_count * tile_indices)) return false;
        // The land mesh has no custom/skinning attributes. A different layout
        // must use the script adapter, which preserves its additional fields.
        for (int field = 6; field < INDEX; ++field) if (p_source[field].get_type() != Variant::NIL) return false;
        const Array keys = p_tiles.keys();
        for (int i = 0; i < keys.size(); ++i) {
            if (keys[i].get_type() != Variant::INT) return false;
            const int64_t id = keys[i];
            if (id < 0 || id >= tile_count) return false;
            const Variant value = p_tiles[keys[i]];
            if (value.get_type() == Variant::NIL) state[id] = 1;
            else if (value.get_type() == Variant::ARRAY && tiles[id].read(value, dense_vertices, dense_indices)) state[id] = 2;
            else return false;
        }
        valid = true;
        return true;
    }

    void run() {
        if (!valid) return;
        Dictionary generated;
        int nv = source.vertices.size(), ni = 0, ns = 0;
        for (int tile = 0; tile < tile_count; ++tile) {
            if (state[tile] == 1) {
                tiles[tile] = subdivide_tile(tile);
                generated[tile] = tiles[tile].arrays();
            }
            if (state[tile]) {
                nv += tiles[tile].vertices.size();
                ni += tiles[tile].indices.size(); ns += tiles[tile].indices.size();
            } else ni += tile_indices;
        }
        Geometry out; out.resize(nv, ni);
        auto *v = out.vertices.ptrw(); auto *n = out.normals.ptrw();
        auto *u = out.uv.ptrw(); auto *u2 = out.uv2.ptrw(); auto *c = out.colors.ptrw();
        auto *indices = out.indices.ptrw();
        auto copy_vertices = [&](const Geometry &g, int base) {
            const int count = g.vertices.size();
            std::copy_n(g.vertices.ptr(), count, v + base); std::copy_n(g.normals.ptr(), count, n + base);
            std::copy_n(g.uv.ptr(), count, u + base); std::copy_n(g.uv2.ptr(), count, u2 + base);
            std::copy_n(g.colors.ptr(), count, c + base);
        };
        copy_vertices(source, 0);
        PackedInt32Array shadow_ids; shadow_ids.resize(ns); auto *shadow = shadow_ids.ptrw();
        const int source_count = source.vertices.size();
        const auto *original = source.indices.ptr();
        int base = source_count, at = 0, shadow_at = 0;
        for (int tile = 0; tile < tile_count; ++tile) {
            if (!state[tile]) {
                std::copy_n(original + tile * tile_indices, tile_indices, indices + at); at += tile_indices;
                continue;
            }
            const Geometry &g = tiles[tile];
            copy_vertices(g, base);
            const auto *ids = g.indices.ptr();
            for (int i = 0; i < g.indices.size(); ++i) {
                indices[at++] = base + ids[i]; shadow[shadow_at++] = base + ids[i] - source_count;
            }
            base += g.vertices.size();
        }
        Array shadow_arrays; shadow_arrays.resize(MAX);
        if (ns) {
            shadow_arrays[VERTEX] = out.vertices.slice(source_count);
            shadow_arrays[NORMAL] = out.normals.slice(source_count);
            shadow_arrays[UV] = out.uv.slice(source_count); shadow_arrays[UV2] = out.uv2.slice(source_count);
            shadow_arrays[COLOR] = out.colors.slice(source_count); shadow_arrays[INDEX] = shadow_ids;
        }
        result = Array(); result.resize(3);
        result[0] = out.arrays(); result[1] = shadow_arrays; result[2] = generated;
    }
    Array read_result() const { return result; }
};
