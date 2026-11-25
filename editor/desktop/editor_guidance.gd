extends RefCounted

const PRIORITY := """优先顺序：.rpy > 单项工具 > 直接编辑工程。批量查询、位置设计、变换和关联修改优先用 run_rpy 处理；单步读取、音频导入、推理、取图和最终校验使用相应工具。仅在编辑器接口确实无法完成、且用户明确授权时，才考虑编辑工程文件。工程在编辑器中打开时，先确认不会覆盖未保存修改。读取和回答问题无需修改工程。"""
const DIRECT := """内置 Co-pilot 使用直接工具。修改几个音符时，先读选中音符编号或所需时间段，再把同类修改合并成一次工具调用。移动时间用 move_notes，移动位置用 set_positions，延长滑动距离用 scale_hold_paths，改变松开时间用 resize_holds。读取和回答问题无需修改工程。检查冲突后用 finish 应用已批准的修改。"""

const CHARTING := """这是浮现式音游。音符可出现在全屏任意位置，玩家按实际落点接键。按乐句安排左右手，用缩圈和连续走位预告下一键，跨屏前留出移手和转移视线的时间。先选要表现的声部，落句首、重音和句尾，再按实测起音补细分拍。用 get_chart_statistics 对照相邻乐句的疏密与音频起伏。舒展段可用少量长键承接延音，节奏变密时再增加单点和滑键。旋律上扬时，横排双键后可接斜上方（屏幕 y 减小）的单键，下行则接斜下方；平稳段可同高横移。困难谱常用双键与三键，留出单键或空拍，高潮重拍最多四键。
长键：用持续音和乐句收尾决定什么时候松手。新写移动长键时，给滑动可辨认的距离，例如在 1920×1080 画板上，用两到四拍走约 240–420 像素的横线或浅弧，再按节奏、手速和下一键的位置调整；静止长键可留给平稳长音。拉长已有长键的滑动距离时，用 scale_hold_paths，按选中的长键编号或时间段限定范围；想改形状或给静止长键安排移动时，用 set_hold_path。先读路径、坐标、判定与松开时间。可从 1.2–1.3 倍试起，保持判定、松开和预告时间，避免出界或和相邻键交叉。只有用户要求延长按住时间时才用 resize_holds。最后用 check_conflicts 校验。隔拍重复落点和横向滑键占比属于编排建议，可以保留有意的处理，同时按需修复阻止提交的实际冲突。"""

const RPY := """run_rpy 接收 source，以及可选的 from_ms、to_ms 和 references。不需要 import。chart.notes(start,end,kind,offset,limit) 读草稿，chart.read(section) 读工程 / 事件 / 动画等快照；chart.pitch(source,detail) 读音高，chart.reference(key) 读预先传入的参考谱查询，chart.linspace(...) 生成等距值。用 chart.edit(\"set_positions\", notes=updates) 等写入草稿，result(value) 返回结构化结果。支持受限的 Python 循环和条件判断。时间以谱面毫秒计，画板 1920×1080，轨道从 0 开始。先用只读脚本确定范围，再用短脚本应用；按时间和页数限制结果。一段参考示例：

from_ms = 32000
to_ms = 46000
holds = chart.notes(from_ms, to_ms, kind=\"hold\")
if holds:
    chart.scale_hold_paths(from_ms, to_ms, 1.3)
result({\"holds\": len(holds), \"path_scale\": 1.3})

横排双键接斜上单键的写入示例。实际时间要用歌曲分析结果替换，先检查该区间的现有音符：
chart.edit(\"add_notes\", notes=[
    {\"type\": \"note\", \"time_ms\": 5000, \"lane\": 2, \"x\": 700, \"y\": 620},
    {\"type\": \"note\", \"time_ms\": 5000, \"lane\": 4, \"x\": 1060, \"y\": 620},
    {\"type\": \"note\", \"time_ms\": 5600, \"lane\": 5, \"x\": 1190, \"y\": 455},
])"""

const AUDIO := """需要音频且用户已经提供本机文件时，先单独调用 import_audio(path)，等待编辑器确认；如果当前有待提交的草稿，先处理草稿。导入会替换当前工程音频并使旧分析失效，保留谱面音符，随后重新读取工程数据。根据任务调用 analyze_audio 或读取已有缓存。只接受用户明确指定的本机 WAV、MP3、OGG 文件。"""

