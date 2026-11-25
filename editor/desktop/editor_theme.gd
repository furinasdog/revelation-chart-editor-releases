extends RefCounted

const BASE := preload("res://main/ui_theme.tres")
const MENU_FONT_SIZE := 13
const DARK := {
	"menu": Color("#171d28"), "heading": Color("#202734"),
	"base": Color("#11151c"), "surface": Color("#202734"), "panel": Color("#171d27"),
	"ink": Color("#e0e7f2"), "muted": Color("#a9b6c9"), "line": Color("#344155"),
	"accent": Color("#7bbcff"), "selected": Color("#294d72"), "beat": Color("#3d83ba"),
	"subdivision": Color("#32475e"), "capture": Color("#ffc976"), "wave": Color("#4595cd"),
	"playhead": Color("#ff8585"),
}
const LIGHT := {
	"menu": Color("#cbd6e3"), "heading": Color("#e0e8f1"),
	"base": Color("#e7edf4"), "surface": Color("#f8fafd"), "panel": Color("#edf2f8"),
	"ink": Color("#15253a"), "muted": Color("#445a72"), "line": Color("#b9c7d7"),
	"accent": Color("#125b9e"), "selected": Color("#c9e3fd"), "beat": Color("#2576ad"),
	"subdivision": Color("#b4cce0"), "capture": Color("#885000"), "wave": Color("#297fb5"),
	"playhead": Color("#b53142"),
}
const GRAY := {
	"menu": Color("#282828"), "heading": Color("#454545"),
	"base": Color("#242424"), "surface": Color("#383838"), "panel": Color("#2d2d2d"),
	"ink": Color("#f1f1f1"), "muted": Color("#bababa"), "line": Color("#535353"),
	"accent": Color("#8ab8f8"), "selected": Color("#3b526d"), "beat": Color("#5599cf"),
	"subdivision": Color("#3d576c"), "capture": Color("#ffcd80"), "wave": Color("#6da9d0"),
	"playhead": Color("#ff8989"),
}

static var light := false
static var gray := false
static var _font: SystemFont

static func use_light(mode: String) -> bool:
	return mode == "light" or (mode == "system" and DisplayServer.is_dark_mode_supported() and not DisplayServer.is_dark_mode())

static func tone(key: String) -> Color:
	return (LIGHT if light else (GRAY if gray else DARK))[key]

static func surface(color: Color) -> Color:
	if color.a == 0.0 or (not light and not gray):
		return color
	var value := color.get_luminance()
	if gray:
		var gray_surface := tone("base") if value < 0.012 else (tone("surface") if value > 0.028 else tone("panel"))
		if color.b - color.r > 0.12:
			gray_surface = tone("selected")
		return Color(gray_surface, color.a)
	var shade := tone("surface") if value < 0.024 else tone("panel")
	if color.b - color.r > 0.10:
		shade = tone("selected")
	return Color(shade, color.a)

