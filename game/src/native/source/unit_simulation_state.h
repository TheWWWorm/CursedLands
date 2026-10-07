// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <vector>
#include <mutex>
#include <unordered_map>

namespace godot {
// Persistent main-thread simulation inputs. Scalars are published by their
// GameUnit setters; containers share the actual live Array/Dictionary backing
// store, including in-place/nested edits. No per-query object-property walk.
// This is NOT a worker snapshot: shared containers stay on the authority thread.
// It holds no owner pointer; identity and the exact script guard every consumer.
class UnitSimulationState : public RefCounted {
    GDCLASS(UnitSimulationState, RefCounted)
    struct Registry {
        std::mutex mutex;
        std::unordered_map<uint64_t,UnitSimulationState *> states;
    };
    static Registry &registry() { static Registry data; return data; }
    uint64_t owner_id = 0;
    uint64_t generation = 0;
    Ref<Script> owner_script;
    static const std::vector<StringName> &keys() {
        static const std::vector<StringName> names = {"pos","facing","uid","controller","faction","dead","hidden","alert","mode",
            "order_failed","_anim_lock","_max_hp","stance","action","info","proto","stats","buffs","orders","order","_pending_hit"};
        return names;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("capture","unit"),&UnitSimulationState::capture);
        ClassDB::bind_method(D_METHOD("attach"),&UnitSimulationState::attach);
        ClassDB::bind_method(D_METHOD("update","field","value"),&UnitSimulationState::update);
        ClassDB::bind_method(D_METHOD("readback"),&UnitSimulationState::readback);
        ClassDB::bind_method(D_METHOD("matches","unit","script"),&UnitSimulationState::matches);
    }
public:
    Vector2 pos;
    double facing = 0., anim_lock = 0., max_hp = 10.;
    int64_t uid = 0, controller = -1, faction = 0, stance = 0;
    bool dead = false, hidden = false, alert = false, order_failed = false;
    String mode = "standard", action = "idle";
    Dictionary info, proto, stats, buffs, order, pending_hit;
    Array orders;
    void capture(Object *unit) {
        detach(owner_id);
        owner_id=0; owner_script.unref();
        if (!unit) return;
        for (const StringName &key : keys()) update(key,unit->get(key));
        owner_id=unit->get_instance_id(); owner_script=unit->get_script();
    }
    bool matches(Object *unit,const Ref<Script> &expected) const {
        return unit && expected.is_valid() && owner_script==expected && owner_id==uint64_t(unit->get_instance_id()) && Ref<Script>(unit->get_script())==expected;
    }
    static Ref<UnitSimulationState> of(Object *unit,const Ref<Script> &expected) {
        if (!unit || expected.is_null()) return Ref<UnitSimulationState>();
        Registry &data=registry();
        std::lock_guard<std::mutex> lock(data.mutex);
        const auto entry=data.states.find(uint64_t(unit->get_instance_id()));
        if (entry==data.states.end() || entry->second->owner_script!=expected) return Ref<UnitSimulationState>();
        return Ref<UnitSimulationState>(entry->second);
    }
    // The registry never owns the record or the actor. A lease is held only
    // by the GameUnit script instance and unregisters before releasing state.
    // Reader references are acquired under the same lock as detach, so no
    // object/instance-binding lookup is needed inside an actor query.
    Ref<RefCounted> attach();
    void detach(uint64_t id,uint64_t version=0) {
        Registry &data=registry(); std::lock_guard<std::mutex> lock(data.mutex);
        const auto found=data.states.find(id);
        if (found!=data.states.end() && found->second==this && (!version || version==generation)) data.states.erase(found);
    }
    ~UnitSimulationState() override { detach(owner_id); }
    bool update(const StringName &field,const Variant &value) {
        const auto &k=keys();
#define EI_STATE_FIELD(index,member) if(field==k[index]) { member=value; return true; }
        EI_STATE_FIELD(0,pos) EI_STATE_FIELD(1,facing) EI_STATE_FIELD(2,uid)
        EI_STATE_FIELD(3,controller) EI_STATE_FIELD(4,faction) EI_STATE_FIELD(5,dead)
        EI_STATE_FIELD(6,hidden) EI_STATE_FIELD(7,alert) EI_STATE_FIELD(8,mode)
        EI_STATE_FIELD(9,order_failed) EI_STATE_FIELD(10,anim_lock) EI_STATE_FIELD(11,max_hp)
        EI_STATE_FIELD(12,stance) EI_STATE_FIELD(13,action) EI_STATE_FIELD(14,info)
        EI_STATE_FIELD(15,proto) EI_STATE_FIELD(16,stats) EI_STATE_FIELD(17,buffs)
        EI_STATE_FIELD(18,orders) EI_STATE_FIELD(19,order) EI_STATE_FIELD(20,pending_hit)
#undef EI_STATE_FIELD
        return false;
    }
    Dictionary readback() const {
        Dictionary out; const auto &k=keys();
#define EI_STATE_FIELD(index,member) out[k[index]]=member;
        EI_STATE_FIELD(0,pos) EI_STATE_FIELD(1,facing) EI_STATE_FIELD(2,uid)
        EI_STATE_FIELD(3,controller) EI_STATE_FIELD(4,faction) EI_STATE_FIELD(5,dead)
        EI_STATE_FIELD(6,hidden) EI_STATE_FIELD(7,alert) EI_STATE_FIELD(8,mode)
        EI_STATE_FIELD(9,order_failed) EI_STATE_FIELD(10,anim_lock) EI_STATE_FIELD(11,max_hp)
        EI_STATE_FIELD(12,stance) EI_STATE_FIELD(13,action) EI_STATE_FIELD(14,info)
        EI_STATE_FIELD(15,proto) EI_STATE_FIELD(16,stats) EI_STATE_FIELD(17,buffs)
        EI_STATE_FIELD(18,orders) EI_STATE_FIELD(19,order) EI_STATE_FIELD(20,pending_hit)
#undef EI_STATE_FIELD
        return out;
    }
};

class UnitSimulationLease : public RefCounted {
    GDCLASS(UnitSimulationLease, RefCounted)
protected:
    static void _bind_methods() {}
public:
    Ref<UnitSimulationState> state;
    uint64_t owner_id = 0;
    uint64_t generation = 0;
    ~UnitSimulationLease() override { if(state.is_valid()) state->detach(owner_id,generation); }
};

inline Ref<RefCounted> UnitSimulationState::attach() {
    if (!owner_id || owner_script.is_null()) return Ref<RefCounted>();
    Ref<UnitSimulationLease> lease; lease.instantiate();
    lease->state=Ref<UnitSimulationState>(this); lease->owner_id=owner_id;
    if (++generation==0) ++generation;
    lease->generation=generation;
    Registry &data=registry(); std::lock_guard<std::mutex> lock(data.mutex);
    data.states[owner_id]=this;
    return lease;
}
} // namespace godot
