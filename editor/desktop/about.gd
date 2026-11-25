extends Window

const LICENSE_ROOT := "res://licenses/"
const SOURCES := {
	"桌面分支自有代码（GPL-3.0-only）": "FFmpeg-COPYING-GPLv3.txt",
	"Godot": "Godot-LICENSE.txt",
	"ONNX Runtime": "ONNXRuntime-LICENSE.txt",
	"Beat This!": "BeatThis-LICENSE.txt",
	"FFmpeg": "FFmpeg-COPYING-GPLv3.txt",
	"Essentia": "AGPL-3.0.txt",
	"madmom-infer": "MADMOM-INFER-BSD-2.txt",
	"madmom C++ 移植": "MADMOM-BEATS-PORT-BSD-2.txt",
	"Music2Emo C++ 移植": "Music2Emo-MIT.txt",
}
const THIRD_PARTY := {
	"组件出处": "Revelation-Native-Audio-NOTICE.md",
	"madmom 模型": "MADMOM-MODELS-CC-BY-NC-SA-4.0.txt",
	"madmom 移植声明": "MADMOM-BEATS-PORT-NOTICE.txt",
	"Music2Emo 与 MERT 模型": "Music2Emo-NOTICE.txt",
	"RMVPE 原始项目": "RMVPE-Apache-2.0.txt",
	"RMVPE ONNX 权重": "RMVPE-MIT.txt",
	"Godot 第三方声明": "Godot-COPYRIGHT.txt",
	"ONNX Runtime 第三方声明": "ONNXRuntime-ThirdPartyNotices.txt",
	"FFmpeg 对应源码": "FFmpeg-Source.txt",
}

func _ready() -> void:
	title = "关于更好的制谱器"
	transient = true
	exclusive = true
	min_size = Vector2i(320, 175)
	close_requested.connect(hide)
	var tabs := TabContainer.new()
	tabs.theme_type_variation = &"DesktopAboutTabs"
	add_child(tabs)
	tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tabs.offset_left = 12
	tabs.offset_top = 10
	tabs.offset_right = -12
	tabs.offset_bottom = -12
	var scroll := ScrollContainer.new()
	scroll.name = "版本信息"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var version := VBoxContainer.new()
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version.add_theme_constant_override("separation", 7)
	scroll.add_child(version)
	for line: String in [
		"更好的制谱器 v%s" % ProjectSettings.get_setting("application/config/version", ""),
		"Revelation 桌面谱面编辑器",
		"分支作者：短夜月",
		"桌面分支自有代码采用 GPL-3.0-only，第三方组件沿用各自许可。",
		"Godot %s" % Engine.get_version_info().string,
		"%s  ·  %s" % [OS.get_name(), RenderingServer.get_current_rendering_method()],
		"音频分析  ·  Beat This!、madmom、Essentia、Music2Emo、RMVPE",
	]:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = line
		version.add_child(label)
	var brand := TextureRect.new()
	brand.texture = preload("res://icon.png")
	brand.custom_minimum_size = Vector2(76, 76)
	brand.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	brand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	brand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	version.add_child(brand)
	_add_licenses(tabs, "开源软件许可", SOURCES)
	_add_licenses(tabs, "第三方许可与声明", THIRD_PARTY)

func _add_licenses(tabs: TabContainer, title_text: String, files: Dictionary) -> void:
	var page := VBoxContainer.new()
	page.name = title_text
	tabs.add_child(page)
	var choose := OptionButton.new()
	choose.fit_to_longest_item = false
	choose.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	page.add_child(choose)
	var text := TextEdit.new()
	text.editable = false
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(text)
	for label: String in files:
		choose.add_item(label)
	var load_text := func(index: int):
		var path := LICENSE_ROOT + str(files.values()[index])
		text.text = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "找不到对应的许可文件。"
	choose.item_selected.connect(load_text)
	choose.select(0)
	load_text.call(0)
