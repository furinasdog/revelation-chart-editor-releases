extends SceneTree

const Access := preload("res://desktop/official_access.gd")
const Agreement := preload("res://desktop/user_agreement.gd")
const Chart := preload("res://main/chart_data.gd")
const ProfileTools := preload("res://desktop/agent_profile_tools.gd")
var _failed := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		_failed += 1

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "derive":
		var output := FileAccess.open(args[1], FileAccess.WRITE)
		var machine := Access.machine_code()
		quit(0 if output and not machine.is_empty() and output.store_string(machine) else 1)
		return
	if args.size() == 2 and args[0] == "seed":
		quit(0 if Access.accept_agreement() and Access.install_code(FileAccess.get_file_as_string(args[1])).is_empty() else 1)
		return
	if args.size() < 2 or args.size() > 3 or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	var token := FileAccess.get_file_as_string(args[0]).strip_edges()
	if not Access.verify_code(token, Access.machine_code()):
		push_error("The smoke test requires a genuine v2 licence for this machine")
		quit(2)
		return
	_check(not Access.has_agreed() and not desktop.features_enabled(), "New profile has no agreement or unlock")
	_check(not Access.install_code(token).is_empty(), "A genuine code cannot be installed before agreement")
	_check(desktop._tabs.is_tab_hidden(desktop._analysis_panel.get_index())
		and not desktop._analysis_menu.get_parent().visible and desktop._copilot_item == -1
		and desktop._results_tabs.is_tab_hidden(1) and not desktop._tabs.is_tab_hidden(desktop._tabs.current_tab)
		and desktop.sidebar.guide_mode == Chart.ReferenceMode.TRADITIONAL, "Locked features are hidden and the manual ruler is active")
	desktop._set_copilot_visible(true)
	desktop.mcp._toggle_server()
	_check(not desktop.copilot.visible and not desktop.mcp._server.is_running()
		and not desktop.copilot._send_prompt("test") and ProfileTools.call_tool("list_agent_prompts", {}).has("error"),
		"Direct entry points respect the lock")
	_check(Access.accept_agreement() and not Access.features_enabled(), "Agreement persists without unlocking features")
	_check(desktop.import_audio(args[1], true, false) and not desktop._ask.visible, "Audio imports without a capture prompt")
	_check(not desktop._start_analysis({}) and not desktop.analysis.start(args[1]), "Default analysis options still require authorization")
	desktop._tabs.set_tab_hidden(desktop._analysis_panel.get_index(), false)
	_check(not desktop._start_analysis({"tasks": ["beats"]}) and not desktop.copilot._send_prompt("test"),
		"Forcing the analysis panel visible does not authorize either execution path")
	desktop._refresh_feature_visibility()
	desktop.chart.set_bpm(120.0)
	var note: int = desktop.chart.add_note_at_times(0, 500, 1000, 1000, 1, Vector2(800, 450))
	_check(note >= 0 and desktop.chart.has_project_bpm and desktop.chart.time_unit_to_ms(64) == 500,
		"Manual note placement and tempo work while locked")
	desktop._play_from_current()
	_check(desktop.chart.rt_playing, "Playback works while locked")
	desktop.chart.pause_rt_playback()
	var zip_path := "user://locked-manual-chart.zip"
	var archive := ZIPReader.new()
	if desktop.sidebar._save_to_current_file() and desktop.chart.export_zip_to(zip_path) and archive.open(zip_path) == OK:
		var exported = JSON.parse_string(archive.read_file("chart.json").get_string_from_utf8())
		_check(exported is Dictionary and exported.basic.allNote == 1 and archive.file_exists(args[1].get_file()),
			"Exported chart ZIP contains the manually placed note and imported audio")
		archive.close()
	else:
		_check(false, "Saving and exporting a manual chart ZIP works while locked")
	var blocked: Dictionary = await desktop._analyze_for_agent({"engine": "native", "tasks": ["beats"]})
	_check(blocked.has("error"), "Analysis action itself is guarded")
	_check(not Access.verify_code(token, Access.derive_machine_code("another device")), "Unlock signature is bound to the machine")
	var replacement := "A" if token[Access.PREFIX.length()] != "A" else "B"
	var edited := Access.PREFIX + replacement + token.substr(Access.PREFIX.length() + 1)
	_check(not Access.install_code(edited).is_empty() and not desktop.features_enabled(),
		"Changing the signature does not unlock the features")
	if args.size() == 3:
		var legacy := FileAccess.get_file_as_string(args[2]).strip_edges()
		_check(Access.Store.write_json(Access.AGREEMENT_RECEIPT, {"agreement": Access.agreement_text().sha256_text(), "unlock": legacy})
			and Access.Store.write_json(Access.UNLOCK_RECEIPT, legacy) and Access.has_agreed()
			and not desktop.features_enabled() and not Access.install_code(legacy).is_empty(),
			"The original agreement remains valid while a genuine v1 signature is rejected")
	_check(Access.Store.write_json(Access.UNLOCK_RECEIPT, true) and not desktop.features_enabled(),
		"A forged local enabled flag does not grant access")
	_check(Access.install_code(token).is_empty() and Access.features_enabled(), "A valid v2 signature enables the features")
	desktop._refresh_feature_visibility()
	_check(not desktop._tabs.is_tab_hidden(desktop._analysis_panel.get_index())
		and not desktop._results_tabs.is_tab_hidden(1) and desktop._analysis_menu.get_parent().visible and desktop._copilot_item >= 0,
		"Successful unlock restores the menu and analysis panel")
	desktop._set_copilot_visible(true)
	_check(desktop.copilot.visible, "The unlocked workspace can open the Co-pilot")
	_check(Access.Store.write_json(Access.UNLOCK_RECEIPT, edited) and not desktop.features_enabled()
		and not desktop.copilot._send_prompt("test") and not desktop.analysis.start(args[1]),
		"Changing a signature on disk relocks an already-running application")
	_check(Access.install_code(token).is_empty() and Access.features_enabled(), "A genuine code restores access after tampering")

	var dialog := Agreement.new()
	current_scene.add_child(dialog)
	dialog.present(Access.agreement_text().repeat(6), "同意", "退出")
	await process_frame
	await process_frame
	var bar := dialog._reader.get_v_scroll_bar()
	_check(bar.visible and dialog._deadline - Time.get_ticks_msec() >= 14000, "Agreement starts a 15 s wait with a scrollable document")
	bar.value = bar.max_value
	dialog._process(0)
	_check(dialog._accept.disabled, "Reading to the end does not skip the wait")
	dialog._deadline = Time.get_ticks_msec()
	bar.value = 0
	dialog._process(0)
	_check(dialog._accept.disabled, "Elapsed time does not skip reading to the end")
	bar.value = bar.max_value
	dialog._process(0)
	_check(not dialog._accept.disabled, "Both conditions enable confirmation")
	dialog.queue_free()
	print("OFFICIAL_ACCESS_SMOKE failures=", _failed)
	quit(0 if _failed == 0 else 1)
