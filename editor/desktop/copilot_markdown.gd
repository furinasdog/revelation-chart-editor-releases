extends RefCounted

static var _inline := RegEx.create_from_string(r"`([^`\n]+)`|\*\*([^*\n]+)\*\*|\*([^*\n]+)\*|\[([^\]\n]+)\]\((https?://[^)\s]+)\)")

static func render(label: RichTextLabel, source: String) -> void:
	label.clear()
	var code := false
	var first := true
	for raw in source.replace("\r\n", "\n").split("\n"):
		var line := str(raw)
		if line.strip_edges().begins_with("```"):
			code = not code
			continue
		if not first:
			label.add_text("\n")
		first = false
		if code:
			label.push_mono()
			label.add_text(line)
			label.pop()
			continue
		var depth := 0
		while depth < mini(6, line.length()) and line[depth] == "#":
			depth += 1
		var heading := depth > 0 and line.substr(depth).begins_with(" ")
		if heading:
			label.push_bold()
			line = line.substr(depth + 1)
		elif line.begins_with("- ") or line.begins_with("* "):
			line = "• " + line.substr(2)
		var pos := 0
		for token: RegExMatch in _inline.search_all(line):
			label.add_text(line.substr(pos, token.get_start() - pos))
			if token.get_start(4) >= 0:
				label.add_text(token.get_string(4) + " (" + token.get_string(5) + ")")
			else:
				var group := 1 if token.get_start(1) >= 0 else (2 if token.get_start(2) >= 0 else 3)
				if group == 1:
					label.push_mono()
				elif group == 2:
					label.push_bold()
				else:
					label.push_italics()
				label.add_text(token.get_string(group))
				label.pop()
			pos = token.get_end()
		label.add_text(line.substr(pos))
		if heading:
			label.pop()
