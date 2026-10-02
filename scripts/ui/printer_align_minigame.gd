class_name PrinterAlignMinigame
extends RetroWindow
const Model := preload("res://scripts/minigames/printer_align_model.gd")
const DepthRig := preload("res://scripts/ui/minigame_depth_rig.gd")
const ENERGY_COST := 4
var _model: PrinterAlignModel
var _page: TestPage
var _status: Label
var _sliders := {}
var _value_labels := {}
var _finished := false

func _init() -> void: title = "DRUCKER · MECHANIK / REGISTRATION"; win_size = Vector2(900, 620)

static func can_start() -> Dictionary:
	if not PlayerStats.has_printer(): return {"ok": false, "reason": Loc.t("ui.printer_align_minigame.kein_drucker_angeschlossen", "Kein Drucker angeschlossen.")}
	if PlayerStats.energie < ENERGY_COST: return {"ok": false, "reason": Loc.t("ui.printer_align_minigame.zu_muede_fuer_kalibrierung", "Zu muede fuer die Kalibrierung.")}
	return {"ok": true, "reason": ""}

func _ready() -> void:
	super._ready(); var wins := int(MinigameManager.record("printer_align").get("wins", 0)); _model = Model.new()
	_model.configure(clampi(1 + floori(wins / 2.0), 1, 5), hash("PRINT/%s/%d/%d" % [PlayerStats.hardware.printer_model, TimeManager.day_counter, wins]), str(PlayerStats.hardware.printer_model)); _build_ui()

func _build_ui() -> void:
	content.add_child(Bezel.dim_label(Loc.t("ui.printer_align_minigame.papier_gerade_fuehren_kopfspalt_bidirektion_abgleichen", "Papier gerade fuehren · Kopfspalt und Bidirektion abgleichen · Farbmodelle zusaetzlich CMY."), 11))
	var split := HBoxContainer.new(); split.name = "PrinterService25D"; split.custom_minimum_size = Vector2(864, 450); split.add_theme_constant_override("separation", 14); content.add_child(split)
	var rig := DepthRig.new(); split.add_child(rig); rig.configure(split, 0.68)
	_page = TestPage.new(); _page.model = _model; _page.custom_minimum_size = Vector2(580, 450); _page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var asset := RoomCompositor.find_asset({
		"dot_matrix_9pin":"PRINTER_DOT_MATRIX_9PIN",
		"dot_matrix_24_mono":"PRINTER_DOT_MATRIX_24PIN_MONO",
		"dot_matrix_24_color":"PRINTER_DOT_MATRIX_24PIN_COLOR",
		"color_inkjet":"PRINTER_COLOR_INKJET_CJ300",
		"laser_mono":"PRINTER_LASER_MONO",
	}.get(_model.printer_model, "PRINTER_DOT_MATRIX_9PIN"))
	if asset != "": _page.printer_texture = RoomCompositor.load_texture(asset)
	split.add_child(_page)
	var controls := VBoxContainer.new(); controls.custom_minimum_size.x = 260; controls.add_theme_constant_override("separation", 3); split.add_child(controls)
	for key in _model.params:
		var parameter_row := HBoxContainer.new()
		var parameter_label := Bezel.dim_label(str(Model.LABELS[key]), 10)
		parameter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_label := Bezel.lcd_label(Loc.t("ui.printer_align_minigame.0_00", "+0.00"), Palette.LCD_AMBER, 10)
		value_label.custom_minimum_size.x = 58
		parameter_row.add_child(parameter_label)
		parameter_row.add_child(value_label)
		controls.add_child(parameter_row)
		var slider := HSlider.new(); slider.min_value=-1; slider.max_value=1; slider.step=.01; slider.value=float(_model.values[key]); slider.custom_minimum_size.y=22
		slider.value_changed.connect(func(v: float) -> void: _model.set_value(key, v); _refresh()); controls.add_child(slider); _sliders[key]=slider
		_value_labels[key] = value_label
	controls.add_child(make_button(Loc.t("ui.printer_align_minigame.messuhr_hinweis", "MESSUHR-HINWEIS"), _hint)); controls.add_child(make_button(Loc.t("ui.printer_align_minigame.werksautomatik", "WERKSAUTOMATIK"), _auto)); controls.add_child(make_button(Loc.t("ui.printer_align_minigame.testseite_uebernehmen", "TESTSEITE UEBERNEHMEN"), _commit))
	_status = Bezel.lcd_label("", Palette.LCD_GREEN, 10); _status.custom_minimum_size.y=54; _status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; content.add_child(_status); _refresh()

