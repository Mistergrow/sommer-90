class_name DiskRescueMinigame
extends RetroWindow
## DISK DOCTOR AGA — zwei Diskettenseiten als echtes Match-3-Spiel.
##
## Der Spieler tauscht benachbarte Datenbloecke und erzeugt Reihen ab drei.
## Jede Seite besitzt einen eigenen Rekonstruktionsbalken und Timer. Seite 2
## wird erst nach 100 % auf Seite 1 freigegeben; erst 100 % + 100 % schreibt
## ein verifiziertes Image auf die reservierte Leerdiskette.

const Model := preload("res://scripts/minigames/disk_rescue_model.gd")
const Board := preload("res://scripts/ui/disk_rescue_board.gd")
const DepthRig := preload("res://scripts/ui/minigame_depth_rig.gd")
const ENERGY_COST := 7

var source: Disk
var repair_mode := false
var _target: Disk
var _model: DiskRescueModel
var _board: DiskRescueBoard
var _status: Label
var _side_title: Label
var _timer_label: Label
var _timer_bar: ProgressBar
var _disk_label: Label
var _side_labels: Array[Label] = []
var _side_bars: Array[ProgressBar] = []
var _hint_button: Button
var _timer_button: Button
var _retry_button: Button
var _finished := false
var _resolving := false
var _last_timer_second := -1


func _init() -> void:
	title = Loc.t("ui.disk_rescue_minigame.disk_doctor_datenrettung", "DISK DOCTOR AGA · DATENRETTUNG")
	win_size = Vector2(1080, 690)


static func can_start(disk: Disk) -> Dictionary:
	if disk == null or disk.content_type == "leer":
		return {"ok": false, "reason": Loc.t("ui.disk_rescue_minigame.belegte_quelldiskette_auswaehlen", "Eine belegte Quelldiskette auswaehlen.")}
	if disk.is_boxed_package():
		return {"ok": false, "reason": Loc.t("ui.disk_rescue_minigame.disketten_werden_als_kompletter_satz_in", "Die Disketten werden als kompletter Satz in der OVP verwahrt.")}
	if not disk.checked:
		return {"ok": false, "reason": Loc.t("ui.disk_rescue_minigame.check_in_xcopy_first", "Quelle zuerst in X-COPY mit PRUEFEN diagnostizieren.")}
	if disk.condition <= 0:
		return {"ok": false, "reason": Loc.t("ui.disk_rescue_minigame.medium_ist_mechanisch_nicht_mehr_lesbar", "Medium ist mechanisch nicht mehr lesbar.")}
	if disk.condition >= 75:
		return {"ok": false, "reason": Loc.t("ui.disk_rescue_minigame.diese_diskette_braucht_keine_datenrettung", "Diese Diskette braucht keine Datenrettung.")}
	if DiskManager.blank_disks().is_empty():
		return {"ok": false, "reason": Loc.t("ui.disk_rescue_minigame.leerdiskette_fuer_image_wird_benoetigt", "Eine Leerdiskette fuer das Image wird benoetigt.")}
	if PlayerStats.energie < ENERGY_COST:
		return {"ok": false, "reason": Loc.t("ui.disk_rescue_minigame.too_tired", "Zu muede fuer einen sicheren Rettungslauf.")}
	return {"ok": true, "reason": ""}


func _ready() -> void:
	super._ready()
	if not repair_mode:
		_target = DiskManager.blank_disks()[0]
	var wins := int(MinigameManager.record("disk_rescue").get("wins", 0))
	_model = Model.new()
	_model.configure(clampi(1 + floori(wins / 2.0), 1, 5),
		hash("RESCUE/%s/%d/%d" % [source.uid, TimeManager.day_counter, wins]), source.condition)
	_build_ui()
	set_process(true)


