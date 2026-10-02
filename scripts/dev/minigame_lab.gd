class_name MinigameLab
extends Control
## Startbare Einzelspiel-Werkstatt. Jede Szene unter scenes/minigame_labs setzt
## nur ihre ID; Level, Seed, Position und Skalierung bleiben im Inspector editierbar.

@export var minigame_id := "box_sort"
@export_range(1,5,1) var level := 1
@export var lab_seed := 1990
@export_range(1990,1999,1) var lab_year := 1991
@export var window_position := Vector2(170,70)
@export_range(.65,1.35,.05) var window_scale := 1.0
@export var mute_world_notifications := true
@export_enum("dot_matrix_9pin", "dot_matrix_24_mono", "dot_matrix_24_color") var printer_model := "dot_matrix_24_color"

const UI_PATHS := {
	"label_design":"res://scripts/ui/label_designer.gd","box_sort":"res://scripts/ui/box_sort_minigame.gd",
	"drive_clean":"res://scripts/ui/drive_clean_minigame.gd","joystick_repair":"res://scripts/ui/joystick_repair_minigame.gd",
	"monitor_tune":"res://scripts/ui/monitor_tune_minigame.gd","cable_untangle":"res://scripts/ui/cable_untangle_minigame.gd",
	"bargain":"res://scripts/ui/bargain_minigame.gd","bbs_link":"res://scripts/ui/bbs_carrier_minigame.gd",
	"tracker_pattern":"res://scripts/ui/tracker_pattern_minigame.gd","paint":"res://scripts/ui/paint_app.gd",
	"room_tidy":"res://scripts/ui/room_tidy_minigame.gd","hardware_assembly":"res://scripts/ui/hardware_assembly_minigame.gd",
	"listing_type":"res://scripts/ui/listing_type_minigame.gd","scene_patch":"res://scripts/ui/scene_patch_app.gd",
	"disk_rescue":"res://scripts/ui/disk_rescue_minigame.gd","disk_media_repair":"res://scripts/ui/disk_repair_minigame.gd",
	"printer_align":"res://scripts/ui/printer_align_minigame.gd",
	"mixtape":"res://scripts/ui/mixtape_minigame.gd","cracktro_opt":"res://scripts/ui/cracktro_optimization_minigame.gd",
	"shop_diagnosis":"res://scripts/ui/shop_diagnosis_minigame.gd",
}
var _game:Control
var _host:Control
var _info:Label

func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_lab_chrome();call_deferred("_restart")

func _build_lab_chrome()->void:
	var bg:=ColorRect.new();bg.color=Color8(18,22,29);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(bg)
	_host=Control.new();_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(_host)
	var bar:=HBoxContainer.new();bar.z_index=500;bar.position=Vector2(12,10);bar.size=Vector2(1416,42);bar.add_theme_constant_override("separation",8);add_child(bar)
	var title:=Label.new();title.text=Loc.t("misc.minigame_lab.minigame_lab", "MINIGAME LAB · ")+minigame_id.to_upper();title.add_theme_font_size_override("font_size",18);title.custom_minimum_size.x=350;bar.add_child(title)
	bar.add_child(_button(Loc.t("misc.minigame_lab.restart", "RESTART"),_restart));bar.add_child(_button(Loc.t("misc.minigame_lab.level_down", "LEVEL −"),func()->void:level=maxi(1,level-1);_restart()));bar.add_child(_button(Loc.t("misc.minigame_lab.level_up", "LEVEL +"),func()->void:level=mini(5,level+1);_restart()));bar.add_child(_button(Loc.t("misc.minigame_lab.seed_down", "SEED −"),func()->void:lab_seed-=1;_restart()));bar.add_child(_button(Loc.t("misc.minigame_lab.seed_up", "SEED +"),func()->void:lab_seed+=1;_restart()))
	_info=Label.new();_info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_info.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;bar.add_child(_info)

func _button(label:String,callback:Callable)->Button:
	var button:=Button.new();button.text=label;button.pressed.connect(callback);return button

