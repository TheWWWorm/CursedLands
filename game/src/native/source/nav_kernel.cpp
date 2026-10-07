// SPDX-License-Identifier: Apache-2.0
// Integer terrain searches. Actor state, path ordering and the simulation
// clock remain in the game. Each instance belongs to one map revision.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <array>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <algorithm>
#include <cstdint>
#include <cmath>
#include <functional>
#include <queue>
#include <map>
#include <tuple>
#include <vector>

#include "window_frontier.h"
#include "unit_simulation_state.h"
#include "unit_query.h"
#include "perception_batch.h"
#include "terrain_color.h"
#include "particle_draw.h"
#include "unit_presentation.h"
#include "motion_spline.h"
#include "mmp_texture.h"
#include "audio_decode.h"
#include "fire_particles.h"
#include "spell_particles.h"
#include "grass_chunk.h"
#include "nav_turn.h"
#include "soft_ground_mesh.h"
#include "ai_activity.h"
#include "screen_rect.h"
#include "nav_build.h"
#include <godot_cpp/variant/dictionary.hpp>
using namespace godot;

class TerrainSearchKernel : public RefCounted {
    GDCLASS(TerrainSearchKernel, RefCounted)
    int width = 0, height = 0;
    bool topology_undirected = true;
    PackedByteArray land;
    PackedInt32Array costs, heights, slopes;
    std::vector<std::array<int, 8>> block_edges;
    std::vector<uint8_t> block_ready;
    static constexpr int limit = 0x7fffffff;
    static constexpr int dx[9] = {0,0,-1,-1,-1,0,1,1,1};
    static constexpr int dy[9] = {0,-1,-1,0,1,1,1,0,-1};
    static constexpr int order[8] = {4,5,6,7,3,2,1,8};
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure_topology", "cost_values"), &TerrainSearchKernel::configure_topology);
        ClassDB::bind_method(D_METHOD("topology_representative", "block"), &TerrainSearchKernel::topology_representative);
        ClassDB::bind_method(D_METHOD("topology_raw", "block"), &TerrainSearchKernel::topology_raw);
        ClassDB::bind_method(D_METHOD("topology_connections", "block"), &TerrainSearchKernel::topology_connections);
        ClassDB::bind_method(D_METHOD("topology_component", "block"), &TerrainSearchKernel::topology_component);
        ClassDB::bind_method(D_METHOD("topology_seeds", "point", "reverse"), &TerrainSearchKernel::topology_seeds);
        ClassDB::bind_method(D_METHOD("topology_stats"), &TerrainSearchKernel::topology_stats);
        ClassDB::bind_method(D_METHOD("prepare_topology", "points"), &TerrainSearchKernel::prepare_topology);
        ClassDB::bind_method(D_METHOD("prepare_routes", "points"), &TerrainSearchKernel::prepare_routes);
        ClassDB::bind_method(D_METHOD("sealed_reach", "rect", "start", "target", "reach", "stamp", "threshold"), &TerrainSearchKernel::sealed_reach);
        ClassDB::bind_method(D_METHOD("configure", "size", "land", "costs", "heights", "slopes"), &TerrainSearchKernel::configure);
        ClassDB::bind_method(D_METHOD("distances", "rect", "start", "reverse", "goals"), &TerrainSearchKernel::distances);
        ClassDB::bind_method(D_METHOD("block_route", "sources", "targets", "avoid", "read_edges"), &TerrainSearchKernel::block_route);
        ClassDB::bind_method(D_METHOD("labels", "rect"), &TerrainSearchKernel::labels);
        ClassDB::bind_method(D_METHOD("paint_stamps", "rect", "centers", "patterns", "clips"), &TerrainSearchKernel::paint_stamps);
        ClassDB::bind_method(D_METHOD("merge_parents", "frontier", "parents"), &TerrainSearchKernel::merge_parents);
        ClassDB::bind_method(D_METHOD("chain", "frontier", "point"), &TerrainSearchKernel::chain);
        ClassDB::bind_method(D_METHOD("flood", "rect", "start", "reverse", "stamp", "flat", "goal", "previous", "reopen", "threshold"), &TerrainSearchKernel::flood);
        ClassDB::bind_method(D_METHOD("advance", "frontier", "current"), &TerrainSearchKernel::advance);
        ClassDB::bind_method(D_METHOD("direct_window", "rect", "start", "goal", "stamp", "flat", "threshold"), &TerrainSearchKernel::direct_window);
    }
