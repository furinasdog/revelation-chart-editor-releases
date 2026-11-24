extends RefCounted

const PROPERTIES := {
	"pos": "位置", "radius": "半径", "feather": "羽化", "color": "颜色",
	"sharpness": "锐度", "brightness": "亮度", "set": "瞬间设置",
	"width": "宽度", "height": "高度", "rgba": "颜色与透明度",
	"rotation": "旋转", "image": "图片", "bgAnim": "背景动画",
	"motion": "移动", "linear": "直线", "bezier": "贝塞尔曲线", "arc": "圆弧",
	"ninepatch": "九宫格切分", "scale": "等比缩放",
	"x": "横坐标", "y": "纵坐标",
}

const EASINGS := {
	"LINEAR": "线性", "SINE": "正弦", "QUAD": "二次", "CUBIC": "三次",
	"QUART": "四次", "QUINT": "五次", "EXPO": "指数", "CIRC": "圆弧",
	"BACK": "回拉", "ELASTIC": "弹性", "BOUNCE": "反弹", "SPRING": "弹簧",
}

static func property_name(key: String) -> String:
	return PROPERTIES.get(key, "自定义属性")

static func easing_name(name: String) -> String:
	return EASINGS.get(name.to_upper(), name)

static func group_name(name: String) -> String:
	if name == "none":
		return "无"
	if name.begins_with("default") and name.substr(7).is_valid_int():
		return "预设组 %s" % name.substr(7)
	if name.begins_with("key") and name.substr(3).is_valid_int():
		return "动画资源 %s" % name.substr(3)
	return name

static func shortcut(event: InputEventKey) -> String:
	var parts := PackedStringArray()
	if event.ctrl_pressed:
		parts.append("控制")
	if event.shift_pressed:
		parts.append("上档")
	if event.alt_pressed:
		parts.append("换档")
	if event.meta_pressed:
		parts.append("系统")
	var key := int(event.keycode)
	var names := {
		KEY_ESCAPE: "退出键", KEY_TAB: "切换键", KEY_BACKTAB: "反向切换键",
		KEY_BACKSPACE: "退格", KEY_ENTER: "回车", KEY_KP_ENTER: "小键盘回车",
		KEY_SPACE: "空格", KEY_UP: "上", KEY_DOWN: "下", KEY_LEFT: "左", KEY_RIGHT: "右",
		KEY_INSERT: "插入", KEY_DELETE: "删除", KEY_HOME: "行首", KEY_END: "行尾",
		KEY_PAGEUP: "上一页", KEY_PAGEDOWN: "下一页", KEY_PRINT: "截屏",
		KEY_PAUSE: "暂停", KEY_CAPSLOCK: "大写锁定", KEY_NUMLOCK: "数字锁定",
	}
	if names.has(key):
		parts.append(names[key])
	elif key >= KEY_F1 and key <= KEY_F35:
		parts.append("功能键 %d" % (key - KEY_F1 + 1))
	elif key >= KEY_KP_0 and key <= KEY_KP_9:
		parts.append("小键盘 %d" % (key - KEY_KP_0))
	elif key >= KEY_A and key <= KEY_Z:
		parts.append("字母键 %s" % String.chr(key + 0xFEE0))
	elif key >= 33 and key <= 126:
		parts.append(String.chr(key))
	else:
		parts.append("按键 %d" % key)
	return "＋".join(parts)