func _build_ui() -> void:
	content.add_child(_build_mission_header())

	var split := HBoxContainer.new()
	split.name = "DiskRescueAgaDeck"
	split.custom_minimum_size = Vector2(1044, 475)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	content.add_child(split)

	var board_shell := PanelContainer.new()
	board_shell.name = "AgaPlayfieldShell"
	board_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_shell.add_theme_stylebox_override("panel", _panel_style(Color8(5, 7, 20), Color8(61, 107, 148), 5.0))
	split.add_child(board_shell)

	_board = Board.new()
	_board.name = "DiskRescueBoard"
	_board.model = _model
	_board.custom_minimum_size = Vector2(760, 475)
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.swap_requested.connect(_swap)
	board_shell.add_child(_board)
	var rig := DepthRig.new()
	_board.add_child(rig)
	rig.configure(_board, 0.22)

	split.add_child(_build_control_deck())

	_status = Bezel.lcd_label("", Palette.LCD_GREEN, 10)
	_status.name = "RescueStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 46
	content.add_child(_status)
	_refresh(Loc.t("ui.disk_rescue_minigame.side_one_intro",
		"SEITE 1 · 0:30 START · Jeder aufgeloeste Block gibt +1 Sekunde · Bilde Reihen aus gleichen %s.") % [
		Loc.t("ui.disk_rescue_minigame.aga_components", "AGA-Bausteinen") if repair_mode
		else Loc.t("ui.disk_rescue_minigame.data_blocks", "Datenbloecken")])
	_board.grab_focus.call_deferred()


func _build_mission_header() -> Control:
	var panel := PanelContainer.new()
	panel.name = "RecoveryProgressDeck"
	panel.add_theme_stylebox_override("panel", _panel_style(Color8(11, 14, 25), Color8(71, 85, 117), 6.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var identity := VBoxContainer.new()
	identity.custom_minimum_size.x = 275
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(identity)
	identity.add_child(Bezel.lcd_label(source.display_name().to_upper().left(34), Palette.LCD_AMBER, 12))
	identity.add_child(Bezel.dim_label(
		Loc.t("ui.disk_rescue_minigame.repair_pipeline",
			"DF0: MEDIUM  >  AGA-SCAN  >  STABILES ORIGINAL") if repair_mode
		else Loc.t("ui.disk_rescue_minigame.rescue_pipeline",
			"DF0: QUELLE  >  CHIP-RAM IMAGE  >  DF1: RETTUNG"), 9))

	for side in Model.SIDE_COUNT:
		var box := VBoxContainer.new()
		box.custom_minimum_size.x = 190
		row.add_child(box)
		var label := Bezel.lcd_label("", Palette.LCD_CYAN, 10)
		_side_labels.append(label)
		box.add_child(label)
		var progress := _progress_bar(TILE_SIDE_COLORS[side])
		progress.custom_minimum_size = Vector2(190, 12)
		_side_bars.append(progress)
		box.add_child(progress)

	var disk_box := VBoxContainer.new()
	disk_box.custom_minimum_size.x = 190
	row.add_child(disk_box)
	_disk_label = Bezel.lcd_label("", Palette.LCD_GREEN, 10)
	_disk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	disk_box.add_child(_disk_label)
	var disk_progress := Bezel.dim_label(
		Loc.t("ui.disk_rescue_minigame.two_sides_original_unchanged",
			"2 SEITEN · MEDIUM BLEIBT IDENTISCH") if repair_mode
		else Loc.t("ui.disk_rescue_minigame.two_sides_auto_verify",
			"2 SEITEN · VERIFY AUTOMATISCH"), 9)
	disk_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	disk_box.add_child(disk_progress)
	return panel


const TILE_SIDE_COLORS := [Color8(48, 213, 225), Color8(235, 79, 157)]


func _build_control_deck() -> Control:
	var panel := PanelContainer.new()
	panel.name = "RecoveryControlDeck"
	panel.custom_minimum_size.x = 255
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color8(13, 14, 20), Color8(72, 73, 88), 8.0))
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 7)
	panel.add_child(controls)

	controls.add_child(Bezel.lcd_label(Loc.t("ui.disk_rescue_minigame.a1200_aga_data_engine", "A1200 · AGA DATA ENGINE"), Palette.LCD_AMBER, 12))
	_side_title = Bezel.lcd_label("", Palette.UI_TEXT, 17)
	_side_title.name = "ActiveDiskSide"
	controls.add_child(_side_title)
	controls.add_child(Bezel.dim_label(Loc.t("ui.disk_rescue_minigame.copper_1024_blitter_dma_256_farb", "COPPER 1024 · BLITTER DMA · 256-FARB-REGISTER"), 11))
	controls.add_child(HSeparator.new())

	_timer_label = Bezel.lcd_label("", Palette.LCD_CYAN, 16)
	_timer_label.name = "SideTimer"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_child(_timer_label)
	_timer_bar = _progress_bar(Palette.LCD_CYAN)
	_timer_bar.custom_minimum_size.y = 14
	controls.add_child(_timer_bar)

	var rules := Bezel.dim_label(
		Loc.t("ui.disk_rescue_minigame.game_rules",
			"SPIELREGEL\n1. Zwei Nachbarn waehlen\n2. Reihen ab 3 bilden\n3. Start mit 0:30 · jeder Block +1 s\n4. Restzeit = DM-Bonusphase\n5. Danach Seite 2 · Disk 100%\n\n4ER  = BLITTER LINE\n5ER  = COPPER BURST\nKETTE = RASTER CASCADE"), 10)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(rules)
	controls.add_child(HSeparator.new())

	_hint_button = make_button(Loc.t("ui.disk_rescue_minigame.zug_zeigen_h", "ZUG ZEIGEN · H"), _hint)
	_hint_button.name = "HintButton"
	controls.add_child(_hint_button)
	var fixed_timer := Bezel.dim_label(Loc.t("ui.disk_rescue_minigame.arcade_lauf_0_30_start_block", "ARCADE-LAUF · 0:30 START · BLOCK +1 s"), 10)
	fixed_timer.add_theme_color_override("font_color", Palette.LCD_CYAN)
	controls.add_child(fixed_timer)
	_retry_button = make_button(Loc.t("ui.disk_rescue_minigame.seite_neu_starten", "SEITE NEU STARTEN"), _restart_side)
	_retry_button.name = "RetrySideButton"
	_retry_button.visible = false
	_retry_button.add_theme_color_override("font_color", Palette.LCD_AMBER)
	controls.add_child(_retry_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)
	var footer := Bezel.dim_label(Loc.t("ui.disk_rescue_minigame.maus_touch_bloecke_antippen_ntastatur_pfeile", "MAUS/TOUCH: BLOECKE ANTIPPEN\nTASTATUR: PFEILE + ENTER\nESC: AUSWAHL LOESCHEN\nORIGINAL: NUR LESEN"), 11)
	footer.add_theme_color_override("font_color", Color8(121, 217, 191))
	controls.add_child(footer)
	return panel


