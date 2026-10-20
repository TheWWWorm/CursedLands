// SPDX-License-Identifier: Apache-2.0
// Lua owns no engine objects or OS handles. Only declared callbacks cross the boundary.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <map>
#include <set>
#include <string>
#include <stdexcept>
#include <vector>
extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}
using namespace godot;

class ModLuaKernel : public RefCounted {
    GDCLASS(ModLuaKernel, RefCounted)
    lua_State *L = nullptr;
    Dictionary sources;
    std::map<std::string, int> modules;
    std::set<std::string> loading;
    size_t allocated = 0;
    static constexpr size_t memory_limit = 32 * 1024 * 1024;
    int instructions = 0;
    int native_steps = 0;
    bool exhausted = false, busy = false;
    std::chrono::steady_clock::time_point deadline;
    uint32_t random_state = 1;
    static constexpr int instruction_limit = 2000000;
    static int self_key;
    static ModLuaKernel *self(lua_State *s) {
        lua_pushlightuserdata(s, &self_key); lua_rawget(s, LUA_REGISTRYINDEX);
        auto *p = static_cast<ModLuaKernel *>(lua_touserdata(s, -1)); lua_pop(s, 1); return p;
    }
    static void *allocate(void *ud, void *ptr, size_t old_size, size_t size) {
        auto *p = static_cast<ModLuaKernel *>(ud);
        if (!ptr) old_size = 0;
        if (!size) { std::free(ptr); p->allocated -= old_size; return nullptr; }
        size_t cap = p->busy ? memory_limit - 4 * 1024 * 1024 : memory_limit;
        if (size > old_size && (p->allocated > cap || size - old_size > cap - p->allocated)) return nullptr;
        void *next = std::realloc(ptr, size);
        if (next) p->allocated = p->allocated - old_size + size;
        return next;
    }
    static void meter(lua_State *s, lua_Debug *) {
        auto *p = self(s); p->instructions += 1000;
        if (p->exhausted || p->instructions >= instruction_limit || std::chrono::steady_clock::now() > p->deadline) {
            p->exhausted = true; luaL_error(s, "Lua execution budget exceeded");
        }
    }
    void begin() {
        instructions = 0; native_steps = 0; exhausted = false; busy = true;
        deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(200);
        lua_sethook(L, meter, LUA_MASKCOUNT, 1000);
    }
    Dictionary result(int code, int base) {
        Dictionary out;
        out["ok"] = code == 0 && !exhausted;
        out["error"] = bool(out["ok"]) ? String() : exhausted ? String("Lua execution budget exceeded") : String::utf8(lua_tostring(L, -1) ? lua_tostring(L, -1) : "Lua failed");
        if (bool(out["ok"]) && lua_gettop(L) > base) {
            bool valid = true; int count = 0; std::set<const void *> seen;
            out["value"] = read(-1, valid, seen, count);
            if (!valid) { out["ok"] = false; out["error"] = "Lua result is not finite plain data"; }
        }
        lua_settop(L, base); lua_sethook(L, nullptr, 0, 0); busy = false;
        return out;
    }
    static Dictionary failure(const String &error) { Dictionary d; d["ok"] = false; d["error"] = error; return d; }
    // API values deliberately exclude Object, Callable and engine resources.
    bool push(const Variant &v, int depth = 0) {
        if (depth > 32 || !lua_checkstack(L, 8)) return false;
        switch (v.get_type()) {
            case Variant::NIL: lua_pushnil(L); break;
            case Variant::BOOL: lua_pushboolean(L, bool(v)); break;
            case Variant::INT: case Variant::FLOAT:
                if (!std::isfinite(double(v))) return false;
                lua_pushnumber(L, double(v)); break;
            case Variant::STRING_NAME: case Variant::STRING: { auto s = String(v).utf8(); lua_pushlstring(L, s.get_data(), s.length()); break; }
            case Variant::ARRAY: {
                Array a = v; if (a.size() > 16384) return false;
                lua_createtable(L, a.size(), 0);
                for (int i = 0; i < a.size(); ++i) { if (!push(a[i], depth + 1)) return false; lua_rawseti(L, -2, i + 1); }
                break;
            }
            case Variant::DICTIONARY: {
                Dictionary d = v; if (d.size() > 16384) return false;
                lua_createtable(L, 0, d.size()); Array keys = d.keys();
                for (int i = 0; i < keys.size(); ++i) {
                    Variant k = keys[i];
                    if (k.get_type() != Variant::STRING && k.get_type() != Variant::STRING_NAME && k.get_type() != Variant::INT) return false;
                    if (!push(k, depth + 1) || !push(d[k], depth + 1)) return false;
                    lua_rawset(L, -3);
                }
                break;
            }
            default: return false;
        }
        return true;
    }
    Variant read(int index, bool &valid, std::set<const void *> &seen, int &count, int depth = 0) {
        if (++count > 16384 || depth > 32 || !lua_checkstack(L, 8)) { valid = false; return Variant(); }
        switch (lua_type(L, index)) {
            case LUA_TNIL: return Variant();
            case LUA_TBOOLEAN: return bool(lua_toboolean(L, index));
            case LUA_TNUMBER: { double n = lua_tonumber(L, index); if (!std::isfinite(n)) valid = false; return n; }
            case LUA_TSTRING: {
                size_t size; const char *s = lua_tolstring(L, index, &size);
                if (size > 1048576) { valid = false; return Variant(); }
                // Repeated references to one Lua string must not expand into
                // unbounded host allocations during argument/result conversion.
                count += int((size + 127) / 128);
                if (count > 16384) { valid = false; return Variant(); }
                return String::utf8(s, size);
            }
            case LUA_TTABLE: {
                const void *id = lua_topointer(L, index);
                if (!seen.insert(id).second) { valid = false; return Variant(); }
                int at = index > 0 ? index : lua_gettop(L) + index + 1;
                Dictionary d; lua_pushnil(L);
                while (lua_next(L, at)) {
                    Variant k = read(-2, valid, seen, count, depth + 1);
                    Variant v = read(-1, valid, seen, count, depth + 1);
                    lua_pop(L, 1);
                    if (k.get_type() != Variant::STRING && k.get_type() != Variant::FLOAT) valid = false;
                    if (!valid) { lua_pop(L, 1); break; }
                    d[k] = v;
                }
                seen.erase(id); return d;
            }
            default: valid = false; return Variant();
        }
    }
    int compile(const String &source, const String &label) {
        auto code = source.trim_prefix(String::chr(0xfeff)).utf8(); auto name = label.utf8();
        if (code.length() > 1048576 || (code.length() && (unsigned char)code[0] == 27)) { lua_pushliteral(L, "Only bounded Lua source text is supported"); return LUA_ERRSYNTAX; }
        return luaL_loadbuffer(L, code.get_data(), code.length(), name.get_data());
    }
    static int require_module(lua_State *s) {
        auto *p = self(s); const char *name = luaL_checkstring(s, 1); int status = 0;
        {
            std::string key(name);
            auto found = p->modules.find(key);
            if (found != p->modules.end()) { lua_rawgeti(s, LUA_REGISTRYINDEX, found->second); return 1; }
            String module = String::utf8(name);
            if (!p->sources.has(module) || p->loading.count(key)) {
                lua_pushliteral(s, "Unknown or cyclic declared Lua module"); status = LUA_ERRRUN;
            } else {
                p->loading.insert(key);
                status = p->compile(p->sources[module], "@" + module + ".lua");
                if (!status) status = lua_pcall(s, 0, 1, 0);
                p->loading.erase(key);
                if (!status) {
                    if (lua_isnil(s, -1)) { lua_pop(s, 1); lua_pushboolean(s, true); }
                    lua_pushvalue(s, -1); p->modules[key] = luaL_ref(s, LUA_REGISTRYINDEX);
                }
            }
        }
        if (status) return lua_error(s);
        return 1;
    }
    void close() {
        if (L) lua_close(L);
        L = nullptr; allocated = 0; sources.clear(); modules.clear(); loading.clear(); busy = false;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure", "sources", "entry"), &ModLuaKernel::configure);
        ClassDB::bind_method(D_METHOD("invoke", "name", "arguments"), &ModLuaKernel::invoke);
        ClassDB::bind_method(D_METHOD("has_function", "name"), &ModLuaKernel::has_function);
        ClassDB::bind_method(D_METHOD("memory_used"), &ModLuaKernel::memory_used);
    }
public:
    static void native_budget(lua_State *s) {
        auto *p = self(s);
        if ((++p->native_steps & 63) == 0) {
            p->instructions += 64;
            if (p->exhausted || p->instructions >= instruction_limit || std::chrono::steady_clock::now() > p->deadline) {
                p->exhausted = true; luaL_error(s, "Lua execution budget exceeded in string operation");
            }
        }
    }
    ~ModLuaKernel() { close(); }
    int64_t memory_used() const { return allocated; }
    bool has_function(const String &name) {
        if (!L || busy) return false;
        auto key = name.utf8(); lua_pushlstring(L, key.get_data(), key.length()); lua_rawget(L, LUA_GLOBALSINDEX); bool yes = lua_isfunction(L, -1); lua_pop(L, 1); return yes;
    }
    Dictionary configure(Dictionary p_sources, String entry) {
        if (busy) return failure("Lua runtime is already executing");
        close();
        if (p_sources.size() < 1 || p_sources.size() > 128 || !p_sources.has(entry)) return failure("Invalid Lua module bundle");
        int64_t total = 0; Array keys = p_sources.keys();
        for (int i = 0; i < keys.size(); ++i) {
            if (keys[i].get_type() != Variant::STRING || p_sources[keys[i]].get_type() != Variant::STRING) return failure("Lua modules must be named source text");
            total += String(p_sources[keys[i]]).utf8().length();
        }
        if (total > 4 * 1024 * 1024) return failure("Lua source bundle exceeds 4 MiB");
        sources = p_sources.duplicate();
        L = lua_newstate(allocate, this); if (!L) return failure("Could not create Lua state");
        lua_pushlightuserdata(L, &self_key); lua_pushlightuserdata(L, this); lua_rawset(L, LUA_REGISTRYINDEX);
        luaopen_base(L); lua_settop(L, 0); luaopen_math(L); lua_pop(L, 1); luaopen_string(L); lua_pop(L, 1); luaopen_table(L); lua_pop(L, 1);
        for (const char *name : {"dofile", "loadfile", "load", "newproxy", "collectgarbage", "print", "coroutine", "loadstring"}) { lua_pushnil(L); lua_setglobal(L, name); }
        lua_getglobal(L, "string"); lua_pushnil(L); lua_setfield(L, -2, "dump"); lua_pop(L, 1);
        lua_getglobal(L, "math");
        for (const char *name : {"random", "randomseed"}) { lua_pushnil(L); lua_setfield(L, -2, name); }
        lua_pop(L, 1);
        lua_pushcfunction(L, require_module); lua_setglobal(L, "require");
        begin(); int status = compile(sources[entry], "@" + entry + ".lua"); if (!status) status = lua_pcall(L, 0, 0, 0);
        Dictionary out = result(status, 0);
        if (bool(out["ok"]) && allocated > 8 * 1024 * 1024) out = failure("Lua initialization exceeds 8 MiB");
        if (!bool(out["ok"])) close();
        return out;
    }
    Dictionary invoke(String name, Array arguments) {
        if (!L || busy) return failure("Lua runtime is unavailable or already executing");
        if (arguments.size() > 32) return failure("Too many Lua arguments");
        auto key = name.utf8(); lua_pushlstring(L, key.get_data(), key.length()); lua_rawget(L, LUA_GLOBALSINDEX);
        if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return failure("Missing Lua function: " + name); }
        for (int i = 0; i < arguments.size(); ++i) if (!push(arguments[i])) { lua_settop(L, 0); return failure("Invalid Lua argument"); }
        begin(); int status = lua_pcall(L, arguments.size(), 1, 0); return result(status, 0);
    }

};
int ModLuaKernel::self_key = 0;
extern "C" void ei_lua_budget(lua_State *s) { ModLuaKernel::native_budget(s); }
static void initialize(ModuleInitializationLevel level) { if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<ModLuaKernel>(); }
static void uninitialize(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT mod_lua_init(GDExtensionInterfaceGetProcAddress address, GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
    GDExtensionBinding::InitObject object(address, library, init);
    object.register_initializer(initialize); object.register_terminator(uninitialize); object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE); return object.init();
}
