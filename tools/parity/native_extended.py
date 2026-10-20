"""Additional bounded original-instruction adapters for the pinned executable."""
import struct
from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ESI, UC_X86_REG_EBP, UC_X86_REG_ESP, UC_X86_REG_EIP


def noticed_retention(o, case):
    """Execute the native living-target drop predicate, not a Python rewrite."""
    observer, target, own, other, frame = [o.alloc(n) for n in [0x600,0x600,0xc00,0xc00,0x100]]
    frame += 0x80
    o.write(frame + 8, own)
    o.write(frame - 0x18, other)
    o.uc.mem_write(frame - 1, bytes([int(case['party'])]))
    o.floats(frame - 0xc, 1.0 if case['party'] else 1.05, case['distance'])
    o.floats(other + 0x900, case['visibility'])
    o.floats(own + 0x904, case['sight_factor'])
    o.floats(other + 0x2c4, case['detect'])
    o.floats(own + 0x294, case['sight'])
    o.floats(other + 0x2d4, case['life_detect'])
    o.floats(own + 0x2a4, case['life'])
    o.uc.mem_write(other + 0x174, bytes([int(case['fighting'])]))
    o.write(other + 0x9ac, observer if case['fighting'] else 0)
    o.hook(0x530150, lambda:o.ret(int(case['hostile']),cleanup=4))
    o.hook(0x5d5f20, lambda:o.ret(0))  # no separate Aggression target
    o.hook(0x5cae03, o.uc.emu_stop)
    o.uc.reg_write(UC_X86_REG_EBP, frame)
    o.uc.reg_write(UC_X86_REG_EBX, observer)
    o.uc.reg_write(UC_X86_REG_ESI, target)
    o.uc.reg_write(UC_X86_REG_ESP, 0x91ff000)
    o.slice(0x5cac76, 0x5cad02, (0x5cae03,))
    return [{'retained':o.uc.reg_read(UC_X86_REG_EIP)==0x5cae03}]


def village_gate(o, case):
    unit, controller = o.alloc(0x600), o.alloc(0xc00)
    o.write(unit + 0x240, controller)
    o.write(controller + 0x190, case["current"])
    o.write(controller + 0x1b4, case["posted"])
    o.hook(0x603ea3, lambda: o.ret(1))
    o.hook(0x60410d, lambda: o.ret(0))
    o.uc.reg_write(UC_X86_REG_EAX, unit)
    o.uc.reg_write(UC_X86_REG_EBX, 0)
    return [{"ready":bool(o.run(0x603e79))}]


def darkness(o, case):
    world = o.alloc(0x100)
    o.floats(world + 0x1c, case["hour"], 0)
    o.write(world + 0x64, 0)
    result, wrapper = o.alloc(4), o.alloc(32)
    # Store the real native floating return value; no darkness calculation here.
    o.uc.mem_write(wrapper, b"\xe8" + struct.pack("<i", 0x55fc50 - wrapper - 5)
                   + b"\xd9\x1d" + struct.pack("<I", result) + b"\xc3")
    o.run(wrapper, world)
    return [{"darkness_bits":o.ints(result)[0]}]


def eye_height(o, case):
    unit, controller, world, uv, wv, ground = [o.alloc(n) for n in [0x600,0xc00,0x100,0x100,0x100,4]]
    o.write(unit, uv)
    o.write(unit + 0x240, controller)
    o.write(unit + 0x124, 2)
    o.write(unit + 0x264, case["posture"])
    o.write(controller + 0x1c, unit)
    o.floats(unit + 0x1c, 1, 2, 0)
    o.floats(unit + 0x14c, case["half"])
    o.floats(ground, case["ground"])
    o.write(world, wv)
    o.write(wv + 0x74, 0x1800, 0x1800)
    o.uc.mem_write(0x1800, b"\xd9\x05" + struct.pack("<I", ground) + b"\xc2\x08\x00")
    o.write(uv + 0xdc, 0x1840)
    o.hook(0x1840, lambda:o.ret(int(case["dead"])))
    o.hook(0x455940, lambda:o.ret(world))
    o.hook(0x455950, lambda:o.ret(world))
    result = o.alloc(12)
    o.run(0x5303a0, unit, [result])
    return [{"eye_bits":o.ints(result + 8)[0]}]