func _process(delta: float) -> void:
	if _model == null or _finished or _resolving:
		return
	if _model.tick_time(delta):
		if _model.side_finished[_model.current_side]:
			_resolving = true
			_board.locked = true
			_complete_current_side.call_deferred()
		else:
			_on_timeout()
		return
	var current_second := ceili(_model.side_time_left[_model.current_side])
	if current_second != _last_timer_second:
		_last_timer_second = current_second
		_refresh_hud()


func _swap(a: Vector2i, b: Vector2i) -> void:
	if _finished or _resolving or _model.failed():
		return
	var result := _model.swap_cells(a, b)
	if not bool(result.get("ok", false)):
		_board.reject_swap(a, b)
		_refresh(str(result.get("reason", Loc.t("ui.disk_rescue_minigame.no_data_row", "Dieser Tausch bildet keine Datenreihe."))))
		if _model.failed():
			_on_timeout()
		return

	_resolving = true
	_board.locked = true
	_board.accept_swap(a, b, result)
	AudioManager.floppy_read()
	var chain := int(result.get("chain", 1))
	var gain := int(result.get("gain", 0))
	var bonus_dm := int(result.get("bonus_dm", 0))
	var time_gain := roundi(float(result.get("time_gain", 0.0)))
	var special := str(result.get("special", "SECTOR LINK"))
	_refresh((Loc.t("ui.disk_rescue_minigame.chain_bonus", "%s · KETTE x%d · +%d DM BONUS.") % [special, chain, bonus_dm])
		if bonus_dm > 0 else Loc.t("ui.disk_rescue_minigame.chain_time", "%s · KETTE x%d · +%d%% · ZEIT +%d s.") % [special, chain, gain, time_gain])
	AudioManager.minigame_cue("disk_rescue", &"success" if chain >= 2 else &"action")

	var delay := 0.08 if bool(SettingsManager.value("reduced_motion")) else 0.38 + minf(0.32, chain * 0.06)
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree() or _finished:
		return
	if bool(result.get("entered_bonus", false)):
		_board.begin_bonus_phase()
		if not _model.timer_enabled:
			_model.finish_side_without_timer()
			await _complete_current_side()
		else:
			_resolving = false
			_board.locked = false
			_refresh(Loc.t("ui.disk_rescue_minigame.bonus_phase", "SEITE %d · 100%% · BONUSPHASE: Kombinationen bringen DM bis 0:00.") % (_model.current_side + 1))
			_board.grab_focus()
	else:
		_resolving = false
		_board.locked = false
		_board.grab_focus()