func _refresh() -> void:
	for key in _model.params:
		var value := float(_model.values[key])
		var locked := absf(value) <= _model.tolerance()
		(_value_labels[key] as Label).text = ("LOCK" if locked else "%+.2f" % value)
		(_value_labels[key] as Label).modulate = Palette.LCD_GREEN if locked else Palette.LCD_AMBER
	_status.text = Loc.t("ui.printer_align_minigame.s_adv_2f_jam_02d_level", "%s · ADV %+.2f · JAM %02d%% · LEVEL %d · VERSATZ %02d%% · %d/%d LOCK") % [str(_model.media).to_upper(),_model.paper_advance,roundi(_model.jam_risk*100),_model.level, roundi(_model.total_error()*100), _locked_count(), _model.params.size()]
	_page.queue_redraw()

func _locked_count() -> int:
	return _model.params.filter(func(key: StringName) -> bool: return absf(float(_model.values[key])) <= _model.tolerance()).size()
func _hint() -> void:
	var key := _model.hint(); (_sliders[key] as HSlider).set_value_no_signal(0); _refresh(); _status.text = Loc.t("ui.printer_align_minigame.s_per_messuhr_auf_null_gesetzt", "%s per Messuhr auf Null gesetzt.") % Model.LABELS[key]
func _auto() -> void:
	_model.auto_align();
	for key in _model.params: (_sliders[key] as HSlider).set_value_no_signal(0)
	_refresh()
func _commit() -> bool:
	if _finished or not _model.calibrated() or not PlayerStats.use_energy(ENERGY_COST):
		if _status != null and not _model.calibrated(): _status.text = Loc.t("ui.printer_align_minigame.testseite_nicht_bestanden_staerksten_geisterversatz_korrigieren", "TESTSEITE NICHT BESTANDEN · staerksten Geisterversatz korrigieren.")
		return false
	_finished=true; var details:=_model.details(); details["date"]=TimeManager.date_string()
	PlayerStats.peripherals.printer["calibration"] = details.duplicate(true); MinigameManager.finish("printer_align", true, _model.score(), details); PlayerStats.stats_changed.emit()
	_status.text=Loc.t("ui.printer_align_minigame.pass_traktor_kopf_bidir_registriert_04d", "PASS · TRAKTOR / KOPF / BIDIR REGISTRIERT · %04d PUNKTE") % _model.score(); AudioManager.key_enter(); return true

