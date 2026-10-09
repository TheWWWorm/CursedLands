#pragma once
// Optional visual-only fixed-step solver. Packed snapshots and a returned
// image payload keep scene, worker, clock and resource ownership in GDScript.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>
#include <algorithm>
#include <cmath>
#include <vector>

namespace godot {
class WaterWaveKernel : public RefCounted {
    GDCLASS(WaterWaveKernel, RefCounted)
    static constexpr int size = 128, count = size * size;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("step", "previous", "domain", "sources", "weights", "origin", "steps", "seconds"), &WaterWaveKernel::step);
    }
public:
    PackedFloat32Array step(const PackedFloat32Array &previous, const PackedFloat32Array &domain,
            const PackedVector4Array &sources, const PackedVector2Array &weights, Vector2 origin, int steps, double seconds) const {
        PackedFloat32Array result;
        if (previous.size() != count * 4 || domain.size() != previous.size() || sources.size() != weights.size() ||
                sources.size() > 16 || steps < 0 || steps > 8 || !origin.is_finite() || !std::isfinite(seconds)) return result;
        const float *d = domain.ptr();
        // Reject malformed external callers before their values enter a
        // persistent state; normal production domains always satisfy this.
        for (int i = 0; i < count * 4; ++i) if (!std::isfinite(d[i]) || !std::isfinite(previous[i])) return result;
        std::vector<float> state(previous.ptr(), previous.ptr() + count * 4), next(count * 4);
        auto compatible = [&](int a, int b) {
            return d[b * 4 + 3] == d[a * 4 + 3] && std::abs(double(d[b * 4]) - d[a * 4]) < .75;
        };
        auto fade = [](int x, int y) { return std::min(std::min({x, y, size - 1 - x, size - 1 - y}) / 6., 1.); };
        auto trail = [&](int at, double px, double py) {
            if (px < -1 || py < -1 || px >= size || py >= size) return 0.;
            const int x = int(std::floor(px)), y = int(std::floor(py));
            const double fx = px - x, fy = py - y;
            double value = 0;
            for (int dy = 0; dy < 2; ++dy) for (int dx = 0; dx < 2; ++dx) {
                if (x + dx < 0 || y + dy < 0 || x + dx >= size || y + dy >= size) continue;
                const int j = (y + dy) * size + x + dx;
                if (compatible(at, j)) value += state[j * 4 + 2] * (dx ? fx : 1. - fx) * (dy ? fy : 1. - fy);
            }
            return value;
        };
        for (int tick = 0; tick < steps; ++tick) {
            std::fill(next.begin(), next.end(), 0.f);
            for (int y = 1; y < size - 1; ++y) for (int x = 1; x < size - 1; ++x) {
                const int i = y * size + x, at = i * 4;
                if (d[at + 3] <= 0) continue;
                double lap = -4. * state[at];
                for (int j : {i - 1, i + 1, i - size, i + size}) if (compatible(i, j)) lap += state[j * 4];
                const double edge = fade(x, y);
                next[at] = float(std::clamp((2. * state[at] - state[at + 1] + .0175 * lap) * .955 * edge, -.15, .15));
                next[at + 1] = float(state[at] * edge);
                // Match Vector2's float32 coordinates in the script oracle.
                const Vector2 sample = Vector2(x, y) - Vector2(d[at + 1], d[at + 2]) * float((1. / 30.) / .25);
                next[at + 2] = float(trail(i, sample.x, sample.y) * .9908 * edge);
                next[at + 3] = d[at];
            }
            const double time = seconds - (steps - 1 - tick) / 30.;
            for (int u = 0; u < sources.size(); ++u) {
                const Vector4 source = sources[u]; const Vector2 weight = weights[u];
                if (!source.is_finite() || !weight.is_finite()) continue;
                const double radius = std::clamp(double(source.z), .25, 2.), reach = radius / .25;
                const Vector2 pos = (Vector2(source.x, source.y) - origin) / .25f - Vector2(.5, .5);
                const double presence = std::clamp(double(weight.x), 0., 1.);
                const double push = (.0007 * std::clamp(double(source.w), 0., 5.) + .0006 * std::sin(time * 5. + weight.y)) *
                    std::clamp(double(source.z) / .35, .15, 5.) * presence;
                // Ignore remote/malformed sources before integer conversion.
                if (pos.x + reach < 1 || pos.y + reach < 1 || pos.x - reach > size - 2 || pos.y - reach > size - 2) continue;
                for (int y = std::max(1, int(std::floor(pos.y - reach))); y < std::min(size - 1, int(std::ceil(pos.y + reach)) + 1); ++y)
                    for (int x = std::max(1, int(std::floor(pos.x - reach))); x < std::min(size - 1, int(std::ceil(pos.x + reach)) + 1); ++x) {
                        const int at = (y * size + x) * 4;
                        if (d[at + 3] <= 0) continue;
                        const double d2 = Vector2(x - pos.x, y - pos.y).length_squared() / (reach * reach);
                        if (d2 >= 1.) continue;
                        const double edge = fade(x, y);
                        next[at] = float(std::clamp(next[at] - push * (1. - d2) * (1. - d2) * edge, -.15, .15));
                        next[at + 2] = float(std::max(double(next[at + 2]), std::max(0., 1. - d2 / .5625) * presence * edge));
                    }
            }
            state.swap(next);
        }
        result.resize(count * 4); std::copy(state.begin(), state.end(), result.ptrw());
        return result;
    }
};
} // namespace godot
