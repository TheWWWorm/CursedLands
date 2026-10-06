// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <algorithm>
#include <array>
#include <vector>

namespace godot {
class TerrainWindowFrontier : public RefCounted {
    GDCLASS(TerrainWindowFrontier, RefCounted)
    PackedInt32Array saved_costs, saved_parents, saved_closed;
    void sync() {
        if (!dirty) return;
        saved_costs.resize(costs.size()); saved_parents.resize(parents.size()); saved_closed.resize(closed.size());
        std::copy(costs.begin(), costs.end(), saved_costs.ptrw());
        std::copy(parents.begin(), parents.end(), saved_parents.ptrw());
        std::copy(closed.begin(), closed.end(), saved_closed.ptrw()); dirty = false;
    }
protected:
    static void _bind_methods() {
#define WINDOW_PROPERTY(kind, name) \
        ClassDB::bind_method(D_METHOD("get_" #name), &TerrainWindowFrontier::get_##name); \
        ADD_PROPERTY(PropertyInfo(Variant::kind, #name), "", "get_" #name);
        WINDOW_PROPERTY(RECT2I, rect)
        WINDOW_PROPERTY(PACKED_INT32_ARRAY, costs)
        WINDOW_PROPERTY(PACKED_INT32_ARRAY, parents)
        WINDOW_PROPERTY(PACKED_INT32_ARRAY, closed)
        WINDOW_PROPERTY(ARRAY, queue)
        WINDOW_PROPERTY(PACKED_INT32_ARRAY, stamp)
        WINDOW_PROPERTY(BOOL, reverse)
        WINDOW_PROPERTY(BOOL, flat)
        WINDOW_PROPERTY(INT, threshold)
#undef WINDOW_PROPERTY
    }
public:
    Rect2i rect;
    std::vector<int> costs, parents, closed;
    std::array<std::vector<int>, 4> queues;
    PackedInt32Array stamp;
    bool reverse = false, flat = false, dirty = true;
    int threshold = 0;
    Rect2i get_rect() const { return rect; }
    PackedInt32Array get_costs() { sync(); return saved_costs; }
    PackedInt32Array get_parents() { sync(); return saved_parents; }
    PackedInt32Array get_closed() { sync(); return saved_closed; }
    PackedInt32Array get_stamp() const { return stamp; }
    bool get_reverse() const { return reverse; }
    bool get_flat() const { return flat; }
    int get_threshold() const { return threshold; }
    Array get_queue() const {
        Array result;
        for (const auto &q : queues) { Array entries; for (int i : q) entries.append(i); result.append(entries); }
        return result;
    }
    void insert(int i, int x) {
        auto &q = queues[x & 3]; auto old = std::find(q.begin(), q.end(), i);
        if (old != q.end()) q.erase(old);
        q.insert(std::lower_bound(q.begin(), q.end(), costs[i],
            [&](int value, int cost) { return costs[value] < cost; }), i);
    }
    int front() const {
        int best = 0x7fffffff, result = -1;
        for (const auto &q : queues) {
            if (!q.empty() && costs[q.front()] < best) { result = q.front(); best = costs[result]; }
        }
        return result;
    }
};
}