class TestPage:
	extends Control
	var model: PrinterAlignModel; var printer_texture: Texture2D
	var head_phase:=0.0
	var print_row:=0
	func _ready()->void:set_process(true)
	func _process(delta:float)->void:
		var previous:=head_phase;head_phase=fmod(head_phase+delta*(.34+model.level*.025),1.0)
		if head_phase<previous:print_row=(print_row+1)%10;AudioManager.minigame_cue("printer_align",&"action")
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color8(24,26,30),true)
		var printer_rect:=Rect2(size.x*.18,8,size.x*.64,130)
		# Papier liegt hinter dem Gehaeuse und kommt erst am Ausgabeschlitz nach
		# vorne. Dadurch kann der animierte Kopf nie auf dem Blatt schweben.
		var paper:=Rect2(55,118,size.x-110,size.y-145);draw_rect(Rect2(paper.position+Vector2(6,8),paper.size),Color(0,0,0,.32),true);draw_rect(paper,Color8(238,229,204),true);draw_rect(paper,Color8(92,79,60),false,3)
		if printer_texture:draw_texture_rect(printer_texture,printer_rect,false)
		# Exakte interne Rail innerhalb des Assets. Der Clamp ist absichtlich
		# doppelt: Phase und Geometrie koennen den Kopf nie aus dem Drucker tragen.
		var rail:=Rect2(printer_rect.position+Vector2(printer_rect.size.x*.245,printer_rect.size.y*.285),Vector2(printer_rect.size.x*.51,printer_rect.size.y*.13))
		draw_line(Vector2(rail.position.x,rail.get_center().y),Vector2(rail.end.x,rail.get_center().y),Color8(32,35,38),6)
		var print_left:=maxf(paper.position.x+22,rail.position.x+12);var print_right:=minf(paper.end.x-22,rail.end.x-12)
		var paper_present:=paper.size.x>60 and paper.size.y>80 and print_right>print_left
		var head_x:=clampf(lerpf(print_left,print_right,head_phase),print_left,print_right)
		if paper_present:
			var carriage:=Rect2(head_x-7,rail.position.y-2,14,rail.size.y+8);draw_rect(carriage,Color8(24,27,29),true);draw_line(Vector2(carriage.position.x+2,carriage.position.y+2),Vector2(carriage.end.x-2,carriage.position.y+2),Color8(112,118,120),1);draw_rect(Rect2(head_x-1.5,carriage.end.y-3,3,5),Color8(72,74,72),true)
		# Schlitzkante liegt vor Papier und Kopf; das verankert beide im Gehaeuse.
		draw_rect(Rect2(printer_rect.position.x+printer_rect.size.x*.19,printer_rect.end.y-14,printer_rect.size.x*.62,8),Color(0.02,.025,.027,.88),true)
		var skew: float=(float(model.values.tractor_r)-float(model.values.tractor_l))*13; var bid: float=float(model.values.bidir)*10; var _gap: float=abs(float(model.values.head_gap))*4+1   # (reserviert: Kopfabstand-Anzeige)
		var pins:=9 if model.printer_model=="dot_matrix_9pin"else 24;var is_color:=model.printer_model=="dot_matrix_24_color"or model.printer_model=="color_inkjet"
		var technology := "INKJET" if model.printer_model == "color_inkjet" else \
			("LASER" if model.printer_model == "laser_mono" else "%02d-PIN" % pins)
		for hole_y in range(16, int(paper.size.y) - 10, 17):
			draw_circle(paper.position + Vector2(9, hole_y), 3, Color8(80, 77, 68), false, 1)
			draw_circle(Vector2(paper.end.x - 9, paper.position.y + hole_y), 3, Color8(80, 77, 68), false, 1)
		for row in 10:
			var yy:=paper.position.y+38+row*26;var row_end:=head_x if row==print_row else print_right
			if row>print_row:row_end=print_left
			for x in range(roundi(print_left),roundi(row_end),4):
				var column:=floori((x-print_left)/4.0)
				for pin in pins:
					if posmod(column*7+pin*3+row*11,7)>2:continue
					var pin_y:=yy+(float(pin)/maxf(1,pins-1)-.5)*(16 if pins==24 else 13)+skew*((x-print_left)/maxf(1,print_right-print_left));var dot_color:=Color8(38,37,34)
					if is_color:dot_color=[Color8(30,145,168),Color8(190,48,128),Color8(210,174,28),Color8(38,37,34)][posmod(pin+row,4)]
					draw_circle(Vector2(x+bid,pin_y),.75 if pins==24 else 1.15,Color(dot_color,.78))
		if model.params.has(&"cyan"):
			for pair in [[&"cyan",Color.CYAN],[&"magenta",Color.MAGENTA],[&"yellow",Color.YELLOW]]:
				var off:=float(model.values[pair[0]])*13
				var target := paper.position + Vector2(paper.size.x - 145 + off, 60)
				draw_circle(target, 27, Color(pair[1], .65), false, 4)
				draw_line(target - Vector2(34, 0), target + Vector2(34, 0), Color(pair[1], .65), 2)
				draw_line(target - Vector2(0, 34), target + Vector2(0, 34), Color(pair[1], .65), 2)
		draw_string(ThemeDB.fallback_font,paper.position+Vector2(20,22),"LQ SERVICE · %s · %s · LINE %02d"%[technology,"CMY/K"if is_color else"SCHWARZ",print_row+1],HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color8(55,50,43))
		draw_string(ThemeDB.fallback_font,paper.position+Vector2(20,paper.size.y-12),"MEDIA %s · ADV %+.2f · JAM %02d%%"%[str(model.media).to_upper(),model.paper_advance,roundi(model.jam_risk*100)],HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color8(70,58,44))
