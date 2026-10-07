// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <limits>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace godot {
// Owned only by the unit's script instance. Releasing that instance (free or
// script replacement) invalidates native rows without a per-frame script
// notification callback or an ObjectDB lookup for every retained neighbour.
class UnitNoticeLifetime : public RefCounted {
    GDCLASS(UnitNoticeLifetime, RefCounted)
protected:
    static void _bind_methods() {}
public:
    static inline std::atomic<uint64_t> epoch{0};
    ~UnitNoticeLifetime() override { epoch.fetch_add(1, std::memory_order_relaxed); }
};

// Validates ordered lists against the live registry. Membership is sampled
// from actual objects/IDs, never inferred from counts or mutation callbacks.
class UnitQueryKernel : public RefCounted {
    GDCLASS(UnitQueryKernel, RefCounted)
    const StringName uid_key = "uid";
    const StringName hidden_key = "hidden", faction_key = "faction", controller_key = "controller", dead_key = "dead";
    const StringName enemy_method = "is_enemy";
    const StringName pos_key = "pos", seq_key = "_seq";
    const StringName lifetime_key = "_notice_lifetime";
    bool batching = false;
    std::unordered_map<uint64_t, bool> checked;
    std::unordered_set<uint64_t> last_members;
    int64_t membership_epoch = 0;
    bool complete_registry = false;
    struct NoticeRow { Variant unit; int64_t faction; bool party; bool dead; };
    struct NoticeCache {
        Array source;
        Ref<Script> script;
        int64_t revision = -1;
        uint64_t lifetime_epoch = 0;
        size_t bytes = 0;
        std::vector<NoticeRow> rows;
    };
    std::unordered_map<uint64_t, NoticeCache> notices;
    size_t notice_bytes = 0;
    static constexpr size_t notice_limit = 8 * 1024 * 1024;
    bool registered(const Variant &entry, const Dictionary &units) {
        const uint64_t id = entry.get_type() == Variant::OBJECT ? static_cast<uint64_t>(static_cast<ObjectID>(entry)) : 0;
        if (batching) {
            const auto found = checked.find(id);
            if (found != checked.end()) return found->second;
            if (complete_registry) return false;
        }
        Object *unit = entry.get_validated_object();
        const bool valid = unit && units.get(unit->get(uid_key), Variant()) == entry;
        if (batching) checked[id] = valid;
        return valid;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("prune_units", "current", "units"), &UnitQueryKernel::prune_units);
        ClassDB::bind_method(D_METHOD("begin_batch"), &UnitQueryKernel::begin_batch);
        ClassDB::bind_method(D_METHOD("begin_registry_batch", "units"), &UnitQueryKernel::begin_registry_batch);
        ClassDB::bind_method(D_METHOD("end_batch"), &UnitQueryKernel::end_batch);
        ClassDB::bind_method(D_METHOD("notice_candidates", "near", "unit_script", "observer", "world", "sides", "npc", "revision"), &UnitQueryKernel::notice_candidates);
        ClassDB::bind_method(D_METHOD("in_cells", "near", "observer", "origin", "cells", "alive"), &UnitQueryKernel::in_cells);
        ClassDB::bind_method(D_METHOD("order_units", "list", "ranks"), &UnitQueryKernel::order_units);
        ClassDB::bind_method(D_METHOD("near_cells", "buckets", "origin", "radius", "cells", "observer", "alive"), &UnitQueryKernel::near_cells);
        ClassDB::bind_method(D_METHOD("near_units", "buckets", "registered", "origin", "radius", "bucket_size", "alive"), &UnitQueryKernel::near_units);
        ClassDB::bind_method(D_METHOD("step_blocker", "unit", "point", "next_cell", "near", "result"), &UnitQueryKernel::step_blocker);
    }
