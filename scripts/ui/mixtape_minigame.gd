class_name MixtapeMinigame
extends RetroWindow
const Model := preload("res://scripts/minigames/mixtape_model.gd")
const DepthRig := preload("res://scripts/ui/minigame_depth_rig.gd")
const STEREO_ART := preload("res://assets/backgrounds/layers/STEREO_COMPACT_CASSETTE_V01.png")
const ENERGY_COST := 5
var _model: MixtapeModel
var _library: ItemList
var _tape: ItemList
var _status: Label
var _gain: HSlider
var _cue:HSlider
var _fade_in:HSlider
var _fade_out:HSlider
var _meter: TapeMeter
var _selected := -1
var _finished := false
var _playing:=false

func _init() -> void: title="TAPE LAB · MIXTAPE MASTER"; win_size=Vector2(900,620)
static func can_start() -> Dictionary:
	if MusicManager.owned_tracks().size()<4: return {"ok":false,"reason":"Mindestens vier gesammelte MOD-Tracks noetig."}
	if PlayerStats.energie<ENERGY_COST: return {"ok":false,"reason":Loc.t("ui.mixtape_minigame.zu_muede_fuer_saubere_aufnahme", "Zu muede fuer eine saubere Aufnahme.")}
	return {"ok":true,"reason":""}
func _ready() -> void:
	super._ready(); var wins:=int(MinigameManager.record("mixtape").get("wins",0)); _model=Model.new(); _model.configure(clampi(1+floori(wins/2.0),1,5),hash("TAPE/%d/%d"%[TimeManager.day_counter,wins]),MusicManager.owned_tracks()); _build_ui()
func _build_ui() -> void:
	content.add_child(Bezel.dim_label(Loc.t("ui.mixtape_minigame.a_b_seiten_ausbalancieren_dramaturgie_ordnen", "A/B-Seiten ausbalancieren · Dramaturgie ordnen · jeden Track ohne Clipping aussteuern."),11))
	var deck:=HBoxContainer.new(); deck.name="MixtapeDeck25D"; deck.custom_minimum_size=Vector2(864,450); deck.add_theme_constant_override("separation",10); content.add_child(deck)
	var rig:=DepthRig.new(); deck.add_child(rig); rig.configure(deck,.68)
	var left:=VBoxContainer.new(); left.custom_minimum_size.x=310; left.add_child(Bezel.lcd_label(Loc.t("ui.mixtape_minigame.mod_bibliothek", "MOD-BIBLIOTHEK"),Palette.LCD_AMBER,10)); _library=ItemList.new(); _library.size_flags_vertical=Control.SIZE_EXPAND_FILL
	for t in _model.library: _library.add_item("%s · %s"%[t.title,t.author])
	left.add_child(_library); left.add_child(make_button(Loc.t("ui.mixtape_minigame.auf_band_legen", "AUF BAND LEGEN →"),_add)); deck.add_child(left)
	var center:=VBoxContainer.new(); center.size_flags_horizontal=Control.SIZE_EXPAND_FILL; center.add_child(Bezel.lcd_label(_model.tape_type+" · SIDE A / B",Palette.LCD_GREEN,10)); _tape=ItemList.new(); _tape.size_flags_vertical=Control.SIZE_EXPAND_FILL; _tape.item_selected.connect(func(i:int)->void:_selected=i;_sync_editors()); center.add_child(_tape)
	var ops:=GridContainer.new(); ops.columns=3; ops.add_child(make_button(Loc.t("ui.mixtape_minigame.text", "↑"),_move.bind(-1))); ops.add_child(make_button(Loc.t("ui.mixtape_minigame.text_a014", "↓"),_move.bind(1))); ops.add_child(make_button(Loc.t("ui.mixtape_minigame.a_b", "A/B"),_side)); ops.add_child(make_button(Loc.t("ui.mixtape_minigame.entfernen", "ENTFERNEN"),_remove)); ops.add_child(make_button(Loc.t("ui.mixtape_minigame.hinweis", "HINWEIS"),_hint)); ops.add_child(make_button(Loc.t("ui.mixtape_minigame.auto_curate", "AUTO-CURATE"),_auto)); center.add_child(ops)
	center.add_child(Bezel.dim_label(Loc.t("ui.mixtape_minigame.pegel_des_markierten_tracks", "PEGEL DES MARKIERTEN TRACKS"),8)); _gain=HSlider.new(); _gain.min_value=0;_gain.max_value=1;_gain.step=.01;_gain.value=.65;_gain.value_changed.connect(_set_gain);center.add_child(_gain); deck.add_child(center)
	var transport:=GridContainer.new();transport.columns=3
	transport.add_child(make_button(Loc.t("ui.mixtape_minigame.a_b_preview", "▶ A/B PREVIEW"),_toggle_preview));transport.add_child(Bezel.dim_label(Loc.t("ui.mixtape_minigame.cue", "CUE"),8));_cue=_slider(0,12,.02,_set_cue);transport.add_child(_cue)
	transport.add_child(Bezel.dim_label(Loc.t("ui.mixtape_minigame.fade_in", "FADE IN"),8));_fade_in=_slider(0,6,.1,_set_fade_in);transport.add_child(_fade_in);transport.add_child(Bezel.dim_label(Loc.t("ui.mixtape_minigame.fade_out", "FADE OUT"),8));_fade_out=_slider(0,6,.1,_set_fade_out);transport.add_child(_fade_out);center.add_child(transport)
	_meter= TapeMeter.new(); _meter.model=_model; _meter.stereo_texture=STEREO_ART; _meter.custom_minimum_size=Vector2(220,450); deck.add_child(_meter); _meter.name="TapeMeter"
	var commit:=make_button(Loc.t("ui.mixtape_minigame.master_aufnehmen", "● MASTER AUFNEHMEN"),_commit);commit.custom_minimum_size.y=36;content.add_child(commit)
	_status=Bezel.lcd_label("",Palette.LCD_GREEN,10);_status.custom_minimum_size.y=42;_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;content.add_child(_status);_refresh()
