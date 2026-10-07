// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <cstdint>

namespace godot {
// Pure byte decoding: no scene, GPU, cache or mutable shared state. Channel
// scaling and rounding match EIMmp's original script decoder exactly.
class MmpTextureKernel : public RefCounted {
    GDCLASS(MmpTextureKernel, RefCounted)
    static uint32_t u32(const uint8_t *p) {
        return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("decode_raw", "data", "width", "height"), &MmpTextureKernel::decode_raw);
    }
public:
    PackedByteArray decode_raw(const PackedByteArray &data, int64_t width, int64_t height) const {
        PackedByteArray output;
        if (data.size() < 76 || width <= 0 || height <= 0 || width > 16384 || height > 16384 ||
                width * height > 64 * 1024 * 1024) return output;
        const uint8_t *input = data.ptr();
        const uint32_t bits = u32(input + 20);
        if (bits != 16 && bits != 32) return output;
        const int64_t bytes = bits / 8, count = width * height;
        if (count * bytes > data.size() - 76) return output;
        uint64_t masks[4], full[4];
        uint32_t shifts[4];
        const bool opaque = u32(input + 32) == 0;
        for (int c = 0; c < 4; ++c) {
            masks[c] = u32(input + 24 + c * 12);
            shifts[c] = u32(input + 28 + c * 12);
            if (shifts[c] >= 64) return output;
            full[c] = masks[c] >> shifts[c];
        }
        output.resize(count * 4);
        uint8_t *out = output.ptrw();
        const uint8_t *src = input + 76;
        for (int64_t i = 0; i < count; ++i, src += bytes, out += 4) {
            const uint32_t pixel = bytes == 2 ? uint32_t(src[0]) | uint32_t(src[1]) << 8 : u32(src);
            for (int c = 0; c < 4; ++c) {
                const uint64_t component = (pixel & masks[c]) >> shifts[c];
                out[(c + 3) % 4] = c == 0 && opaque ? 255 : full[c] ?
                    uint8_t(0.5 + 255.0 * double(component) / double(full[c])) : 0;
            }
        }
        return output;
    }
};
}
