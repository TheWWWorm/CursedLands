// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace ei_activity {
// Pure data only: no Godot objects, world access, random numbers or shared state.
// A cell summary deliberately overestimates activity. It cannot omit an actor
// inside the observer's radius, and its cost is independent of cell occupancy.
struct Actor { double x, y, radius; int64_t faction; uint8_t flags; uint32_t hostile; };
enum : uint8_t { PARTY = 1, DEAD = 2, HIDDEN = 4 };
constexpr double CELL = 32.;
struct Cell { uint32_t factions = 0; bool stimulus = false; };
inline int64_t key(int x, int y) { return int64_t((uint64_t(uint32_t(x)) << 32) | uint32_t(y)); }

inline std::vector<uint8_t> evaluate(const std::vector<Actor> &actors) {
    std::vector<uint8_t> active(actors.size(), 1);
    std::unordered_map<int64_t, Cell> cells;
    cells.reserve(actors.size());
    for (const auto &a : actors) {
        if (!std::isfinite(a.x) || !std::isfinite(a.y) || std::abs(a.x) > 1e7 || std::abs(a.y) > 1e7 || a.faction < 0 || a.faction >= 32)
            return active; // Unknown target position: fail open for the whole batch.
        if (a.flags & HIDDEN) continue;
        auto &c = cells[key(int(std::floor(a.x / CELL)), int(std::floor(a.y / CELL)))];
        c.factions |= uint32_t(1) << a.faction;
        c.stimulus = c.stimulus || (a.flags & (PARTY | DEAD));
    }
    for (size_t i = 0; i < actors.size(); ++i) {
        const auto &a = actors[i];
        if (a.flags || !std::isfinite(a.radius) || a.radius < 0. || a.radius > 512.) continue;
        const int x0 = int(std::floor((a.x - a.radius) / CELL)), x1 = int(std::floor((a.x + a.radius) / CELL));
        const int y0 = int(std::floor((a.y - a.radius) / CELL)), y1 = int(std::floor((a.y + a.radius) / CELL));
        bool found = false;
        for (int y = y0; y <= y1 && !found; ++y) {
            for (int x = x0; x <= x1; ++x) {
                const double dx = std::max({x * CELL - a.x, a.x - (x + 1.) * CELL, 0.});
                const double dy = std::max({y * CELL - a.y, a.y - (y + 1.) * CELL, 0.});
                if (dx * dx + dy * dy > a.radius * a.radius) continue;
                const auto entry = cells.find(key(x, y));
                if (entry == cells.end()) continue;
                const auto &c = entry->second;
                if (c.stimulus || (c.factions & a.hostile)) { found = true; break; }
            }
        }
        active[i] = found;
    }
    return active;
}
}