public:
    static int64_t fistp(double value) {
        if (!std::isfinite(value) || value <= -0x1p63 || value >= 0x1p63) return std::numeric_limits<int64_t>::min();
        const double f = std::floor(value), d = value - f;
        const int64_t whole = int64_t(f);
        return whole + (d > .5 || (d == .5 && whole % 2 != 0));
    }
    static Vector2i cell(Vector2 p) {
        return Vector2i(fistp(double(p.x) * 2. - .5) / 32, fistp(double(p.y) * 2. - .5) / 32);
    }
    Array near_units(const Dictionary &buckets, const Dictionary &registered, Vector2 origin,
                     double radius, double bucket_size, bool alive) const {
        Array out;
        const double r2 = radius * radius;
        auto append = [&](const Variant &entry) {
            Object *unit = entry.get_validated_object();
            if (!unit || (alive && bool(unit->get(dead_key)))) return;
            const Vector2 p = unit->get(pos_key);
            if (double(p.distance_squared_to(origin)) <= r2) out.append(entry);
        };
        bool local = std::isfinite(radius) && radius >= 0. && origin.is_finite() &&
            double(origin.x) - radius >= 0. && double(origin.y) - radius >= 0. && bucket_size > 0.;
        const double x0 = std::floor((double(origin.x) - radius) / bucket_size), x1 = std::floor((double(origin.x) + radius) / bucket_size);
        const double y0 = std::floor((double(origin.y) - radius) / bucket_size), y1 = std::floor((double(origin.y) + radius) / bucket_size);
        const double width = x1 - x0 + 1., height = y1 - y0 + 1.;
        local = local && std::isfinite(x0) && std::isfinite(x1) && std::isfinite(y0) && std::isfinite(y1) &&
            x0 < 0x1p50 && x1 < 0x1p50 && y0 < 0x1p50 && y1 < 0x1p50 &&
            width > 0. && height > 0. && width < 4096. && height < 4096. &&
            width * height <= double(std::max(int64_t(16), registered.size() * 4));
        if (!local) {
            const Array values = registered.values();
            for (int64_t i = 0; i < values.size(); ++i) append(values[i]);
        } else {
            for (int64_t y = int64_t(y0); y <= int64_t(y1); ++y) {
                for (int64_t x = int64_t(x0); x <= int64_t(x1); ++x) {
                    const Variant value = buckets.get(x + y * 4096, Variant());
                    if (value.get_type() != Variant::ARRAY) continue;
                    const Array bucket = value;
                    for (int64_t i = 0; i < bucket.size(); ++i) append(bucket[i]);
                }
            }
        }
        return out;
    }
private:
    mutable std::unordered_map<int64_t, std::array<uint8_t, 256>> stamps;
    static Vector2i nav_cell(Vector2 p) { return Vector2i(fistp(double(p.x) * 2. - .5), fistp(double(p.y) * 2. - .5)); }
    static int64_t stamp_key(double radius) { return radius <= 0.20000000298023224 ? 0 : fistp(float(radius * 10. + 1.)); }
    int stamp_value(int64_t k, Vector2i delta) const {
        if (!k || delta.x < -8 || delta.y < -8 || delta.x > 7 || delta.y > 7) return 0;
        auto it = stamps.find(k);
        if (it == stamps.end()) {
            if (stamps.size() >= 64) stamps.clear();
            std::array<uint8_t, 256> values;
            const double radius = float(double(k) * .1);
            for (int y = -8; y < 8; ++y) for (int x = -8; x < 8; ++x) {
                const int64_t value = fistp(float((radius + 2. - std::sqrt(double(x*x + y*y)) * .5) * 16.));
                values[(y + 8) * 16 + x + 8] = value > 0 ? uint8_t(value) : 0;
            }
            it = stamps.emplace(k, values).first;
        }
        return it->second[(delta.y + 8) * 16 + delta.x + 8];
    }
    static int signed_stamp(int value) { return value & 128 ? value - 256 : value; }