func _complete_current_side() -> void:
	var side := _model.current_side
	if side == 0:
		_board.begin_side_complete()
		_refresh(Loc.t("ui.disk_rescue_minigame.side_one_complete", "SEITE 1 ABGESCHLOSSEN · +%d DM Bonus · Diskette wenden ...") % _model.side_bonus_dm[0])
		AudioManager.minigame_cue("disk_rescue", &"success")
		var wait := 0.12 if bool(SettingsManager.value("reduced_motion")) else 1.25
		await get_tree().create_timer(wait).timeout
		if not is_inside_tree() or _finished:
			return
		_model.advance_side()
		_board.reset_for_side()
		_resolving = false
		_last_timer_second = -1
		_refresh(Loc.t("ui.disk_rescue_minigame.side_two_intro", "SEITE 2 · NEUE 0:30 · Zweite %s auf 100%% bringen · Block +1 s.") % [
			Loc.t("ui.disk_rescue_minigame.media_side", "Medienseite") if repair_mode
			else Loc.t("ui.disk_rescue_minigame.sector_half", "Sektorhaelfte")])
		_board.grab_focus()
	else:
		_board.begin_disk_complete()
		_refresh(Loc.t("ui.disk_rescue_minigame.side_two_complete", "SEITE 2 ABGESCHLOSSEN · Beide Seiten 100%% · Bonus gesamt +%d DM.") % _model.bonus_total_dm())
		AudioManager.minigame_cue("disk_rescue", &"success")
		var wait := 0.12 if bool(SettingsManager.value("reduced_motion")) else 1.05
		await get_tree().create_timer(wait).timeout
		if is_inside_tree():
			_commit()


func _hint() -> void:
	if _finished or _resolving or _model.failed():
		return
	var move := _model.hint()
	if move.x < 0:
		_refresh(Loc.t("ui.disk_rescue_minigame.no_move", "Kein Zug sichtbar · Datenmatrix wird neu synchronisiert."))
		return
	_board.show_hint(Vector2i(move.x, move.y), Vector2i(move.z, move.w))
	_refresh(Loc.t("ui.disk_rescue_minigame.move_marker", "ZUGMARKER aktiv · tausche die beiden blinkenden Nachbarbloecke."))


func _on_timeout() -> void:
	if _model.failed_side < 0 or _finished:
		return
	_resolving = false
	_board.locked = true
	_retry_button.visible = true
	_hint_button.disabled = true
	_refresh(Loc.t("ui.disk_rescue_minigame.time_expired", "ZEIT ABGELAUFEN · Das Original blieb unveraendert. Nur diese Seite neu starten."))
	AudioManager.minigame_cue("disk_rescue", &"error")


func _restart_side() -> void:
	if _finished or _model.failed_side < 0:
		return
	_model.restart_side()
	_retry_button.visible = false
	_hint_button.disabled = false
	_resolving = false
	_last_timer_second = -1
	_board.reset_for_side()
	_refresh(Loc.t("ui.disk_rescue_minigame.side_reloaded", "SEITE %d NEU EINGELESEN · Timer und Matrix zurueckgesetzt.") % (_model.current_side + 1))
	_board.grab_focus()


func _refresh(message: String) -> void:
	if is_instance_valid(_status):
		_status.text = Loc.t("ui.disk_rescue_minigame.s_n_s_d_rpm_seite", "%s\n%s · %d RPM · SEITE %d: %d%% · DISK: %d%% · FEHLTAUSCH %d") % [
			message, str(_model.disk_format).to_upper(), _model.rpm,
			_model.current_side + 1, _model.side_progress[_model.current_side],
			_model.disk_progress(), _model.mistakes]
	_refresh_hud()
	if is_instance_valid(_board):
		_board.queue_redraw()