public:
    bool configure(Vector2i size, const PackedByteArray &p_land, const PackedInt32Array &p_costs,
                   const PackedInt32Array &p_heights, const PackedInt32Array &p_slopes) {
        reset_topology();
        width = 0; height = 0;
        int64_t n = int64_t(size.x) * size.y;
        if (size.x <= 0 || size.y <= 0 || n > 0x7fffffff || p_land.size() != n ||
            p_costs.size() != n || p_heights.size() != n || p_slopes.is_empty()) return false;
        width = size.x; height = size.y;
        block_edges.resize((width / 8) * (height / 8));
        block_ready.assign(block_edges.size(), 0);
        land = p_land; costs = p_costs; heights = p_heights; slopes = p_slopes;
        topology_undirected = true;
        for (int64_t i = 0; i < slopes.size(); ++i) {
            if ((p_slopes[i] >= 0) != (p_slopes[slopes.size() - 1 - i] >= 0)) {
                topology_undirected = false; break;
            }
        }
        return true;
    }
    // A conservative bounded flood for AI reachability, not a route search.
    // Exhausting a closed component proves failure; all uncertainty falls back.
    bool sealed_reach(Rect2i rect, Vector2i start, Vector2 target, double reach,
                      const PackedInt32Array &stamp, int threshold) const {
        const int rw = rect.size.x, rh = rect.size.y;
        const int64_t n = int64_t(rw) * rh;
        if (!width || rw <= 0 || rh <= 0 || n > 4096 || stamp.size() != n ||
            !std::isfinite(reach) || !target.is_finite() || !rect.has_point(start) || start.x < 0 || start.y < 0 || start.x >= width || start.y >= height) return false;
        std::vector<uint8_t> seen(n, 0);
        std::array<int, 128> pending;
        int count = 1;
        pending[0] = (start.y - rect.position.y) * rw + start.x - rect.position.x;
        seen[pending[0]] = 1;
        const auto *st = stamp.ptr(); const auto *l = land.ptr(); const auto *c = costs.ptr();
        const auto *h = heights.ptr(); const auto *s = slopes.ptr();
        const double radius = std::max(reach, 0.0) + 0.354;
        for (int at = 0; at < count; ++at) {
            const int i = pending[at], x = rect.position.x + i % rw, y = rect.position.y + i / rw;
            const double rx = x * 0.5 + 0.25 - target.x, ry = y * 0.5 + 0.25 - target.y;
            if (rx * rx + ry * ry <= radius * radius) return false;
            const int gi = y * width + x;
            const int64_t barrier = std::max(int64_t(threshold), int64_t(st[i]) - 1);
            for (int k : order) {
                const int qx = x + dx[k], qy = y + dy[k];
                if (qx < 0 || qy < 0 || qx >= width || qy >= height) continue;
                const int qg = qy * width + qx;
                const int64_t dh = int64_t(h[qg]) - h[gi] + 1023;
                if (l[qg] || c[qg] < 0 || dh < 0 || dh >= slopes.size() || s[dh] < 0) continue;
                if (!rect.has_point(Vector2i(qx, qy))) return false;
                const int qi = (qy - rect.position.y) * rw + qx - rect.position.x;
                if (seen[qi] || st[qi] > barrier) continue;
                if (count == int(pending.size())) return false;
                seen[qi] = 1; pending[count++] = qi;
            }
        }
        return true;
    }
    void merge_parents(const Ref<TerrainWindowFrontier> &f, Dictionary parents) const {
        if (f.is_null()) return;
        const int rw = f->rect.size.x;
        for (int y = 0; y < f->rect.size.y; ++y) {
            const int gy = f->rect.position.y + y;
            if (gy < 0 || gy >= height) continue;
            for (int x = 0; x < rw; ++x) {
                const int gx = f->rect.position.x + x;
                if (gx < 0 || gx >= width) continue;
                const int i = y * rw + x, key = gy * width + gx;
                if (f->costs[i] < limit && int64_t(parents.get(key, 0)) == 0) parents[key] = f->parents[i];
            }
        }
    }
    PackedInt32Array chain(const Ref<TerrainWindowFrontier> &f, Vector2i point) const {
        PackedInt32Array result;
        if (f.is_null()) return result;
        for (size_t guard = 0; f->rect.has_point(point) && guard <= f->parents.size(); ++guard) {
            result.append(point.y * width + point.x);
            const int i = (point.y - f->rect.position.y) * f->rect.size.x + point.x - f->rect.position.x;
            const int k = f->parents[i];
            if (!k) break;
            if (k < 1 || k > 8) return PackedInt32Array();
            point += Vector2i(dx[k], dy[k]);
        }
        return result;
    }
    PackedInt32Array paint_stamps(Rect2i rect, const Array &centers, const Array &patterns, const Array &clips) const {
        PackedInt32Array output;
        const int rw = rect.size.x, rh = rect.size.y;
        const int64_t n = int64_t(rw) * rh;
        if (rw <= 0 || rh <= 0 || n > 65536 || centers.size() != patterns.size() || centers.size() != clips.size()) return output;
        output.resize(n); auto *values = output.ptrw(); std::fill(values, values + n, 0);
        for (int64_t i = 0; i < centers.size(); ++i) {
            const Vector2i c = centers[i]; const PackedInt32Array pattern = patterns[i]; const Rect2i clip = clips[i];
            const auto *entries = pattern.ptr();
            const int cx = c.x - rect.position.x, cy = c.y - rect.position.y;
            for (int64_t j = 0; j + 2 < pattern.size(); j += 3) {
                const int x = cx + entries[j], y = cy + entries[j + 1];
                if (x < 0 || y < 0 || x >= rw || y >= rh || !clip.has_point(rect.position + Vector2i(x, y))) continue;
                const int at = y * rw + x;
                values[at] = std::max(values[at], entries[j + 2]);
            }
        }
        return output;
    }
    void advance(const Ref<TerrainWindowFrontier> &f, int current) const {
        if (f.is_null()) return;
        if (current < 0) current = f->front();
        if (current < 0 || current >= int(f->costs.size())) return;
        const int rw = f->rect.size.x, rh = f->rect.size.y;
        const int x = current % rw, y = current / rw;
        const int gx = f->rect.position.x + x, gy = f->rect.position.y + y;
        auto &q = f->queues[(x + 1) & 3];
        auto at = std::find(q.begin(), q.end(), current); if (at != q.end()) q.erase(at);
        f->closed[current] = 1; f->dirty = true;
        if (gx < 0 || gy < 0 || gx >= width || gy >= height) return;
        const int gi = gy * width + gx;
        const auto *l = land.ptr(); const auto *c = costs.ptr();
        const auto *h = heights.ptr(); const auto *s = slopes.ptr();
        const auto *stamp = f->stamp.is_empty() ? nullptr : f->stamp.ptr();
        const int64_t barrier = stamp ? std::max(int64_t(f->threshold), int64_t(stamp[current]) - 1) : 0;
        for (int k : order) {
            const int qx = x + dx[k], qy = y + dy[k];
            if (qx < 0 || qy < 0 || qx >= rw || qy >= rh || gx + dx[k] < 0 || gy + dy[k] < 0 ||
                gx + dx[k] >= width || gy + dy[k] >= height) continue;
            const int qi = qy * rw + qx;
            if (f->closed[qi] || (stamp && stamp[qi] > barrier)) continue;
            int from = gi, to = gi + dy[k] * width + dx[k];
            if (f->reverse) std::swap(from, to);
            const int64_t dh = int64_t(h[to]) - h[from] + 1023;
            if (l[to] || dh < 0 || dh >= slopes.size() || s[dh] < 0 || c[to] < 0) continue;
            const int base = (k & 1) == 0 ? 0x5a8 : 0x400;
            const int64_t edge = f->flat ? (int64_t(s[dh]) * base) >> 10 :
                (((int64_t(s[dh]) * c[to]) >> 10) * base) >> 10;
            const int64_t next = int64_t(f->costs[current]) + edge;
            if (next < f->costs[qi]) {
                f->costs[qi] = int(next); f->parents[qi] = ((k + 3) & 7) + 1; f->insert(qi, qx + 1);
            }
        }
    }
    Ref<TerrainWindowFrontier> flood(Rect2i rect, Vector2i start, bool reverse, const PackedInt32Array &stamp,
            bool flat, Vector2i goal, const Ref<TerrainWindowFrontier> &previous, bool reopen, int threshold) const {
        Ref<TerrainWindowFrontier> f;
        const int rw = rect.size.x, rh = rect.size.y;
        const int64_t n = int64_t(rw) * rh;
        if (width == 0 || rw <= 0 || rh <= 0 || n > 65536 || (!stamp.is_empty() && stamp.size() != n)) return f;
        f.instantiate(); f->rect = rect; f->reverse = reverse; f->flat = flat; f->stamp = stamp; f->threshold = threshold;
        f->costs.assign(n, limit); f->parents.assign(n, 0); f->closed.assign(n, 0);
        int cutoff = limit;
        if (previous.is_valid() && reopen) {
            const Rect2i old = previous->rect;
            for (int y = old.position.y; y < old.position.y + old.size.y; ++y) {
                for (int x = old.position.x; x < old.position.x + old.size.x; ++x) {
                    if (rect.has_point(Vector2i(x, y)) && (x == old.position.x || x == old.position.x + old.size.x - 1 ||
                        y == old.position.y || y == old.position.y + old.size.y - 1)) {
                        cutoff = std::min(cutoff, previous->costs[(y - old.position.y) * old.size.x + x - old.position.x]);
                    }
                }
            }
        }
        for (int y = 0; y < rh; ++y) {
            for (int x = 0; x < rw; ++x) {
                const int gx = rect.position.x + x, gy = rect.position.y + y;
                if (gx < 0 || gy < 0 || gx >= width || gy >= height) f->closed[y * rw + x] = 1;
            }
        }
        if (previous.is_valid()) {
            const Rect2i overlap = rect.intersection(previous->rect), old = previous->rect;
            for (int y = overlap.position.y; y < overlap.position.y + overlap.size.y; ++y) {
                for (int x = overlap.position.x; x < overlap.position.x + overlap.size.x; ++x) {
                    const int i = (y - rect.position.y) * rw + x - rect.position.x;
                    const int oi = (y - old.position.y) * old.size.x + x - old.position.x;
                    f->costs[i] = previous->costs[oi]; f->parents[i] = previous->parents[oi];
                    f->closed[i] = reopen ? int(f->costs[i] < cutoff) : previous->closed[oi];
                    if (f->costs[i] < limit && !f->closed[i]) f->insert(i, x - rect.position.x + 1);
                }
            }
        } else if (rect.has_point(start)) {
            const int i = (start.y - rect.position.y) * rw + start.x - rect.position.x;
            f->costs[i] = 0; f->closed[i] = 0; f->insert(i, start.x - rect.position.x + 1);
        }
        while (true) {
            const int current = f->front();
            if (current < 0 || rect.position + Vector2i(current % rw, current / rw) == goal) break;
            advance(f, current);
        }
        return f;
    }
    Dictionary direct_window(Rect2i rect, Vector2i start, Vector2i goal, const PackedInt32Array &stamp, bool flat, int threshold) const {
        Dictionary result;
        Ref<TerrainWindowFrontier> a = flood(rect, start, false, stamp, flat, start, Ref<TerrainWindowFrontier>(), false, threshold);
        Ref<TerrainWindowFrontier> b = flood(rect, goal, true, stamp, flat, goal, Ref<TerrainWindowFrontier>(), false, threshold);
        if (a.is_null() || b.is_null()) return result;
        const std::array<Ref<TerrainWindowFrontier>, 2> sides = {a, b};
        int meet = -1;
        while (true) {
            advance(a, -1); advance(b, -1);
            for (int side = 0; side < 2; ++side) {
                const int current = sides[side]->front();
                if (current < 0) return result;
                if (sides[1-side]->closed[current] && sides[1-side]->costs[current] < limit) { meet = current; break; }
            }
            if (meet >= 0) break;
        }
        PackedInt32Array cells;
        for (int side = 0; side < 2; ++side) {
            std::vector<int> chain; int i = meet;
            for (int guard = 0; guard <= int(a->costs.size()); ++guard) {
                const Vector2i p = rect.position + Vector2i(i % rect.size.x, i / rect.size.x);
                chain.push_back(p.y * width + p.x);
                const int k = sides[side]->parents[i];
                if (!k) break;
                const Vector2i next = p + Vector2i(dx[k], dy[k]);
                if (!rect.has_point(next)) break;
                i = (next.y - rect.position.y) * rect.size.x + next.x - rect.position.x;
                if (guard == int(a->costs.size())) return Dictionary();
            }
            if (side == 0) { for (auto it = chain.rbegin(); it != chain.rend(); ++it) cells.append(*it); }
            else { for (size_t j = 1; j < chain.size(); ++j) cells.append(chain[j]); }
        }
        Array windows; windows.append(rect);
        result["cells"] = cells; result["end"] = Vector2(goal) + Vector2(0.5, 0.5); result["partial"] = false;
        result["blocks"] = Array(); result["windows"] = windows; result["cost"] = int64_t(a->costs[meet]) + b->costs[meet];
        return result;
    }
    PackedInt32Array labels(Rect2i rect) const {
        PackedInt32Array output;
        const int rw = rect.size.x, rh = rect.size.y;
        const int64_t n = int64_t(rw) * rh;
        if (width == 0 || rw <= 0 || rh <= 0 || n > 65536) return output;
        output.resize(n); auto *values = output.ptrw(); std::fill(values, values + n, 0);
        const auto *l = land.ptr(); const auto *c = costs.ptr();
        const auto *h = heights.ptr(); const auto *s = slopes.ptr();
        const int sc = int(slopes.size());
        auto slope_open = [&](int from, int to) {
            const int64_t dh = int64_t(h[to]) - h[from] + 1023;
            return dh >= 0 && dh < sc && s[dh] >= 0;
        };
        // Preserve the full-open rectangle proof used by the script, before
        // its row-ordered union of left and upper neighboring components.
        bool connected = rect.position.x >= 0 && rect.position.y >= 0 &&
            int64_t(rect.position.x) + rw <= width && int64_t(rect.position.y) + rh <= height;
        for (int y = 0; y < rh && connected; ++y) {
            for (int x = 0; x < rw; ++x) {
                const int i = (rect.position.y + y) * width + rect.position.x + x;
                if (l[i] || (x + 1 < rw && !slope_open(i, i + 1)) || (y + 1 < rh && !slope_open(i, i + width))) {
                    connected = false; break;
                }
            }
        }
        if (connected) { std::fill(values, values + n, 1); return output; }
        std::vector<int> parents(1, 0); parents.reserve(n + 1);
        for (int y = 0; y < rh; ++y) {
            const int gy = rect.position.y + y;
            if (gy < 0 || gy >= height) continue;
            for (int x = 0; x < rw; ++x) {
                const int gx = rect.position.x + x;
                if (gx < 0 || gx >= width) continue;
                const int gi = gy * width + gx, i = y * rw + x;
                if (l[gi]) continue;
                auto open = [&](int tx, int ty) {
                    if (tx < 0 || ty < 0 || tx >= width || ty >= height) return false;
                    const int to = ty * width + tx;
                    return !l[to] && c[to] >= 0 && slope_open(gi, to);
                };
                int label = x > 0 && open(gx - 1, gy) ? values[i - 1] : 0;
                if (!label) { label = int(parents.size()); parents.push_back(label); }
                values[i] = label;
                if (y == 0) continue;
                for (int ox = -1; ox <= 1; ++ox) {
                    if (x + ox < 0 || x + ox >= rw || !open(gx + ox, gy - 1)) continue;
                    const int above = values[i - rw + ox];
                    if (!above || above == label) continue;
                    int a = label, b = above;
                    while (parents[a] != a) a = parents[a];
                    while (parents[b] != b) b = parents[b];
                    if (a != b) parents[std::max(a, b)] = std::min(a, b);
                }
            }
        }
        for (size_t i = 1; i < parents.size(); ++i) parents[i] = parents[parents[i]];
        for (int i = 0; i < n; ++i) values[i] = parents[values[i]];
        return output;
    }
    TypedArray<Vector2i> block_route(const Array &sources, const Array &targets, const Array &avoid, const Callable &read_edges) {
        TypedArray<Vector2i> result;
        const int bw = width / 8, bh = height / 8, count = bw * bh;
        if (!count || !read_edges.is_valid()) return result;
        struct Side {
            std::vector<int> costs, parents;
            std::vector<uint8_t> closed;
            std::array<std::vector<int>, 8> queues;
            explicit Side(int n) : costs(n, limit), parents(n, 0), closed(n, 0) {}
            void insert(int i, int x) {
                auto &q = queues[x & 7];
                auto previous = std::find(q.begin(), q.end(), i);
                if (previous != q.end()) q.erase(previous);
                auto at = std::lower_bound(q.begin(), q.end(), costs[i],
                    [&](int entry, int cost) { return costs[entry] < cost; });
                q.insert(at, i);
            }
            int front() const {
                int chosen = -1, best = limit;
                for (const auto &q : queues) {
                    if (!q.empty() && costs[q.front()] < best) {
                        chosen = q.front(); best = costs[chosen];
                    }
                }
                return chosen;
            }
        };
        std::array<Side, 2> sides = {Side(count), Side(count)};
        for (int side = 0; side < 2; ++side) {
            auto &s = sides[side];
            for (int64_t j = 0; j < avoid.size(); ++j) {
                Vector2i b = avoid[j];
                if (b.x >= 0 && b.y >= 0 && b.x < bw && b.y < bh) s.costs[b.y * bw + b.x] = -1;
            }
            const Array &seeds = side == 0 ? sources : targets;
            for (int64_t j = 0; j < seeds.size(); ++j) {
                Array entry = seeds[j]; Vector2i b = entry[0];
                if (b.x < 0 || b.y < 0 || b.x >= bw || b.y >= bh) continue;
                const int i = b.y * bw + b.x, cost = int(entry[1]);
                if (cost <= s.costs[i]) { s.costs[i] = cost; s.insert(i, b.x); }
            }
        }
        bool valid = true;
        auto raw = [&](int i) -> const std::array<int, 8> & {
            if (!block_ready[i]) {
                const PackedInt32Array value = read_edges.call(Vector2i(i % bw, i / bw));
                if (value.size() != 8) {
                    valid = false; block_edges[i].fill(-1);
                } else {
                    std::copy(value.ptr(), value.ptr() + 8, block_edges[i].begin());
                    block_ready[i] = 1;
                }
            }
            return block_edges[i];
        };
        int meet = -1;
        while (true) {
            for (auto &s : sides) {
                const int current = s.front();
                if (current < 0) return result;
                const int x = current % bw, y = current / bw;
                auto &q = s.queues[x & 7]; q.erase(q.begin()); s.closed[current] = 1;
                for (int k = 1; k <= 8; ++k) {
                    const int qx = x + dx[k], qy = y + dy[k];
                    if (qx < 0 || qy < 0 || qx >= bw || qy >= bh) continue;
                    const int qi = qy * bw + qx;
                    // Keep callback evaluation order explicit: it warms the
                    // same immutable representative data as the script.
                    const int first = raw(current)[k - 1];
                    const int second = raw(qi)[(k + 3) & 7];
                    if (!valid) return result;
                    const int edge = std::min(first, second);
                    if (edge < 0) continue;
                    const int64_t next = int64_t(s.costs[current]) + edge;
                    if (next < s.costs[qi]) {
                        s.costs[qi] = int(next); s.parents[qi] = ((k + 3) & 7) + 1; s.insert(qi, qx);
                    }
                }
            }
            for (int side = 0; side < 2; ++side) {
                const int current = sides[side].front();
                if (current < 0) return result;
                if (sides[1 - side].closed[current] && sides[1 - side].costs[current] < limit) {
                    meet = current; break;
                }
            }
            if (meet >= 0) break;
        }
        for (int side = 0; side < 2; ++side) {
            std::vector<Vector2i> path;
            int i = meet;
            for (int guard = 0; guard <= count; ++guard) {
                const Vector2i b(i % bw, i / bw); path.push_back(b);
                const int k = sides[side].parents[i];
                if (k == 0) break;
                i = (b.y + dy[k]) * bw + b.x + dx[k];
                if (guard == count || i < 0 || i >= count) return TypedArray<Vector2i>();
            }
            if (side == 0) {
                for (auto it = path.rbegin(); it != path.rend(); ++it) result.append(*it);
            } else {
                for (size_t j = 1; j < path.size(); ++j) result.append(path[j]);
            }
        }
        return result;
    }
    PackedInt32Array distances(Rect2i rect, Vector2i start, bool reverse, const Array &goals) const {
        PackedInt32Array output;
        const int rw = rect.size.x, rh = rect.size.y;
        const int64_t n64 = int64_t(rw) * rh;
        if (width == 0 || rw <= 0 || rh <= 0 || n64 > 65536) return output;
        const int n = int(n64);
        output.resize(n);
        auto *distance = output.ptrw();
        std::fill(distance, distance + n, limit);
        if (!rect.has_point(start) || goals.is_empty()) return output;
        const auto *l = land.ptr(); const auto *c = costs.ptr();
        const auto *h = heights.ptr(); const auto *s = slopes.ptr();
        const int slope_count = int(slopes.size());
        // Bounds and destination passability use the same directed step in
        // both searches, including slopes that permit only one direction.
        auto step = [&](int from, int to, int k) -> int {
            if (reverse) std::swap(from, to);
            const int64_t dh = int64_t(h[to]) - h[from] + 1023;
            if (l[to] != 0 || dh < 0 || dh >= slope_count || s[dh] < 0 || c[to] < 0) return -1;
            const int base = (k & 1) == 0 ? 0x5a8 : 0x400;
            return int((((int64_t(s[dh]) * c[to]) >> 10) * base) >> 10);
        };
        auto each_neighbor = [&](int i, auto visit) {
            const int x = i % rw, y = i / rw;
            const int gx = rect.position.x + x, gy = rect.position.y + y;
            if (gx < 0 || gy < 0 || gx >= width || gy >= height) return;
            const int gi = gy * width + gx;
            for (int k : order) {
                const int qx = x + dx[k], qy = y + dy[k];
                if (qx < 0 || qy < 0 || qx >= rw || qy >= rh ||
                    gx + dx[k] < 0 || gy + dy[k] < 0 || gx + dx[k] >= width || gy + dy[k] >= height) continue;
                const int cost = step(gi, gi + dy[k] * width + dx[k], k);
                if (cost >= 0) visit(qy * rw + qx, cost);
            }
        };
        const int si = (start.y - rect.position.y) * rw + start.x - rect.position.x;
        // Only reachable endpoints count toward early termination. This also
        // preserves tentative distances when an unreachable goal is present.
        std::vector<uint8_t> reached(n, 0), wanted(n, 0), closed(n, 0);
        const bool labelled = topology_undirected && start.x >= 0 && start.y >= 0 &&
            start.x < width && start.y < height && l[start.y * width + start.x] == 0;
        std::vector<int> pending; pending.reserve(n); pending.push_back(si); reached[si] = 1;
        for (size_t at = 0; at < pending.size(); ++at) {
            each_neighbor(pending[at], [&](int q, int) {
                const int gi = (rect.position.y + q / rw) * width + rect.position.x + q % rw;
                // The script's undirected component labels contain open cells
                // only, including for reverse searches from an open start.
                if (!reached[q] && (!labelled || l[gi] == 0)) { reached[q] = 1; pending.push_back(q); }
            });
        }
        int remaining = 0;
        for (int64_t i = 0; i < goals.size(); ++i) {
            const Vector2i p = goals[i];
            if (!rect.has_point(p)) continue;
            const int q = (p.y - rect.position.y) * rw + p.x - rect.position.x;
            if (reached[q] && !wanted[q]) { wanted[q] = 1; ++remaining; }
        }
        if (!remaining) return output;
        std::priority_queue<uint64_t, std::vector<uint64_t>, std::greater<uint64_t>> heap;
        distance[si] = 0; heap.push(uint64_t(si));
        while (!heap.empty()) {
            const uint64_t item = heap.top(); heap.pop();
            const int current = int(item & 0xffff), cost = int(item >> 16);
            if (closed[current] || distance[current] != cost) continue;
            closed[current] = 1;
            if (wanted[current] && --remaining == 0) break;
            each_neighbor(current, [&](int q, int edge) {
                const int64_t next = int64_t(cost) + edge;
                if (!closed[q] && next < distance[q]) {
                    distance[q] = int(next);
                    heap.push((uint64_t(next) << 16) | uint64_t(q));
                }
            });
        }
        return output;
    }
