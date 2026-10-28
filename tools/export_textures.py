#!/usr/bin/env python3
"""Export Evil Islands MMP textures as editable full-colour PNG images.

Python 3.10+, standard library only. Inputs are read-only. The output uses the
texture-pack folder layout: <output>/<archive>/<entry>.png. Copy the images you
edit into a mod folder and run tools/package_mod.py; the game loads the PNGs
without DXT compression. Pixels match game/src/ei/mmp_texture.gd decode(),
including Godot's BC1/BC2 (bcdec) rounding.
"""
from __future__ import annotations

import argparse
import fnmatch
import struct
import sys
import zlib
from pathlib import Path

from convert_legacy_mod import Archive

MAGIC = 0x00504D4D  # "MMP\0"
DATA_OFFSET = 76
MAX_SIDE = 16384
MAX_PIXELS = 64 * 1024 * 1024
# Archives whose MMP entries texture packs can replace (game/src/game/mod_schema.gd).
TEXTURE_ARCHIVES = ("textures.res", "redress.res", "menus.res")


def _bc_colors(c0: int, c1: int, opaque: bool) -> list[bytes]:
    """bcdec__color_block palette as RGBA bytes."""
    r0, g0, b0 = (c0 >> 11) & 31, (c0 >> 5) & 63, c0 & 31
    r1, g1, b1 = (c1 >> 11) & 31, (c1 >> 5) & 63, c1 & 31
    colors = [bytes(((r0 * 527 + 23) >> 6, (g0 * 259 + 33) >> 6, (b0 * 527 + 23) >> 6, 255)),
              bytes(((r1 * 527 + 23) >> 6, (g1 * 259 + 33) >> 6, (b1 * 527 + 23) >> 6, 255))]
    if c0 > c1 or opaque:
        colors.append(bytes((((2 * r0 + r1) * 351 + 61) >> 7, ((2 * g0 + g1) * 2763 + 1039) >> 11,
                             ((2 * b0 + b1) * 351 + 61) >> 7, 255)))
        colors.append(bytes((((r0 + 2 * r1) * 351 + 61) >> 7, ((g0 + 2 * g1) * 2763 + 1039) >> 11,
                             ((b0 + 2 * b1) * 351 + 61) >> 7, 255)))
    else:
        colors.append(bytes((((r0 + r1) * 1053 + 125) >> 8, ((g0 + g1) * 4145 + 1019) >> 11,
                             ((b0 + b1) * 1053 + 125) >> 8, 255)))
        colors.append(bytes(4))
    return colors


def _decode_bc(data: bytes, w: int, h: int, alpha: bool) -> bytearray:
    """First level of a DXT1 (alpha=False) or DXT3 image, cropped to w×h."""
    block = 16 if alpha else 8
    bw, bh = (w + 3) // 4, (h + 3) // 4
    if len(data) < bw * bh * block:
        raise ValueError("Truncated DXT data")
    out = bytearray(w * h * 4)
    pos = 0
    for by in range(bh):
        for bx in range(bw):
            color = pos + 8 if alpha else pos
            c0, c1, indices = struct.unpack_from("<HHI", data, color)
            palette = _bc_colors(c0, c1, alpha)
            alphas = struct.unpack_from("<Q", data, pos)[0] if alpha else 0
            pos += block
            for row in range(4):
                y = by * 4 + row
                for col in range(4):
                    x = bx * 4 + col
                    i = row * 4 + col
                    if x < w and y < h:
                        p = (y * w + x) * 4
                        out[p:p + 4] = palette[(indices >> (i * 2)) & 3]
                        if alpha:
                            out[p + 3] = ((alphas >> (i * 4)) & 15) * 17
    return out


def _decode_pnt3(data: bytes, size: int, w: int, h: int) -> bytearray:
    """RLE: a dword with non-zero alpha is a BGRA pixel, otherwise a count of zero bytes."""
    out = bytearray(w * h * 4)
    dst, src = 0, DATA_OFFSET
    end = min(DATA_OFFSET + size, len(data))
    while src + 4 <= end and dst < len(out):
        if data[src + 3]:
            out[dst:dst + 4] = bytes((data[src + 2], data[src + 1], data[src], data[src + 3]))[: len(out) - dst]
            dst += 4
        else:
            value = struct.unpack_from("<I", data, src)[0]
            dst += value if value else 4
        src += 4
    return out


