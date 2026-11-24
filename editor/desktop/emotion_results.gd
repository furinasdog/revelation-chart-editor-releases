extends VBoxContainer

signal analyze_requested
signal models_requested
signal download_requested
signal segment_chosen(time_ms: int)

const LABELS := {
	"action": "动感", "adventure": "冒险", "advertising": "广告感", "ambient": "氛围感", "background": "背景感",
	"ballad": "抒情", "calm": "平静", "children": "童趣", "christmas": "圣诞氛围", "commercial": "商业感",
	"cool": "酷感", "corporate": "企业宣传感", "dark": "阴暗", "deep": "深沉", "documentary": "纪录片感",
	"drama": "戏剧感", "dramatic": "戏剧感", "dream": "梦幻", "emotional": "感性", "energetic": "充满活力",
	"epic": "宏大", "fast": "轻快", "film": "电影感", "fun": "有趣", "funny": "诙谐",
	"game": "游戏感", "groovy": "律动感", "happy": "快乐", "heavy": "厚重", "holiday": "节日感",
	"hopeful": "希望", "inspiring": "鼓舞", "intense": "强烈", "love": "爱意", "meditative": "冥想感",
	"melancholic": "忧郁", "melodic": "旋律感", "motivational": "励志", "movie": "电影感", "nature": "自然感",
	"party": "派对感", "peaceful": "安宁", "positive": "积极", "powerful": "有力量", "relaxing": "放松",
	"retro": "复古", "romantic": "浪漫", "sad": "悲伤", "sexy": "性感", "slow": "舒缓",
	"soft": "柔和", "soundscape": "声景", "space": "太空感", "sport": "运动感", "summer": "夏日感",
	"suspense": "悬疑", "trailer": "预告片感", "travel": "旅行感", "upbeat": "欢快", "uplifting": "振奋",
}

var _table: Tree
var _status: Label
var _run: Button
var _models: Button
var _download: Button
var _downloading := false
var _keys: Array = []

func setup() -> void:
	var title := Label.new()
	title.text = "Music2Emo · 分段情绪"
	add_child(title)
	var header := HFlowContainer.new()
	add_child(header)
	_run = Button.new()
	_run.text = "分析情绪"
	_run.pressed.connect(analyze_requested.emit)
	header.add_child(_run)
	_download = Button.new()
	_download.text = "下载模型"
	_download.tooltip_text = "约 152 MiB。MERT 权重仅限非商业用途。"
	_download.pressed.connect(download_requested.emit)
	header.add_child(_download)
	_models = Button.new()
	_models.text = "模型目录…"
	_models.pressed.connect(models_requested.emit)
	header.add_child(_models)
	var licenses := LinkButton.new()
	licenses.text = "模型与许可"
	licenses.uri = "https://github.com/furinasdog/music2emo-native/releases/tag/models-v1"
	header.add_child(licenses)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_table = Tree.new()
	_table.columns = 4
	_table.hide_root = true
	_table.column_titles_visible = true
	for index in range(4):
		_table.set_column_title(index, ["时间范围", "情绪标签（置信分数）", "效价", "唤醒度"][index])
		_table.set_column_expand(index, index == 1)
		_table.set_column_custom_minimum_width(index, [108, 115, 46, 52][index])
	_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table.item_activated.connect(func():
		var item := _table.get_selected()
		if item:
			segment_chosen.emit(item.get_metadata(0)))
	add_child(_table)

func refresh(chart: Node, installed: bool, running: bool, feedback: String) -> void:
	_run.disabled = running or chart.audio_path.is_empty() or not installed
	_download.visible = _downloading or not installed
	var segments: Array = chart.rhythm_analysis.get("emotions", [])
	_status.text = feedback if not feedback.is_empty() else (
		"约每 30 秒标注一次。效价表示情绪正负，唤醒度表示激活强度，均为 1–9。双击一行可定位时间轴。"
		if installed or not segments.is_empty() else "首次使用需下载约 152 MiB。MERT 权重仅限非商业用途。")
	var delay := roundi(chart.audio_delay_ms)
	if _keys == [delay, segments]:
		return
	_keys = [delay, segments]
	_table.clear()
	var root := _table.create_item()
	for segment: Dictionary in segments:
		var row := _table.create_item(root)
		var first := maxi(0, int(segment.time_ms) + delay)
		var end := maxi(first, int(segment.end_ms) + delay)
		row.set_text(0, "%s – %s" % [_time(first), _time(end)])
		row.set_metadata(0, first)
		var tags := PackedStringArray()
		for tag: Dictionary in segment.tags:
			tags.append("%s %.0f%%" % [LABELS.get(tag.label, tag.label), tag.score * 100])
		row.set_text(1, " · ".join(tags))
		row.set_text(2, "%.1f" % segment.valence)
		row.set_text(3, "%.1f" % segment.arousal)

func set_downloading(active: bool) -> void:
	_downloading = active
	_download.text = "正在下载…" if active else "下载模型"
	_download.disabled = active
	_models.disabled = active

static func _time(ms: int) -> String:
	@warning_ignore("integer_division")
	return "%d:%04.1f" % [ms / 60000, float(ms % 60000) / 1000.0]