#include "nav_topology.h"
};

static void initialize_kernel(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(TerrainWindowFrontier); GDREGISTER_CLASS(TerrainSearchKernel);
        GDREGISTER_CLASS(UnitSimulationState); GDREGISTER_CLASS(UnitSimulationLease);
        GDREGISTER_CLASS(UnitNoticeLifetime); GDREGISTER_CLASS(UnitQueryKernel);
        GDREGISTER_CLASS(PerceptionKernel);
        GDREGISTER_CLASS(TerrainColorField);
        GDREGISTER_CLASS(ParticleDrawBuffer);
        GDREGISTER_CLASS(ScreenRectKernel);
        GDREGISTER_CLASS(NavigationBuildKernel); GDREGISTER_CLASS(AIActivityKernel);
        GDREGISTER_CLASS(MotionSplineKernel);
        GDREGISTER_CLASS(MmpTextureKernel);
        GDREGISTER_CLASS(AudioDecodeKernel);
        GDREGISTER_CLASS(FireParticleKernel);
        GDREGISTER_CLASS(SpellParticleKernel);
        GDREGISTER_CLASS(GrassFieldKernel); GDREGISTER_CLASS(GrassChunkJob);
        GDREGISTER_CLASS(NavTurnKernel);
        GDREGISTER_CLASS(SoftGroundMeshJob);
        GDREGISTER_CLASS(UnitPresentationKernel);
        GDREGISTER_CLASS(NetSmoothKernel);
    }
}
static void terminate_kernel(ModuleInitializationLevel) {}
extern "C" {
GDExtensionBool GDE_EXPORT terrain_search_init(GDExtensionInterfaceGetProcAddress get_proc_address,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize_kernel); init.register_terminator(terminate_kernel);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
}