def _decode_raw(data: bytes, w: int, h: int) -> bytearray:
    """Uncompressed 16/32-bit ARGB with masks, as EIMmp._decode_raw_script()."""
    bits = struct.unpack_from("<I", data, 20)[0]
    if bits not in (16, 32) or w * h * (bits // 8) > len(data) - DATA_OFFSET:
        raise ValueError("Unsupported or truncated raw MMP")
    channels = []
    for c in range(4):  # a, r, g, b: (mask, shift, bit count)
        mask, shift, count = struct.unpack_from("<III", data, 24 + c * 12)
        if shift >= 64:
            raise ValueError("Invalid raw MMP channel")
        full = mask >> shift
        # Alpha without bits is opaque; a colour channel without bits is zero.
        table = None if c == 0 and count == 0 else [int(0.5 + 255.0 * v / full) if full else 0 for v in range(full + 1)] \
            if full <= 0xFFFF else None
        channels.append((mask, shift, full, count, table))
    pixels = struct.unpack_from("<%d%s" % (w * h, "H" if bits == 16 else "I"), data, DATA_OFFSET)
    out = bytearray(w * h * 4)
    for c, (mask, shift, full, count, table) in enumerate(channels):
        target = (c + 3) % 4  # a,r,g,b -> r,g,b,a
        if c == 0 and count == 0:
            out[target::4] = b"\xff" * (w * h)
        elif table is not None:
            out[target::4] = bytes(table[(px & mask) >> shift] for px in pixels)
        else:
            out[target::4] = bytes((int(0.5 + 255.0 * ((px & mask) >> shift) / full) if full else 0) for px in pixels)
    return out


def decode(data: bytes) -> tuple[int, int, bytearray]:
    """(width, height, RGBA8 pixels) of the first MMP level, top row first."""
    if len(data) < DATA_OFFSET or struct.unpack_from("<I", data)[0] != MAGIC:
        raise ValueError("Not an MMP texture")
    w, h, size = struct.unpack_from("<III", data, 4)
    if w <= 0 or h <= 0 or w > MAX_SIDE or h > MAX_SIDE or w * h > MAX_PIXELS:
        raise ValueError(f"Unsupported MMP size {w}x{h}")
    tag = data[16:20]
    if tag == b"DXT1":
        return w, h, _decode_bc(data[DATA_OFFSET:], w, h, False)
    if tag == b"DXT3":
        return w, h, _decode_bc(data[DATA_OFFSET:], w, h, True)
    if tag == b"PNT3":
        return w, h, _decode_pnt3(data, size, w, h)
    pixels = _decode_raw(data, w, h)
    if tag == b"\x88\x88\0\0":  # 8888 textures are stored bottom-up
        stride = w * 4
        pixels = bytearray(b"".join(pixels[y * stride:(y + 1) * stride] for y in reversed(range(h))))
    return w, h, pixels


def png(w: int, h: int, rgba: bytes) -> bytes:
    """Lossless 8-bit RGBA PNG."""
    stride = w * 4
    raw = b"".join(b"\0" + bytes(rgba[y * stride:(y + 1) * stride]) for y in range(h))

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def sources(source: Path, archives: list[str], name: str | None) -> list[tuple[str, Path]]:
    """(output folder, archive path) pairs from a game folder or a single .res file."""
    if source.is_file():
        return [((name or source.name).lower(), source)]
    if name:
        raise ValueError("--name applies to a single .res file")
    found = []
    res = next((p for p in source.iterdir() if p.is_dir() and p.name.lower() == "res"), None) if source.is_dir() else None
    if res is None:
        raise ValueError(f"No res folder in {source}")
    files = {p.name.lower(): p for p in res.iterdir() if p.is_file()}
    for archive in archives:
        if archive.lower() in files:
            found.append((archive.lower(), files[archive.lower()]))
    if not found:
        raise ValueError(f"None of {', '.join(archives)} found in {res}")
    return found


def export(source: Path, output: Path, archives=TEXTURE_ARCHIVES, patterns=("*",), name=None,
           overwrite=False, log=print) -> dict:
    """Write PNGs; returns counts. Existing different files are kept unless overwrite."""
    counts = {"written": 0, "unchanged": 0, "kept": 0, "failed": 0}
    output = output.resolve()
    for folder, path in sources(source, list(archives), name):
        archive = Archive(path)
        for entry in sorted(archive.entries):
            if not entry.endswith(".mmp") or not any(fnmatch.fnmatchcase(entry, p.lower()) for p in patterns):
                continue
            target = output / folder / (entry[: -len(".mmp")] + ".png")
            if not target.resolve().is_relative_to(output):
                raise ValueError(f"Unsafe archive entry: {entry}")
            try:
                data = png(*decode(archive.read(entry)))
            except (ValueError, struct.error) as error:
                counts["failed"] += 1
                log(f"skipped {folder}/{entry}: {error}")
                continue
            if target.exists():
                if target.read_bytes() == data:
                    counts["unchanged"] += 1
                    continue
                if not overwrite:
                    counts["kept"] += 1
                    log(f"kept edited {target.relative_to(output)} (use --overwrite to replace)")
                    continue
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_name(target.name + ".part")
            temporary.write_bytes(data)
            temporary.replace(target)
            counts["written"] += 1
    return counts


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path, help="Game folder (containing res/) or a single .res archive")
    parser.add_argument("output", type=Path, help="Folder for <archive>/<entry>.png images")
    parser.add_argument("--archive", action="append", choices=TEXTURE_ARCHIVES,
                        help="Archive to export from a game folder; repeat for several (default: all three)")
    parser.add_argument("--match", action="append", default=[],
                        help="Entry name pattern such as 'unhufe*' or 'sub/*'; repeat for several")
    parser.add_argument("--name", help="Output folder for a single .res file, e.g. textures.res for a legacy mod part")
    parser.add_argument("--overwrite", action="store_true", help="Replace existing PNGs that differ from the export")
    args = parser.parse_args(argv)
    patterns = [p if p.endswith(".mmp") or p.endswith("*") else p + ".mmp" for p in args.match] or ["*"]
    try:
        counts = export(args.source, args.output, args.archive or TEXTURE_ARCHIVES, patterns, args.name, args.overwrite)
    except (ValueError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print("{written} written, {unchanged} unchanged, {kept} kept, {failed} skipped".format(**counts))
    return 1 if counts["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
