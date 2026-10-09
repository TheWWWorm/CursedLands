#pragma once
// Optional scalar hot path for the immutable authored-water snapshot. No scene
// access, navigation state, clocks or GPU resources are owned by this class.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <algorithm>
#include <cmath>
#include <limits>
#include <vector>

namespace godot {
class WaterCurrentKernel : public RefCounted {
    GDCLASS(WaterCurrentKernel, RefCounted)
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("build","size","rest","material","bed","levels"),&WaterCurrentKernel::build);
    }
public:
    PackedFloat32Array build(Vector2i dim,const PackedFloat32Array &rest,const PackedInt32Array &material,
            const PackedFloat32Array &bed,const PackedFloat32Array &levels) const {
        PackedFloat32Array result;
        const int64_t count64=int64_t(dim.x)*dim.y;
        if(dim.x<1 || dim.y<1 || count64>4194304 || rest.size()!=count64 || material.size()!=count64 || bed.size()!=count64)return result;
        const int count=int(count64),width=dim.x;
        const float infinity=std::numeric_limits<float>::infinity();
        std::vector<float> heights(count,infinity);
        std::vector<Vector2> gradient(count);
        std::vector<int> active;
        const float *r=rest.ptr(),*b=bed.ptr(),*l=levels.ptr();const int32_t *m=material.ptr();
        for(int i=0;i<count;++i) {
            if(m[i]<0 || m[i]>=levels.size())continue;
            const double h=double(r[i])+l[m[i]];
            if(!std::isfinite(h) || !std::isfinite(b[i]) || h<double(b[i])-.05)continue;
            heights[i]=float(h);
            if(!std::isfinite(heights[i]))continue;
            active.push_back(i);
        }
        auto difference=[](double c,double a,double b) {
            if(std::isfinite(a)&&std::isfinite(b))return (b-a)*.5;
            if(std::isfinite(a))return c-a;
            return std::isfinite(b)?b-c:0.;
        };
        for(int i:active) {
            const int x=i%width,y=i/width;
            gradient[i]=Vector2(difference(heights[i],x>0?heights[i-1]:infinity,x+1<width?heights[i+1]:infinity),
                difference(heights[i],y>0?heights[i-width]:infinity,y+1<dim.y?heights[i+width]:infinity));
        }
        result.resize(count64*4);float *out=result.ptrw();std::fill(out,out+count64*4,0.f);
        for(int i:active) {
            const int x=i%width,y=i/width;Vector2 sum;double weight=0;
            for(int dy=-2;dy<=2;++dy) {
                if(y+dy<0 || y+dy>=dim.y)continue;
                for(int dx=-2;dx<=2;++dx) {
                    if(x+dx<0 || x+dx>=width)continue;
                    const int j=i+dy*width+dx;
                    if(!std::isfinite(heights[j]))continue;
                    const int w=(3-std::abs(dx))*(3-std::abs(dy));sum+=gradient[j]*w;weight+=w;
                }
            }
            double bend=0;
            for(int axis=0;axis<2;++axis) {
                const int step=axis?width*2:2,coordinate=axis?y:x,limit=axis?dim.y:width;
                const bool left=coordinate>=2&&std::isfinite(heights[i-step]);
                const bool right=coordinate+2<limit&&std::isfinite(heights[i+step]);
                const Vector2 a=left?gradient[i-step]:gradient[i],b=right?gradient[i+step]:gradient[i];
                const Vector2 delta=(b-a)/(left&&right?4.f:2.f);bend+=delta.length_squared();
            }
            out[i*4]=float(-sum.x/weight);out[i*4+1]=float(sum.y/weight);out[i*4+2]=float(std::sqrt(bend));out[i*4+3]=1.f;
        }
        return result;
    }
};
} // namespace godot
