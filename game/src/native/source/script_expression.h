// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {
// Evaluate the hot, read-only expression nodes in one native traversal. The
// scheduler, statements, special forms and unrecognized calls stay in ScriptVM.
// No AST, world dictionary, object or result is retained between evaluations:
// edits, removed objects and a lever changed by an earlier body are visible now.
// Group and perception queries (ScriptVM._group/_unit/_sees/_sees_has) read
// each watcher's noticed list through ScriptVM._noticed, which owns the AI
// refresh and the per-tick memo; the kernel only combines the lists.
class ScriptExpressionKernel : public RefCounted {
    GDCLASS(ScriptExpressionKernel, RefCounted)
    enum Node { NUMBER, STRING, VARIABLE, CALL };
    enum Op { FALLBACK, NOT, EQUAL, LESS, GREATER, STRING_EQUAL, ADD, SUB, MUL, DIV,
        GET_OBJECT, GET_LEVER_STATE, GROUP_SIZE, IS_DEAD, UNIT_SEE, GROUP_SEE, GROUP_HAS, GROUP_CROSS,
        OP_COUNT };
    static constexpr const char *op_names[OP_COUNT - 1] = {"Not", "IsEqual", "IsLess", "IsGreater",
        "IsEqualString", "Add", "Sub", "Mul", "Div", "GetObject", "GetLeverState", "GroupSize", "IsDead",
        "UnitSee", "GroupSee", "GroupHas", "GroupCross"};
    const StringName locals_key = "locals", globals_key = "globals", world_key = "world";
    const StringName units_key = "units", objects_key = "objects", levers_key = "levers";
    const StringName script_eval = "_eval_script", script_call = "_call", object_id = "_obj_id";
    const StringName script_noticed = "_noticed", looted_key = "looted", uid_key = "uid";
    const StringName dead_key = "dead", seq_key = "_seq";
    const String null_name = "NULL", state_key = "state", unit_see = "UnitSee", group_see = "GroupSee";
    Dictionary ops;
    // GameUnit, held weakly so the kernel never extends the class's lifetime;
    // unit queries return to the interpreter without it.
    uint64_t unit_script = 0;
    bool has_unit_script() const { return unit_script != 0 && ObjectDB::get_instance(unit_script) != nullptr; }

