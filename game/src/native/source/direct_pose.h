// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/animation.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/classes/weak_ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/node_path.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <map>
#include <vector>

namespace godot {
// Sample the current Animation resource and compose its authored keys in part
// order. Interpolation stays in the engine. Only track paths/types are retained;
// resource changes invalidate them. Nodes and sampled poses are always live.
class DirectPoseKernel : public RefCounted {
    GDCLASS(DirectPoseKernel, RefCounted)
    const StringName parent_key = "animation_parent";
    static constexpr size_t MAX_CLIPS = 64, MAX_TRACKS = 512;
    struct Track { NodePath path; Animation::TrackType type; };
    struct Metadata {
        Ref<WeakRef> source;
        Callable invalidator;
        std::vector<Track> tracks;
        uint64_t stamp = 0;
        bool dirty = true;
    };
    std::map<uint64_t, Metadata> metadata;
    uint64_t stamp = 0, rebuilds = 0, hits = 0;
    void erase_metadata(std::map<uint64_t, Metadata>::iterator at) {
        const Ref<Resource> source = at->second.source->get_ref();
        if (source.is_valid() && source->is_connected("changed", at->second.invalidator))
            source->disconnect("changed", at->second.invalidator);
        metadata.erase(at);
    }
    Metadata *tracks_for(const Ref<Animation> &animation) {
        const uint64_t id = animation->get_instance_id();
        auto at = metadata.find(id);
        if (at == metadata.end()) {
            for (auto row = metadata.begin(); row != metadata.end();) {
                auto current = row++;
                if (!current->second.source->get_ref().get_validated_object()) erase_metadata(current);
            }
            if (metadata.size() >= MAX_CLIPS) {
                auto oldest = metadata.begin();
                for (auto row = metadata.begin(); row != metadata.end(); ++row)
                    if (row->second.stamp < oldest->second.stamp) oldest = row;
                erase_metadata(oldest);
            }
            Metadata entry;
            entry.source = UtilityFunctions::weakref(animation);
            entry.invalidator = Callable(this, "invalidate_metadata").bind(int64_t(id));
            if (animation->connect("changed", entry.invalidator) != OK) return nullptr;
            at = metadata.emplace(id, std::move(entry)).first;
        }
        Metadata &entry = at->second;
        entry.stamp = ++stamp;
        if (!entry.dirty) { ++hits; return &entry; }
        const int64_t count = animation->get_track_count();
        if (count < 0 || size_t(count) > MAX_TRACKS) { erase_metadata(at); return nullptr; }
        entry.tracks.clear();
        int64_t characters = 0;
        for (int64_t i = 0; i < count; ++i) {
            const String names = animation->track_get_path(i).get_concatenated_names();
            characters += names.length();
            if (characters > 65536) { erase_metadata(at); return nullptr; }
            entry.tracks.push_back({ NodePath(names), animation->track_get_type(i) });
        }
        entry.dirty = false;
        ++rebuilds;
        return &entry;
    }
    static bool is_part(Node *node, const Ref<Script> &part_script) {
        if (!node) return false;
        Ref<Script> script = node->get_script();
        while (script.is_valid()) {
            if (script == part_script) return true;
            script = script->get_base_script();
        }
        return false;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("sample", "model", "parts", "animation", "time", "part_script", "absolute", "parent_first"), &DirectPoseKernel::sample);
        ClassDB::bind_method(D_METHOD("invalidate_metadata", "instance"), &DirectPoseKernel::invalidate_metadata);
        ClassDB::bind_method(D_METHOD("metadata_stats"), &DirectPoseKernel::metadata_stats);
    }
public:
    ~DirectPoseKernel() { while (!metadata.empty()) erase_metadata(metadata.begin()); }
    void invalidate_metadata(int64_t instance) {
        auto at = metadata.find(uint64_t(instance));
        if (at != metadata.end()) at->second.dirty = true;
    }
    Dictionary metadata_stats() const {
        Dictionary result;
        result["clips"] = int64_t(metadata.size());
        result["hits"] = int64_t(hits);
        result["rebuilds"] = int64_t(rebuilds);
        return result;
    }
    Variant sample(Node *model, const Array &parts, const Ref<Resource> &source,
            double time, const Ref<Script> &part_script, bool absolute, bool parent_first) {
        // Scripted Animation overrides keep the complete script path, including
        // their side effects. Normal engine track methods are read-only.
        const Ref<Animation> animation = source;
        if (!model || animation.is_null() || animation->get_script().get_validated_object() || part_script.is_null()) return {};
        const Metadata *entry = tracks_for(animation);
        if (!entry) return {};
        Dictionary rotations, positions, world_rot;
        const int64_t count = entry->tracks.size();
        for (int64_t i = 0; i < count; ++i) {
            const Track &track = entry->tracks[i];
            Node *node = model->get_node_or_null(track.path);
            if (!is_part(node, part_script)) continue;
            const Animation::TrackType type = track.type;
            if (type == Animation::TYPE_VALUE) rotations[node] = animation->value_track_interpolate(i, time);
            else if (type == Animation::TYPE_POSITION_3D) positions[node] = animation->position_track_interpolate(i, time);
        }
        for (int64_t i = 0; i < parts.size(); ++i) {
            Node *node = Object::cast_to<Node>(parts[i].get_validated_object());
            if (!is_part(node, part_script)) return {};
            const Variant parent = node->get(parent_key);
            const Variant rotation = rotations.get(node, Quaternion());
            if (rotation.get_type() != Variant::QUATERNION) return {};
            const Quaternion q = rotation;
            const Quaternion inherited = world_rot.get(parent, Quaternion());
            world_rot[node] = absolute || !parent.get_validated_object() ? q :
                    parent_first ? inherited * q : q * inherited;
        }
        Dictionary result;
        result["rot"] = world_rot;
        result["pos"] = positions;
        return result;
    }
};
}
