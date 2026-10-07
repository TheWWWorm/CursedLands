// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <algorithm>
#include <array>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {
// The ordered local turn pass. Templates are configured once from NavTurn;
// every refinement owns its frontier, chains and cost cache. Actor stamps
// are captured by the caller once per changed rectangle, never per edge.
class NavTurnKernel : public RefCounted {
    GDCLASS(NavTurnKernel, RefCounted)
    static constexpr int limit = INT32_MAX;
    static constexpr int dx[9] = {0,0,-1,-1,-1,0,1,1,1};
    static constexpr int dy[9] = {0,-1,-1,0,1,1,1,0,-1};
    struct Template { std::vector<int> copy, cross, within; };
    std::array<Template,81> templates;
    bool ready = false;
    struct State {
        std::array<int,9> costs, chain;
        State() { costs.fill(limit); chain.fill(-1); }
    };
    struct Runner {
        const std::array<Template,81> &templates;
        Vector2i size;
        // Const indexing is essential: writable PackedArray indexing would
        // detach and copy the entire shared map for every path request.
        const PackedByteArray land;
        const PackedInt32Array costs, heights, slopes;
        PackedInt32Array stamps;
        bool flat, valid = true;
        int threshold;
        Callable read_stamps;
        Rect2i rect;
        std::unordered_map<int64_t,int> base;
        std::vector<int> nodes, parents;

        bool inside(Vector2i p) const { return p.x >= 0 && p.y >= 0 && p.x < size.x && p.y < size.y; }
        int base_cost(Vector2i p, int dir) {
            if (!inside(p)) return -1;
            const int i = p.y * size.x + p.x;
            const int64_t key = int64_t(i) * 9 + dir;
            auto found = base.find(key);
            if (found != base.end()) return found->second;
            const Vector2i q = p + Vector2i(dx[dir],dy[dir]);
            int value = -1;
            if (inside(q)) {
                const int j = q.y * size.x + q.x;
                const int64_t dh = int64_t(heights[j]) - heights[i] + 1023;
                if (!land[j] && dh >= 0 && dh <= 2046 && dh < slopes.size() && slopes[dh] >= 0) {
                    bool clear = true;
                    if (!stamps.is_empty()) {
                        if (!rect.has_point(p) || !rect.has_point(q)) { valid = false; return -1; }
                        const Vector2i s = p - rect.position, t = q - rect.position;
                        const int32_t *values = stamps.ptr();
                        const int v = values[t.y * rect.size.x + t.x];
                        clear = v <= threshold || v < values[s.y * rect.size.x + s.x];
                    }
                    if (clear) value = int((int64_t(slopes[dh]) * (flat ? 1024 : costs[j])) >> 10);
                }
            }
            base.emplace(key,value);
            return value;
        }
        int node(int cell, int parent) {
            nodes.push_back(cell); parents.push_back(parent);
            return int(nodes.size()) - 1;
        }
        void relax(const std::vector<int> &records, const State &from, State &to, Vector2i at) {
            for (size_t m = 0; m < records.size(); m += 9) {
                const int i = records[m], j = records[m+1];
                if (from.costs[i] == limit) continue;
                const Vector2i p = at + Vector2i(records[m+2],records[m+3]);
                const int dir = ((records[m+8]+3)&7)+1;
                const int cost_base = base_cost(p,dir);
                if (cost_base < 0) continue;
                const int64_t cost = int64_t(from.costs[i]) + ((int64_t(cost_base) * records[m+7]) >> 10) + records[m+6] * 600;
                if (cost < to.costs[j]) {
                    to.costs[j] = int(cost);
                    const Vector2i q = p + Vector2i(records[m+4],records[m+5]);
                    to.chain[j] = node(q.y * size.x + q.x,from.chain[i]);
                }
            }
        }
        State advance(const State &from, int prev, int next, Vector2i at) {
            State to;
            const auto &t = templates[prev*9+next];
            for (size_t m = 0; m < t.copy.size(); m += 2) {
                to.costs[t.copy[m+1]] = from.costs[t.copy[m]];
                to.chain[t.copy[m+1]] = from.chain[t.copy[m]];
            }
            relax(t.cross,from,to,at);
            relax(t.within,to,to,at);
            return to;
        }
        std::pair<PackedInt32Array,int> once(const PackedInt32Array &cells, int facing, int end_cost) {
            const Vector2i start(cells[0] % size.x,cells[0] / size.x);
            Rect2i bounds(start,Vector2i(1,1));
            for (int64_t i = 0; i < cells.size(); ++i) bounds = bounds.expand(Vector2i(cells[i] % size.x,cells[i] / size.x));
            bounds = bounds.grow(2).intersection(Rect2i(Vector2i(),size));
            if (bounds != rect) {
                rect = bounds;
                const Variant captured = read_stamps.call(rect);
                if (captured.get_type() != Variant::PACKED_INT32_ARRAY) { valid = false; return {{},limit}; }
                stamps = captured;
                if (!stamps.is_empty() && stamps.size() != int64_t(rect.size.x) * rect.size.y) { valid = false; return {{},limit}; }
            }
            nodes.clear(); parents.clear();
            State state;
            for (int k = 1; k <= 8; ++k) {
                const int cost_base = base_cost(start,k);
                if (cost_base < 0) continue;
                const int turn = std::min(std::abs(k-facing),8-std::abs(k-facing));
                state.costs[k-1] = int(((int64_t(cost_base) * ((k&1) ? 1024 : 1448)) >> 10) + std::max(0,turn-1)*600);
                const Vector2i q = start + Vector2i(dx[k],dy[k]);
                state.chain[k-1] = node(q.y * size.x + q.x,-1);
            }
            int prev = 0;
            Vector2i at = start;
            for (int64_t m = 1; m < cells.size(); ++m) {
                const Vector2i q(cells[m] % size.x,cells[m] / size.x), delta = q-at;
                int next = 0;
                for (int k = 1; k <= 8; ++k) if (delta == Vector2i(dx[k],dy[k])) { next = k; break; }
                state = advance(state,prev,next,at);
                prev = next; at = q;
            }
            state = advance(state,prev,0,at);
            int best = limit, chain = -1;
            for (int k = 1; k <= 8; ++k) {
                if (state.costs[k-1] == limit) continue;
                const int64_t cost = int64_t(state.costs[k-1]) + ((k&1) ? 0 : end_cost);
                if (cost < best) { best = int(cost); chain = state.chain[k-1]; }
            }
            PackedInt32Array out;
            while (chain >= 0) { out.append(nodes[chain]); chain = parents[chain]; }
            out.append(cells[0]); out.reverse();
            return {out,best};
        }
    };
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure", "templates"), &NavTurnKernel::configure);
        ClassDB::bind_method(D_METHOD("refine", "context", "cells", "heading", "end_cost", "read_stamps"), &NavTurnKernel::refine);
    }