func _refresh_hud() -> void:
	if _model == null:
		return
	for side in Model.SIDE_COUNT:
		if side < _side_labels.size() and is_instance_valid(_side_labels[side]):
			_side_labels[side].text = (Loc.t("ui.disk_rescue_minigame.side_bonus", "SEITE %d · BONUS +%d DM") % [side + 1, _model.side_bonus_dm[side]]) \
				if _model.side_progress[side] >= 100 and not _model.side_finished[side] \
				else Loc.t("ui.disk_rescue_minigame.side_progress", "SEITE %d · %03d%%") % [side + 1, _model.side_progress[side]]
			_side_labels[side].add_theme_color_override("font_color",
				Palette.LCD_GREEN if _model.side_progress[side] >= 100 else TILE_SIDE_COLORS[side])
		if side < _side_bars.size() and is_instance_valid(_side_bars[side]):
			_side_bars[side].value = _model.side_progress[side]
	if is_instance_valid(_disk_label):
		_disk_label.text = Loc.t("ui.disk_rescue_minigame.disk_image_03d", "DISK IMAGE · %03d%%") % _model.disk_progress()
	if is_instance_valid(_side_title):
		_side_title.text = Loc.t("ui.disk_rescue_minigame.seite_d_2", "SEITE %d / 2") % (_model.current_side + 1)
	if is_instance_valid(_timer_label) and is_instance_valid(_timer_bar):
		if not _model.timer_enabled:
			_timer_label.text = Loc.t("ui.disk_rescue_minigame.zeit_ohne_limit", "ZEIT · OHNE LIMIT")
			_timer_label.add_theme_color_override("font_color", Palette.LCD_AMBER)
			_timer_bar.value = 100
		else:
			var time_left := _model.side_time_left[_model.current_side]
			_timer_label.text = (Loc.t("ui.disk_rescue_minigame.bonus_timer", "BONUS · %02d:%02d · +%d DM") % [floori(time_left / 60.0), floori(time_left) % 60,
				_model.side_bonus_dm[_model.current_side]]) if _model.side_progress[_model.current_side] >= 100 \
				else Loc.t("ui.disk_rescue_minigame.side_timer", "ZEIT · %02d:%02d") % [floori(time_left / 60.0), floori(time_left) % 60]
			var timer_color := Color8(238, 76, 73) if time_left <= 5.0 else (Palette.LCD_AMBER if time_left <= 12.0 else Palette.LCD_CYAN)
			_timer_label.add_theme_color_override("font_color", timer_color)
			_timer_bar.value = time_left / maxf(1.0, _model.side_time_limit) * 100.0


func _commit() -> bool:
	if repair_mode:
		return _commit_repair()
	if _finished or not _model.complete() or source == null or _target == null:
		return false
	if not DiskManager.disks.has(source) or not DiskManager.disks.has(_target) or _target.content_type != "leer":
		return false
	if not PlayerStats.use_energy(ENERGY_COST):
		return false
	_finished = true
	_resolving = false
	_target.template_id = source.template_id
	_target.content_type = source.content_type
	_target.content_title = source.content_title
	_target.rarity = source.rarity
	_target.software_id = source.software_id
	_target.software_set_id = source.software_set_id
	_target.disk_number = source.disk_number
	_target.disk_count = source.disk_count
	_target.program_id = source.program_id
	_target.boot_mode = source.boot_mode
	_target.virus = source.virus
	_target.provenance = "copy"
	_target.copy_generation = maxi(1, source.copy_generation + 1)
	_target.source_uid = source.uid
	_target.source_provenance = source.provenance
	_target.condition = _model.quality()
	_target.checked = false
	_target.label = "RESCUE " + source.display_name().left(20)
	_target.labeled = true
	_target.rescue_source_uid = source.uid
	_target.rescue_quality = _model.quality()
	_target.memory = Loc.t("ui.disk_rescue_minigame.rescue_memory", "Zweiseitiges Sektorimage von %s gerettet, %s") % [source.display_name(), TimeManager.date_string()]
	var details := _model.details()
	details["source_uid"] = source.uid
	details["target_uid"] = _target.uid
	MinigameManager.finish("disk_rescue", true, _model.score(), details)
	var bonus_dm := _model.bonus_total_dm()
	if bonus_dm > 0:
		PlayerStats.add_money(float(bonus_dm))
	DiskManager._apply_sort()
	DiskManager.disks_changed.emit()
	if is_instance_valid(_status):
		_status.text = Loc.t("ui.disk_rescue_minigame.disk_image_verified_100_qualitaet_d", "DISK IMAGE VERIFIED · 100%% · QUALITAET %d%% · %04d PUNKTE · BONUS +%d DM") % [_model.quality(), _model.score(), bonus_dm]
	if is_instance_valid(_board):
		_board.locked = true
	if is_instance_valid(_hint_button):
		_hint_button.disabled = true
	if is_instance_valid(_timer_button):
		_timer_button.disabled = true
	AudioManager.key_enter()
	UIManager.toast(Loc.t("ui.disk_rescue_minigame.datenrettung_abgeschlossen_beide_diskettenseiten_100", "Datenrettung abgeschlossen: beide Diskettenseiten 100%."))
	return true