public:
    Object *step_blocker(Object *unit, Vector2 point, Vector2i next_cell, const Array &near, Dictionary result) const {
        if (!unit) return nullptr;
        const Vector2 origin = unit->get(pos_key);
        const Vector2i c0 = nav_cell(origin), cq = next_cell.x >= 0 ? next_cell : nav_cell(point);
        if (c0 == cq) return nullptr;
        static const StringName radius_method("body_radius"), moving_key("_moving");
        const double radius = unit->call(radius_method);
        struct Row { Object *unit; Vector2 pos; Vector2i cell; double radius; int64_t key; };
        std::vector<Row> rows; rows.reserve(size_t(near.size()));
        int now[2] = {}, next[2] = {};
        for (int64_t i = 0; i < near.size(); ++i) {
            Object *other = near[i].get_validated_object();
            if (!other || other == unit || bool(other->get(dead_key))) continue;
            const Vector2 p = other->get(pos_key);
            const double r = other->call(radius_method);
            const int64_t k = stamp_key(r);
            const Vector2i c = nav_cell(p);
            const int layer = bool(other->get(moving_key)) ? 1 : 0;
            next[layer] = std::max(next[layer], stamp_value(k, cq - c));
            now[layer] = std::max(now[layer], stamp_value(k, c0 - c));
            rows.push_back({other, p, c, r, k});
        }
        const int threshold = std::max(int64_t(0), fistp(float((2. - radius) * 16.))) & 255;
        const int layer = next[0] > threshold && next[0] > now[0] ? 1 :
            signed_stamp(next[1]) > threshold && signed_stamp(next[1]) > signed_stamp(now[1]) ? 2 : 0;
        if (!layer) return nullptr;
        for (const auto &row : rows) {
            if (double(point.distance_to(row.pos)) >= radius + row.radius) continue;
            const Vector2i offset = c0 - row.cell;
            if (!row.key || offset.x < -8 || offset.y < -8 || offset.x > 7 || offset.y > 7 ||
                signed_stamp(stamp_value(row.key, offset)) >= threshold) {
                result["standing"] = layer == 1;
                return row.unit;
            }
        }
        return nullptr;
    }
    Array in_cells(const Array &near, Object *observer, Vector2 origin, const Dictionary &cells, bool alive) const {
        Array result;
        const Vector2i center = cell(origin);
        for (int64_t i = 0; i < near.size(); ++i) {
            const Variant entry = near[i];
            Object *unit = entry.get_validated_object();
            if (!unit || unit == observer || (alive && bool(unit->get(dead_key)))) continue;
            if (cells.has(cell(unit->get(pos_key)) - center)) result.append(entry);
        }
        return result;
    }
    // Only used for fully registered positive-coordinate local queries.
    // There the original nearest-even / truncated native16m cells coincide
    // with coarse buckets. Filter before reading buckets and sorting rows.
    Array near_cells(const Dictionary &buckets, Vector2 origin, double radius,
                     const Dictionary &cells, Object *observer, bool alive) const {
        Array result;
        // Also guard direct extension callers before any integer conversion.
        if (!std::isfinite(radius) || radius < 6. || !std::isfinite(origin.x) || !std::isfinite(origin.y) ||
            origin.x - radius < 0. || origin.y - radius < 0. ||
            origin.x + radius >= 65536. || origin.y + radius >= 65536.) return result;
        const Vector2i center = cell(origin);
        const int x0 = int(std::floor((origin.x - radius) / 16.));
        const int x1 = int(std::floor((origin.x + radius) / 16.));
        const int y0 = int(std::floor((origin.y - radius) / 16.));
        const int y1 = int(std::floor((origin.y + radius) / 16.));
        const double r2 = radius * radius;
        for (int y = y0; y <= y1; ++y) {
            for (int x = x0; x <= x1; ++x) {
                if (!cells.has(Vector2i(x, y) - center)) continue;
                const Variant value = buckets.get(x + y * 4096, Variant());
                if (value.get_type() != Variant::ARRAY) continue;
                const Array bucket = value;
                for (int64_t i = 0; i < bucket.size(); ++i) {
                    const Variant entry = bucket[i];
                    Object *unit = entry.get_validated_object();
                    if (!unit || unit == observer || (alive && bool(unit->get(dead_key)))) continue;
                    const Vector2 position = unit->get(pos_key);
                    if (double(position.distance_squared_to(origin)) <= r2 && cells.has(cell(position) - center)) result.append(entry);
                }
            }
        }
        return result;
    }
    Array order_units(const Array &list, const Dictionary &ranks) const {
        if (list.size() < 2) return list;
        bool sequence = false;
        std::vector<std::pair<int64_t, int64_t>> keys;
        keys.reserve(size_t(list.size()));
        for (int64_t i = 0; i < list.size(); ++i) {
            Object *unit = list[i].get_validated_object();
            if (!unit) return list;
            const int64_t id = unit->get_instance_id();
            if (!ranks.has(id)) { sequence = true; break; }
            keys.emplace_back(int64_t(ranks[id]), i);
        }
        if (sequence) {
            keys.clear();
            for (int64_t i = 0; i < list.size(); ++i) {
                Object *unit = list[i].get_validated_object();
                if (!unit) return list;
                keys.emplace_back(int64_t(unit->get(seq_key)), i);
            }
        }
        std::sort(keys.begin(), keys.end());
        Array result; result.resize(list.size());
        for (int64_t i = 0; i < list.size(); ++i) result[i] = list[keys[size_t(i)].second];
        return result;
    }
    // A batch is one synchronous combat-flag query, during which registry
    // membership and unit IDs do not change. Never cache across queries.
    void begin_batch() { checked.clear(); batching = true; complete_registry = false; }
    void end_batch() { batching = false; complete_registry = false; checked.clear(); }
    int64_t begin_registry_batch(const Dictionary &units) {
        begin_batch();
        std::unordered_set<uint64_t> members;
        const Array values = units.values();
        for (int64_t i = 0; i < values.size(); ++i) {
            const Variant entry = values[i];
            if (registered(entry, units)) members.insert(static_cast<uint64_t>(static_cast<ObjectID>(entry)));
        }
        complete_registry = true;
        if (members != last_members) { last_members.swap(members); ++membership_epoch; }
        return membership_epoch;
    }
    Array notice_candidates(const Array &near, const Ref<Script> &unit_script, Object *observer,
                            Object *world, Dictionary sides, bool npc, int64_t revision) {
        Array result;
        if (unit_script.is_null() || !observer || !world) return result;
        const uint64_t id = observer->get_instance_id();
        const uint64_t lifetime_epoch = UnitNoticeLifetime::epoch.load(std::memory_order_relaxed);
        auto found = notices.find(id);
        NoticeCache fresh;
        NoticeCache *cache = found == notices.end() ? nullptr : &found->second;
        if (!cache || cache->revision != revision || cache->lifetime_epoch != lifetime_epoch || cache->script != unit_script || cache->source != near) {
            if (cache) { notice_bytes -= cache->bytes; notices.erase(id); }
            fresh.source = near.duplicate();
            fresh.script = unit_script;
            fresh.revision = revision;
            fresh.lifetime_epoch = lifetime_epoch;
            fresh.bytes = 512 + size_t(near.size()) * 128;
            bool cacheable = true;
            for (int64_t i = 0, n = near.size(); i < n; ++i) {
                const Variant entry = near[i];
                Object *unit = entry.get_validated_object();
                if (!unit) continue;
                Ref<Script> script = unit->get_script();
                while (script.is_valid() && script != unit_script) script = script->get_base_script();
                if (script != unit_script) { cacheable = false; continue; }
                const Variant lifetime = unit->get(lifetime_key);
                if (!Object::cast_to<UnitNoticeLifetime>(lifetime.get_validated_object())) cacheable = false;
                if (bool(unit->get(hidden_key))) continue;
                fresh.rows.push_back({entry, int64_t(unit->get(faction_key)),
                    int64_t(unit->get(controller_key)) >= 0, bool(unit->get(dead_key))});
            }
            cache = &fresh;
            if (cacheable && fresh.bytes <= notice_limit) {
                if (notices.size() >= 1024 || notice_bytes + fresh.bytes > notice_limit) {
                    notices.clear(); notice_bytes = 0;
                }
                notice_bytes += fresh.bytes;
                cache = &notices.emplace(id, std::move(fresh)).first->second;
            }
        }
        for (const NoticeRow &row : cache->rows) {
            if (UnitNoticeLifetime::epoch.load(std::memory_order_relaxed) != lifetime_epoch && !row.unit.get_validated_object()) continue;
            if (npc) {
                const Variant side = row.faction;
                Variant hostile = sides.get(side, Variant());
                if (hostile.get_type() == Variant::NIL) {
                    hostile = world->call(enemy_method, observer, row.unit);
                    sides[side] = hostile;
                }
                if ((bool(hostile) || row.party) == row.dead) continue;
            }
            result.append(row.unit);
        }
        return result;
    }
    Array prune_units(const Array &current, const Dictionary &units) {
        for (int64_t i = 0; i < current.size(); ++i) {
            if (registered(current[i], units)) continue;
            Array result = current.duplicate();
            for (int64_t j = result.size() - 1; j >= i; --j) {
                if (!registered(result[j], units)) result.remove_at(j);
            }
            return result;
        }
        return current;
    }
};
}