func _restart()->void:
	if is_instance_valid(_game):_game.queue_free();await get_tree().process_frame
	_prepare_world();_game=_create_game()
	if _game==null:_info.text=Loc.t("misc.minigame_lab.fehler_ui_nicht_erzeugt", "FEHLER: UI NICHT ERZEUGT");return
	_host.add_child(_game)
	if _game is WbApp:_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:_game.position=window_position;_game.scale=Vector2.ONE*window_scale
	_info.text=Loc.t("misc.minigame_lab.level_d_seed_d_f1_hilfe", "LEVEL %d · SEED %d · F1 HILFE · F5 RESTART")%[level,lab_seed]
	if mute_world_notifications:call_deferred("_hide_noise")

func _prepare_world()->void:
	GameManager.new_game();GameManager.state=GameManager.State.PLAYING;GameManager.current_location_id="room"
	PlayerStats.energie=100;PlayerStats.wissen=100;PlayerStats.ruf=20
	for hardware in ["computer_amiga_500", "monitor", "modem"]:
		PlayerStats.add_hardware(hardware)
	PlayerStats.add_hardware({
		"dot_matrix_9pin": "dot_matrix",
		"dot_matrix_24_mono": "dot_matrix_24",
		"dot_matrix_24_color": "dot_matrix_24_color",
	}.get(printer_model, "dot_matrix_24_color"))
	for program in ["protracker","noisetracker_homage"]:PlayerStats.add_program(program)
	PlayerStats.hardware["drive_dirt"]=.78
	GameManager.flags["gruber_workshop_basic"]=true
	TimeManager.year=lab_year
	MinigameManager.reset();MinigameManager.records[minigame_id]={"plays":0,"wins":maxi(0,(level-1)*2),"best_score":0,"last_score":0}
	if minigame_id in ["cable_untangle","hardware_assembly","shop_diagnosis"]:
		GameManager.current_location_id="computer_shop";TimeManager.slot=1
		var trust:Dictionary=NPCManager.trust;trust["npc_gruber"]=50;NPCManager.trust=trust
	if minigame_id=="bargain":FleaMarketManager.offers=[{"id":99001,"template_id":"games_bundle","price":24,"seller":"Krause","haggled":false,"checked":false}]
	if minigame_id=="bbs_link":
		var boards:=BBSManager.boards_for_year();if not boards.is_empty():BBSManager.current_board=(boards[0]as Dictionary).duplicate(true)

func _create_game()->Control:
	var script:=load(str(UI_PATHS.get(minigame_id,"")))as GDScript;if script==null:return null
	var game:=script.new()as Control
	match minigame_id:
		"label_design":game.set("disk",DiskManager.disks[0])
		"bargain":game.set("offer_id",99001)
		"bbs_link":game.set("file_entry",{"id":"lab_download","content_title":"LAB DEMO","content_type":"demo","condition":88})
		"scene_patch":game.set("disk",_bytewerk_copy())
		"disk_rescue":game.set("source",_rescue_source())
		"disk_media_repair":game.set("source",_repair_source())
		"cracktro_opt":game.set("project",DemoManager.create_project(lab_seed))
		"shop_diagnosis":game.set("job_id","job_gruber_diagnosis")
	return game

func _bytewerk_copy()->Disk:
	GameManager.flags["tut_bytewerk_intro"]=true
	var source:=Disk.new();source.uid="lab_original";source.software_id="monkey_adventure";source.content_type="spiel";source.content_title="LAB ADVENTURE";source.provenance="original";source.condition=100
	var target:=Disk.new();target.uid="lab_workcopy";target.condition=100;CultureManager.copy_rules(source,target);return target

func _rescue_source()->Disk:
	for disk:Disk in DiskManager.disks:
		if disk.content_type!="leer":disk.checked=true;disk.condition=35;return disk
	return DiskManager.disks[0]

func _repair_source()->Disk:
	for disk:Disk in DiskManager.disks:
		if disk.content_type!="leer":disk.checked=true;disk.condition=48;disk.last_repair_day=-1;return disk
	return DiskManager.disks[0]

func _hide_noise()->void:
	for node in get_tree().root.find_children("*","",true,false):
		if not node is CanvasItem or node==self or is_ancestor_of(node):continue
		var script:=node.get_script()as Script
		if script and(script.resource_path.ends_with("dialogue_window.gd")or script.resource_path.ends_with("juice_layer.gd")):(node as CanvasItem).visible=false

func _unhandled_key_input(event:InputEvent)->void:
	if event.pressed and not event.echo and event.keycode==KEY_F5:_restart();get_viewport().set_input_as_handled()
