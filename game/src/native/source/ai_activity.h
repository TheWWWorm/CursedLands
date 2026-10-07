// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "ai_activity_core.h"
#include "unit_simulation_state.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <unordered_map>
#include <unordered_set>

namespace godot {
class AIActivityKernel : public RefCounted {
    GDCLASS(AIActivityKernel, RefCounted)
    std::unordered_map<uint64_t,Vector2> origins;
    std::unordered_set<uint64_t> quiet;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("evaluate", "positions", "radii", "factions", "flags", "hostile_masks"), &AIActivityKernel::evaluate);
        ClassDB::bind_method(D_METHOD("evaluate_senses", "positions", "terms", "factions", "flags", "hostile_masks", "margin"), &AIActivityKernel::evaluate_senses);
        ClassDB::bind_method(D_METHOD("evaluate_world", "units", "side_masks", "darkness", "weather", "margin"), &AIActivityKernel::evaluate_world);
        ClassDB::bind_method(D_METHOD("can_defer", "unit", "ai", "time"), &AIActivityKernel::can_defer);
        ClassDB::bind_method(D_METHOD("can_defer_owned", "unit", "ai", "time", "unit_script", "ai_script"), &AIActivityKernel::can_defer_owned, DEFVAL(Ref<Script>()));
        ClassDB::bind_method(D_METHOD("begin_world", "units", "side_masks", "darkness", "weather", "margin", "unit_script"), &AIActivityKernel::begin_world);
        ClassDB::bind_method(D_METHOD("can_defer_in_batch", "unit", "ai", "time", "unit_script", "ai_script"), &AIActivityKernel::can_defer_in_batch, DEFVAL(Ref<Script>()));
        ClassDB::bind_method(D_METHOD("moved_beyond", "unit", "position", "distance_squared"), &AIActivityKernel::moved_beyond);
        ClassDB::bind_method(D_METHOD("is_quiet", "unit"), &AIActivityKernel::is_quiet);
    }
