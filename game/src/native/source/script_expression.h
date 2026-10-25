// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {
// Evaluate the hot, read-only expression nodes in one native traversal. The
// scheduler, statements, special forms and unrecognized calls stay in ScriptVM.
// No AST, world dictionary, object or result is retained between evaluations:
// edits, removed objects and a lever changed by an earlier body are visible now.
class ScriptExpressionKernel : public RefCounted {
    GDCLASS(ScriptExpressionKernel, RefCounted)
    enum Node { NUMBER, STRING, VARIABLE, CALL };
    enum Op { FALLBACK, NOT, EQUAL, LESS, GREATER, STRING_EQUAL, ADD, SUB, MUL, DIV,
        GET_OBJECT, GET_LEVER_STATE };
    const StringName locals_key = "locals", globals_key = "globals", world_key = "world";
    const StringName units_key = "units", objects_key = "objects", levers_key = "levers";
    const StringName script_eval = "_eval_script", script_call = "_call", object_id = "_obj_id";
    const String null_name = "NULL", state_key = "state";
    Dictionary ops;

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
        const int arity = (op == NOT || op == GET_OBJECT || op == GET_LEVER_STATE) ? 1 : 2;
        if (op == FALLBACK || args.size() != arity)
            return rounded(vm->call(script_call, name, args, instance));
        // Validate shape before evaluating anything: a fallback must never
        // repeat a nested Random, assignment or other observable operation.
        for (int i = 0; i < arity; ++i)
            if (args[i].get_type() != Variant::ARRAY)
                return rounded(vm->call(script_call, name, args, instance));
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
            default: return Variant();
        }
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("evaluate", "expression", "vm", "instance"), &ScriptExpressionKernel::evaluate);
    }
public:
    ScriptExpressionKernel() {
        const char *names[] = {"Not", "IsEqual", "IsLess", "IsGreater", "IsEqualString",
            "Add", "Sub", "Mul", "Div", "GetObject", "GetLeverState"};
        for (int i = 0; i < 11; ++i) ops[names[i]] = i + 1;
    }
    Variant evaluate(const Array &expression, Object *vm, Object *instance) const {
        return vm ? eval(expression, vm, instance, 0) : Variant();
    }
};
}
