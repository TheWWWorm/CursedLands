// SPDX-License-Identifier: Apache-2.0
// Bounded, read-only 7z decoding for pinned community downloads. Call extract
// once on a worker; cancel/progress are the only cross-thread operations.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <atomic>
#include <algorithm>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>
#include <vector>
#include "7z.h"
#include "7zCrc.h"
using namespace godot;

class ModArchiveExtractor : public RefCounted {
    GDCLASS(ModArchiveExtractor, RefCounted)
    static constexpr uint64_t total_limit = 1024ULL * 1024 * 1024;
    std::atomic<bool> cancelled{false};
    std::atomic<uint64_t> written{0}, total{0};
    bool used = false;
    struct Input {
        ISeekInStream vt;
        Ref<FileAccess> file;
        std::atomic<bool> *cancel;
        static SRes read(ISeekInStreamPtr p, void *out, size_t *size) {
            auto *s = reinterpret_cast<const Input *>(p);
            if (s->cancel->load()) { *size = 0; return SZ_ERROR_PROGRESS; }
            auto bytes = s->file->get_buffer(*size);
            *size = bytes.size();
            if (*size) std::memcpy(out, bytes.ptr(), *size);
            return s->file->get_error() == OK || s->file->get_error() == ERR_FILE_EOF ? SZ_OK : SZ_ERROR_READ;
        }
        static SRes seek(ISeekInStreamPtr p, Int64 *offset, ESzSeek origin) {
            auto *s = reinterpret_cast<const Input *>(p);
            if (s->cancel->load()) return SZ_ERROR_PROGRESS;
            int64_t base = origin == SZ_SEEK_CUR ? s->file->get_position() : origin == SZ_SEEK_END ? s->file->get_length() : 0;
            if (*offset < -base || *offset > int64_t(s->file->get_length()) - base) return SZ_ERROR_READ;
            *offset += base;
            s->file->seek(*offset);
            return s->file->get_error() == OK ? SZ_OK : SZ_ERROR_READ;
        }
    };
    struct Allocator {
        ISzAlloc vt{allocate, release};
        size_t allocated = 0, limit = 16 * 1024 * 1024;
        struct alignas(std::max_align_t) Header { size_t size; };
        static void *allocate(ISzAllocPtr p, size_t size) {
            auto *a = const_cast<Allocator *>(reinterpret_cast<const Allocator *>(p));
            if (!size || size > a->limit || a->allocated > a->limit - size) return nullptr;
            auto *h = static_cast<Header *>(std::malloc(sizeof(Header) + size));
            if (!h) return nullptr;
            h->size = size; a->allocated += size; return h + 1;
        }
        static void release(ISzAllocPtr p, void *ptr) {
            if (!ptr) return;
            auto *a = const_cast<Allocator *>(reinterpret_cast<const Allocator *>(p));
            auto *h = static_cast<Header *>(ptr) - 1;
            a->allocated -= h->size; std::free(h);
        }
    };
    struct Archive {
        Allocator memory;
        CSzArEx db;
        Byte *buffer = nullptr;
        size_t size = 0;
        UInt32 block = UINT32_MAX;
        Archive() { SzArEx_Init(&db); }
        ~Archive() { Allocator::release(&memory.vt, buffer); SzArEx_Free(&db, &memory.vt); }
    };
    static bool safe_name(const String &name) {
        if (name.is_empty() || name.length() > 240 || name.is_absolute_path() || name.contains("\\")) return false;
        for (int i = 0; i < name.length(); ++i) if (name[i] < 32 || String(":<>\"|?*").contains(String::chr(name[i]))) return false;
        for (auto part : name.split("/")) {
            if (part.is_empty() || part == "." || part == ".." || part.ends_with(".") || part.ends_with(" ")) return false;
            String stem = part.get_slice(".", 0).to_lower();
            if (stem == "con" || stem == "prn" || stem == "aux" || stem == "nul" ||
                (stem.length() == 4 && (stem.begins_with("com") || stem.begins_with("lpt")) && stem[3] >= '1' && stem[3] <= '9')) return false;
        }
        return true;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("extract", "path", "destination"), &ModArchiveExtractor::extract);
        ClassDB::bind_method(D_METHOD("cancel"), &ModArchiveExtractor::cancel);
        ClassDB::bind_method(D_METHOD("progress"), &ModArchiveExtractor::progress);
    }