public:
    bool configure(const Array &source) {
        ready = false;
        if (source.size() != 81) return false;
        for (int i = 0; i < 81; ++i) {
            if (source[i].get_type() != Variant::ARRAY) return false;
            const Array row = source[i];
            if (row.size() != 3) return false;
            for (int j = 0; j < 3; ++j) {
                if (row[j].get_type() != Variant::PACKED_INT32_ARRAY) return false;
                const PackedInt32Array records = row[j];
                const int stride = j == 0 ? 2 : 9;
                if (records.size() % stride) return false;
                for (int64_t m = 0; m < records.size(); m += stride) {
                    if (records[m] < 0 || records[m] >= 9 || records[m+1] < 0 || records[m+1] >= 9) return false;
                    if (j && (records[m+8] < 1 || records[m+8] > 8)) return false;
                }
                auto &target = j == 0 ? templates[i].copy : (j == 1 ? templates[i].cross : templates[i].within);
                if (records.is_empty()) target.clear();
                else target.assign(records.ptr(),records.ptr()+records.size());
            }
        }
        ready = true;
        return true;
    }
    Dictionary refine(const Dictionary &context, const PackedInt32Array &cells, int facing, int end_cost, const Callable &read_stamps) const {
        Dictionary result;
        if (!ready || cells.is_empty() || facing < 1 || facing > 8 || !read_stamps.is_valid()) return result;
        Runner run{templates, context.get("size",Vector2i()), context.get("land",PackedByteArray()),
            context.get("costs",PackedInt32Array()), context.get("heights",PackedInt32Array()),
            context.get("slopes",PackedInt32Array()), PackedInt32Array(), bool(context.get("flat",false)), true,
            int(context.get("threshold",0)), read_stamps};
        const int64_t n = int64_t(run.size.x) * run.size.y;
        if (run.size.x <= 0 || run.size.y <= 0 || n > INT32_MAX || run.land.size() != n ||
                run.costs.size() != n || run.heights.size() != n || run.slopes.size() < 2047) return result;
        for (int64_t i = 0; i < cells.size(); ++i) if (cells[i] < 0 || cells[i] >= n) return result;
        int best = limit;
        PackedInt32Array path = cells;
        while (true) {
            const auto next = run.once(path,facing,end_cost);
            if (!run.valid) return Dictionary();
            if (next.second >= best) break;
            best = next.second;
            if (next.first == path) break;
            path = next.first;
        }
        result["cells"] = path; result["cost"] = best;
        return result;
    }
};
} // namespace godot