func _add()->void:
	var sel:=_library.get_selected_items();if sel.is_empty():return
	_model.add_track(str(_model.library[sel[0]].id));_refresh()
func _move(delta:int)->void:
	if _model.move(_selected,delta):_selected+=delta;_refresh()
func _side()->void:
	if _model.toggle_side(_selected):_refresh()
func _remove()->void:
	if _model.remove_at(_selected):_selected=-1;_refresh()
func _set_gain(v:float)->void:
	if _selected>=0:_model.set_gain(_selected,v);_refresh(false)
func _slider(lo:float,hi:float,step:float,cb:Callable)->HSlider:
	var slider:=HSlider.new();slider.min_value=lo;slider.max_value=hi;slider.step=step;slider.custom_minimum_size.x=95;slider.value_changed.connect(cb);return slider
func _sync_editors()->void:
	if _selected>=0 and _selected<_model.entries.size():
		var e:Dictionary=_model.entries[_selected];_gain.set_value_no_signal(float(e.gain));_cue.set_value_no_signal(float(e.get("cue",0)));_fade_in.set_value_no_signal(float(e.get("fade_in",.8)));_fade_out.set_value_no_signal(float(e.get("fade_out",1.2)));_meter.selected=_selected;_meter.queue_redraw()
func _set_cue(v:float)->void:
	if _selected>=0:_cue.set_value_no_signal(_model.set_cue(_selected,v));_refresh(false)
func _set_fade_in(v:float)->void:
	if _selected>=0:_model.set_fade(_selected,v,_fade_out.value);_refresh(false)
func _set_fade_out(v:float)->void:
	if _selected>=0:_model.set_fade(_selected,_fade_in.value,v);_refresh(false)
func _toggle_preview()->void:
	_playing=not _playing;_meter.playing=_playing;_meter.queue_redraw();_status.text=Loc.t("ui.mixtape_minigame.a_b_preview_s", "A/B PREVIEW · %s")%(Loc.t("ui.mixtape_minigame.transport_running", "TRANSPORT LAEUFT")if _playing else Loc.t("ui.mixtape_minigame.stop", "STOP"))
func _hint()->void:_status.text=_model.hint()
func _auto()->void:_model.auto_curate();_selected=-1;_refresh()
func _refresh(rebuild:=true)->void:
	if rebuild:
		_tape.clear()
		for e in _model.entries:_tape.add_item("%s  %02d:%02d  %s  %02d%%"%[e.side,floori(int(e.duration)/60.0),int(e.duration)%60,e.title,roundi(float(e.gain)*100)])
		if _selected>=0 and _selected<_tape.item_count:_tape.select(_selected)
	var ev:=_model.evaluation();_status.text=Loc.t("ui.mixtape_minigame.side_a_02d_02d_side_b", "SIDE A %02d:%02d · SIDE B %02d:%02d · BALANCE %02d%% · %s")%[floori(int(ev.a)/60.0),int(ev.a)%60,floori(int(ev.b)/60.0),int(ev.b)%60,roundi(float(ev.balance)*100),(Loc.t("ui.mixtape_minigame.master_ready", "MASTER READY")if ev.valid else Loc.t("ui.mixtape_minigame.not_master_ready", "NOCH NICHT MASTERFAEHIG"))]
	if _meter: _meter.queue_redraw()