public:
    // Main-thread live predicate, never a worker job or a cached decision.
    // The spatial batch only proves absence of nearby stimuli. These fields
    // can change during a sequential tick and must be read at decision time.
    bool can_defer(Object *unit, Object *ai, double time) const { return can_defer_impl(unit,ai,time,nullptr,false); }
    bool can_defer_owned(Object *unit,Object *ai,double time,const Ref<Script> &unit_script,const Ref<Script> &ai_script=Ref<Script>()) const {
        const Ref<UnitSimulationState> state=UnitSimulationState::of(unit,unit_script);
        return can_defer_impl(unit,ai,time,state.ptr(),ai && ai_script.is_valid() && Ref<Script>(ai->get_script())==ai_script);
    }
    bool is_quiet(Object *unit) const { return unit && quiet.count(unit->get_instance_id()); }
    bool can_defer_in_batch(Object *unit,Object *ai,double time,const Ref<Script> &unit_script,const Ref<Script> &ai_script=Ref<Script>()) const {
        return is_quiet(unit) && can_defer_owned(unit,ai,time,unit_script,ai_script);
    }
    bool moved_beyond(Object *unit,Vector2 position,double distance_squared) const {
        if (!unit) return true;
        const auto found=origins.find(unit->get_instance_id());
        return found==origins.end() || position.distance_squared_to(found->second)>distance_squared;
    }
    bool can_defer_impl(Object *unit,Object *ai,double time,const UnitSimulationState *state,bool standard_ai) const {
        if (!unit || !ai) return false;
        // Shared read-only defaults avoid allocating containers for each live
        // eligibility query. Consumers only inspect them, never mutate them.
        static const Dictionary empty_dictionary;
        static const Array empty_array;
        static const StringName controller("controller"), dead("dead"), hidden("hidden"), alert("alert"),
            hero("hero"), mode_key("mode"), info_key("info"), orders_key("orders"), failed("order_failed"),
            lock("_anim_lock"), pending("_pending_hit"), buffs_key("buffs"), hp("hp"), max_hp("max_hp"),
            suspect("suspect"), fear_on("fear_on"), attacker("attacker"), um("um"), alerted("alerted"),
            hate("hate"), peace("peace"), noticed("noticed"), corpses("seen_corpses"), dangers("dangers"),
            spell_list("_spell_list"), fear_key("fear"), calm_key("calm"), logic("logic"), order_key("order");
        static const String standard("standard"), sentry("sentry"), guard("guard"), scripted("use_in_script"),
            r_key("r"), j_key("j"), danger("danger"), logic_model("logic_model"), busy("busy"),
            until("until"), calm_order("calm"), type("type"), move("move");
        if ((state ? state->controller : int64_t(unit->get(controller))) >= 0 || (state ? state->dead : bool(unit->get(dead))) || (state ? state->hidden : bool(unit->get(hidden))) ||
                (state ? state->alert : bool(unit->get(alert))) || unit->has_meta(hero)) return false;
        const String mode = state ? state->mode : String(unit->get(mode_key));
        if (mode != standard && mode != sentry && mode != guard) return false;
        const Dictionary info = state ? state->info : Dictionary(unit->get(info_key));
        if (bool(info.get(scripted, false)) || !(state ? state->orders : Array(unit->get(orders_key))).is_empty() ||
                (state ? state->order_failed : bool(unit->get(failed))) || (state ? state->anim_lock : double(unit->get(lock))) > 0. ||
                !(state ? state->pending_hit : Dictionary(unit->get(pending))).is_empty() || !(state ? state->buffs : Dictionary(unit->get(buffs_key))).is_empty() ||
                double(unit->get(hp)) < (state ? state->max_hp : double(unit->get(max_hp)))) return false;
        if (unit->has_meta(suspect) || unit->has_meta(fear_on) || unit->has_meta(attacker) ||
                unit->has_meta(um) || unit->has_meta(alerted) || unit->has_meta(hate) || unit->has_meta(peace) ||
                !Dictionary(unit->get_meta(noticed, empty_dictionary)).is_empty() ||
                !Dictionary(unit->get_meta(corpses, empty_dictionary)).is_empty() ||
                !Array(ai->get(dangers)).is_empty()) return false;
        // Prototype classification remains owned by UnitAI. Existing entries
        // can be read without another script invocation; misses and custom AI
        // retain the original helper and its exact conversion/caching rules.
        bool support = false, found_spells = false;
        if (state && standard_ai) {
            if (state->uid>=1000000000 && state->uid<2000000000) found_spells=true;
            else {
                static const StringName options_key("_spell_opts");
                static const String name_key("name");
                const Variant options=ai->get(options_key), name=state->proto.get(name_key,"");
                if (options.get_type()==Variant::DICTIONARY && name.get_type()==Variant::STRING) {
                    const Dictionary cache=options;
                    const Variant entry=cache.get(name,Variant());
                    if (entry.get_type()==Variant::ARRAY) {
                        const Array spells=entry;
                        if (spells.size()==2 && spells[1].get_type()==Variant::ARRAY) {
                            support=!Array(spells[1]).is_empty(); found_spells=true;
                        }
                    }
                }
            }
        }
        if (!found_spells) {
            const Array spells=ai->call(spell_list,unit);
            if(spells.size()!=2) return false;
            support=!Array(spells[1]).is_empty();
        }
        if(support) return false;
        const Dictionary fear = unit->get_meta(fear_key, empty_dictionary);
        if (double(fear.get(r_key, 10.)) != 10. || double(fear.get(j_key, 3.)) != 3. || fear.has(danger)) return false;
        const Dictionary calm = unit->get_meta(calm_key, empty_dictionary);
        if (mode == standard) {
            Dictionary descriptor = empty_dictionary;
            bool direct=false;
            if (state && standard_ai) {
                static const String list_key("logic"); static const StringName index_key("logic_idx");
                const Variant source=info.get(list_key,empty_array);
                if (source.get_type()==Variant::ARRAY) {
                    const Array list=source; const int64_t index=unit->get_meta(index_key,0);
                    if (index>=list.size()) { descriptor=info; direct=true; }
                    else if (index>=-list.size() && list[index<0?index+list.size():index].get_type()==Variant::DICTIONARY) {
                        descriptor=list[index<0?index+list.size():index]; direct=true;
                    }
                }
            }
            if(!direct) descriptor=ai->call(logic,unit);
            const int64_t model = descriptor.get(logic_model, 3);
            if (model != 1 && model != 2 && model != 3 && model != 5) return false;
        }
        if (!bool(calm.get(busy, false))) return false;
        const Dictionary order = state ? state->order : Dictionary(unit->get(order_key));
        if (order.is_empty()) {
            if (double(calm.get(until, -1.)) <= time) return false;
        } else if (!bool(order.get(calm_order, false)) || String(order.get(type, "")) != move) return false;
        return true;
    }

    PackedByteArray evaluate(const PackedVector2Array &positions, const PackedFloat64Array &radii,
                             const PackedInt64Array &factions, const PackedByteArray &flags, const PackedInt64Array &hostile_masks) const {
        const int64_t n = positions.size();
        PackedByteArray result; result.resize(n); result.fill(1);
        if (radii.size() != n || factions.size() != n || flags.size() != n || hostile_masks.size() != n) return result;
        std::vector<ei_activity::Actor> rows;
        rows.reserve(size_t(n));
        for (int64_t i = 0; i < n; ++i) {
            const Vector2 p = positions[i];
            rows.push_back({double(p.x), double(p.y), radii[i], factions[i], flags[i], uint32_t(hostile_masks[i])});
        }
        const auto active = ei_activity::evaluate(rows);
        for (int64_t i = 0; i < n; ++i) result[i] = active[size_t(i)];
        return result;
    }
    PackedByteArray evaluate_senses(const PackedVector2Array &positions, const PackedFloat64Array &terms,
                             const PackedInt64Array &factions, const PackedByteArray &flags,
                             const PackedInt64Array &hostile_masks, double margin) const {
        const int64_t n = positions.size();
        PackedByteArray result; result.resize(n); result.fill(1);
        if (terms.size() != n * 5 || factions.size() != n || flags.size() != n || hostile_masks.size() != n) return result;
        std::vector<ei_activity::SensedActor> rows;
        rows.reserve(size_t(n));
        for (int64_t i = 0; i < n; ++i) {
            const Vector2 p = positions[i];
            rows.push_back({{double(p.x), double(p.y), 0., factions[i], flags[i], uint32_t(hostile_masks[i])},
                terms[i * 5], terms[i * 5 + 1], terms[i * 5 + 2], terms[i * 5 + 3], terms[i * 5 + 4]});
        }
        const auto active = ei_activity::evaluate_senses(rows, margin);
        for (int64_t i = 0; i < n; ++i) result[i] = active[size_t(i)];
        return result;
    }
    // Capture each actor's public data once in compiled code. The pure
    // spatial pass below never calls back into the scene or mutates it.
    PackedByteArray evaluate_world(const Array &units, const PackedInt64Array &side_masks,
                                  double darkness, double weather, double margin) const {
        return evaluate_world_impl(units,side_masks,darkness,weather,margin,Ref<Script>(),nullptr,nullptr);
    }
    bool begin_world(const Array &units,const PackedInt64Array &side_masks,double darkness,double weather,double margin,const Ref<Script> &unit_script) {
        origins.clear(); quiet.clear(); std::vector<uint64_t> ids;
        const PackedByteArray active=evaluate_world_impl(units,side_masks,darkness,weather,margin,unit_script,&origins,&ids);
        if (ids.size()!=size_t(units.size())) return false;
        for (size_t i=0;i<ids.size();++i) if(active[int64_t(i)]==0) quiet.insert(ids[i]);
        return true;
    }
    PackedByteArray evaluate_world_impl(const Array &units,const PackedInt64Array &side_masks,
            double darkness,double weather,double margin,const Ref<Script> &unit_script,
            std::unordered_map<uint64_t,Vector2> *capture,std::vector<uint64_t> *ids) const {
        static const Array empty_array;
        PackedByteArray result; result.resize(units.size()); result.fill(1);
        if (side_masks.size() != 32) return result;
        static const StringName pos_key("pos"), faction_key("faction"), controller_key("controller"),
            dead_key("dead"), hidden_key("hidden"), proto_key("proto"), stats_key("stats"), buffs_key("buffs");
        static const String senses_key("senses"), detection_key("detection"), peripheral_key("peripheral_skills"),
            sight_key("sight"), sense_key("sense"), detect_key("detect");
        std::vector<ei_activity::SensedActor> rows; rows.reserve(size_t(units.size()));
        for (int64_t i = 0; i < units.size(); ++i) {
            Object *unit = units[i].get_validated_object();
            if (!unit) return result;
            const Ref<UnitSimulationState> state=UnitSimulationState::of(unit,unit_script);
            const Vector2 p = state.is_valid() ? state->pos : Vector2(unit->get(pos_key));
            const int64_t faction = state.is_valid() ? state->faction : int64_t(unit->get(faction_key));
            if (capture && ids) { const uint64_t id=unit->get_instance_id(); (*capture)[id]=p; ids->push_back(id); }
            const uint8_t flags = ((state.is_valid() ? state->controller : int64_t(unit->get(controller_key))) >= 0 ? ei_activity::PARTY : 0) |
                ((state.is_valid() ? state->dead : bool(unit->get(dead_key))) ? ei_activity::DEAD : 0) | ((state.is_valid() ? state->hidden : bool(unit->get(hidden_key))) ? ei_activity::HIDDEN : 0);
            if (faction < 0 || faction >= 32) return result;
            const Dictionary proto = state.is_valid() ? state->proto : Dictionary(unit->get(proto_key)),
                stats = state.is_valid() ? state->stats : Dictionary(unit->get(stats_key)),
                buffs = state.is_valid() ? state->buffs : Dictionary(unit->get(buffs_key));
            const Array senses = proto.get(senses_key, empty_array), detection = proto.get(detection_key, empty_array);
            double bonus[3] = {}, high[3] = {};
            const Array values = buffs.is_empty() ? empty_array : buffs.values();
            for (int64_t bi = 0; bi < values.size(); ++bi) {
                const Dictionary buff = values[bi];
                if (buff.has(sense_key)) {
                    const Array term = buff[sense_key];
                    if (term.size() < 2) return result;
                    const int64_t index = term[0];
                    if (!std::isfinite(double(term[1]))) return result;
                    if (index >= 0 && index < 3) bonus[index] = std::max(bonus[index], double(term[1]));
                }
                if (buff.has(detect_key)) {
                    const Array term = buff[detect_key];
                    if (term.size() < 2) return result;
                    const int64_t index = term[0];
                    if (!std::isfinite(double(term[1]))) return result;
                    if (index >= 0 && index < 3) high[index] = std::max(high[index], double(term[1]));
                }
            }
            const double night = (senses.size() > 1 ? double(senses[1]) : 100.) + bonus[1];
            // Quiet eligibility excludes heroes, so their night-vision perk
            // cannot turn this observer bound into a false negative.
            const double factor = float((1. - darkness + darkness * night * 0.009999999776482582) * weather);
            const double sight = (double(stats.get(sight_key, 0.)) + bonus[0]) * factor;
            const double life = (senses.size() > 2 ? double(senses[2]) : 0.) + bonus[2];
            const double sight_base = detection.size() > 0 ? double(detection[0]) : 1.;
            const double life_base = detection.size() > 2 ? double(detection[2]) : 1.;
            // Enclose standing/crawling/casting and expiration of an
            // invisibility effect anywhere in the current sequential tick.
            // A negative effect can expire before an overlapping positive
            // effect, so the negative contribution must never shrink this bound.
            const double sight_detect = std::max(0., sight_base + high[0]) * 1.5;
            const double life_detect = std::max(0., life_base + high[2]);
            rows.push_back({{double(p.x), double(p.y), 0., faction, flags, uint32_t(side_masks[faction])},
                sight, life, double(proto.get(peripheral_key, 0.)), sight_detect, life_detect});
        }
        const auto active = ei_activity::evaluate_senses(rows, margin);
        for (int64_t i = 0; i < units.size(); ++i) result[i] = active[size_t(i)];
        return result;
    }
};
}