def faction_relation(o, case):
    table = o.alloc(0x100)
    for side in range(32):
        o.write(table + side * 4, 1 << side)
    a, b = case["actor"], case["target"]
    states = []
    for value in case["values"]:
        o.run(0x4554e0, table, [a,b,value,0])
        states.append({"actor_friend":o.ints(table+a*4)[0], "actor_enemy":o.ints(table+0x80+a*4)[0],
                       "target_friend":o.ints(table+b*4)[0], "target_enemy":o.ints(table+0x80+b*4)[0]})
    return states


def path_refine(o, case):
    o.hook(0x70056f, lambda:o.ret(o.alloc(o.args(1)[0])))
    o.hook(0x700598, lambda:o.ret())
    o.run(0x5c42b0)
    w, h = case["size"]
    nav, rows = o.alloc(0x2700), o.alloc(h*4)
    o.write(nav + 0x269c, rows)
    costs = [-1,0x6400,0x77ec,0x8bd8,0x2ff8,0x37f0,0x3ffc,0xdfc,0xfff,0x11fd,0x1400,0x666,0x732,0x800,0x400,0x4cc]
    o.write(nav + 0x14, *costs)
    o.write(nav + 0x54, -1, *([1024]*15))
    slope = o.alloc(4*len(case["slope"]))
    o.write(slope, *case["slope"])
    middle = slope + len(case["slope"])//2*4
    def tables():
        result = o.args(2)[1]
        o.write(result, nav + (0x54 if case["flat"] else 0x14), middle, case["cls"]*4,
                0x3dcccccd, 0x41200000, 0x3dcccccd)
        o.ret(cleanup=8)
    o.hook(0x5b9580, tables)
    o.hook(0x5b7b70, lambda:o.ret(case["threshold"],cleanup=4))
    for y in range(h):
        row = o.alloc(w*9)
        o.write(rows+y*4, row)
        for x in range(w):
            i = y*w+x
            o.uc.mem_write(row+x*9, struct.pack("<IHBBB", case["values"][i] << (case["cls"]*4),
                                              case["heights"][i] & 0xffff, 0,0,case["stamps"][i]))
    unit, path, context = o.alloc(0x480), o.alloc(0x20), o.alloc(0x28)
    o.write(unit + 0x324, case["cls"])
    previous = 0
    for cell in reversed(case["cells"]):
        node = o.alloc(16)
        o.write(node,previous,0)
        o.uc.mem_write(node+8,struct.pack("<hhI",cell%w,cell//w,0))
        if previous: o.write(previous+4,node)
        else: o.write(path+8,node)
        previous = node
    o.write(path+4,previous)
    o.write(path+0xc,len(case["cells"]),0,0,1024)
    end_x = case["end"][0]/0.5
    fraction = struct.unpack("<I",struct.pack("<f",2*abs(end_x-round(end_x))))[0]
    cost = o.run(0x5c46c0,context,[unit,nav,path,case["heading"],fraction])
    cells = []
    node = o.ints(path+4)[0]
    while node:
        x, y = struct.unpack("<hh",o.uc.mem_read(node+8,4))
        cells.append(y*w+x)
        node = o.ints(node)[0]
        if len(cells)>w*h: raise ValueError("Corrupt original refined route")
    return [{"cost":cost,"cells":cells}]


CAPTURES = {"village_gate":village_gate, "darkness":darkness, "eye_height":eye_height,
            "faction_relation":faction_relation, "path_refine":path_refine,
            "noticed_retention":noticed_retention}
