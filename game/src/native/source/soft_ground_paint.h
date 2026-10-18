// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform2d.hpp>
#include <algorithm>
#include <cmath>

namespace godot {
// Same ordered footprint/travel raster as SoftGroundDeform. Only CPU images
// change here; terrain geometry, collision, lifetimes and uploads stay in script.
class SoftGroundPaintKernel : public RefCounted {
    GDCLASS(SoftGroundPaintKernel, RefCounted)
    static double smooth(double a, double b, double x) {
        const double t = std::clamp((x-a)/(b-a), 0.0, 1.0);
        return t*t*(3.0-2.0*t);
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("paint", "image", "marks", "origin", "noise"), &SoftGroundPaintKernel::paint);
    }
public:
    bool paint(const Ref<Image> &image, const Array &marks, Vector2 origin, const Ref<FastNoiseLite> &noise) const {
        if (image.is_null() || image->get_format()!=Image::FORMAT_RGBAF || image->has_mipmaps() ||
                image->get_width()!=512 || image->get_height()!=512 || marks.size()>1024) return false;
        // Reject before writing, so the ordinary script fallback cannot paint
        // an accepted prefix twice. These dictionaries are local renderer data.
        for (int i=0; i<marks.size(); ++i) {
            if (marks[i].get_type()!=Variant::DICTIONARY) return false;
            const Dictionary m=marks[i];
            if (!m.has("p") || !m.has("extent") || !m.has("time") || !m.has("angle")) return false;
            const Vector2 p=m["p"], extent=m["extent"];
            if (!p.is_finite() || !extent.is_finite() || extent.x<=0 || extent.y<=0 ||
                    !std::isfinite(double(m["time"])) || !std::isfinite(double(m["angle"]))) return false;
            if (m.has("to") && (noise.is_null() || !Vector2(m["to"]).is_finite())) return false;
        }
        constexpr double scale=511.0/32.0;
        for (int i=0; i<marks.size(); ++i) {
            const Dictionary m=marks[i];
            const Vector2 from=Vector2(m["p"])-origin, extent=m["extent"];
            const bool trail=m.has("to");
            const Vector2 to=trail ? Vector2(m["to"])-origin : from;
            const double stamp=m["time"], angle=m["angle"];
            const double width=extent.x, radius=trail ? width*2.6 : extent.length()*1.8;
            const Vector2 lo=((from.min(to)-Vector2(1,1)*radius)*scale).floor().clamp(Vector2(),Vector2(511,511));
            const Vector2 hi=((from.max(to)+Vector2(1,1)*radius)*scale).ceil().clamp(Vector2(),Vector2(511,511));
            const Transform2D turn(-angle,Vector2());
            const Vector2 along=to-from;
            const double length_sq=std::max(double(along.length_squared()),1e-6);
            const double pressure=trail ? double(m.get("pressure",1.0)) : std::clamp(std::sqrt(double(extent.x*extent.y)/0.009),0.35,1.0);
            for (int y=int(lo.y); y<=int(hi.y); ++y) for (int x=int(lo.x); x<=int(hi.x); ++x) {
                const Vector2 p=Vector2(x,y)/scale;
                double r, depression, rim;
                if (trail) {
                    const Vector2 nearest=from+along*std::clamp(double((p-from).dot(along))/length_sq,0.0,1.0);
                    r=p.distance_to(nearest)/width;
                    if (r>2.6) continue;
                    const Vector2 q=p+origin;
                    const double rough=noise->get_noise_2d(q.x,q.y)*0.18 + noise->get_noise_2d(q.x*3.7+43.0,q.y*3.7-17.0)*0.07;
                    r/=1.0+rough;
                    if (r>2.05) continue;
                    depression=(1.0-smooth(0.2,1.6,r))*pressure*0.64;
                    rim=(smooth(1.0,1.45,r)-smooth(1.45,2.05,r))*pressure*0.05;
                } else {
                    r=(turn.xform(p-from)/extent).length();
                    if (r>1.8) continue;
                    depression=(1.0-smooth(0.35,1.25,r))*0.82*pressure;
                    rim=(smooth(0.9,1.3,r)-smooth(1.3,1.8,r))*0.06*pressure;
                }
                const Color old=image->get_pixel(x,y);
                const double fade=std::clamp((240.0-std::max(stamp-double(old.b),0.0))/60.0,0.0,1.0);
                image->set_pixel(x,y,Color(std::max(old.r*fade,depression),std::max(old.g*fade,rim),stamp,1));
            }
        }
        return true;
    }
};
}
