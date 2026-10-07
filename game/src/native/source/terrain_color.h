// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

namespace godot {
// Immutable atlas pixels and map tile codes, captured on the main thread.
// Baking only touches these owned bytes; no scene, rendering or script calls.
class TerrainColorField : public RefCounted {
    GDCLASS(TerrainColorField, RefCounted)
    struct Pixel { float r, g, b; };
    struct StoredPixel { uint8_t r, g, b; };
    struct Atlas { int width = 0, height = 0; std::vector<StoredPixel> pixels; };
    static constexpr uint64_t max_atlas_bytes = 128 * 1024 * 1024;
    std::array<float,256> lut;
    std::vector<Atlas> atlases;
    std::vector<int32_t> tiles;
    int width = 0, height = 0, per_row = 0;
    float border = 0.f, padding = 0.f;
    bool linear = false, valid = false;
    static Pixel mix(Pixel a, Pixel b, float t) {
        return {a.r+(b.r-a.r)*t, a.g+(b.g-a.g)*t, a.b+(b.b-a.b)*t};
    }
    static float from_srgb(float v) { return v <= .04045f ? v/12.92f : std::pow((v+.055f)/1.055f,2.4f); }
    static float to_srgb(float v) { return v <= .0031308f ? v*12.92f : 1.055f*std::pow(v,1.f/2.4f)-.055f; }
    Pixel tile_sample(int x, int y, float px, float py) const {
        const int code=tiles[std::clamp(y,0,height-1)*width+std::clamp(x,0,width-1)];
        const int tile=code&63, rotation=(code>>14)&3, layer=(code>>6)&255;
        if (layer >= int(atlases.size()) || tile >= per_row*per_row) return {1.f,0.f,1.f};
        const Atlas &a=atlases[layer];
        float tx=px-.5f, ty=py-.5f;
        if(rotation==1) { const float old=tx;tx=-ty;ty=old; }
        else if(rotation==2) { tx=-tx;ty=-ty; }
        else if(rotation==3) { const float old=tx;tx=ty;ty=-old; }
        const float interior=1.f-2.f*border, span=1.f+2.f*padding;
        const float lx=std::clamp(border+(.5f+tx)*interior,0.f,1.f);
        const float ly=std::clamp(1.f-(border+(.5f+ty)*interior),0.f,1.f);
        const float u=(float(tile%per_row)+(lx+padding)/span)/float(per_row);
        const float v=(float(per_row-1-tile/per_row)+(ly+padding)/span)/float(per_row);
        const float ix=u*a.width-.5f, iy=v*a.height-.5f;
        const int x0=int(std::floor(ix)), y0=int(std::floor(iy));
        auto at=[&](int xx,int yy) {
            const StoredPixel p=a.pixels[std::clamp(yy,0,a.height-1)*a.width+std::clamp(xx,0,a.width-1)];
            return Pixel{lut[p.r],lut[p.g],lut[p.b]};
        };
        return mix(mix(at(x0,y0),at(x0+1,y0),ix-x0),mix(at(x0,y0+1),at(x0+1,y0+1),ix-x0),iy-y0);
    }
    Pixel ground(float x,float y) const {
        const int cx=int(std::floor(x)),cy=int(std::floor(y));
        const float px=x-cx,py=y-cy;
        auto weight=[](float p) { const float t=std::clamp(std::min(p,1.f-p)/.12f,0.f,1.f);return .5f*(1.f-t*t*(3.f-2.f*t)); };
        const float wx=weight(px),wy=weight(py);const int sx=px<.5f?-1:1,sy=py<.5f?-1:1;
        Pixel c=tile_sample(cx,cy,px,py);
        if(wx>0.f)c=mix(c,tile_sample(cx+sx,cy,px-sx,py),wx);
        if(wy>0.f) {
            Pixel other=tile_sample(cx,cy+sy,px,py-sy);
            if(wx>0.f)other=mix(other,tile_sample(cx+sx,cy+sy,px-sx,py-sy),wx);
            c=mix(c,other,wy);
        }
        return c;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure","images","tiles","map_size","source_size","tile_size","gutter","linear"),&TerrainColorField::configure);
        ClassDB::bind_method(D_METHOD("sample","point"),&TerrainColorField::sample);
        ClassDB::bind_method(D_METHOD("bake","sector","pixels_per_tile"),&TerrainColorField::bake);
        ClassDB::bind_method(D_METHOD("memory_bytes"),&TerrainColorField::memory_bytes);
    }
public:
    bool configure(const TypedArray<Image> &images,const PackedInt32Array &codes,Vector2i size,int source_size,int tile_size,int gutter,bool p_linear) {
        valid=false; atlases.clear();tiles.clear();
        if(size.x<=0 || size.y<=0 || size.x>4096 || size.y>4096 || codes.size()!=int64_t(size.x)*size.y ||
                tile_size<=16 || source_size<tile_size || source_size%tile_size || gutter<0 || gutter>tile_size || images.is_empty() || images.size()>256)return false;
        width=size.x;height=size.y;per_row=source_size/tile_size;border=8.f/tile_size;padding=float(gutter)/tile_size;linear=p_linear;
        if(per_row>8)return false;
        for(int i=0;i<256;++i)lut[i]=linear?from_srgb(float(i)/255.f):float(i)/255.f;
        uint64_t atlas_bytes=0;
        for(int i=0;i<images.size();++i) {
            Ref<Image> image=images[i];
            if(image.is_null() || image->is_empty() || image->is_compressed())return false;
            Atlas a;a.width=image->get_width();a.height=image->get_height();
            if(a.width<=0 || a.height<=0 || a.width>8192 || a.height>8192 || a.width!=a.height)return false;
            atlas_bytes+=uint64_t(a.width)*a.height*sizeof(StoredPixel);
            if(atlas_bytes>max_atlas_bytes)return false;
            // Normalize an owned image, never mutate a shared loader/texture image.
            image=Image::create_from_data(image->get_width(),image->get_height(),false,image->get_format(),image->get_data().slice(0,image->get_mipmap_count()>0?image->get_mipmap_offset(1):image->get_data().size()));
            image->convert(Image::FORMAT_RGBA8);
            const PackedByteArray data=image->get_data(); const uint8_t *bytes=data.ptr();
            a.pixels.resize(size_t(a.width)*a.height);
            for(size_t j=0;j<a.pixels.size();++j)a.pixels[j]={bytes[j*4],bytes[j*4+1],bytes[j*4+2]};
            atlases.push_back(std::move(a));
        }
        tiles.assign(codes.ptr(),codes.ptr()+codes.size());valid=true;return true;
    }
    int64_t memory_bytes() const {
        int64_t bytes=int64_t(tiles.size()*sizeof(int32_t));
        for(const Atlas &a:atlases)bytes+=int64_t(a.pixels.size()*sizeof(StoredPixel));
        return bytes;
    }
    Color sample(Vector2 p) const {
        if(!valid || !p.is_finite() || std::abs(p.x)>65536.f || std::abs(p.y)>65536.f)return Color(1,0,1);
        const Pixel c=ground(p.x,p.y);return Color(c.r,c.g,c.b,1.f);
    }
    Ref<Image> bake(Vector2i sector,int pixels_per_tile) const {
        if(!valid || sector.x<0 || sector.y<0 || sector.x>=(width+15)/16 || sector.y>=(height+15)/16 || pixels_per_tile<16 || pixels_per_tile>192)return Ref<Image>();
        const int n=pixels_per_tile*18;PackedByteArray data;data.resize(int64_t(n)*n*4);uint8_t *out=data.ptrw();
        const float ox=sector.x*16.f-1.f,oy=sector.y*16.f-1.f;
        for(int y=0;y<n;++y)for(int x=0;x<n;++x) {
            const Pixel c=ground(ox+(float(x)+.5f)/pixels_per_tile,oy+(float(y)+.5f)/pixels_per_tile);
            const float channels[3]={c.r,c.g,c.b};const size_t offset=(size_t(y)*n+x)*4;
            for(int k=0;k<3;++k)out[offset+k]=uint8_t(std::clamp(std::round((linear?to_srgb(channels[k]):channels[k])*255.f),0.f,255.f));
            out[offset+3]=255;
        }
        Ref<Image> image=Image::create_from_data(n,n,false,Image::FORMAT_RGBA8,data);
        image->generate_mipmaps();return image;
    }
};
} // namespace godot