const SPACING := """借鉴 Phigros 随乐句引导视线的思路。用 list_notes 的判定坐标 x、y 安排落点，卷帘轨道仅供编辑。同一手势内用相邻落点，句尾或空拍再换区。重复乐句可沿用相对拍位，只将落点左右镜像或改变弧线方向。转段前可把上一句末次单点换成长键，提前引出下一句的手势。连续双滑先排一侧，再等距平移另一侧，让两手同向转折。由下一键倒推长键终点，松开后可在原位接滑。用 list_note_paths 核对实际路径，用 locate_notes 检查长键头尾和快滑中间相差几毫秒的额外判定，复核占手、可达距离与遮挡。按当前难度和拍长调整间距。check_conflicts 的中心集中提示是警告，有意聚焦的段落可以保留。"""
const MASKS := """用户需要背景遮罩动画且动画工具可用时，先用 list_artwork 和 list_animation_layers 确认底图、现有遮罩和切换时间，再用 get_animation_cues 找乐句转折。背景可沿用连续双滑的节奏，让细线按同一间隔依次展开，起始时刻与判定稍微错开，给可玩音符留出视线。比如在一段副歌前调用 create_solid_mask(color="#18202C", opacity=0.75)，把返回的 mask_id 交给 set_mask_cue，time_ms 选在转折前。有已选曲绘时传实际 artwork_id，沿用现有底图则省略。转折处调用 add_mask_reveal，在曲绘主体附近用约两拍展开并收回圆形窗口，duration_ms 取 700–12000 且不越过曲尾。收回后原遮罩仍生效，想恢复常亮可在下一句切换到更透明的遮罩。预览开场、展开和收回三处，检查黄键、缩圈与长键尾的对比度；具备取帧权限时使用 view_rendered_frames。"""
const WORKFLOW := """把谱师给的标尺、时码和选区当成任务坐标。局部编辑先按目标定位一次，例如“12s 的音符”直接用 locate_notes({"seconds":12})，“第25拍”用 {"ruler_beat":25}。截图同列的“25 / 0:12.0”是同一位置的两种表示，可同时传入。时码是谱面时间，使用当前变速表，工具已处理音频偏移。检查精确判定、同时键、跨过此处的长键以及选中状态。附近候选用 delta_ms 说明偏差。指定的键不唯一且不同选择会改变结果时，列出具体候选让谱师选择。按返回 ID 批量修改，回读草稿确认，finish 自带冲突校验。向谱师报告标尺位置、音符和实际改动。
创作或重排乐句时，先用 get_audio_features 读目标和相邻乐句的同一组时间窗。将拍点作为计时参考，用实测重音和起音选击打点，用响度变化分配疏密，用低中高频能量变化和音高持续时间决定主次、键型、走位与留白。分辨鼓击、旋律延音和高频装饰时结合这些证据。缺少必要数据时只补相应分析，反馈中标出缺项；可用频谱图时按需核对。机械改坐标或时长可直接编辑。整曲按乐句设计，seed_pattern 只在用户明确需要自动铺底时用。"""
const QUICK := PRIORITY + "\n" + WORKFLOW + "\n" + CHARTING + "\n" + SPACING + "\n" + MASKS + "\n" + AUDIO + "\n使用 get_editing_guide 或 revelation-charting 提示模板获得 .rpy 示例。MCP 改动进入当前会话草稿，finish 请求用户确认。"
const FULL := PRIORITY + "\n\n" + WORKFLOW + "\n\n" + RPY + "\n\n" + CHARTING + "\n\n" + SPACING + "\n\n" + MASKS + "\n\n" + AUDIO
const EDITOR := DIRECT + "\n\n" + WORKFLOW + "\n\n" + CHARTING + "\n\n" + SPACING + "\n\n" + AUDIO
const PROMPT_NAME := "revelation-charting"

static func prompt_list() -> Dictionary:
	return {"prompts": [{"name": PROMPT_NAME, "title": "Revelation 制谱与 .rpy",
		"description": "制谱工作流、脚本 API 示例、空间走位、长键路径、音频导入与草稿提交。"}]}

static func prompt_get() -> Dictionary:
	return {"description": "Revelation 制谱与 .rpy", "messages": [{"role": "user",
		"content": {"type": "text", "text": FULL}}]}
