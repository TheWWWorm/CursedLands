// SPDX-License-Identifier: Apache-2.0
// Included inside TerrainSearchKernel. Static, revision-owned navigation
// records: no scene objects, actor occupancy, callbacks or saved game state.
private:
    bool topology_ready = false;
    int topology_next_component = 0;
    std::vector<Vector2i> topology_representatives;
    std::vector<uint16_t> topology_connection_bits; // bit 8 means initialized
    std::vector<int> topology_components;
    std::unordered_map<int, int> topology_cost_values;
    std::map<std::tuple<int, int, int, int>, PackedInt32Array> topology_labels;
    std::unordered_map<uint64_t, Array> topology_seed_cache[2];

    void reset_topology() {
        topology_ready = false;
        topology_next_component = 0;
        topology_representatives.clear(); topology_connection_bits.clear();
        topology_components.clear(); topology_cost_values.clear();
        topology_labels.clear();
        topology_seed_cache[0].clear(); topology_seed_cache[1].clear();
    }
    bool topology_inside(Vector2i b) const {
        return b.x >= 0 && b.y >= 0 && b.x < width / 8 && b.y < height / 8;
    }
    struct TopologyReach {
        Rect2i rect;
        PackedInt32Array labels;
        std::vector<uint8_t> reached;
        int component = 0;
        bool seen(Vector2i p) const {
            if (!rect.has_point(p)) return false;
            const int i = (p.y - rect.position.y) * rect.size.x + p.x - rect.position.x;
            return labels.is_empty() ? reached[size_t(i)] != 0 : labels[i] == component;
        }
    };
    TopologyReach topology_reach(Rect2i rect, Vector2i start, bool reverse = false) {
        TopologyReach result; result.rect = rect;
        const int rw = rect.size.x, rh = rect.size.y;
        const bool in_map = start.x >= 0 && start.y >= 0 && start.x < width && start.y < height;
        if (topology_undirected && rect.has_point(start) && in_map && land[start.y * width + start.x] == 0) {
            const auto key = std::make_tuple(rect.position.x, rect.position.y, rw, rh);
            auto it = topology_labels.find(key);
            if (it == topology_labels.end()) it = topology_labels.emplace(key, labels(rect)).first;
            result.labels = it->second;
            result.component = result.labels[(start.y - rect.position.y) * rw + start.x - rect.position.x];
            return result;
        }
        // A blocked start may step out; a reversed directed search may enter
        // a blocked cell. Keep the original exceptional-start flood semantics.
        result.reached.assign(size_t(rw) * rh, 0);
        if (!rect.has_point(start)) return result;
        std::vector<int> pending;
        const int si = (start.y - rect.position.y) * rw + start.x - rect.position.x;
        pending.push_back(si); result.reached[si] = 1;
        const auto *l = land.ptr();
        const auto *c = costs.ptr(), *h = heights.ptr(), *s = slopes.ptr();
        for (size_t at = 0; at < pending.size(); ++at) {
            const int i = pending[at], x = i % rw, y = i / rw;
            const int gx = rect.position.x + x, gy = rect.position.y + y;
            if (gx < 0 || gy < 0 || gx >= width || gy >= height) continue;
            const int gi = gy * width + gx;
            for (int k : order) {
                const int qx = x + dx[k], qy = y + dy[k];
                if (qx < 0 || qy < 0 || qx >= rw || qy >= rh || gx + dx[k] < 0 || gy + dy[k] < 0 ||
                    gx + dx[k] >= width || gy + dy[k] >= height) continue;
                const int qi = qy * rw + qx;
                if (result.reached[qi]) continue;
                int from = gi, to = gi + dy[k] * width + dx[k];
                if (reverse) std::swap(from, to);
                const int64_t dh = int64_t(h[to]) - h[from] + 1023;
                if (l[to] || c[to] < 0 || dh < 0 || dh >= slopes.size() || s[dh] < 0) continue;
                result.reached[qi] = 1; pending.push_back(qi);
            }
        }
        return result;
    }
    uint8_t topology_connection_mask(Vector2i b) {
        const int i = b.y * (width / 8) + b.x;
        if (topology_connection_bits[i] & 256) return uint8_t(topology_connection_bits[i]);
        const auto reachable = topology_reach(Rect2i(b * 8 - Vector2i(8, 8), Vector2i(25, 25)), topology_representative(b));
        uint8_t bits = 0;
        for (int k = 1; k <= 8; ++k) {
            const Vector2i q = b + Vector2i(dx[k], dy[k]);
            if (topology_inside(q) && reachable.seen(topology_representative(q))) bits |= 1 << (k - 1);
        }
        topology_connection_bits[i] = uint16_t(bits) | 256;
        return bits;
    }
