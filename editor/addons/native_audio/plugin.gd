@tool
extends EditorPlugin

class AudioExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "RevelationNativeAudio"

	func _export_begin(features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
		if "windows" not in features or "x86_64" not in features:
			return
		for file in ["revelation-madmom.exe", "revelation-essentia.exe", "revelation-music2emo.exe", "revelation-rmvpe.exe", "revelation-stems.exe"]:
			var path: String = "res://bin/" + file
			if FileAccess.file_exists(path):
				add_shared_object(path, PackedStringArray(["windows", "x86_64"]), "")
			else:
				push_warning("导出目录将缺少原生音频分析程序 " + file)

var _audio_export := AudioExport.new()

func _enter_tree() -> void:
	add_export_plugin(_audio_export)

func _exit_tree() -> void:
	remove_export_plugin(_audio_export)