    static Variant rounded(const Variant &value) {
        if (value.get_type() == Variant::FLOAT || value.get_type() == Variant::INT)
            return double(float(double(value)));
        return value;
    }
    static double number(const Variant &value) {
        switch (value.get_type()) {
            case Variant::FLOAT: case Variant::INT: return double(value);
            case Variant::BOOL: return bool(value) ? 1.0 : 0.0;
            case Variant::STRING: return String(value).to_float();
            default: return 0.0;
        }
    }
    static bool truthy(const Variant &value) {
        switch (value.get_type()) {
            case Variant::NIL: return false;
            case Variant::OBJECT: return value.get_validated_object() != nullptr;
            case Variant::BOOL: return bool(value);
            case Variant::FLOAT: case Variant::INT: return double(value) != 0.0;
            case Variant::STRING: return !String(value).is_empty();
            case Variant::ARRAY: return !Array(value).is_empty();
            default: return true;
        }
    }
    // `v is GameUnit` on a live object, including derived unit scripts.
    bool is_unit(const Variant &value) const {
        if (value.get_type() != Variant::OBJECT) return false;
        const Object *object = value.get_validated_object();
        if (!object) return false;
        Ref<Script> script = object->get_script();
        while (script.is_valid()) {
            if (script->get_instance_id() == unit_script) return true;
            script = script->get_base_script();
        }
        return false;
    }
    // ScriptVM._group: live objects of a list; a single non-null value.
    static Array group(const Variant &value) {
        Array out;
        if (value.get_type() == Variant::ARRAY) {
            const Array items = value;
            for (int64_t i = 0; i < items.size(); ++i) {
                const Variant item = items[i];
                if (item.get_type() == Variant::OBJECT && item.get_validated_object()) out.push_back(item);
            }
        } else if (value.get_type() != Variant::NIL
                && (value.get_type() != Variant::OBJECT || value.get_validated_object())) {
            out.push_back(value);
        }
        return out;
    }
    // ScriptVM._unit: a live unit that is still on the server (not looted).
    Variant unit_of(const Variant &value, Object *world) const {
        if (!is_unit(value)) return Variant();
        const Dictionary looted = world->get(looted_key);
        if (looted.get(value.get_validated_object()->get(uid_key), Variant()) == value) return Variant();
        return value;
    }
    Array noticed(Object *vm, const Variant &watcher, Dictionary &lists) const {
        // _noticed is idempotent within one evaluation: the AI refresh runs at
        // most once per world time and the tick memo returns the same list.
        if (lists.has(watcher)) return lists[watcher];
        const Array list = vm->call(script_noticed, watcher);
        lists[watcher] = list;
        return list;
    }
    // ScriptVM._sees: the watchers' noticed units, first sighting order.
    Array sees(Object *vm, const Array &watchers) const {
        Array out;
        Dictionary have, lists;
        for (int64_t i = 0; i < watchers.size(); ++i) {
            const Variant watcher = watchers[i];
            if (!is_unit(watcher)) continue;
            const Array list = noticed(vm, watcher, lists);
            for (int64_t k = 0; k < list.size(); ++k) {
                const Variant seen = list[k];
                if (!have.has(seen)) {
                    have[seen] = true;
                    out.push_back(seen);
                }
            }
        }
        return out;
    }
    // ScriptVM._sees_has: watchers are asked lazily, in order, as the script does.
    bool sees_has(Object *vm, const Array &watchers, const Variant &target, Dictionary &lists) const {
        if (!is_unit(target) || int64_t(target.get_validated_object()->get(seq_key)) == 0) return false;
        for (int64_t i = 0; i < watchers.size(); ++i) {
            const Variant watcher = watchers[i];
            if (!is_unit(watcher) || watcher == target) continue;
            if (noticed(vm, watcher, lists).has(target)) return true;
        }
        return false;
    }
    // GroupHas(UnitSee/GroupSee(x), y) and GroupCross(g, UnitSee/GroupSee(x))
    // are lazy special forms in ScriptVM._call: 1 UnitSee, 2 GroupSee, 0 an
    // ordinary argument, -1 a shape only the interpreter should judge.
    int see_form(const Variant &argument) const {
        const Array call = argument;
        if (call.is_empty()) return -1;
        if (call[0] != Variant(int64_t(CALL))) return 0;
        if (call.size() < 3) return -1;
        const String name = call[1];
        if (name != unit_see && name != group_see) return 0;
        if (call[2].get_type() != Variant::ARRAY) return -1;
        const Array args = call[2];
        if (args.size() != 1) return 0;
        if (args[0].get_type() != Variant::ARRAY) return -1;
        return name == unit_see ? 1 : 2;
    }
    Array watchers(int form, const Variant &source, Object *world) const {
        if (form == 2) return group(source);
        Array out;
        out.push_back(unit_of(source, world));
        return out;
    }
    Variant eval(const Array &expression, Object *vm, Object *instance, int depth) const {
        if (expression.size() < 2 || depth > 128)
            return vm->call(script_eval, expression, instance);
        const int node = int(expression[0]);
        if (node == STRING) return expression[1];
        if (node == NUMBER) return rounded(expression[1]);
        if (node == VARIABLE && instance) {
            const Variant key = expression[1];
            const Dictionary locals = instance->get(locals_key);
            if (locals.has(key)) return rounded(locals[key]);
            if (key == Variant(null_name)) return Variant();
            const Dictionary globals = vm->get(globals_key);
            return rounded(globals.get(key, Variant()));
        }
        if (node != CALL || expression.size() < 3 || expression[2].get_type() != Variant::ARRAY)
            return vm->call(script_eval, expression, instance);
        const String name = expression[1];
        const Array args = expression[2];
        const Op op = Op(int(ops.get(name, FALLBACK)));
        const int arity = (op == NOT || op == GET_OBJECT || op == GET_LEVER_STATE || op == GROUP_SIZE
            || op == IS_DEAD || op == UNIT_SEE || op == GROUP_SEE) ? 1 : 2;
        if (op == FALLBACK || args.size() != arity)
            return rounded(vm->call(script_call, name, args, instance));
        // Validate shape before evaluating anything: a fallback must never
        // repeat a nested Random, assignment or other observable operation.
        for (int i = 0; i < arity; ++i)
            if (args[i].get_type() != Variant::ARRAY)
                return rounded(vm->call(script_call, name, args, instance));
        if (op == IS_DEAD || op == UNIT_SEE || op == GROUP_SEE || op == GROUP_HAS || op == GROUP_CROSS) {
            const int form = op == GROUP_HAS ? see_form(args[0]) : op == GROUP_CROSS ? see_form(args[1]) : 0;
            const bool needs_world = op == UNIT_SEE || form == 1;
            Object *world = needs_world ? vm->get(world_key).get_validated_object() : nullptr;
            const bool needs_unit = op == IS_DEAD || op == UNIT_SEE || op == GROUP_SEE || form > 0;
            if (form < 0 || (needs_unit && !has_unit_script()) || (needs_world && !world))
                return rounded(vm->call(script_call, name, args, instance));
            if (form > 0) {
                const Array see = args[op == GROUP_HAS ? 0 : 1];
                Dictionary lists;
                if (op == GROUP_HAS) {
                    const Array seen_by = watchers(form, eval(Array(see[2])[0], vm, instance, depth + 1), world);
                    return sees_has(vm, seen_by, eval(args[1], vm, instance, depth + 1), lists) ? 1.0 : 0.0;
                }
                const Variant other = eval(args[0], vm, instance, depth + 1);
                const Array seen_by = watchers(form, eval(Array(see[2])[0], vm, instance, depth + 1), world);
                const Array candidates = group(other);
                Array out;
                for (int64_t i = 0; i < candidates.size(); ++i)
                    if (sees_has(vm, seen_by, candidates[i], lists)) out.push_back(candidates[i]);
                return out;
            }
        }
        const Variant a = eval(args[0], vm, instance, depth + 1);
        const Variant b = arity == 2 ? eval(args[1], vm, instance, depth + 1) : Variant();
        switch (op) {
            case NOT: return truthy(a) ? 0.0 : 1.0;
            case EQUAL:
                return (a.get_type() == Variant::OBJECT || b.get_type() == Variant::OBJECT
                    ? UtilityFunctions::is_same(a, b) : number(a) == number(b)) ? 1.0 : 0.0;
            case LESS: return number(a) < number(b) ? 1.0 : 0.0;
            case GREATER: return number(a) > number(b) ? 1.0 : 0.0;
            case STRING_EQUAL: return UtilityFunctions::str(a) == UtilityFunctions::str(b) ? 1.0 : 0.0;
            case ADD: return rounded(number(a) + number(b));
            case SUB: return rounded(number(a) - number(b));
            case MUL: return rounded(number(a) * number(b));
            case DIV: return rounded(number(a) / number(b));
            case GET_OBJECT: {
                Object *world = vm->get(world_key).get_validated_object();
                if (!world) return Variant();
                // Use the engine's Variant conversion, as GDScript int() does.
                const int64_t id = int64_t(Variant(number(a)));
                const Dictionary units = world->get(units_key);
                if (units.has(id)) return units[id];
                const Dictionary objects = world->get(objects_key);
                const Variant object = objects.get(id, Variant());
                return object.get_validated_object() ? object : Variant();
            }
            case GET_LEVER_STATE: {
                Object *world = vm->get(world_key).get_validated_object();
                if (!world) return 0.0;
                // ScriptVM owns GameUnit/subclass and scenery metadata rules.
                const int64_t id = vm->call(object_id, a);
                const Dictionary levers = world->get(levers_key);
                const Dictionary lever = levers.get(id, Dictionary());
                return rounded(double(lever.get(state_key, 0)));
            }
            case GROUP_SIZE: return double(group(a).size());
            case IS_DEAD: return is_unit(a) && bool(a.get_validated_object()->get(dead_key)) ? 1.0 : 0.0;
            case UNIT_SEE: {
                Object *world = vm->get(world_key).get_validated_object();
                if (!world) return Variant();
                Array seen_by;
                seen_by.push_back(unit_of(a, world));
                return sees(vm, seen_by);
            }
            case GROUP_SEE: return sees(vm, group(a));
            case GROUP_HAS: return group(a).has(b) ? 1.0 : 0.0;
            case GROUP_CROSS: {
                const Array right = group(b), left = group(a);
                Array out;
                for (int64_t i = 0; i < left.size(); ++i)
                    if (right.has(left[i])) out.push_back(left[i]);
                return out;
            }
            default: return Variant();
        }
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("evaluate", "expression", "vm", "instance"), &ScriptExpressionKernel::evaluate);
        ClassDB::bind_method(D_METHOD("set_unit_script", "script"), &ScriptExpressionKernel::set_unit_script);
        ClassDB::bind_method(D_METHOD("native_calls"), &ScriptExpressionKernel::native_calls);
    }
public:
    ScriptExpressionKernel() {
        for (int i = 0; i < OP_COUNT - 1; ++i) ops[op_names[i]] = i + 1;
    }
    void set_unit_script(const Ref<Script> &script) { unit_script = script.is_valid() ? script->get_instance_id() : 0; }
    PackedStringArray native_calls() const {
        PackedStringArray out;
        for (int i = 0; i < OP_COUNT - 1; ++i)
            if (has_unit_script() || (i + 1 != IS_DEAD && i + 1 != UNIT_SEE && i + 1 != GROUP_SEE)) out.push_back(op_names[i]);
        return out;
    }
    Variant evaluate(const Array &expression, Object *vm, Object *instance) const {
        return vm ? eval(expression, vm, instance, 0) : Variant();
    }
};
}