public:
    bool configure_topology(const PackedInt32Array &values) {
        reset_topology();
        if (!width || !height || width % 8 || height % 8 || values.is_empty()) return false;
        const size_t n = size_t(width / 8) * (height / 8);
        topology_representatives.assign(n, Vector2i(-1, -1));
        topology_connection_bits.assign(n, 0); topology_components.assign(n, 0);
        block_ready.assign(n, 0);
        for (int64_t i = 0; i < values.size(); ++i) topology_cost_values.emplace(values[i], int(i));
        topology_ready = true;
        return true;
    }
    Vector2i topology_representative(Vector2i b) {
        if (!topology_ready || !topology_inside(b)) return Vector2i(-1, -1);
        const int index = b.y * (width / 8) + b.x;
        if (topology_representatives[index].x >= 0) return topology_representatives[index];
        Vector2i chosen = b * 8 + Vector2i(3, 3);
        int best = 0; bool crossing = false;
        const Rect2i rect(b * 8, Vector2i(9, 9));
        for (int radius = 1; radius < 5; ++radius) {
            for (int y = 4 - radius; y < 4 + radius; ++y) {
                for (int x = 4 - radius; x < 4 + radius; ++x) {
                    const Vector2i p = b * 8 + Vector2i(x, y);
                    const int gi = p.y * width + p.x;
                    const auto found = topology_cost_values.find(costs[gi]);
                    const int value = land[gi] ? 0 : (found == topology_cost_values.end() ? -1 : found->second);
                    if (!value || (crossing && value <= best)) continue;
                    const auto reachable = topology_reach(rect, p);
                    bool left = false, right = false, top = false, bottom = false;
                    for (int j = 0; j < 9; ++j) {
                        left = left || reachable.seen(b * 8 + Vector2i(0, j));
                        right = right || reachable.seen(b * 8 + Vector2i(8, j));
                        top = top || reachable.seen(b * 8 + Vector2i(j, 0));
                        bottom = bottom || reachable.seen(b * 8 + Vector2i(j, 8));
                    }
                    const bool connects = (left && right) || (top && bottom);
                    if (connects || !crossing) { chosen = p; best = value; crossing = connects; }
                }
            }
        }
        topology_representatives[index] = chosen;
        return chosen;
    }
    PackedByteArray topology_connections(Vector2i b) {
        PackedByteArray result;
        if (!topology_ready || !topology_inside(b)) return result;
        const uint8_t mask = topology_connection_mask(b);
        result.resize(8);
        for (int k = 0; k < 8; ++k) result[k] = (mask >> k) & 1;
        return result;
    }
    int topology_component(Vector2i b) {
        if (!topology_ready || !topology_inside(b)) return 0;
        const int bw = width / 8, first = b.y * bw + b.x;
        if (topology_components[first]) return topology_components[first];
        const int component = ++topology_next_component;
        std::vector<int> pending{first}; topology_components[first] = component;
        for (size_t at = 0; at < pending.size(); ++at) {
            const int i = pending[at]; const Vector2i p(i % bw, i / bw);
            const uint8_t open = topology_connection_mask(p);
            for (int k = 1; k <= 8; ++k) {
                const Vector2i q = p + Vector2i(dx[k], dy[k]);
                if (!topology_inside(q)) continue;
                const int qi = q.y * bw + q.x;
                if (topology_components[qi] || !(open & (1 << (k - 1)))) continue;
                if (topology_connection_mask(q) & (1 << ((k + 3) & 7))) {
                    topology_components[qi] = component; pending.push_back(qi);
                }
            }
        }
        return component;
    }
    Array topology_seeds(Vector2i p, bool reverse) {
        Array result;
        if (!topology_ready) return result;
        const uint64_t key = (uint64_t(uint32_t(p.x)) << 32) | uint32_t(p.y);
        auto &cache = topology_seed_cache[reverse ? 1 : 0];
        const auto saved = cache.find(key);
        if (saved != cache.end()) return saved->second;
        const Vector2i block(std::clamp(p.x / 8, 0, width / 8 - 1), std::clamp(p.y / 8, 0, height / 8 - 1));
        const auto reachable = topology_reach(Rect2i(block * 8 - Vector2i(8, 8), Vector2i(25, 25)), p, reverse);
        for (int y = block.y - 1; y <= block.y + 1; ++y) {
            for (int x = block.x - 1; x <= block.x + 1; ++x) {
                const Vector2i b(x, y);
                if (topology_inside(b) && reachable.seen(topology_representative(b))) {
                    Array entry; entry.append(b); entry.append(0); result.append(entry);
                }
            }
        }
        // A long session can visit arbitrarily many cells; static block and
        // label records remain bounded by the map, seed lookup stays bounded.
        if (cache.size() >= 8192) cache.clear();
        cache.emplace(key, result);
        return result;
    }
    PackedInt32Array topology_raw(Vector2i b) {
        PackedInt32Array result;
        if (!topology_ready || !topology_inside(b)) return result;
        const int i = b.y * (width / 8) + b.x;
        if (!block_ready[i]) {
            Array goals;
            for (int k = 1; k <= 8; ++k) {
                const Vector2i q = b + Vector2i(dx[k], dy[k]);
                if (topology_inside(q)) goals.append(topology_representative(q));
            }
            const Rect2i rect(b * 8 - Vector2i(8, 8), Vector2i(25, 25));
            const auto costs = distances(rect, topology_representative(b), false, goals);
            for (int k = 1; k <= 8; ++k) {
                const Vector2i q = b + Vector2i(dx[k], dy[k]);
                int value = limit;
                if (topology_inside(q)) {
                    const Vector2i p = topology_representative(q) - rect.position;
                    value = costs[p.y * rect.size.x + p.x];
                }
                block_edges[i][k - 1] = value < limit ? std::min(value >> 7, 32767) : -1;
            }
            block_ready[i] = 1;
        }
        result.resize(8);
        for (int k = 0; k < 8; ++k) result[k] = block_edges[i][k];
        return result;
    }
    Dictionary topology_stats() const {
        Dictionary out;
        out["representatives"] = std::count_if(topology_representatives.begin(), topology_representatives.end(), [](Vector2i p) { return p.x >= 0; });
        out["components"] = std::count_if(topology_components.begin(), topology_components.end(), [](int c) { return c != 0; });
        out["labels"] = int64_t(topology_labels.size());
        out["seeds"] = int64_t(topology_seed_cache[0].size() + topology_seed_cache[1].size());
        return out;
    }
