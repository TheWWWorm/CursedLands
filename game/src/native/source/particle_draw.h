// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <algorithm>
#include <cmath>
#include <vector>

namespace godot {
// One emitter owns this writer. A worker packs the complete instance buffer
// without script callbacks or scene/rendering API calls in the particle loop.
class ParticleDrawBuffer : public RefCounted {
    GDCLASS(ParticleDrawBuffer, RefCounted)
    PackedFloat32Array buffer;
    int capacity=0;
    static constexpr double size_k=1.1099162;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("pack","particles","sorted","eye","forward","minimum_capacity","origin","previous_box","previous_reach"),&ParticleDrawBuffer::pack);
    }
public:
    Dictionary pack(const Array &particles,bool sorted,Vector3 eye,Vector3 forward,int minimum_capacity,Vector3 origin,AABB previous_box,double previous_reach) {
        const int64_t n=particles.size();if(n>1000000)return Dictionary();
        std::vector<Array> rows;rows.reserve(size_t(n));std::vector<Vector2> keys;keys.reserve(size_t(n));
        for(int64_t i=0;i<n;++i) {
            if(particles[i].get_type()!=Variant::ARRAY)return Dictionary();
            const Array p=particles[i];if(p.size()<24)return Dictionary();
            for(int k : {0,1,2,3,4,5,6,7,18,22,23}) {
                if(p[k].get_type()!=Variant::FLOAT && p[k].get_type()!=Variant::INT)return Dictionary();
                if(p[k].get_type()==Variant::FLOAT) {
                    const double value=p[k];
                    if(!std::isfinite(value) || (k>=18 && (value < -9223372036854775808. || value >= 9223372036854775808.)))return Dictionary();
                }
            }
            rows.push_back(p);
            if(sorted) {
                const Vector3 point(p[0],p[1],p[2]);
                const float depth=-(point-eye).dot(forward);
                // Nonfinite ordering keeps the legacy scalar path, without
                // supplying an invalid comparator to a native sort.
                if(!std::isfinite(depth))return Dictionary();
                keys.emplace_back(depth,real_t(i));
            }
        }
        if(sorted)std::sort(keys.begin(),keys.end(),[](Vector2 a,Vector2 b){return a<b;});
        if(capacity<n) {
            capacity=std::max(int(n),n<=64?std::min(minimum_capacity,64):int(n)*2);
            buffer.resize(int64_t(capacity)*20);buffer.fill(0.f);
        }
        float *out=buffer.ptrw();
        Vector3 lo(INFINITY,INFINITY,INFINITY),hi(-INFINITY,-INFINITY,-INFINITY);
        double big=0.;
        for(int64_t i=0;i<n;++i) {
            const Array &p=rows[sorted?int(keys[size_t(i)].y):size_t(i)];
            const uint32_t c0=uint32_t(int64_t(p[23])),c1=uint32_t(int64_t(p[22]));const int frame=int64_t(p[18])&15;
            const Vector3 a(p[4],p[6],-double(p[5])),b(p[0],p[2],-double(p[1]));
            float *dst=out+i*20;
            dst[0]=a.x;dst[1]=a.y;dst[2]=a.z;dst[3]=b.x;dst[4]=b.y;dst[5]=b.z;dst[6]=double(p[7]);dst[7]=double(p[3]);
            const uint32_t colors[2]={c0,c1};
            for(int j=0;j<2;++j) {
                const uint32_t c=colors[j];const int o=8+j*4;
                dst[o]=double((c>>16)&255)/255.;dst[o+1]=double((c>>8)&255)/255.;dst[o+2]=double(c&255)/255.;dst[o+3]=double((c>>24)&255)/255.;
            }
            const int cx=frame&3,ry=frame>>2;
            dst[16]=cx*.25+.001953125;dst[17]=1.-((ry+1)*.25-.001953125);
            dst[18]=(cx+1)*.25-.001953125;dst[19]=1.-(ry*.25+.001953125);
            lo=lo.min(a).min(b);hi=hi.max(a).max(b);
            big=std::max(big,std::max(std::abs(double(p[3])),std::abs(double(p[7])))*size_k);
        }
        const Vector3 expansion=Vector3(1,1,1)*real_t(big);
        const AABB box(lo-expansion,hi-lo+expansion*2.f);
        if(n>0 && box.position.is_finite() && box.size.is_finite())previous_box=box;
        else if(!previous_box.position.is_finite() || !previous_box.size.is_finite())previous_box=AABB();
        if(n>0) {
            const Vector3 at(origin.x,origin.z,-origin.y);
            const double reach=std::max(double((lo-at).abs().max((hi-at).abs()).length())+big,0.);
            if(std::isfinite(reach))previous_reach=reach;
        }
        Dictionary result;result["buffer"]=buffer;result["capacity"]=capacity;result["count"]=n;result["box"]=previous_box;result["reach"]=previous_reach;return result;
    }
};
} // namespace godot
