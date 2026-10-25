// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/quaternion.hpp>

namespace godot {
// Live, ordered EIAnimPart composition. Keep custom child dispatch and the
// existing dirty-branch shortcut. No nodes, topology or sampled keys persist.
class AnimationCompositionKernel : public RefCounted {
    GDCLASS(AnimationCompositionKernel, RefCounted)
    const StringName parent_name="animation_parent", children_name="animation_children";
    const StringName key_name="animation_key", world_name="_world_key", parent_key_name="_parent_key";
    const StringName local_name="_local_key", applied_name="_applied_quaternion";
    const StringName dirty_name="_key_dirty", has_name="_has_applied";
    const StringName absolute_name="absolute", first_name="parent_first";
    const StringName saved_absolute_name="_absolute", saved_first_name="_parent_first", apply_name="_apply_key";
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("apply", "part", "part_script", "mode_script"), &AnimationCompositionKernel::apply);
    }
public:
    bool apply(Node3D *part, const Ref<Script> &part_script, const Ref<Script> &mode_script) const {
        if (!part || part_script.is_null() || mode_script.is_null() || Ref<Script>(part->get_script())!=part_script) return false;
        const Variant parent_value=part->get(parent_name);
        Node3D *parent=Object::cast_to<Node3D>(parent_value.get_validated_object());
        const Quaternion p=parent ? Quaternion(parent->get(world_name)) : Quaternion();
        const bool absolute=mode_script->get(absolute_name), parent_first=mode_script->get(first_name);
        if (!bool(part->get(dirty_name)) && p==Quaternion(part->get(parent_key_name)) &&
                absolute==bool(part->get(saved_absolute_name)) && parent_first==bool(part->get(saved_first_name))) return true;
        part->set(dirty_name,false);
        part->set(parent_key_name,p);
        part->set(saved_absolute_name,absolute);
        part->set(saved_first_name,parent_first);
        const Quaternion key=part->get(key_name);
        const Quaternion world=!parent || absolute ? key : parent_first ? p*key : key*p;
        part->set(world_name,world);
        const Quaternion local=parent ? p.inverse()*world : world;
        if (!bool(part->get(has_name)) || local!=Quaternion(part->get(local_name)) ||
                part->get_quaternion()!=Quaternion(part->get(applied_name))) {
            const uint64_t id=part->get_instance_id();
            part->set_quaternion(local);
            // Transform notifications may release a node. Never reuse its
            // pointer after that engine call without checking the object ID.
            if (ObjectDB::get_instance(id)!=part) return true;
            part->set(local_name,local);
            part->set(applied_name,part->get_quaternion());
            part->set(has_name,true);
        }
        const Array children=part->get(children_name);
        for (int64_t i=0;i<children.size();++i) {
            Node3D *child=Object::cast_to<Node3D>(children[i].get_validated_object());
            if (!child) return true;
            if (!apply(child,part_script,mode_script)) child->call(apply_name);
        }
        return true;
    }
};
}
