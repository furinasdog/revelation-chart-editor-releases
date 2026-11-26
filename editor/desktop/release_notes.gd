extends RefCounted

const ENTRIES := {
	"v1.4.2": [
		"「自动采音」可从完整音频或分轨采集。分轨完成后，在「采音／应用」按钮上方选择人声、鼓组、贝斯或其他伴奏。采音音源可以和试听音源分别选择。",
		"采音结果按音源、内容与模型分别缓存。分轨控件与画笔工具栏之间增加了间距。",
	],
	"v1.4.1": [
		"移除了帮助菜单和新手教程中的「8 拍练习谱」。",
		"Co-pilot 默认可发送工程曲绘。模型明确拒绝图像时，助手会用同一轮的文字和工具记录自动重试。",
		"已连接的 MCP 客户端默认可用工具读取工程曲绘、预览画面和音频图。提交草稿时仍由你确认。",
	],
	"v1.4.0": [
		"在「自动采音」选择一项内容和模型。首次点「采音」，已有缓存时可调整灵敏度后点「应用」。面板显示本次采用的标记数和首个标记时间。",
		"节拍分析会补全空缺的工程 BPM。「参考线量化」可切换传统参考线与自动采音线。",
		"新增 HTDemucs 四轨试听。分轨后可切换人声、鼓组、贝斯、其他伴奏或完整音频，播放头和循环区间会保留。",
		"madmom、Music2Emo 和 HTDemucs 模型统一在 Hub 的「下载 → 模型管理」安装或修复。返回编辑器点「刷新」即可使用。",
		"Co-pilot 和 MCP 的制谱提示加入了重复乐句、段落疏密、双手衔接和跨屏走位的编排经验。",
	],
	"v1.3.0": [
		"草稿支持保存、自动保存和续编。分段 BPM 按本机工程与难度保存。",
		"卷帘右键可跨工程复制音符 JSON、查看手序。框选后可让助手改谱，在提交前循环对比原谱与草稿。",
		"帮助菜单和首次教程加入可重置的 8 拍黄键与背景遮罩练习。",
		"「文件 → 渲染视频」可设置目录、文件名、分辨率、帧率、画质和导出时段。支持多线程并行渲染及 NVIDIA 硬件编码。",
		"编辑器默认使用 CPU 进行 ONNX 推理。可在 Hub 的已安装版本卡片添加或卸载 CUDA 支持。",
		"调整了菜单、检查器标题栏的层次和字号，以及「关于」页面的正文间距。",
	],
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
