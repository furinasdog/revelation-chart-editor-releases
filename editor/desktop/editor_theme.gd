extends RefCounted

const BASE := preload("res://main/ui_theme.tres")
const MENU_FONT_SIZE := 13
const DARK := {
	"menu": Color("#272727"), "heading": Color("#303030"),
	"base": Color("#141414"), "surface": Color("#222222"), "panel": Color("#1c1c1c"),
	"raised": Color("#383838"), "hover": Color("#414141"), "field": Color("#171717"),
	"ink": Color("#e4e4e4"), "muted": Color("#ababab"), "line": Color("#4a4a4a"), "rule": Color("#333333"),
	"accent": Color("#73b6ff"), "selected": Color("#244664"), "beat": Color("#46637e"),
	"subdivision": Color("#34414c"), "capture": Color("#ffc976"), "wave": Color("#5c90b9"),
	"playhead": Color("#ff8585"),
}
const LIGHT := {
	"menu": Color("#d8dade"), "heading": Color("#e4e5e8"),
	"base": Color("#cfd1d5"), "surface": Color("#f5f5f6"), "panel": Color("#ebedef"),
	"raised": Color("#f3f4f5"), "hover": Color("#e0e3e7"), "field": Color("#fbfbfc"),
	"ink": Color("#22262b"), "muted": Color("#515963"), "line": Color("#aeb4bb"), "rule": Color("#d2d6da"),
	"accent": Color("#125a9d"), "selected": Color("#cedff3"), "beat": Color("#467399"),
	"subdivision": Color("#b4c5d4"), "capture": Color("#885000"), "wave": Color("#297fb5"),
	"playhead": Color("#b53142"),
}
const GRAY := {
	"menu": Color("#393939"), "heading": Color("#454545"),
	"base": Color("#232323"), "surface": Color("#383838"), "panel": Color("#303030"),
	"raised": Color("#4a4a4a"), "hover": Color("#535353"), "field": Color("#272727"),
	"ink": Color("#f1f1f1"), "muted": Color("#c1c1c1"), "line": Color("#636363"), "rule": Color("#505050"),
	"accent": Color("#91c5ff"), "selected": Color("#3b526d"), "beat": Color("#5599cf"),
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

static func make() -> Theme:
	var result := BASE.duplicate() as Theme
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
			var source := result.get_stylebox(name, kind) as StyleBoxFlat
			if source:
				var box := source.duplicate() as StyleBoxFlat
				_style_base_box(box, kind, name)
				result.set_stylebox(name, kind, box)
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
	var separator := StyleBoxLine.new()
	separator.color = tone("line")
	result.set_stylebox("separator", "HSeparator", separator)
	var vertical_separator := separator.duplicate() as StyleBoxLine
	vertical_separator.vertical = true
	result.set_stylebox("separator", "VSeparator", vertical_separator)
	# Keep active tabs legible against both the header strip and the panels beneath it.
	for state in ["tab_unselected", "tab_hovered", "tab_selected"]:
		var tab := StyleBoxFlat.new()
		tab.bg_color = Color.TRANSPARENT
		tab.content_margin_left = 9
		tab.content_margin_right = 9
		tab.content_margin_top = 4
		tab.content_margin_bottom = 4
		if state == "tab_selected":
			tab.bg_color = tone("surface")
			tab.border_width_bottom = 2
			tab.border_color = tone("accent")
		elif state == "tab_hovered":
			tab.bg_color = tone("hover")
		for kind in ["TabContainer", "TabBar"]:
			result.set_stylebox(state, kind, tab)
			result.set_color("font_unselected_color", kind, tone("muted"))
			result.set_font_size("font_size", kind, 13)
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
			"hover": brush.bg_color = tone("hover")
			_:
				brush.bg_color = tone("selected")
				brush.border_width_bottom = 2
				brush.border_color = tone("accent")
		result.set_stylebox(state, "TimelineBrush", brush)
	var inspector_panel := result.get_stylebox("panel", "TabContainer").duplicate() as StyleBoxFlat
	inspector_panel.content_margin_left = 10.0
	inspector_panel.content_margin_top = 6.0
	inspector_panel.content_margin_right = 10.0
	result.set_type_variation("DesktopInspectorTabs", "TabContainer")
	result.set_stylebox("panel", "DesktopInspectorTabs", inspector_panel)
	var inspector_tabs := StyleBoxFlat.new()
	inspector_tabs.bg_color = tone("menu")
	result.set_stylebox("tabbar_background", "DesktopInspectorTabs", inspector_tabs)
	_style_inspector_fields(result)
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

static func _style_base_box(box: StyleBoxFlat, kind: String, state: String) -> void:
	var token := "surface"
	match kind:
		"Button", "OptionButton", "MenuButton":
			token = "raised"
			box.set_corner_radius_all(2)
			box.content_margin_left = 8
			box.content_margin_right = 8
		"LineEdit", "TextEdit":
			token = "field"
			box.set_corner_radius_all(2)
		"HScrollBar", "VScrollBar":
			token = "base" if state == "scroll" else "line"
	match state:
		"hover", "grabber_highlight": token = "hover" if state == "hover" else "muted"
		"pressed", "hover_pressed", "grabber_pressed": token = "selected"
		"disabled": token = "panel"
	if box.bg_color.a > 0.0:
		box.bg_color = Color(tone(token), box.bg_color.a)
	if box.border_color.a > 0.0:
		box.border_color = tone("accent") if state in ["focus", "pressed", "hover_pressed"] else tone("line")
	if state == "focus":
		box.draw_center = false

static func _style_inspector_fields(result: Theme) -> void:
	result.set_type_variation("SpinBoxInnerLineEdit", "LineEdit")
	result.set_color("font_color", "SpinBoxInnerLineEdit", tone("accent"))
	result.set_font_size("font_size", "SpinBoxInnerLineEdit", 13)
	var value := result.get_stylebox("normal", "LineEdit").duplicate() as StyleBoxFlat
	value.bg_color = tone("field")
	value.border_color = tone("rule")
	value.content_margin_left = 5
	value.content_margin_right = 5
	value.content_margin_top = 2
	value.content_margin_bottom = 2
	result.set_stylebox("normal", "SpinBoxInnerLineEdit", value)
	result.set_stylebox("read_only", "SpinBoxInnerLineEdit", value)
	result.set_type_variation("InspectorSection", "Button")
	result.set_font_size("font_size", "InspectorSection", 13)
	for state in ["normal", "pressed", "hover", "hover_pressed"]:
		var section := StyleBoxFlat.new()
		section.bg_color = tone("hover") if "hover" in state else tone("heading")
		section.border_color = tone("rule")
		section.border_width_bottom = 1
		section.content_margin_left = 7
		section.content_margin_right = 7
		section.content_margin_top = 3
		section.content_margin_bottom = 3
		result.set_stylebox(state, "InspectorSection", section)