func _commit()->bool:
	if _finished or not _model.complete() or not PlayerStats.use_energy(ENERGY_COST):return false
	_finished=true;var details:=_model.details();var serial:=(MinigameManager.creations.get("mixtape",[])as Array).size()+1
	var payload:={"id":"mixtape_%d_%02d"%[TimeManager.day_counter,serial],"title":"MIXTAPE %02d"%serial,"tracks":_model.entries.duplicate(true),"side_a":details.side_a,"side_b":details.side_b,"tape_type":_model.tape_type,"quality":_model.score()}
	MinigameManager.save_creation("mixtape",payload);MinigameManager.finish("mixtape",true,_model.score(),details);GameManager.flags["last_mixtape"]=payload
	_status.text=Loc.t("ui.mixtape_minigame.master_rec_d_tracks_04d_punkte", "MASTER REC · %d TRACKS · %04d PUNKTE")%[_model.entries.size(),_model.score()];AudioManager.key_enter();return true
class TapeMeter:
	extends Control
	var model:MixtapeModel
	var stereo_texture: Texture2D
	var selected:=-1
	var playing:=false
	var phase:=0.0
	func _ready()->void:set_process(true)
	func _process(delta:float)->void:
		if playing:phase=fmod(phase+delta*.22,1.0);queue_redraw()
	func _draw()->void:
		draw_rect(Rect2(Vector2.ZERO,size),Color8(21,24,27),true)
		if stereo_texture:
			draw_texture_rect(stereo_texture, Rect2(8, 6, size.x - 16, 128), false)
		draw_rect(Rect2(13,126,size.x-26,151),Color8(173,157,122),true)
		draw_rect(Rect2(20,135,size.x-40,132),Color8(42,38,32),true)
		draw_rect(Rect2(31,148,size.x-62,77),Color8(198,188,158),true)
		draw_rect(Rect2(63,160,size.x-126,34),Color8(69,59,48),true)
		for x in [size.x*.34,size.x*.66]:
			draw_circle(Vector2(x,177),27,Color8(32,30,27))
			draw_circle(Vector2(x,177),16,Color8(190,181,151),false,4)
			for spoke in 5:
				var angle := TAU * spoke / 5.0
				draw_line(Vector2(x,177), Vector2(x,177) + Vector2.from_angle(angle) * 12, Color8(105,98,82), 2)
		draw_colored_polygon(PackedVector2Array([Vector2(50,230),Vector2(size.x-50,230),Vector2(size.x-35,258),Vector2(35,258)]),Color8(116,101,78))
		for screw in [Vector2(27,143),Vector2(size.x-27,143),Vector2(27,256),Vector2(size.x-27,256)]: draw_circle(screw,2.2,Color8(225,214,185))
		var ev:=model.evaluation();var a:=minf(1,float(ev.a)/model.side_capacity);var b:=minf(1,float(ev.b)/model.side_capacity)
		draw_rect(Rect2(22,294,size.x-44,58),Color8(7,15,13),true)
		draw_rect(Rect2(29,306,(size.x-58)*a,12),Color8(71,220,125),true)
		draw_rect(Rect2(29,328,(size.x-58)*b,12),Color8(255,183,62),true)
		draw_string(ThemeDB.fallback_font,Vector2(30,286),"C-60 MASTER · DOLBY B",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color8(225,207,169))
		draw_string(ThemeDB.fallback_font,Vector2(25,382),"A/B TAPE COUNTER",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color8(225,207,169))
		draw_string(ThemeDB.fallback_font,Vector2(25,410),"REC PEAK  <  84%",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color8(125,235,160))
		if selected>=0:
			var wave:=model.waveform(selected,64);var mid:=374.0
			for i in range(1,wave.size()):
				var x0:=22+float(i-1)/63*(size.x-44);var x1:=22+float(i)/63*(size.x-44)
				draw_line(Vector2(x0,mid-wave[i-1]*18),Vector2(x1,mid-wave[i]*18),Color8(94,220,235),1.5)
			draw_line(Vector2(22+phase*(size.x-44),352),Vector2(22+phase*(size.x-44),398),Color8(255,191,70),2)
