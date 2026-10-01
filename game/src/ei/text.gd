class_name EIText
extends RefCounted
## Text helpers. Game strings are 8-bit text in the Windows ANSI code page of
## the edition: the original draws them with GDI fonts made
## (CFont::CreatePointFont, lfCharSet 1 = DEFAULT_CHARSET), so the system code
## page decides — Windows-1251 for the Russian edition, Windows-1252 for the
## English and German ones. `code_page` is set from the installed texts.res
## (detect_code_page) when the game data is opened.

static var code_page := 1251
static var _t1251: PackedStringArray
static var _t1252: PackedStringArray


## Bytes in the edition's code page (stops at a NUL).
static func ansi(bytes: PackedByteArray) -> String:
	return cp1252(bytes) if code_page == 1252 else cp1251(bytes)


static func cp1251(bytes: PackedByteArray) -> String:
	if _t1251.is_empty():
		var hi := "ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—\u0098™љ›њќћџ ЎўЈ¤Ґ¦§Ё©Є«¬­®Ї°±Ііґµ¶·ё№є»јЅѕї"
		for c in hi:
			_t1251.append(c)
		for i in 64:
			_t1251.append(char(0x410 + i))  # А..я
	return _decode(bytes, _t1251)


static func cp1252(bytes: PackedByteArray) -> String:
	if _t1252.is_empty():
		# 0x80..0x9f; 0x81, 0x8d, 0x8f, 0x90, 0x9d are unassigned and kept as C1.
		for c in "€\u0081‚ƒ„…†‡ˆ‰Š‹Œ\u008dŽ\u008f\u0090‘’“”•–—˜™š›œ\u009džŸ":
			_t1252.append(c)
		for i in range(0xa0, 0x100):
			_t1252.append(char(i))   # Latin-1
	return _decode(bytes, _t1252)


static func _decode(bytes: PackedByteArray, table: PackedStringArray) -> String:
	var out := ""
	for b in bytes:
		if b == 0:
			break
		out += char(b) if b < 128 else table[b - 128]
	return out


## The edition's code page from its texts.res: Russian strings are mostly
## bytes 0xc0..0xff (А..я in 1251), the English and German ones mostly ASCII
## letters with a few accented ones (ä ö ü ß in 1252). Samples the "string"
## entries (menus, options, messages).
static func detect_code_page(texts: EIResArchive) -> int:
	if texts == null:
		return 1251
	var ascii := 0
	var high := 0
	for n: String in texts.entries:
		if not n.begins_with("string "):
			continue
		for b in texts.read(n):
			if b >= 0xc0:
				high += 1
			elif (b >= 0x41 and b <= 0x5a) or (b >= 0x61 and b <= 0x7a):
				ascii += 1
	return 1251 if high > ascii else 1252
