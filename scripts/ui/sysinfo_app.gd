extends WbApp
## SysInfo — Systemmonitor im Look der Amiga-Diagnosetools von 1989/90
## (Homage an SysInfo & Co.): graue 3D-Tafeln, Readout-Zeilen, Speicher-
## Balken und der berühmte Geschwindigkeitsvergleich gegen andere Rechner.
## Liest die echte Spiel-Hardware (PlayerStats).

const WorkbenchVersionCatalog := preload("res://scripts/ui/workbench_versions.gd")
const BG := Color8(146, 148, 156)
const PANEL := Color8(122, 126, 136)
const INK := Color8(16, 18, 28)
const VALUE := Color8(250, 244, 160)
const HEAD := Color8(46, 60, 120)
const BAR := Color8(210, 84, 48)

var _busmhz := 7.09
var _flash := 0.0


func _init() -> void:
	app_title = "SysInfo"


func _build_app() -> void:
	_busmhz = PlayerStats.cpu_clock_mhz()
	add_button("", Rect2(388, 358, 76, 26), _remeasure, Color.WHITE, false)
	add_button("", Rect2(472, 358, 76, 26), func() -> void:
		var boards: Array[String] = PlayerStats.expansion_summary()
		UIManager.toast(Loc.t("ui.sysinfo_app.boards_s", "BOARDS: %s") % ("keine Erweiterungskarten gefunden."
			if boards.is_empty() else " · ".join(boards))), Color.WHITE, false)
	add_button("", Rect2(556, 358, 68, 26), close_app, Color.WHITE, false)


func _remeasure() -> void:
	var clock: float = PlayerStats.cpu_clock_mhz()
	_busmhz = clock + randf_range(-0.02, 0.02)
	_flash = 1.0
	var profile := PlayerStats.performance_profile()
	UIManager.toast(Loc.t("ui.sysinfo_app.sysinfo_0_2f_mhz_cpu_2fx", "SysInfo: %0.2f MHz · CPU %.2fx · I/O %.2fx · System %.2fx.") % [
		_busmhz,
		float(profile.get("cpu_speed_multiplier", 1.0)),
		float(profile.get("io_speed_multiplier", 1.0)),
		float(profile.get("performance_multiplier", 1.0)),
	])


func _app_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)


func _os_version() -> String:
	var profile := WorkbenchVersionCatalog.active()
	return "%s  (%s)" % [str(profile.get("release", "1.3")),
		str(profile.get("workbench_revision", "34.20"))]


func _speed_factor() -> float:
	return PlayerStats.cpu_speed_multiplier()


func _system_label() -> String:
	var machine := str({
		"amiga_1200": "A1200",
		"amiga_600": "A600",
	}.get(PlayerStats.desk_model("computer_model"), "A500"))
	var accelerator := PlayerStats.active_accelerator_id()
	if accelerator.contains("68060"):
		return machine + "/060"
	if accelerator.contains("68040"):
		return machine + "/040"
	if accelerator.contains("68030"):
		return machine + "/030"
	return machine


func _panel(r: Rect2, title: String, font: Font, fs: int) -> void:
	UiPaint.button3d(self, _R, r, PANEL, true)
	if title != "":
		draw_rect(_R(Rect2(r.position.x + 4, r.position.y + 4, r.size.x - 8, 18)), HEAD)
		draw_string(font, _V(r.position.x + 10, r.position.y + 18), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(240, 244, 252))


