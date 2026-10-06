// SPDX-License-Identifier: Apache-2.0
// Bulk construction of NavGrid's existing arrays and AStar grids. No actor
// state, random draws, search ordering, or persistent cache lives here.
#pragma once
#include <godot_cpp/classes/a_star_grid2d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

using namespace godot;

class NavigationBuildKernel : public RefCounted {
    GDCLASS(NavigationBuildKernel, RefCounted)
    static constexpr int step_cost[16] = {
        -1, 0x6400, 0x77ec, 0x8bd8, 0x2ff8, 0x37f0, 0x3ffc, 0xdfc,
        0xfff, 0x11fd, 0x1400, 0x666, 0x732, 0x800, 0x400, 0x4cc};
    // Kept in NavGrid.VALUE order; tests compare every class/value/boundary.
    static constexpr uint8_t values[80] = {
        0,0,1,1,1,1,4,7,11,12,14,14,15,15,15,15,
        0,0,1,1,1,1,4,7,11,12,13,13,13,13,13,13,
        0,0,1,1,1,1,4,7,8,9,10,10,10,10,10,10,
        0,0,1,1,1,1,4,5,6,6,6,6,6,6,6,6,
        0,0,1,1,1,1,2,3,3,3,3,3,3,3,3,3};
    static constexpr double class_height[8] = {2.0,0.4,1.0,1.6,2.2,1.7,3.0,6.0};
    static int value(int64_t cost, int64_t speed) {
        if (cost < 0 || cost > 70 || speed < 0) return 0;
        const int row = cost < 3 ? (cost > 1 ? 1 : 0) : (cost < 10 ? 2 : (cost < 35 ? 3 : 4));
        return values[row * 16 + std::min<int64_t>(15, (speed + 50) / 102)];
    }
    static int64_t rounded(double x) { return int64_t(std::round(x)); }
    static int count(Vector2i size) {
        const int64_t n = int64_t(size.x) * size.y;
        return size.x > 0 && size.y > 0 && n <= 0x7fffffff ? int(n) : 0;
    }
    static std::vector<Vector2i> shape(int cls) {
        if (cls < 5) return {{0,0},{1,0},{-1,0},{0,1},{0,-1}};
        std::vector<Vector2i> result;
        for (int y = -2; y <= 2; ++y) for (int x = -2; x <= 2; ++x)
            if (cls == 7 || std::abs(x) + std::abs(y) <= 2) result.emplace_back(x,y);
        if (cls == 7) for (Vector2i d : {Vector2i(3,0),Vector2i(-3,0),Vector2i(0,3),Vector2i(0,-3)}) result.push_back(d);
        return result;
    }
    static void paint(uint8_t *dst, int i, Vector2i size, const std::vector<Vector2i> &offsets) {
        const int x = i % size.x, y = i / size.x;
        for (Vector2i d : offsets) {
            const int qx = x + d.x, qy = y + d.y;
            if (qx >= 0 && qy >= 0 && qx < size.x && qy < size.y) dst[qy * size.x + qx] = 1;
        }
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("base_cells", "input"), &NavigationBuildKernel::base_cells);
        ClassDB::bind_method(D_METHOD("prepare", "input"), &NavigationBuildKernel::prepare);
        ClassDB::bind_method(D_METHOD("build_layer", "input"), &NavigationBuildKernel::build_layer);
        ClassDB::bind_method(D_METHOD("labels", "size", "land"), &NavigationBuildKernel::labels);
    }
