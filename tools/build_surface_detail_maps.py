#!/usr/bin/env python3
"""Bake authored UV-space surface data without reading or redistributing albedo.

RGBA stores tangent-normal XY, perceptual roughness and metalness, all linear.
The original texture hashes identify the atlas layouts these recipes target.
Requires Pillow; --check compares decoded pixels rather than PNG compression.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/materials/surface-detail'
SIZE = 512
TAU = math.tau
SOURCES = {
    'stone03': '379da2ea1a3acc8ddfc473120f8a96a235bb582bcd6971f930eb709c0adc6126',
    'columnruins01': '58da94fa231fc508aa527c466d3f24cf96275f6ae671284edd52bf4d4bae5f3c',
    'bridge00': '65f4989267e4ff3fdc4e314af3a0492e7a929eee6042c271864d96dfd11292ec',
}


def smooth(a, b, value):
    t = max(0.0, min(1.0, (value-a)/(b-a)))
    return t*t*(3.0-2.0*t)


def segment(u, v, ax, ay, bx, by, width):
    dx, dy = bx-ax, by-ay
    t = max(0.0, min(1.0, ((u-ax)*dx+(v-ay)*dy)/(dx*dx+dy*dy)))
    d2 = (u-ax-t*dx)**2+(v-ay-t*dy)**2
    return math.exp(-d2/(2*width*width)) if d2 < 18*width*width else 0.0


def noise(u, v, seed):
    """Deterministic smooth value noise, with no repeating wave directions."""
    x, y = math.floor(u), math.floor(v)
    fx, fy = u-x, v-y
    fx = fx*fx*fx*(fx*(fx*6-15)+10)
    fy = fy*fy*fy*(fy*(fy*6-15)+10)
    def value(a, b):
        h = (a*374761393+b*668265263+seed*2246822519)&0xffffffff
        h = ((h^(h>>13))*1274126177)&0xffffffff
        return ((h^(h>>16))&65535)/32767.5-1
    lo = value(x,y)*(1-fx)+value(x+1,y)*fx
    hi = value(x,y+1)*(1-fx)+value(x+1,y+1)*fx
    return lo*(1-fy)+hi*fy


def wood(u, v):
    # Long fibres meander together; pores and worn fibres share the pattern.
    phase = TAU*29*u+1.4*math.sin(TAU*1.3*v)+0.4*math.sin(TAU*3*v)
    grain = math.sin(phase)
    height = 0.0008*grain+0.00018*math.sin(TAU*83*u+math.sin(TAU*2*v))
    return height, 0.76-0.065*grain+0.035*math.sin(TAU*7*v)


def recipe(name, u, v):
    if name == 'stone03':
        h = 0.006*noise(7*u,7*v,3)+0.0022*noise(23*u,23*v,11)+0.0007*noise(67*u,67*v,19)
        # Principal fissures follow the inspected rock atlas, not luminance.
        for line in [(0.06,0.10,0.25,0.42),(0.25,0.42,0.18,0.72),
                     (0.18,0.72,0.35,0.88),(0.49,0.05,0.61,0.29),
                     (0.61,0.29,0.53,0.52),(0.53,0.52,0.72,0.77)]:
            h -= 0.0011*segment(u,v,*line,0.005)
        roughness = 0.80+0.07*noise(4*u,4*v,31)+0.03*noise(17*u,17*v,41)
        # The lower atlas fringe is snow and the right strip is unused.
        # Neither should inherit rock fissures or regular-looking ripples.
        rock = (1-smooth(0.85,0.94,v))*(1-smooth(0.79,0.83,u))
        return h*rock, roughness*rock+0.9*(1-rock), 0.0
    if name == 'columnruins01':
        h = 0.0008*noise(43*u,43*v,47)+0.0004*noise(79*u,79*v,53)
        # Main panel's block joints; the glyph strip retains its original art.
        if 0.31 < u < 0.95 and 0.045 < v < 0.60:
            for x in [95,115,140,165,190,215,239]:
                h -= 0.0014*segment(u,v,x/256,16/256,x/256,148/256,0.003)
            for ax, ay, bx in [(95,62,140),(140,87,190),(190,58,239),(115,118,165),(190,121,239)]:
                h -= 0.0012*segment(u,v,ax/256,ay/256,bx/256,ay/256,0.003)
        return h, 0.82+0.055*math.sin(TAU*(4*u-3*v)), 0.0
    # The bridge's broad diagonal beams, top horizontal boards and right-hand
    # vertical stakes use different grain directions. Leave the skull/bone
    # ornament smooth instead of treating every light-coloured texel as wood.
    if u < 0.34 and 0.15 < v < 0.65 and u+v < 0.68:
        return 0.0, 0.73, 0.0
    if v < 0.17 and u < 0.6:
        h, roughness = wood(v,u)
    elif u+v > 1.31:
        h, roughness = wood(u,v)
    else:
        h, roughness = wood((u+v)/math.sqrt(2),(v-u)/math.sqrt(2))
    return h, roughness, 0.0


def bake(name):
    # Authoring coordinates follow the vertically flipped inspection previews.
    # EIMmp and FIG UVs use D3D rows (row zero is V zero). Convert HEIGHT before
    # taking derivatives, so both placement and the tangent Y sign are correct.
    rows = [recipe(name,(x+0.5)/SIZE,1.0-(y+0.5)/SIZE) for y in range(SIZE) for x in range(SIZE)]
    pixels = bytearray(SIZE*SIZE*4)
    def channel(value): return round(max(0.0,min(1.0,value))*255)
    for y in range(SIZE):
        for x in range(SIZE):
            at=y*SIZE+x
            # Clamp at atlas boundaries rather than joining unrelated islands.
            dx=(rows[y*SIZE+min(x+1,SIZE-1)][0]-rows[y*SIZE+max(x-1,0)][0])*SIZE*0.5
            dy=(rows[min(y+1,SIZE-1)*SIZE+x][0]-rows[max(y-1,0)*SIZE+x][0])*SIZE*0.5
            dx=max(-0.45,min(0.45,dx));dy=max(-0.45,min(0.45,dy))
            scale=1/math.sqrt(1+dx*dx+dy*dy)
            pixels[at*4:at*4+4]=bytes((channel(0.5-0.5*dx*scale),channel(0.5-0.5*dy*scale),channel(rows[at][1]),channel(rows[at][2])))
    return Image.frombytes('RGBA',(SIZE,SIZE),bytes(pixels))


def import_settings(name):
    source='res://assets/materials/surface-detail/'+name+'.png'
    dest='res://.godot/imported/'+name+'.png-'+hashlib.md5(source.encode()).hexdigest()+'.ctex'
    return f'''[remap]
importer="texture"
type="CompressedTexture2D"
path="{dest}"
metadata={{"vram_texture": false}}

[deps]
source_file="{source}"
dest_files=["{dest}"]

[params]
compress/mode=0
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=true
roughness/mode=0
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
detect_3d/compress_to=0
'''


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args();OUT.mkdir(parents=True,exist_ok=True)
    records={}
    for name,checksum in SOURCES.items():
        image=bake(name);target=OUT/(name+'.png')
        if args.check:
            assert Image.open(target).convert('RGBA').tobytes()==image.tobytes(),name+' pixels differ'
        else:
            image.save(target,optimize=True)
            (OUT/(name+'.png.import')).write_text(import_settings(name))
        records[name]={'source_mmp_sha256':checksum,'pixel_sha256':hashlib.sha256(image.tobytes()).hexdigest(),'size':[SIZE,SIZE]}
    manifest={'format':'linear tangent normal XY / roughness / metalness','normal_convention':'OpenGL +Y; positive reconstructed Z',
              'uv_rows':'D3D image order, row 0 = V 0, matching EIMmp and unmodified FIG UVs',
              'generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'materials':records}
    target=OUT/'provenance.json'
    if args.check: assert json.loads(target.read_text())==manifest,'provenance differs'
    else: target.write_text(json.dumps(manifest,indent=2)+'\n')
    print(('Verified' if args.check else 'Built'),len(records),'authored surface data maps')


if __name__=='__main__':main()
