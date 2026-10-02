class_name CracktroOptimizationMinigame
extends RetroWindow
const Model:=preload("res://scripts/minigames/cracktro_opt_model.gd")
const DepthRig:=preload("res://scripts/ui/minigame_depth_rig.gd")
const ENERGY_COST:=4
var project:Dictionary={}
var _model:CracktroOptimizationModel
var _board:ProfilerBoard
var _status:Label
var _buttons:Dictionary={}
var _finished:=false
func _init()->void:title="RASTER LAB · CRACKTRO OPTIMIERUNG";win_size=Vector2(900,620)
static func can_start()->Dictionary:
	if PlayerStats.energie<ENERGY_COST:return{"ok":false,"reason":Loc.t("ui.cracktro_optimization_minigame.zu_muede_fuer_profiling_rebuild", "Zu muede fuer Profiling und Rebuild.")}
	return{"ok":true,"reason":""}
func _ready()->void:
	super._ready();if project.is_empty():project=DemoManager.load_draft();if project.is_empty():project=DemoManager.create_project()
	var report:=DemoManager.compile_project(project);var met:Dictionary=report.get("metrics",{});var wins:=int(MinigameManager.record("cracktro_opt").get("wins",0));_model=Model.new();_model.configure(clampi(1+floori(wins/2.0),1,5),hash("OPT/%d/%d"%[TimeManager.day_counter,wins]),{"cpu":int(met.get("peak_cpu_pct",0)),"chip":int(met.get("peak_chip_kb",0)),"blitter":int(met.get("peak_blitter_pct",0)),"colors":int(met.get("peak_colors",0))});_build_ui()
func _build_ui()->void:
	content.add_child(Bezel.dim_label(Loc.t("ui.cracktro_optimization_minigame.profiler_lesen_engpass_gezielt_behandeln_pal", "Profiler lesen · Engpass gezielt behandeln · PAL 50 Hz und audiovisuelle Qualitaet gemeinsam halten."),11))
	var panel:=VBoxContainer.new();panel.name="RasterProfiler25D";panel.custom_minimum_size=Vector2(864,445);content.add_child(panel);var rig:=DepthRig.new();panel.add_child(rig);rig.configure(panel,.7)
	_board=ProfilerBoard.new();_board.model=_model;_board.custom_minimum_size=Vector2(864,290);panel.add_child(_board)
	var cards:=GridContainer.new();cards.columns=3;cards.add_theme_constant_override("h_separation",7);cards.add_theme_constant_override("v_separation",6);panel.add_child(cards)
	for card in Model.CARDS:
		var effect: Dictionary = Model.EFFECTS[card]
		var effect_text := "CPU %s · CHIP %s · BLT %s · Q %s" % [_signed(effect.cpu), _signed(effect.chip), _signed(effect.blitter), _signed(effect.quality)]
		var b:=make_button(Loc.t("ui.cracktro_optimization_minigame.s_s", "%s\n%s") % [Model.LABELS[card], effect_text],_toggle.bind(card))
		b.toggle_mode=true
		b.custom_minimum_size=Vector2(270,48)
		b.tooltip_text = Loc.t("ui.cracktro_optimization_minigame.farben_s_optimierung_belegt_karte", "Farben %s · Optimierung belegt eine Karte") % _signed(effect.colors)
		cards.add_child(b)
		_buttons[card]=b
	var row:=HBoxContainer.new();row.add_child(make_button(Loc.t("ui.cracktro_optimization_minigame.profiler_hinweis", "PROFILER-HINWEIS"),_hint));row.add_child(make_button(Loc.t("ui.cracktro_optimization_minigame.auto_opt_assistiert", "AUTO-OPT (ASSISTIERT)"),_auto));row.add_child(make_button(Loc.t("ui.cracktro_optimization_minigame.rebuild_in_draft", "REBUILD IN DRAFT"),_commit));panel.add_child(row)
	_status=Bezel.lcd_label("",Palette.LCD_GREEN,10);_status.custom_minimum_size.y=45;content.add_child(_status);_refresh()

func _signed(value: int) -> String:
	return "%+d" % value
func _toggle(card:StringName)->void:
	if _finished:return
	if not _model.toggle(card):(_buttons[card]as Button).button_pressed=false;_status.text=Loc.t("ui.cracktro_optimization_minigame.kartenbudget_d_erreicht", "Kartenbudget %d erreicht.")%_model.budget
	_refresh()
func _hint()->void:
	var card:=_model.hint();_status.text=Loc.t("ui.cracktro_optimization_minigame.profiler_markiert_s_adressiert_den_groessten", "Profiler markiert: %s adressiert den groessten Engpass.")%Model.LABELS[card]