func _row(font: Font, fs: int, x: float, y: float, key: String, val: String) -> void:
	draw_string(font, _V(x, y), key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	draw_string(font, _V(x + 118, y), val, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, VALUE)


func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	var font := Wb13.font()
	var fs := Wb13.fsize(_sy())
	var small := maxi(4, int(fs * 0.8))
	draw_rect(Rect2(Vector2.ZERO, size), BG)

	# Kopf mit Logo-Tafel
	UiPaint.button3d(self, _R, Rect2(8, 8, VW - 16, 34), PANEL, false)
	draw_string(font, _V(20, 32), "SysInfo", HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 1.3), Color8(200, 32, 28))
	draw_string(font, _V(120, 32), "v2.62  ·  Systemmonitor", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	draw_string(font, _V(VW - 190, 32), TimeManager.date_string(), HORIZONTAL_ALIGNMENT_LEFT, -1, small, INK)

	var hw: Dictionary = PlayerStats.hardware
	var memory: Dictionary = PlayerStats.ram_breakdown()
	var total_kb := int(memory["total_kb"])
	var chip := int(memory["chip_kb"])
	var slow := int(memory["slow_kb"])
	var fast := int(memory["fast_kb"])

	# SYSTEM
	_panel(Rect2(8, 50, 310, 150), "SYSTEM", font, small)
	var y := 92.0
	_row(font, small, 20, y, "Prozessor", PlayerStats.cpu_description()); y += 20
	var kick_cfg := KickstartScreen.config()
	_row(font, small, 20, y, "Kickstart", "%s  (%s)" % [
		str(kick_cfg.get("rom_version", "1.3")),
		str(kick_cfg.get("rom_revision", "34.5"))]); y += 20
	_row(font, small, 20, y, "Werkbank", _os_version()); y += 20
	_row(font, small, 20, y, "Chipsatz", PlayerStats.chipset_description()); y += 20
	_row(font, small, 20, y, "Sound", "4 Kanäle, 8-Bit Stereo")

	# MEMORY mit Balken
	_panel(Rect2(326, 50, 306, 150), "MEMORY", font, small)
	y = 92.0
	_row(font, small, 338, y, "Chip-RAM", "%d KB" % chip); y += 18
	_row(font, small, 338, y, "Slow-RAM", ("%d KB" % slow) if slow > 0 else "— keins —"); y += 18
	_row(font, small, 338, y, "Fast-RAM", ("%d KB" % fast) if fast > 0 else "— keins —"); y += 18
	_row(font, small, 338, y, "Gesamt", "%d KB" % total_kb); y += 18
	_row(font, small, 338, y, "Frei", "%d Bytes" % maxi(51200, int(total_kb * 1024 * 0.62))); y += 10
	_mem_bar(Rect2(338, y, 280, 8), 0.62)

	# DRIVES
	_panel(Rect2(8, 208, 310, 118), "DRIVES", font, small)
	y = 250.0
	_row(font, small, 20, y, "DF0:", "880 KB, 3,5\"  [intern]"); y += 20
	_row(font, small, 20, y, "DF1:", "880 KB  [extern]" if hw.get("external_drive", false) else "nicht angeschlossen"); y += 20
	var hdd: String = PlayerStats.active_hdd_description()
	_row(font, small, 20, y, "DH0:", hdd.trim_prefix("DH0: ") if hdd != "" else "nicht vorhanden"); y += 20
	var baud: int = PlayerStats.modem_baud()
	_row(font, small, 20, y, "I/O:", ("%d Baud · %s" % [baud,
		PlayerStats.printer_name() if PlayerStats.has_printer() else "PAR frei"])
		if baud > 0 else (PlayerStats.printer_name() if PlayerStats.has_printer() else "SER/PAR frei"))

	# SPEED-Vergleich (der berühmte Balken-Screen)
	_panel(Rect2(326, 208, 306, 118), "SPEED", font, small)
	y = 246.0
	var speed_rows: Array = [
		["HC 500", 1.00, false],
		["HC 1200", 2.65, false],
		["HC 3000/25", 6.88, false],
		["HC 4000/040", 14.00, false],
		[_system_label(), _speed_factor(), true],
	]
	for row in speed_rows:
		var mine: bool = bool(row[2])
		draw_string(font, _V(338, y + 9), str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, small,
			VALUE if mine else INK)
		var frac: float = minf(1.0, float(row[1]) / 28.0)
		var br := _R(Rect2(432, y, 150.0 * frac, 10))
		draw_rect(br, VALUE if mine and _flash > 0.0 else BAR)
		draw_rect(br, INK, false, 1.0)
		draw_string(font, _V(436 + 150.0 * frac, y + 9), "%.2f" % float(row[1]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, INK)
		y += 16

	# Fußzeile + Knöpfe
	UiPaint.button3d(self, _R, Rect2(8, 334, VW - 16, 58), PANEL, false)
	var profile := PlayerStats.performance_profile()
	draw_string(font, _V(20, 352), "CPU %.2fx · I/O %.2fx · Gesamt %.2fx" % [
		float(profile.get("cpu_speed_multiplier", 1.0)),
		float(profile.get("io_speed_multiplier", 1.0)),
		float(profile.get("performance_multiplier", 1.0)),
	],
		HORIZONTAL_ALIGNMENT_LEFT, -1, small, INK)
	_button3d_label(font, small, Rect2(388, 358, 76, 26), "SPEED")
	_button3d_label(font, small, Rect2(472, 358, 76, 26), "BOARDS")
	_button3d_label(font, small, Rect2(556, 358, 68, 26), "EXIT")
	_draw_workbench_chrome(font)
	_draw_scanlines()


func _mem_bar(r: Rect2, frac: float) -> void:
	var pr := _R(r)
	draw_rect(pr, Color8(60, 64, 76))
	if frac > 0.0:
		draw_rect(Rect2(pr.position, Vector2(pr.size.x * frac, pr.size.y)), BAR)
	draw_rect(pr, INK, false, 1.0)


func _button3d_label(font: Font, fs: int, r: Rect2, label: String) -> void:
	UiPaint.button3d(self, _R, r, Color8(160, 162, 170), false)
	var pr := _R(r)
	draw_string(font, Vector2(pr.position.x, pr.get_center().y + 5.0 * _sy()), label,
		HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, fs, INK)
