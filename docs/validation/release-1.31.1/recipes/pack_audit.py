"""Pinned pack-directory validator reused from the qualified release recipe."""
import struct

def checked_pack_entries(label, data):
    """Reject truncated payloads/directories rather than scanning empty slices."""
    if len(data) < 40:
        raise ValueError(f'{label}: truncated pack header')
    magic, _version, _major, _minor, _patch, flags, base, directory = struct.unpack_from('<4sIIIIIQQ', data)
    if magic != b'GDPC' or flags & 1:
        raise ValueError(f'{label}: not an unencrypted Godot 4 pack')
    if directory < 40 or directory + 4 > len(data):
        raise ValueError(f'{label}: pack directory outside file')
    count = struct.unpack_from('<I', data, directory)[0]
    offset = directory + 4
    if count > (len(data) - offset) // 41:
        raise ValueError(f'{label}: impossible pack entry count')
    for _ in range(count):
        if offset + 4 > len(data):
            raise ValueError(f'{label}: truncated pack directory')
        length = struct.unpack_from('<I', data, offset)[0]
        offset += 4
        if not length or offset + length + 36 > len(data):
            raise ValueError(f'{label}: truncated pack entry')
        name = data[offset:offset + length].rstrip(b'\0').decode('utf-8')
        if not name or '\0' in name:
            raise ValueError(f'{label}: invalid resource name')
        offset += length
        start, size = struct.unpack_from('<QQ', data, offset)
        file_flags = struct.unpack_from('<I', data, offset + 32)[0]
        offset += 36
        if file_flags & 1 or base + start > len(data) or size > len(data) - base - start:
            raise ValueError(f'{label}: encrypted/truncated resource {name}')
        yield name, data[base + start:base + start + size]
