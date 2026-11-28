extends RefCounted

const AGREEMENT := "res://licenses/USER-AGREEMENT.txt"
const PUBLIC_KEY := "res://licenses/FEATURE-UNLOCK-PUBLIC.txt"
const RECEIPT := "user://official_access.json"
const PREFIX := "REV-UNLOCK-1."
const Store := preload("res://desktop/project_cache.gd")

var agreement_text := FileAccess.get_file_as_string(AGREEMENT)
var _agreement_revision := agreement_text.sha256_text()
var _receipt := {}
var _verified := false
var _machine_code := derive_machine_code(OS.get_unique_id())

func _init() -> void:
	if FileAccess.file_exists(RECEIPT):
		var file := FileAccess.open(RECEIPT, FileAccess.READ)
		if file and file.get_length() <= 4096:
			var data: Variant = JSON.parse_string(file.get_as_text())
			if data is Dictionary:
				_receipt = data
	_verified = verify_code(str(_receipt.get("unlock", "")), _machine_code)

func has_agreed() -> bool:
	return not agreement_text.is_empty() and _receipt.get("agreement") == _agreement_revision

func features_enabled() -> bool:
	return has_agreed() and _verified

func accept_agreement() -> bool:
	if agreement_text.is_empty():
		return false
	var next := _receipt.duplicate()
	next["agreement"] = _agreement_revision
	return _save(next)

func install_code(input: String) -> String:
	if not has_agreed():
		return "请先同意当前用户使用协议。"
	var token := input.strip_edges()
	if not verify_code(token, _machine_code):
		return "解锁码无效，或不适用于本机。"
	var next := _receipt.duplicate()
	next["unlock"] = token
	if not _save(next):
		return "无法保存解锁状态，请检查用户目录写入权限。"
	_verified = true
	return ""

func _save(next: Dictionary) -> bool:
	if not Store.write_json(RECEIPT, next):
		return false
	_receipt = next
	return true

static func derive_machine_code(device: String) -> String:
	return "" if device.is_empty() else "rev1-" + ("revelation-machine-code/v1|" + device).sha256_text()

static func verify_code(token: String, machine: String) -> bool:
	if machine.is_empty() or not token.begins_with(PREFIX):
		return false
	var signature := token.trim_prefix(PREFIX)
	if RegEx.create_from_string(r"\A[A-Za-z0-9+/]{512}\z").search(signature) == null:
		return false
	var key := CryptoKey.new()
	if key.load_from_string(FileAccess.get_file_as_string(PUBLIC_KEY), true) != OK:
		return false
	var digest := ("revelation-feature-unlock/v1|agent+audio|" + machine).sha256_buffer()
	return Crypto.new().verify(HashingContext.HASH_SHA256, digest, Marshalls.base64_to_raw(signature), key)
