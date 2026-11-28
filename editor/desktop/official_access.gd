extends RefCounted

const AGREEMENT := "res://licenses/USER-AGREEMENT.txt"
const PUBLIC_KEY := "res://licenses/FEATURE-UNLOCK-V2-PUBLIC.txt"
const AGREEMENT_RECEIPT := "user://official_access.json"
const UNLOCK_RECEIPT := "user://official_unlock_v2.json"
const PREFIX := "REV-UNLOCK-2."
const CODE_LENGTH := 697
const LOCKED := "请联系原作者解锁 Agent 和自动采音。"
const Store := preload("res://desktop/project_cache.gd")

static func agreement_text() -> String:
	return FileAccess.get_file_as_string(AGREEMENT)

static func has_agreed() -> bool:
	var terms := agreement_text()
	var receipt: Variant = _read_json(AGREEMENT_RECEIPT, 4096)
	return not terms.is_empty() and receipt is Dictionary and receipt.get("agreement") == terms.sha256_text()

static func features_enabled() -> bool:
	var token: Variant = _read_json(UNLOCK_RECEIPT, 1024)
	return token is String and has_agreed() and verify_code(token, machine_code())

static func accept_agreement() -> bool:
	var terms := agreement_text()
	if terms.is_empty():
		return false
	var stored: Variant = _read_json(AGREEMENT_RECEIPT, 4096)
	var receipt: Dictionary = stored if stored is Dictionary else {}
	receipt["agreement"] = terms.sha256_text()
	return Store.write_json(AGREEMENT_RECEIPT, receipt)

static func install_code(input: String) -> String:
	if not has_agreed():
		return "请先同意当前用户使用协议。"
	var token := input.strip_edges()
	if not verify_code(token, machine_code()):
		return "解锁码无效，或不适用于本机。请使用新版解锁码。"
	if not Store.write_json(UNLOCK_RECEIPT, token):
		return "无法保存解锁状态，请检查用户目录写入权限。"
	return ""

static func _read_json(path: String, limit: int) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file or file.get_length() > limit:
		return null
	var parser := JSON.new()
	return parser.data if parser.parse(file.get_buffer(limit).get_string_from_utf8()) == OK else null

static func machine_code() -> String:
	return derive_machine_code(OS.get_unique_id())

static func derive_machine_code(device: String) -> String:
	return "" if device.is_empty() else "rev1-" + ("revelation-machine-code/v1|" + device).sha256_text()

static func verify_code(token: String, machine: String) -> bool:
	if machine.is_empty() or token.length() != CODE_LENGTH or not token.begins_with(PREFIX):
		return false
	var signature := token.trim_prefix(PREFIX)
	if RegEx.create_from_string(r"\A[A-Za-z0-9+/]{683}=\z").search(signature) == null:
		return false
	var raw := Marshalls.base64_to_raw(signature)
	if raw.size() != 512 or Marshalls.raw_to_base64(raw) != signature:
		return false
	var key := CryptoKey.new()
	if key.load_from_string(FileAccess.get_file_as_string(PUBLIC_KEY), true) != OK:
		return false
	var digest := ("revelation-feature-unlock/v2|agent+audio|" + machine).sha256_buffer()
	return Crypto.new().verify(HashingContext.HASH_SHA256, digest, raw, key)
