"""Tiny adversarial 7z fixtures. libarchive is a test dependency only."""
import ctypes as c
import ctypes.util
from pathlib import Path
import sys

lib = c.CDLL(ctypes.util.find_library("archive"))
for name, args, result in [
    ("archive_write_new", [], c.c_void_p),
    ("archive_write_set_format_7zip", [c.c_void_p], c.c_int),
    ("archive_write_open_filename", [c.c_void_p, c.c_char_p], c.c_int),
    ("archive_entry_new", [], c.c_void_p),
    ("archive_entry_set_pathname", [c.c_void_p, c.c_char_p], None),
    ("archive_entry_set_mode", [c.c_void_p, c.c_int], None),
    ("archive_entry_set_size", [c.c_void_p, c.c_longlong], None),
    ("archive_entry_set_symlink", [c.c_void_p, c.c_char_p], None),
    ("archive_write_header", [c.c_void_p, c.c_void_p], c.c_int),
    ("archive_write_data", [c.c_void_p, c.c_char_p, c.c_size_t], c.c_ssize_t),
    ("archive_entry_free", [c.c_void_p], None),
    ("archive_write_close", [c.c_void_p], c.c_int),
    ("archive_write_free", [c.c_void_p], c.c_int),
]:
    fn = getattr(lib, name)
    fn.argtypes, fn.restype = args, result


def write(path, names, link=False):
    archive = lib.archive_write_new()
    assert lib.archive_write_set_format_7zip(archive) == 0
    assert lib.archive_write_open_filename(archive, str(path).encode()) == 0
    for name in names:
        entry = lib.archive_entry_new()
        lib.archive_entry_set_pathname(entry, name.encode())
        lib.archive_entry_set_mode(entry, 0o120777 if link else 0o100644)
        data = b"download fixture\n"
        lib.archive_entry_set_size(entry, 0 if link else len(data))
        if link:
            lib.archive_entry_set_symlink(entry, b"../../outside")
        assert lib.archive_write_header(archive, entry) == 0
        if not link:
            assert lib.archive_write_data(archive, data, len(data)) == len(data)
        lib.archive_entry_free(entry)
    assert lib.archive_write_close(archive) == 0
    lib.archive_write_free(archive)


if __name__ == "__main__":
    root = Path(sys.argv[1])
    root.mkdir(parents=True, exist_ok=True)
    write(root / "valid.7z", ["pack/hello.txt", "pack/текст.txt"])
    write(root / "traversal.7z", ["../escaped.txt"])
    write(root / "case.7z", ["pack/FILE.txt", "pack/file.txt"])
    write(root / "reserved.7z", ["pack/CON.txt"])
    write(root / "symlink.7z", ["pack/link"], link=True)
    (root / "invalid.7z").write_bytes(b"not an archive")