func _auto()->void:
	_model.auto_optimize();for card in Model.CARDS:(_buttons[card]as Button).button_pressed=card in _model.selected
	_refresh()
func _refresh()->void:
	var m:=_model.metrics();_status.text=Loc.t("ui.cracktro_optimization_minigame.s_cpu_d_chip_dkb_blitter", "%s · CPU %d%% · CHIP %dKB · BLITTER %d%% · %d FARBEN · Q %d · KARTEN %d/%d · %s")%[str(_model.hardware_target).to_upper(),m.cpu,m.chip,m.blitter,m.colors,m.quality,_model.selected.size(),_model.budget,("PAL LOCK"if _model.valid()else"OVER BUDGET")];_board.queue_redraw()
func _commit()->bool:
	if _finished or not _model.valid() or not PlayerStats.use_energy(ENERGY_COST):return false
	_finished=true;var clean:=project.duplicate(true);var parts:Array=clean.get("parts",[])
	for i in parts.size():var p:Dictionary=parts[i];var opts:Array=p.get("optimizations",[]).duplicate();for card in _model.selected:var id:=str(card);if id not in opts:opts.append(id);p.optimizations=opts;parts[i]=p
	clean.parts=parts;clean.revision=int(clean.get("revision",1))+1;clean["optimization_lab"]=_model.details();DemoManager.save_draft(clean);MinigameManager.finish("cracktro_opt",true,_model.score(),_model.details());_status.text=Loc.t("ui.cracktro_optimization_minigame.pal_50_hz_lock_draft_rev", "PAL 50 HZ LOCK · DRAFT REV %d · %04d PUNKTE")%[clean.revision,_model.score()];AudioManager.key_enter();return true
class ProfilerBoard:
	extends Control
	var model:CracktroOptimizationModel
	func _draw()->void:
		draw_rect(Rect2(Vector2.ZERO,size),Color8(6,9,16),true)
		for y in range(0,int(size.y),4):draw_line(Vector2(0,y),Vector2(size.x,y),Color(0,.1,.2,.16))
		for x in range(0, int(size.x), 32): draw_line(Vector2(x, 30), Vector2(x, size.y), Color(0.1, 0.28, 0.34, 0.10))
		var m:=model.metrics();var data=[["CPU / 20ms",int(m.cpu),100,Color8(69,210,255)],["CHIP RAM",int(m.chip),512,Color8(255,184,67)],["BLITTER",int(m.blitter),100,Color8(174,105,255)],["COLORS",int(m.colors),32,Color8(255,91,105)],["A/V QUALITY",int(m.quality),100,Color8(86,230,132)]]
		for i in data.size():
			var y:=40+i*46
			draw_string(ThemeDB.fallback_font,Vector2(34,y+13),data[i][0],HORIZONTAL_ALIGNMENT_LEFT,155,11,Color8(188,211,226))
			var bar := Rect2(205,y,size.x-260,20)
			draw_rect(bar,Color8(20,30,42),true)
			var ratio: float = float(data[i][1]) / float(data[i][2])
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * minf(1, ratio), bar.size.y)), data[i][3], true)
			draw_line(Vector2(bar.end.x, bar.position.y - 3), Vector2(bar.end.x, bar.end.y + 3), Color8(245, 245, 225), 2)
			if ratio > 1.0:
				draw_rect(Rect2(bar.end - Vector2(0, 0), Vector2(minf(42, (ratio - 1.0) * bar.size.x), bar.size.y)), Color8(238, 56, 67), true)
			draw_string(ThemeDB.fallback_font,Vector2(size.x-115,y+15),"%d / %d"%[data[i][1],data[i][2]],HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color.WHITE)
		draw_string(ThemeDB.fallback_font,Vector2(34,24),"BYTEWERK PROFILER · COPPER / BLITTER / VBLANK",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color8(115,236,219))
		# Live-Abhaengigkeitsgraph und A/B-Mini-Szene: Karten veraendern sofort
		# Knotenfarbe, Rasterdichte und den sichtbaren Qualitaetsgrad.
		var graph_y:=size.y-24.0;var nodes:=Model.CARDS
		for i in nodes.size():
			var p:=Vector2(70+i*(size.x-140)/float(nodes.size()-1),graph_y);if i>0:draw_line(Vector2(70+(i-1)*(size.x-140)/float(nodes.size()-1),graph_y),p,Color8(62,108,128),2)
			draw_circle(p,7,Color8(88,232,150)if nodes[i]in model.selected else Color8(78,91,108));draw_string(ThemeDB.fallback_font,p+Vector2(-22,-10),str(nodes[i]).left(5),HORIZONTAL_ALIGNMENT_LEFT,44,7,Color8(205,221,226))
