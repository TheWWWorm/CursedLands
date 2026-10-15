class_name WikiHtml
extends RefCounted
## Small, offline HTML reader for encyclopedia articles. The document is data:
## no scripts, CSS execution, network requests, files or external navigation.
## Original text is escaped by WikiCatalog, then escaped again for BBCode here.

static func to_bbcode(html: String, scale := 1.0) -> String:
	var parser := XMLParser.new()
	if parser.open_buffer(html.to_utf8_buffer()) != OK: return ""
	var out := ""
	var skipped := 0
	var anchors: Array[bool] = []
	while parser.read() == OK:
		var type := parser.get_node_type()
		if type == XMLParser.NODE_ELEMENT:
			var tag := parser.get_node_name().to_lower()
			if skipped > 0:
				if not parser.is_empty(): skipped += 1
				continue
			if tag in ["figure", "script", "style", "head"]:
				if not parser.is_empty(): skipped = 1
				continue
			match tag:
				"h1": out += "[font_size=%d][b]" % roundi(28 * scale)
				"h2": out += "[font_size=%d][b]" % roundi(21 * scale)
				"strong", "b": out += "[b]"
				"em", "i": out += "[i]"
				"code": out += "[code]"
				"br": out += "\n"
				"li": out += "• "
				"table":
					var columns := clampi(parser.get_named_attribute_value_safe("data-columns").to_int(), 1, 8)
					out += "[table=%d]" % columns
				"td": out += "[cell]"
				"th": out += "[cell][b]"
				"a":
					var href := parser.get_named_attribute_value_safe("href")
					var allowed := not key_from_url(href).is_empty()
					anchors.append(allowed)
					if allowed: out += "[url=%s]" % href
		elif type == XMLParser.NODE_ELEMENT_END:
			if skipped > 0:
				skipped -= 1
				continue
			match parser.get_node_name().to_lower():
				"h1", "h2": out += "[/b][/font_size]\n\n"
				"strong", "b": out += "[/b]"
				"em", "i": out += "[/i]"
				"code": out += "[/code]"
				"p", "ul": out += "\n\n"
				"li": out += "\n"
				"table": out += "[/table]\n\n"
				"td": out += "  [/cell]"
				"th": out += "  [/b][/cell]"
				"a":
					if not anchors.is_empty() and anchors.pop_back(): out += "[/url]"
		elif type == XMLParser.NODE_TEXT and skipped == 0:
			out += parser.get_node_data().replace("[", "[lb]")
	return out.strip_edges()


static func key_from_url(url: String) -> String:
	if not url.begins_with("wiki://"): return ""
	var key := url.trim_prefix("wiki://")
	# Generated navigation has no raw brackets, quotes, whitespace or path
	# traversal. In particular it cannot break out of a RichTextLabel URL tag.
	for c: String in ["[", "]", '"', "'", "<", ">", " ", "\n", "\r", "\t", "..", "\\"]:
		if c in key: return ""
	return key
