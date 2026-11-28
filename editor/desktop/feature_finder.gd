extends Window

const DialogLayout := preload("res://desktop/dialog_layout.gd")

const EditorTheme := preload("res://desktop/editor_theme.gd")

var _entries: Array
var _workspace: Node
var _surface: ColorRect
var _query: LineEdit
var _results: ItemList
var _path: Label
var _description: Label
var _open_button: Button

func setup(workspace: Node) -> void:
	title = "功能速查"
	transient = true
	exclusive = true
	min_size = Vector2i(320, 220)
	close_requested.connect(hide)
	window_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			hide())
	_workspace = workspace
	_surface = ColorRect.new()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	var scroll := ScrollContainer.new()
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(margin)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	_query = LineEdit.new()
	_query.placeholder_text = "搜索，例如歌词、吸附、音量或快捷键"
	_query.clear_button_enabled = true
	_query.text_changed.connect(_filter)
	_query.text_submitted.connect(func(_value: String): _go())
	column.add_child(_query)
	_results = ItemList.new()
	_results.custom_minimum_size.y = 70
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results.item_selected.connect(_update_detail)
	_results.item_activated.connect(func(_index: int): _go())
	column.add_child(_results)
	_path = Label.new()
	_path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_path)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_description)
	_open_button = Button.new()
	_open_button.text = "前往此处"
	_open_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_open_button.pressed.connect(_go)
	column.add_child(_open_button)

func open() -> void:
	_entries = _commands(_workspace)
	_query.clear()
	_filter("")
	DialogLayout.present(self, Vector2i(630, 420))
	_query.grab_focus()

func apply_theme(value: Theme) -> void:
	theme = value
	_surface.color = EditorTheme.tone("surface")
	_description.add_theme_color_override("font_color", EditorTheme.tone("muted"))
	var selection := StyleBoxFlat.new()
	selection.bg_color = EditorTheme.tone("selected")
	_results.add_theme_stylebox_override("selected", selection)
	_results.add_theme_stylebox_override("selected_focus", selection)

func _filter(query: String) -> void:
	_results.clear()
	for entry: Array in _entries:
		var search := " ".join([entry[0], entry[1], entry[2], entry[4]]).to_lower()
		if _matches(search, query.to_lower()):
			_results.add_item(entry[0])
			_results.set_item_metadata(_results.item_count - 1, entry)
	if _results.item_count:
		_results.select(0)
		_update_detail(0)
	else:
		_path.text = "没有找到匹配的功能"
		_description.text = "可以换一个词，例如「播放」或「设置」。"
		_open_button.disabled = true

func _matches(haystack: String, query: String) -> bool:
	for word: String in query.split(" ", false):
		if not haystack.contains(word):
			return false
	return true

func help_topics(query: String) -> Dictionary:
	var entries := _commands(_workspace)
	var matches := []
	for entry: Array in entries:
		if _matches(" ".join([entry[0], entry[1], entry[2], entry[4]]).to_lower(), query.strip_edges().to_lower()):
			matches.append({"title": entry[0], "menu": entry[1], "instructions": entry[2]})
	return {"topics": matches.slice(0, 30)}

func _update_detail(index: int) -> void:
	var entry: Array = _results.get_item_metadata(index)
	_path.text = entry[1]
	_description.text = entry[2]
	_open_button.disabled = false

func _go() -> void:
	var selected := _results.get_selected_items()
	if selected.is_empty():
		return
	var entry: Array = _results.get_item_metadata(selected[0])
	var action: Callable = entry[3]
	hide()
	action.call_deferred()