public:
    void cancel() { cancelled.store(true); }
    double progress() const { auto t = total.load(); return t ? double(written.load()) / t : 0.0; }
    String extract(const String &path, const String &destination) {
        if (used) return "Archive reader already used.";
        used = true;
        auto dir = DirAccess::open(destination);
        if (dir.is_null() || !dir->get_files().is_empty() || !dir->get_directories().is_empty()) return "Archive destination must be an empty staging folder.";
        Input input{{Input::read, Input::seek}, FileAccess::open(path, FileAccess::READ), &cancelled};
        if (input.file.is_null()) return "Could not open the downloaded archive.";
        Archive a;
        CLookToRead2 look{};
        std::vector<Byte> input_buffer(65536);
        LookToRead2_CreateVTable(&look, False);
        look.realStream = &input.vt; look.buf = input_buffer.data(); look.bufSize = input_buffer.size();
        LookToRead2_INIT(&look)
        if (SzArEx_Open(&a.db, &look.vt, &a.memory.vt, &a.memory.vt) != SZ_OK) return "Could not read the downloaded 7z archive.";
        if (a.db.NumFiles > 4096) return "Too many archive entries.";
        std::vector<String> names;
        std::set<std::string> seen, files;
        uint64_t sum = 0;
        for (UInt32 i = 0; i < a.db.NumFiles; ++i) {
            size_t len = SzArEx_GetFileNameUtf16(&a.db, i, nullptr);
            if (!len || len > 241) return "Unsafe archive path.";
            std::vector<UInt16> text(len);
            SzArEx_GetFileNameUtf16(&a.db, i, text.data());
            String name = String::utf16(reinterpret_cast<const char16_t *>(text.data()), len - 1);
            if (!safe_name(name)) return "Unsafe archive path.";
            std::string key = name.to_lower().utf8().get_data();
            if (!seen.insert(key).second) return "Duplicate archive path.";
            if (!SzArEx_IsDir(&a.db, i)) files.insert(key);
            if (SzBitWithVals_Check(&a.db.Attribs, i)) {
                auto attr = a.db.Attribs.Vals[i];
                auto type = (attr >> 16) & 0170000;
                if ((attr & 0x400) || (type && type != 0100000 && type != 0040000)) return "Linked or special archive entry.";
            }
            uint64_t size = SzArEx_GetFileSize(&a.db, i);
            if (size > total_limit || sum > total_limit - size) return "Archive exceeds the extraction limit.";
            sum += size; names.push_back(name);
        }
        for (auto &name : seen) {
            size_t at = 0;
            while ((at = name.find('/', at)) != std::string::npos) {
                if (files.count(name.substr(0, at))) return "Conflicting archive paths.";
                ++at;
            }
        }
        for (UInt32 i = 0; i < a.db.db.NumFolders; ++i)
            if (SzAr_GetFolderUnpackSize(&a.db.db, i) > total_limit) return "Archive block exceeds the extraction limit.";
        total.store(sum);
        a.memory.limit = total_limit + 16 * 1024 * 1024;
        for (UInt32 i = 0; i < a.db.NumFiles; ++i) {
            if (cancelled.load()) return "Download cancelled.";
            if (SzArEx_IsDir(&a.db, i)) continue;
            size_t offset = 0, length = 0;
            if (SzArEx_Extract(&a.db, &look.vt, i, &a.block, &a.buffer, &a.size, &offset, &length, &a.memory.vt, &a.memory.vt) != SZ_OK)
                return cancelled.load() ? "Download cancelled." : "Could not unpack the downloaded archive.";
            String target = destination.path_join(names[i]);
            if (DirAccess::make_dir_recursive_absolute(target.get_base_dir()) != OK || FileAccess::file_exists(target)) return "Could not create the extraction folder.";
            auto output = FileAccess::open(target, FileAccess::WRITE);
            if (output.is_null()) return "Could not write the extracted file.";
            for (size_t pos = 0; pos < length;) {
                if (cancelled.load()) return "Download cancelled.";
                size_t size = std::min<size_t>(1048576, length - pos);
                PackedByteArray chunk; chunk.resize(size);
                std::memcpy(chunk.ptrw(), a.buffer + offset + pos, size);
                output->store_buffer(chunk);
                if (output->get_error() != OK) return "Not enough space to extract the download.";
                written.fetch_add(size); pos += size;
            }
            output->flush();
            if (output->get_error() != OK) return "Not enough space to extract the download.";
        }
        return "";
    }
};
static void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) { CrcGenerateTable(); ClassDB::register_class<ModArchiveExtractor>(); }
}
static void uninitialize(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT mod_archive_init(GDExtensionInterfaceGetProcAddress address, GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
    GDExtensionBinding::InitObject object(address, library, init);
    object.register_initializer(initialize); object.register_terminator(uninitialize);
    object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE); return object.init();
}
