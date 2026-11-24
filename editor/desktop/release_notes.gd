extends RefCounted

const ENTRIES := {
	"v1.2.0": [
		"在「工具 → Revelation Co-pilot」勾选「自动审批」后，独立审查助手会按本轮要求核对工具调用。读取直接执行，明确越界的操作会被拒绝，需要判断时会请你确认。",
		"Co-pilot 的回复支持 Markdown 标题、列表、强调和代码。浮现式制谱会结合重音、响度和频谱安排落点，并考虑左右手手序、长键占手和跨屏引导。",
		"检查器已移除废弃的「预览设置」页。仍可在主工作区预览谱面、播放时间轴和渲染视频。",
	],
	"v1.1.1": [
		"Agent 设置根据表单内容确定高度。拖动边缘可以缩小窗口，空间不足时可滚动表单，保存和取消始终位于底部。",
		"修正高 DPI 和紧凑窗口下的弹窗布局。偏好设置、一键制谱、MCP、功能速查、缓动编辑及分析进度使用当前可用区域。",
	],
	"v1.1.0": [
		"Co-pilot 底部新增「一键制谱」。选择 EZ、HD 或 EX，填写整曲或局部补谱要求，确认后由助手编写草稿。",
		"首次制谱教程可直接打开 Agent 设置、填写 API Key，并练习从工具菜单进入助手。",
		"时间标尺定位、重音和频段分析可用于补谱；检查器与教程适配紧凑窗口。",
	],
	"v0.4.0": [
		"困难制谱以双键、三键和四键组合为主，保留独立长键和释放间隔。",
		"Revelation Co-pilot 完成请求后自动收起过程，点标题即可重看。",
		"Agent 优先流式响应，连接中断可以重试当前轮，长任务会整理较早的工具记录。",
		"首次设置和编辑器偏好设置新增工作室灰主题。",
		"改进了谱面压缩包检查和大素材加载，Music2Emo 支持低内存推理。",
	],
}

static func should_show(current: String, previous: String, has_preferences: bool) -> bool:
	if current == previous or not ENTRIES.has(current):
		return false
	if previous.is_empty():
		return has_preferences
	var next := current.trim_prefix("v")
	var last := previous.trim_prefix("v")
	var next_count := next.get_slice_count(".")
	var last_count := last.get_slice_count(".")
	for index in range(maxi(next_count, last_count)):
		var left := next.get_slice(".", index).to_int() if index < next_count else 0
		var right := last.get_slice(".", index).to_int() if index < last_count else 0
		if left != right:
			return left > right
	return false