static func make() -> Theme:
	var result := BASE.duplicate(true) as Theme
	if not _font:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC"])
		_font.hinting = TextServer.HINTING_NORMAL
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	result.default_font = _font
	result.default_font_size = 14
	for kind in ["Button", "CheckBox", "LineEdit", "OptionButton", "TextEdit"]:
		result.set_font_size("font_size", kind, 14)
	result.set_type_variation("DesktopMenuPopup", "PopupMenu")
	result.set_font_size("font_size", "DesktopMenuPopup", result.default_font_size)
	result.set_constant("v_separation", "DesktopMenuPopup", 8)
	result.set_type_variation("DesktopTopMenu", "MenuButton")
	result.set_type_variation("DesktopCommandPopup", "DesktopMenuPopup")
	for kind in ["DesktopTopMenu", "DesktopCommandPopup"]:
		result.set_font_size("font_size", kind, MENU_FONT_SIZE)
	for kind in result.get_type_list():
		for name in result.get_stylebox_list(kind):
			var box := result.get_stylebox(name, kind) as StyleBoxFlat
			if box and (light or gray):
				box.bg_color = surface(box.bg_color)
				if box.border_color.a:
					box.border_color = tone("accent") if "focus" in name or "pressed" in name else tone("line")
		for name in result.get_color_list(kind):
			if "font" in name or name in ["caret_color", "font_outline_color"]:
				result.set_color(name, kind, tone("muted") if "disabled" in name else tone("ink"))
	for kind in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton", "Label", "LineEdit",
			"SpinBox", "PopupMenu", "TabBar", "TabContainer", "TextEdit", "Window", "Tree", "ItemList", "FileDialog"]:
		for name in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_selected_color", "title_color"]:
			result.set_color(name, kind, tone("ink"))
		result.set_color("font_disabled_color", kind, tone("muted"))
	# Godot uses different hover color keys for tabs, list items, and pressed buttons.
	for kind in ["TabBar", "TabContainer", "Tree", "ItemList"]:
		result.set_color("font_hovered_color", kind, tone("ink"))
	for kind in ["Tree", "ItemList"]:
		result.set_color("font_hovered_selected_color", kind, tone("ink"))
	result.set_color("font_hovered_dimmed_color", "Tree", tone("muted"))
	for kind in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		result.set_color("font_hover_pressed_color", kind, tone("ink"))
	# A single marked edge keeps the active page visible among dense inspector tabs.
	for state in ["tab_unselected", "tab_hovered", "tab_selected"]:
		var tab := StyleBoxFlat.new()
		tab.bg_color = tone("surface") if state != "tab_unselected" else Color.TRANSPARENT
		tab.content_margin_left = 9
		tab.content_margin_right = 9
		tab.content_margin_top = 4
		tab.content_margin_bottom = 4
		if state == "tab_selected":
			tab.border_width_bottom = 2
			tab.border_color = tone("accent")
		for kind in ["TabContainer", "TabBar"]:
			result.set_stylebox(state, kind, tab)
			result.set_color("font_unselected_color", kind, tone("muted"))
	result.set_type_variation("TimelineBrush", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var brush := StyleBoxFlat.new()
		brush.content_margin_left = 7
		brush.content_margin_right = 7
		brush.content_margin_top = 4
		brush.content_margin_bottom = 4
		brush.set_corner_radius_all(3)
		match state:
			"normal": brush.bg_color = Color.TRANSPARENT
			"hover": brush.bg_color = tone("surface")
			_:
				brush.bg_color = tone("selected")
				brush.border_width_bottom = 2
				brush.border_color = tone("accent")
		result.set_stylebox(state, "TimelineBrush", brush)
	var inspector_panel := result.get_stylebox("panel", "TabContainer").duplicate() as StyleBoxFlat
	if light or gray:
		inspector_panel.bg_color = tone("surface")
	inspector_panel.content_margin_left = 10.0
	inspector_panel.content_margin_top = 8.0
	inspector_panel.content_margin_right = 10.0
	result.set_type_variation("DesktopInspectorTabs", "TabContainer")
	result.set_stylebox("panel", "DesktopInspectorTabs", inspector_panel)
	var about_panel := result.get_stylebox("panel", "TabContainer").duplicate() as StyleBoxFlat
	about_panel.content_margin_left = 18
	about_panel.content_margin_right = 18
	about_panel.content_margin_top = 12
	about_panel.content_margin_bottom = 12
	result.set_type_variation("DesktopAboutTabs", "TabContainer")
	result.set_stylebox("panel", "DesktopAboutTabs", about_panel)
	result.set_stylebox("read_only", "LineEdit", result.get_stylebox("normal", "LineEdit"))
	result.set_color("font_uneditable_color", "LineEdit", tone("muted"))
	for pair in [["panel", "PopupMenu"], ["panel", "PopupPanel"], ["panel", "AcceptDialog"], ["embedded_border", "Window"],
			["embedded_unfocused_border", "Window"], ["panel", "Tree"], ["panel", "ItemList"], ["normal", "TextEdit"]]:
		var box := StyleBoxFlat.new()
		box.bg_color = tone("surface")
		box.border_color = tone("line")
		box.set_border_width_all(1)
		box.set_content_margin_all(5)
		if pair[1] == "Window":
			box.set_expand_margin_all(4)
			box.expand_margin_top = 26
		result.set_stylebox(pair[0], pair[1], box)
	return result