func _commands(w: Node) -> Array:
	var file_menu: MenuButton = w._menu.get_child(0).get_child(0)
	return [
		["导入音频", "文件 → 导入音频", "可以拖入音频。导入后的弹窗可调整分析项目或暂不分析。", w._open_audio_dialog, "歌曲 mp3 wav ogg"],
		["导入参考谱", "工具 → 导入参考谱", "将本机谱面的制谱与动画数据加入参考谱库，供助手查询。", w.scripts.open_reference_import, "参考 谱面 动画"],
		["运行脚本", "工具 → 运行 .rpy", "运行可信任的本机制谱脚本。", w.scripts.open_script, "Python rpy 脚本"],
		["Agent 设置", "工具 → Agent 设置", "填写 API 地址、密钥和模型名称。", w.automatic.open_settings, "API 模型 密钥"],
		["一键制谱", "工具 → Revelation Co-pilot → 一键制谱", "在右侧助手底部选择一键制谱，选难度并填写整曲或补谱要求。发送后可逐项审批。", w._set_copilot_visible.bind(true), "Agent 自动写谱 补谱 预置提示词 难度"],
		["MCP 服务器", "工具 → MCP 服务器", "点击「配置 MCP 工作目录」，把返回的目录作为 Codex 或 Claude Code 项目打开。提交草稿时在编辑器内确认。", w.mcp.open, "MCP Codex Claude 外部客户端 工作目录 端口 连接"],
		["Revelation Co-pilot", "工具 → Revelation Co-pilot", "可以说「把 12 秒处的普通键往左移」，也可以指定标尺拍号或选区。展开工具记录可查看命中的音符、重音、响度和频段。", w._set_copilot_visible.bind(true), "助手 AI 对话 编辑 批准 拍号 秒数 响度 频谱"],
		["打开已有谱面", "文件 → 打开已有谱面", "同一个文件框打开 ZIP 谱面包或 JSON 文件。", w._open_chart_dialog, "旧谱 恢复 加载"],
		["导入 LRC 歌词", "文件 → 导入歌词", "选择 LRC 或拖到窗口，按时间生成底部文字事件。", w._open_lyrics_dialog, "字幕 歌词 lrc"],
		["导入背景图片", "文件 → 导入背景图片", "也可以拖入 PNG、JPG 或 JPEG 图片。", w._open_background_dialog, "封面 底图 素材"],
		["保存或导出谱面", "文件 → 保存谱面 / 导出谱面压缩包", "导入歌曲后按 Ctrl+S 保存到当前草稿目录。「另存到目录」可将工程与素材复制到指定位置。ZIP 同时打包谱面、音频和图片。", file_menu.show_popup, "保存目录 另存 导出 交付 游戏 zip json"],
		["导出谱面文件", "文件 → 导出谱面文件", "单独导出 JSON 谱面文件。要连同歌曲和图片一起打包，请选择「导出谱面压缩包」。", file_menu.show_popup, "导出 json 游戏"],
		["渲染 MP4", "文件 → 渲染视频", "将游戏画面、歌曲和打击音效导出为视频。", w._choose_video_path, "录像 录制 mp4"],
		["选择和放置音符", "钢琴卷帘 → 画笔", "在卷帘上沿选择工具。普通键和滑键点一下，长键在同一轨点两次。", w._choose_tool.bind(0), "键 放置 普通键 滑键 长键 右键"],
		["黄键（滑键）", "卷帘画笔 → 滑键", "在判定拍单击空轨，点预览上方「添加滑动路径」，再拖动起点或终点。也可打开「在画面放键」，点击预览决定落点。", w._choose_tool.bind(1), "黄键 滑键 拖键 横滑 路径"],
		["移动和框选音符", "钢琴卷帘 → 选择", "当前方案可用%s移动，%s。" % [w.preferences.move_gesture(), w.preferences.selection_gesture()], w._choose_tool.bind(-1), "拖动 框选 shift ctrl 选择"],
		["音符时间、位置与路径", "检查器 → 键设置", "选中音符后可修改判定、位置、移动路径、缓动和关键帧。", w._open_inspector_page.bind("键设置"), "长键 时长 动画 缓动 坐标"],
		["编辑文字和背景事件", "卷帘画笔 → 文本事件 / 检查器 → 事件", "在卷帘放置文本或换图事件，选中后打开「事件」修改。", w._open_inspector_page.bind("事件"), "封面 底图 字幕 文字"],
		["背景与遮罩", "卷帘画笔 → 背景与遮罩", "定位到目标拍，切换底图、压暗背景或添加圆形揭示。选中轨道片段可循环预览和编辑。", w._set_background_track.bind(true), "动画键 背景 遮罩 关键帧 揭示"],
		["自动采音和力度重音", "检查器 → 自动采音", "单选内容与模型组合。首次点「采音」，有缓存时调整灵敏度后点「应用」。节拍未能填入工程 BPM 时可单选 BPM 采音。", w._open_inspector_page.bind("自动采音"), "自动抓音 分析 鼓点 起音 主旋律 bpm 灵敏度"],
		["分轨试听", "检查器 → 自动采音 → 分轨", "点「分轨」后可在播放中切换人声、鼓组、贝斯、其他伴奏或完整音频。", w._open_inspector_page.bind("自动采音"), "分离 音源 监听 HTDemucs 循环"],
		["参考线和时间吸附", "检查器 → 参考线量化", "选择传统参考线后可填写手动 BPM，点「应用」更新谱面。自动采音线显示上次应用的标记。时间吸附开关在卷帘上沿。", w._open_inspector_page.bind("参考线量化"), "自动吸附 网格吸附 时间轴吸附 手动BPM 速度 bpm 量化 分段"],
		["频谱和旋律结果", "右上 → 频率显示", "在「频谱」查看能量，在「主旋律」查看分析出的音高。", func(): w._results_tabs.current_tab = 2, "音高 频率 横轴"],
		["查看分段情绪", "右上 → 情绪分析", "在 Hub「下载 → 模型管理」安装 Music2Emo，回到编辑器刷新即可分析。表中列出每段的情绪、效价和唤醒度，双击可定位。", func(): w._results_tabs.current_tab = 3, "情绪 情感 Music2Emo 模型"],
		["播放、循环和游戏画面", "右上 → 预览控制", "框选卷帘范围可循环。进入游戏画面后可在右上点「返回编辑」。", _open_preview_menu, "试玩 暂停 循环 选区"],
		["预览位置吸附", "右上 → 谱面预览 → 位置吸附", "拖动预览中的音符时对齐画面网格。分格数在检查器「预览工具」。", w._open_inspector_page.bind("预览工具"), "坐标 拖动 网格 位置"],
		["谱面信息", "检查器 → 谱面信息", "可以填写曲名、难度、曲师及说明。", w._open_inspector_page.bind("谱面信息"), "基本信息 标题 作者"],
		["歌曲延迟和倍速", "检查器 → 音频", "这里设置当前谱面的歌曲、时间偏移和编辑时播放速度。", w._open_inspector_page.bind("音频"), "歌曲 音频 偏移 offset 倍速"],
		["主题与界面缩放", "编辑 → 编辑器偏好设置 → 界面", "选择工作室灰等主题，或根据窗口自动缩放。拖工作区分隔线能调节各区尺寸。", w.preferences.open.bind("界面"), "分辨率 大小 深色 浅色 灰色"],
		["版本更新公告", "帮助 → 版本更新公告", "查看当前版本的更新内容。", w._open_release_notes, "更新 公告 版本 发行"],
		["快捷键和原版方案", "编辑 → 编辑器偏好设置 → 快捷键", "在标准方案和原版方案之间切换，也能逐个修改键位。", w.preferences.open.bind("快捷键"), "键盘 原版 恢复 默认"],
		["声音设备、启动音效和同名歌词", "编辑 → 编辑器偏好设置 → 音频", "选择输出设备，试听或关闭启动音效，也可主动开启同名歌词导入。", w.preferences.open.bind("音频"), "外放 扬声器 耳机 音量 配对"],
		["波形分频、精度和对比度", "编辑 → 编辑器偏好设置 → 波形", "设置卷帘波形显示哪些频段，以及采样精度和对比度。", w.preferences.open.bind("波形"), "波形 取样 低频 高频"],
		["解码工具", "编辑 → 编辑器偏好设置 → 分析工具", "配置 FFmpeg 的路径，留空时自动查找。", w.preferences.open.bind("分析工具"), "ffmpeg 分析失败 解码"],
		["导出错误包", "帮助 → 导出错误包", "将近期编辑操作、报错和运行环境写入 ZIP，便于反馈问题。", w._open_diagnostic_export, "日志 崩溃 诊断 反馈"],
		["查看新手教程", "帮助 → 首次制谱教程 / 原版迁移引导", "首次制谱教程带你走过导入、放置、播放和导出。迁移引导介绍原版常用功能的新位置。", w._onboarding.open_beginner, "入门 教程 使用 帮助"],
	]

func _open_preview_menu() -> void:
	_workspace._results_tabs.current_tab = 0
	_workspace._preview_controls.show_popup()