func _commit_repair() -> bool:
	if _finished or not _model.complete() or source == null or not DiskManager.disks.has(source):
		return false
	if source.condition <= 0 or source.condition >= 95 or source.last_repair_day == TimeManager.day_counter:
		_status.text = Loc.t("ui.disk_rescue_minigame.medienzustand_hat_sich_waehrend_des_laufs", "Medienzustand hat sich waehrend des Laufs geaendert; Reparatur nicht verbucht.")
		return false
	if not PlayerStats.use_energy(ENERGY_COST):
		_status.text = Loc.t("ui.disk_rescue_minigame.zu_wenig_energie_reparatur_nicht_verbucht", "Zu wenig Energie; Reparatur nicht verbucht.")
		return false
	_finished = true
	_resolving = false
	var before := source.condition
	source.condition = 95
	source.read_error_chance = maxf(0.005, source.read_error_chance * 0.55)
	source.write_error_chance = maxf(0.005, source.write_error_chance * 0.62)
	source.checked = true
	source.media_repairs += 1
	source.last_repair_day = TimeManager.day_counter
	var details := _model.details()
	details["uid"] = source.uid
	details["condition_before"] = before
	details["condition_after"] = source.condition
	MinigameManager.finish("disk_media_repair", true, _model.score(), details)
	var bonus_dm := _model.bonus_total_dm()
	if bonus_dm > 0:
		PlayerStats.add_money(float(bonus_dm))
	DiskManager.disks_changed.emit()
	MemoryManager.record("reparatur", Loc.t("ui.disk_rescue_minigame.repair_memory", "%s im Disk Doctor AGA stabilisiert") % source.display_name())
	_status.text = Loc.t("ui.disk_rescue_minigame.medium_stabil_beide_seiten_100_zustand", "MEDIUM STABIL · BEIDE SEITEN 100%% · ZUSTAND %d%% -> 95%% · BONUS +%d DM") % [before, bonus_dm]
	_board.locked = true
	_hint_button.disabled = true
	AudioManager.play("continuity_ok")
	UIManager.toast(Loc.t("ui.disk_rescue_minigame.diskette_stabilisiert_d_95_d_dm", "Diskette stabilisiert: %d%% -> 95%% · +%d DM Bonus.") % [before, bonus_dm])
	return true


# Unsichtbarer Test-/Barrierefreiheitsadapter; nicht Bestandteil des Control-Decks.
func _auto() -> void:
	if _finished:
		return
	_model.auto_finish()
	_commit()


func _progress_bar(color: Color) -> ProgressBar:
	var progress := ProgressBar.new()
	progress.min_value = 0
	progress.max_value = 100
	progress.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color8(4, 6, 13)
	background.border_color = Color8(55, 62, 78)
	background.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.border_color = color.lightened(0.28)
	fill.set_border_width_all(1)
	progress.add_theme_stylebox_override("background", background)
	progress.add_theme_stylebox_override("fill", fill)
	return progress


func _panel_style(background: Color, border: Color, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style


func _unhandled_key_input(event: InputEvent) -> void:
	super._unhandled_key_input(event)
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_H:
			_hint()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if is_instance_valid(_board):
				_board.clear_selection()
			get_viewport().set_input_as_handled()
