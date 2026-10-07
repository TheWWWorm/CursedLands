// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <algorithm>
#include <array>
#include <cstdint>

namespace godot {
// Pure IMA byte conversion. The immutable tables may be shared by sound
// prefetch workers; each invocation owns its predictors and output buffer.
class AudioDecodeKernel : public RefCounted {
    GDCLASS(AudioDecodeKernel, RefCounted)
    struct Tables {
        std::array<int, 89 * 16> diff{}, next{};
        Tables() {
            constexpr int steps[] = {7,8,9,10,11,12,13,14,16,17,19,21,23,25,28,31,34,37,41,45,50,55,60,
                66,73,80,88,97,107,118,130,143,157,173,190,209,230,253,279,307,337,371,408,449,494,
                544,598,658,724,796,876,963,1060,1166,1282,1411,1552,1707,1878,2066,2272,2499,2749,3024,
                3327,3660,4026,4428,4871,5358,5894,6484,7132,7845,8630,9493,10442,11487,12635,13899,15289,
                16818,18500,20350,22385,24623,27086,29794,32767};
            constexpr int changes[] = {-1,-1,-1,-1,2,4,6,8,-1,-1,-1,-1,2,4,6,8};
            for (int index = 0; index < 89; ++index) {
                for (int nibble = 0; nibble < 16; ++nibble) {
                    const int step = steps[index];
                    int delta = (step >> 3) + ((nibble & 4) ? step : 0) +
                        ((nibble & 2) ? step >> 1 : 0) + ((nibble & 1) ? step >> 2 : 0);
                    diff[index * 16 + nibble] = (nibble & 8) ? -delta : delta;
                    next[index * 16 + nibble] = std::clamp(index + changes[nibble], 0, 88);
                }
            }
        }
    };
    static int predictor(const uint8_t *p) {
        const int value = int(p[0]) | int(p[1]) << 8;
        return value >= 32768 ? value - 65536 : value;
    }
    static void write(uint8_t *out, int value) {
        const uint16_t bits = uint16_t(value);
        out[0] = uint8_t(bits); out[1] = uint8_t(bits >> 8);
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("decode_ima", "data", "block_align", "channels"), &AudioDecodeKernel::decode_ima);
    }
public:
    PackedByteArray decode_ima(const PackedByteArray &data, int64_t align, int64_t channels) const {
        PackedByteArray output;
        if (channels < 1 || channels > 8 || align <= channels * 4 || align > INT32_MAX ||
                data.size() > 128 * 1024 * 1024) return output;
        const int64_t header = channels * 4, length = data.size();
        int64_t samples = 0;
        for (int64_t pos = 0; pos + header <= length; pos += align) {
            const int64_t body = std::min(length - pos, align) - header;
            samples += channels + (channels == 1 ? body * 2 : body / header * 8 * channels);
        }
        if (!samples) return output;
        output.resize(samples * 2);
        const uint8_t *src = data.ptr();
        uint8_t *out = output.ptrw();
        static const Tables tables;
        int64_t offset = 0;
        for (int64_t pos = 0; pos + header <= length; pos += align) {
            const int64_t end = pos + std::min(length - pos, align);
            std::array<int, 8> pred{}, index{};
            for (int c = 0; c < channels; ++c) {
                pred[c] = predictor(src + pos + c * 4);
                index[c] = std::min(int(src[pos + c * 4 + 2]), 88);
                write(out + offset, pred[c]); offset += 2;
            }
            auto sample = [&](int c, int nibble, int64_t at) {
                const int key = index[c] * 16 + nibble;
                pred[c] = std::clamp(pred[c] + tables.diff[key], -32768, 32767);
                index[c] = tables.next[key];
                write(out + at, pred[c]);
            };
            if (channels == 1) {
                for (int64_t at = pos + header; at < end; ++at) {
                    sample(0, src[at] & 15, offset);
                    sample(0, src[at] >> 4, offset + 2);
                    offset += 4;
                }
            } else {
                for (int64_t group = pos + header; group + header <= end; group += header) {
                    for (int c = 0; c < channels; ++c) {
                        int64_t at = offset + c * 2;
                        for (int k = 0; k < 4; ++k) {
                            const int byte = src[group + c * 4 + k];
                            sample(c, byte & 15, at); at += channels * 2;
                            sample(c, byte >> 4, at); at += channels * 2;
                        }
                    }
                    offset += channels * 16;
                }
            }
        }
        return output;
    }
};
} // namespace godot