public:
    Dictionary base_cells(const Dictionary &d) const {
        const Vector2i size = d.get("size", Vector2i());
        const int n = count(size), gw = d.get("grid_width", 0);
        const double alt = d.get("alt", 0.0);
        const PackedFloat32Array heights = d.get("heights", PackedFloat32Array()), water = d.get("water", PackedFloat32Array());
        const PackedByteArray ground = d.get("ground", PackedByteArray()), material = d.get("water_mat", PackedByteArray()),
            liquid = d.get("liquid", PackedByteArray()), liq_ok = d.get("liq_ok", PackedByteArray());
        const PackedInt32Array costs = d.get("cost_of", PackedInt32Array());
        const int64_t quads = int64_t(size.x / 2) * (size.y / 2);
        if (!n || (size.x & 1) || (size.y & 1) || gw != size.x / 2 + 1 ||
            heights.size() != int64_t(gw) * (size.y / 2 + 1) || costs.size() != 32 ||
            (!ground.is_empty() && ground.size() != quads) || (!water.is_empty() && water.size() != quads) ||
            !std::isfinite(alt) || alt <= 0.0) return {};
        const bool has_liq = !water.is_empty() && liquid.size() == water.size() && material.size() == water.size();
        if (has_liq && liq_ok.size() != 256) return {};
        PackedFloat32Array h, depth; PackedInt32Array hq, cost; PackedByteArray liq;
        h.resize(n); depth.resize(n); hq.resize(n); cost.resize(n); liq.resize(n);
        auto *hp = h.ptrw(); auto *dp = depth.ptrw(); auto *qp = hq.ptrw(); auto *cp = cost.ptrw(); auto *lp = liq.ptrw();
        const float *hs = heights.ptr(), *wl = water.ptr(); const auto *ct = costs.ptr();
        const auto *gr = ground.ptr(), *wm = material.ptr(), *lg = liquid.ptr(), *ok = liq_ok.ptr();
        for (int cy = 0; cy < size.y; ++cy) for (int cx = 0; cx < size.x; ++cx) {
            const int qx = cx >> 1, qy = cy >> 1, nx = cx & 1, ny = (cy & 1) ? gw : 0;
            const int vi = qy * gw + qx, i = cy * size.x + cx, q = qy * (size.x / 2) + qx;
            // GDScript arithmetic is double; round before narrowing to the
            // packed float array, as the original script does.
            const double gz = double(hs[vi + ny + nx]) * 0.5 +
                (double(hs[vi + ny + 1 - nx]) + double(hs[vi + gw - ny + nx])) * 0.25;
            const double quantized = gz * alt;
            if (!std::isfinite(quantized) || std::abs(quantized) > 2147483646.0) return {};
            hp[i] = float(gz); qp[i] = int32_t(rounded(quantized)); cp[i] = ground.is_empty() ? 2 : ct[gr[q] & 31];
            dp[i] = 0.0f; lp[i] = 255;
            if (!water.is_empty()) {
                const double dep = std::max(0.0, double(wl[q]) - gz);
                if (!std::isfinite(dep * alt) || dep * alt > 2147483646.0) return {};
                if (rounded(dep * alt) >= 1) {
                    dp[i] = float(dep);
                    if (has_liq && lg[q] != 255 && ok[wm[q]] == 1) { lp[i] = lg[q] & 31; cp[i] = ct[lp[i]]; }
                }
            }
        }
        Dictionary out; out["h"] = h; out["hq"] = hq; out["cost"] = cost; out["depth"] = depth; out["liq"] = liq;
        return out;
    }

    Dictionary prepare(const Dictionary &d) const {
        const Vector2i size = d.get("size", Vector2i()); const int n = count(size), w = size.x;
        const PackedInt32Array hq = d.get("hq", PackedInt32Array()), cost = d.get("cost", PackedInt32Array()),
            slope60 = d.get("slope60", PackedInt32Array()), slope40 = d.get("slope40", PackedInt32Array());
        const PackedFloat32Array depth = d.get("depth", PackedFloat32Array()); const Dictionary spans = d.get("spans", Dictionary());
        if (!n || hq.size() != n || cost.size() != n || depth.size() != n || slope60.size() != 2047 || slope40.size() != 2047) return {};
        PackedByteArray steep, raw, special; PackedFloat32Array weight; PackedInt32Array steep_cells, special_cells, diff;
        steep.resize(n); raw.resize(n); special.resize(n); weight.resize(n);
        auto *st = steep.ptrw(), *r = raw.ptrw(), *sp = special.ptrw(); auto *wt = weight.ptrw();
        const auto *hs = hq.ptr(), *cs = cost.ptr(), *s60 = slope60.ptr(), *s40 = slope40.ptr(); const auto *dep = depth.ptr();
        std::vector<int> first_values; int histogram[16] = {};
        for (int i = 0; i < n; ++i) {
            st[i] = 0; r[i] = 0; wt[i] = 1.0f;
            const int x = i % w, y = i / w;
            if (x > 0 && x < w - 1 && y > 0 && y < size.y - 1) {
                const int64_t z = hs[i];
                const int64_t dh = std::max({std::abs(int64_t(hs[i-1])-z),std::abs(int64_t(hs[i+1])-z),
                    std::abs(int64_t(hs[i-w])-z),std::abs(int64_t(hs[i+w])-z)});
                st[i] = dh > 1023 || s60[dh + 1023] < 0 ? 2 : (s40[dh + 1023] < 0 ? 1 : 0);
            }
            sp[i] = dep[i] > 0.0f || spans.has(i);
            if (sp[i]) { special_cells.append(i); continue; }
            const int v = value(cs[i], 1024);
            if (!v) r[i] = 1;
            else {
                wt[i] = v == 14 ? 1.0f : float(step_cost[v]) / 1024.0f;
                // The script histogram is ordered by first encountered weight.
                // Values with the same weight must share a histogram entry.
                int bucket = v;
                for (int first : first_values) if (step_cost[first] == step_cost[v]) { bucket = first; break; }
                if (!histogram[bucket]) first_values.push_back(bucket);
                ++histogram[bucket];
            }
        }
        for (int v : {1,2}) for (int i = 0; i < n; ++i) if (st[i] == v) steep_cells.append(i);
        double mode = 1.0; int best = -1;
        for (int v : first_values) if (histogram[v] > best) { best = histogram[v]; mode = double(step_cost[v]) / 1024.0; }
        for (int i = 0; i < n; ++i) if (!r[i] && !sp[i] && wt[i] != mode) diff.append(i);
        Dictionary out; out["steep"] = steep; out["steep_cells"] = steep_cells; out["raw"] = raw;
        out["weight"] = weight; out["special"] = special; out["special_cells"] = special_cells;
        out["mode"] = mode; out["diff"] = diff; return out;
    }

    PackedInt32Array labels(Vector2i size, const PackedByteArray &land) const {
        const int n = count(size); PackedInt32Array result;
        if (!n || land.size() != n) return result;
        result.resize(n); auto *ids = result.ptrw(); std::fill(ids, ids + n, 0);
        const auto *closed = land.ptr(); std::vector<int> queue; int next = 0;
        for (int i = 0; i < n; ++i) {
            if (closed[i] || ids[i]) continue;
            ++next; ids[i] = next; queue.clear(); queue.push_back(i);
            for (size_t at = 0; at < queue.size(); ++at) {
                const int x = queue[at] % size.x, y = queue[at] / size.x;
                for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx) {
                    const int qx = x + dx, qy = y + dy;
                    if (qx < 0 || qy < 0 || qx >= size.x || qy >= size.y) continue;
                    const int q = qy * size.x + qx;
                    if (!closed[q] && !ids[q]) { ids[q] = next; queue.push_back(q); }
                }
            }
        }
        return result;
    }

    Dictionary build_layer(const Dictionary &d) const {
        const Vector2i size = d.get("size", Vector2i()); const int n = count(size), cls = d.get("cls", -1);
        const double alt = d.get("alt", 0.0), mode = cls == 0 ? 1.0 : double(d.get("mode", 1.0));
        const PackedByteArray dry_raw = d.get("dry_raw", PackedByteArray()), steep = d.get("steep", PackedByteArray());
        const PackedFloat32Array dry_weight = d.get("dry_weight", PackedFloat32Array()), depth = d.get("depth", PackedFloat32Array());
        const PackedInt32Array special = d.get("special_cells", PackedInt32Array()), diff = d.get("diff", PackedInt32Array()),
            cost0 = d.get("cost", PackedInt32Array()), heights = d.get("hq", PackedInt32Array());
        const Dictionary spans = d.get("spans", Dictionary()); PackedByteArray fixed = d.get("fixed", PackedByteArray());
        if (!n || cls < 0 || cls > 7 || dry_raw.size() != n || steep.size() != n || dry_weight.size() != n ||
            depth.size() != n || cost0.size() != n || heights.size() != n || (!fixed.is_empty() && fixed.size() != n) ||
            !std::isfinite(alt) || alt <= 0.0 || alt > 1e8 || !std::isfinite(mode) || mode < 0.0 || mode > 1e6) return {};
        PackedByteArray raw = dry_raw.duplicate(); auto *rp = raw.ptrw(); const auto *cs = cost0.ptr(), *hs = heights.ptr();
        const auto *dp = depth.ptr(); const auto *dry = dry_raw.ptr(), *st = steep.ptr();
        std::vector<int> weights(special.size(), 0); const int64_t body = rounded(class_height[cls] * alt);
        for (int64_t k = 0; k < special.size(); ++k) {
            const int i = special[k]; if (i < 0 || i >= n || !std::isfinite(dp[i]) || std::abs(double(dp[i]) * alt) > 2147483646.0) return {};
            int64_t cost = cls == 0 ? 1 : cs[i], speed = 1024;
            if (cost < 0) { rp[i] = 1; continue; }
            const int64_t dq = std::min<int64_t>(63, rounded(double(dp[i]) * alt));
            if (dp[i] > 0.0f && cls != 0) {
                const int64_t hq = cls == 1 ? 0 : body;
                if (dq == 63 || hq - 1 <= dq) { rp[i] = 1; continue; }
                if (hq < 1024) { if (hq / 2 < dq) { speed = 800; cost += 30; } else speed = 880; }
            }
            if (spans.has(i)) {
                const Array list = spans[i]; const int64_t bb = hs[i] + (cls == 0 ? dq : 0), bt = bb + body;
                for (int64_t j = 0; j < list.size(); ++j) {
                    const Array span = list[j]; if (span.size() < 3) return {};
                    const int64_t lo = span[0], hi = span[1], kind = span[2];
                    if (kind >= 2 || lo > bt || hi < bb) continue;
                    if (kind < 0 || !body) return {};
                    const double fraction = double(std::min(hi, bt) - std::max(lo, bb)) / double(body);
                    cost += rounded((kind == 0 ? 290 : 20) * fraction);
                    speed = rounded(speed * std::pow(0.6, (kind == 0 ? 7 : 2) * fraction));
                }
            }
            const int v = value(cost, speed); weights[k] = step_cost[v]; if (!v) rp[i] = 1;
        }
        const auto offsets = shape(cls);
        if (fixed.is_empty()) {
            fixed.resize(n); auto *fp = fixed.ptrw(); std::fill(fp, fp + n, 0);
            const std::vector<Vector2i> near = cls == 7 ? shape(5) : (cls == 5 || cls == 6 ?
                std::vector<Vector2i>{{1,0},{-1,0},{0,1},{0,-1}} : std::vector<Vector2i>{});
            for (int i = 0; i < n; ++i) {
                if (dry[i]) paint(fp, i, size, offsets);
                if (st[i]) { if (st[i] == 2 || cls != 0) fp[i] = 1; paint(fp, i, size, near); }
                const int x = i % size.x, y = i / size.x;
                if (x < 3 || y < 3 || x >= size.x - 3 || y >= size.y - 3) fp[i] = 1;
            }
        }
        PackedByteArray land = fixed.duplicate(); auto *lp = land.ptrw();
        for (int64_t k = 0; k < special.size(); ++k) if (rp[special[k]]) paint(lp, special[k], size, offsets);
        Ref<AStarGrid2D> astar; astar.instantiate(); astar->set_region(Rect2i(Vector2i(),size));
        astar->set_cell_size(Vector2(1,1)); astar->set_diagonal_mode(AStarGrid2D::DIAGONAL_MODE_ALWAYS);
        astar->set_default_compute_heuristic(AStarGrid2D::HEURISTIC_OCTILE);
        astar->set_default_estimate_heuristic(AStarGrid2D::HEURISTIC_OCTILE); astar->update();
        astar->fill_weight_scale_region(astar->get_region(),mode);
        PackedInt32Array cost, bmin; cost.resize(n); const int bw = (size.x + 7) / 8;
        bmin.resize(bw * ((size.y + 7) / 8)); auto *cp = cost.ptrw(), *bp = bmin.ptrw();
        std::fill(cp,cp+n,int(rounded(mode*1024.0))); std::fill(bp,bp+bmin.size(),int(rounded(mode*1024.0)));
        const auto set_weight = [&](int i, double weight) {
            const int x = i % size.x, y = i / size.x, block = (y / 8) * bw + x / 8;
            astar->set_point_weight_scale(Vector2i(x,y),weight); cp[i] = int(rounded(weight*1024.0));
            bp[block] = std::min(bp[block],cp[i]);
        };
        for (int64_t k = 0; k < diff.size(); ++k) {
            const int i = diff[k]; if (i < 0 || i >= n) return {};
            set_weight(i,cls == 0 ? 1.0 : double(dry_weight[i]));
        }
        for (int64_t k = 0; k < special.size(); ++k) if (weights[k] > 0) set_weight(special[k],double(weights[k])/1024.0);
        for (int i = 0; i < n; ++i) if (lp[i]) astar->set_point_solid(Vector2i(i%size.x,i/size.x),true);
        Dictionary out; out["astar"] = astar; out["raw"] = raw; out["land"] = land; out["cost"] = cost;
        out["bmin"] = bmin; out["fixed"] = fixed; out["comp"] = labels(size,land); return out;
    }
};
