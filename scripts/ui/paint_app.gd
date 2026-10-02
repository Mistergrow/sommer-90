extends WbApp
## DELUXE MALEN PRO — zweilagiges 46×32-Pixelstudio im Amiga-Programmstil.

const Model := preload("res://scripts/minigames/paint_studio_model.gd")
const CW := Model.W
const CH := Model.H
const CX := 156.0
const CY := 42.0
const CELL := 10.0
const PAL := [
	Color8(0,0,0),Color8(255,255,255),Color8(120,120,120),Color8(60,60,60),
	Color8(200,40,40),Color8(240,130,40),Color8(240,220,60),Color8(90,200,90),
	Color8(40,150,90),Color8(60,130,230),Color8(40,60,160),Color8(150,80,210),
	Color8(220,120,190),Color8(150,90,50),Color8(230,190,140),Color8(20,30,50),
]
const TOOL_NAMES := {"pen":"PEN","line":"LINE","rect":"BOX","ellipse":"OVAL","fill":"FILL","dither":"DITHER","erase":"ERASE"}

var _model: PaintStudioModel
var _tool := "pen"
var _painting := false
var _anchor := Vector2i(-1,-1)
var _hover := Vector2i(-1,-1)
var _saved_revision := ""
var _title_edit: LineEdit
var _message := "READY"
@warning_ignore("unused_private_class_variable")   # Property-Brücke (Tests/extern lesen/schreiben via _cells)
var _cells: PackedInt32Array:
	get: return _model.composite() if _model else PackedInt32Array()
	set(value):
		if _model and value.size()==CW*CH:_model.layers[1]=value.duplicate()

func _init()->void:
	app_title="DELUXE MALEN II 1.0  ·  HAM-FREIE 16-FARBEN-WORKSTATION"
	app_bg=Color8(27,30,39);app_bar=Color8(55,71,106);app_accent=Color8(149,192,225)

func _build_app()->void:
	var wins:=int(MinigameManager.record("paint").get("wins",0))
	_model=Model.new();_model.configure(clampi(1+floori(wins/2.0),1,5),hash("PAINT/%d/%d"%[TimeManager.day_counter,wins]))
	for i in PAL.size():
		var col:=i%4;var row:=floori(i/4.0)
		add_button("",Rect2(12+col*31,40+row*22,28,19),_pick_color.bind(i),Color.WHITE,false)
	var tool_specs=[["pen",12,138],["line",73,138],["rect",12,162],["ellipse",73,162],["fill",12,186],["dither",73,186],["erase",12,210]]
	for spec in tool_specs:add_button(str(TOOL_NAMES[spec[0]]),Rect2(spec[1],spec[2],58,20),_set_tool.bind(spec[0]),Color8(225,229,235))
	add_button("BG LAYER",Rect2(12,238,58,20),_set_layer.bind(0),Color8(155,205,255))
	add_button("INK LAYER",Rect2(73,238,58,20),_set_layer.bind(1),Color8(255,198,100))
	add_button("MIRROR X",Rect2(12,262,58,20),_toggle_mirror.bind(true),Color8(190,215,235))
	add_button("MIRROR Y",Rect2(73,262,58,20),_toggle_mirror.bind(false),Color8(190,215,235))
	add_button("UNDO",Rect2(12,286,58,20),_undo_edit,Color8(160,185,235))
	add_button("REDO",Rect2(73,286,58,20),_redo_edit,Color8(160,185,235))
	add_button("CLEAR",Rect2(12,312,58,20),_clear,Color8(245,166,80))
	add_button("LOAD LAST",Rect2(73,312,58,20),_load_last,Color8(110,205,245))
	add_button("BILD SICHERN",Rect2(12,340,119,28),_save_bitmap,Color8(105,235,155))
	_title_edit=LineEdit.new();_title_edit.placeholder_text=Loc.t("ui.paint_app.artwork_title", "ARTWORK TITLE");_title_edit.max_length=24;_title_edit.text=Loc.t("ui.paint_app.scene_art_01", "SCENE ART 01");add_child(_title_edit)

func _layout_app()->void:
	if _title_edit:_title_edit.position=_V(430,21);_title_edit.size=Vector2(184*_sx(),18*_sy())

func _set_tool(tool:String)->void:_tool=tool;_anchor=Vector2i(-1,-1);_message="TOOL: "+TOOL_NAMES[tool]
func _pick_color(index:int)->void:_model.color=index;_tool="pen";_message="COLOR %02d"%index
func _set_layer(index:int)->void:_model.set_layer(index);_message="ACTIVE: "+("BACKGROUND"if index==0 else"INK")
func _toggle_mirror(horizontal:bool)->void:
	if horizontal:_model.mirror_x=not _model.mirror_x
	else:_model.mirror_y=not _model.mirror_y
	_message="SYMMETRY X:%s Y:%s"%["ON"if _model.mirror_x else"OFF","ON"if _model.mirror_y else"OFF"]
func _clear()->void:_model.clear_layer();_anchor=Vector2i(-1,-1);_message="ACTIVE LAYER CLEARED"
func _undo_edit()->void:if _model.undo():_anchor=Vector2i(-1,-1);_message="UNDO"
func _redo_edit()->void:if _model.redo():_anchor=Vector2i(-1,-1);_message="REDO"
func _load_last()->void:
	var last:=MinigameManager.latest_creation("paint")
	if last.is_empty():_message="NO SAVED ARTWORK";return
	if _model.load_layers(last.get("layer_rle",[])):
		_title_edit.text=str(last.get("title","LOADED ART"));_saved_revision="";_message="LOADED FOR RE-EDIT"
	else:_message="LEGACY ART HAS NO LAYERS"

func _gui_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode==KEY_Z:_undo_edit();accept_event();return
		if event.ctrl_pressed and event.keycode==KEY_Y:_redo_edit();accept_event();return
		match event.keycode:
			KEY_P:_set_tool("pen")
			KEY_L:_set_tool("line")
			KEY_R:_set_tool("rect")
			KEY_O:_set_tool("ellipse")
			KEY_F:_set_tool("fill")
			KEY_D:_set_tool("dither")
			KEY_E:_set_tool("erase")
			KEY_X:_toggle_mirror(true)
			KEY_Y:_toggle_mirror(false)
			KEY_H:
				var bounds:=_paint_bounds();if bounds.size!=Vector2i.ZERO:_model.flip_region_x(bounds);_message="SELECTION FLIPPED"
			KEY_LEFT:
				if event.ctrl_pressed:_model.move_region(_paint_bounds(),Vector2i.LEFT);_message="SELECTION LEFT"
			KEY_RIGHT:
				if event.ctrl_pressed:_model.move_region(_paint_bounds(),Vector2i.RIGHT);_message="SELECTION RIGHT"
	if event is InputEventMouseMotion:
		_hover=_cell_at(event.position)
		if _painting and _hover.x>=0:
			if _tool=="dither":_model.dither(_hover,false)
			else:_model.paint(_hover,Model.TRANSPARENT if _tool=="erase" else -99)
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		var erase: bool = event.button_index == MOUSE_BUTTON_RIGHT
		if event.pressed:
			var point:=_cell_at(event.position);if point.x<0:return
			match _tool:
				"pen","erase","dither":
					_model.begin_action();_painting=true
					if _tool=="dither":_model.dither(point,erase)
					else:_model.paint(point,Model.TRANSPARENT if erase or _tool=="erase" else -99)
				"fill":_model.flood(point,Model.TRANSPARENT if erase else -99)
				"line","rect","ellipse":
					if _anchor.x<0:_anchor=point;_message="ANCHOR SET"
					elif _tool=="line":_model.line(_anchor,point,Model.TRANSPARENT if erase else -99);_anchor=Vector2i(-1,-1)
					elif _tool=="rect":_model.rectangle(_anchor,point,false,Model.TRANSPARENT if erase else -99);_anchor=Vector2i(-1,-1)
					else:_model.ellipse(_anchor,point,Model.TRANSPARENT if erase else -99);_anchor=Vector2i(-1,-1)
		else:_painting=false

func _cell_at(screen_pos:Vector2)->Vector2i:
	var vx:=screen_pos.x/_sx();var vy:=screen_pos.y/_sy()
	if vx<CX or vy<CY or vx>=CX+CW*CELL or vy>=CY+CH*CELL:return Vector2i(-1,-1)
	return Vector2i(int((vx-CX)/CELL),int((vy-CY)/CELL))

func _paint_bounds()->Rect2i:
	var min_p:=Vector2i(CW,CH);var max_p:=Vector2i(-1,-1)
	for y in CH:
		for x in CW:
			if _model.layer_at(_model.active_layer,x,y)>=0:min_p.x=mini(min_p.x,x);min_p.y=mini(min_p.y,y);max_p.x=maxi(max_p.x,x);max_p.y=maxi(max_p.y,y)
	return Rect2i()if max_p.x<0 else Rect2i(min_p,max_p-min_p+Vector2i.ONE)

func _save_bitmap()->bool:
	if not _model.print_ready():UIManager.toast(Loc.t("ui.paint_app.artwork_braucht_mindestens_48_pixel_zwei", "Artwork braucht mindestens 48 Pixel und zwei Farben."));return false
	var signature:=_rle()
	if signature==_saved_revision:UIManager.toast(Loc.t("ui.paint_app.diese_revision_ist_bereits_gesichert", "Diese Revision ist bereits gesichert."));return false
	if not PlayerStats.use_energy(3):UIManager.toast(Loc.t("ui.paint_app.zu_muede_zum_speichern_3_energie", "Zu muede zum Speichern (3 Energie)."));return false
	var index:=(MinigameManager.creations.get("paint",[])as Array).size()+1
	var title_text:=_title_edit.text.strip_edges();if title_text.is_empty():title_text="PIXELBILD %02d"%index
	var details:=_model.details();var score:=_model.score()
	var payload:={"id":"bitmap_%d_%02d"%[TimeManager.day_counter,index],"title":title_text,"width":CW,"height":CH,"rle":signature,"layer_rle":[_model.rle(_model.layers[0]),_model.rle(_model.layers[1])],"coverage":details.used,"colors":details.colors,"score":score,"brief":details.brief,"layers":2}
	MinigameManager.save_creation("paint",payload);MinigameManager.finish("paint",true,score,details)
	GameManager.flags["paint_created"]=true;GameManager.flags["last_paint_art"]=payload
	_saved_revision=signature;AudioManager.floppy_read();UIManager.toast(Loc.t("ui.paint_app.s_gesichert_d_punkte_szene_studio", "%s gesichert · %d Punkte · Szene-Studio aktualisiert.")%[title_text,score]);_message="SAVED REVISION %02d"%index;return true

func _rle()->String:return _model.rle()

func _content(font:Font)->void:
	# Workbench chrome and canvas.
	rect(6,24,132,352,Color8(33,40,55));rect_line(6,24,132,352,Color8(91,111,144))
	text(font,"16-COLOR PALETTE",12,36,8,Color8(202,217,232))
	for widget in _widgets:
		if widget.get("auto_draw",true):continue
		var index:=_palette_index(widget.rect);if index<0:continue
		var r:Rect2=widget.rect;rect(r.position.x,r.position.y,r.size.x,r.size.y,PAL[index]);rect_line(r.position.x-1,r.position.y-1,r.size.x+2,r.size.y+2,Color8(255,226,92)if index==_model.color else Color8(20,22,28),2 if index==_model.color else 1)
	text(font,"L%d  %s"%[_model.level,Model.BRIEF_NAMES[_model.brief]],CX,34,9,Color8(109,236,170))
	text(font,"TITLE",390,34,8,Color8(166,180,204))
	rect(CX-3,CY-3,CW*CELL+6,CH*CELL+6,Color8(9,11,17))
	var cells:=_model.composite()
	for y in CH:
		for x in CW:
			var value:=cells[y*CW+x]
			var color_value:Color=PAL[value]if value>=0 else(Color8(57,60,69)if(x+y)%2==0 else Color8(48,51,60))
			rect(CX+x*CELL,CY+y*CELL,CELL,CELL,color_value)
			# Das Studio zeigt bewusst immer das native Pixelraster; dies ist Teil
			# der Werkzeugpraezision und keine globale Grafikoption.
			rect_line(CX+x*CELL,CY+y*CELL,CELL,CELL,Color(0,0,0,.07))
	if _model.mirror_x:rect(CX+CW*CELL*.5-1,CY,2,CH*CELL,Color(1,.65,.18,.55))
	if _model.mirror_y:rect(CX,CY+CH*CELL*.5-1,CW*CELL,2,Color(1,.65,.18,.55))
	if _hover.x>=0:rect_line(CX+_hover.x*CELL,CY+_hover.y*CELL,CELL,CELL,Color8(255,221,92),2)
	if _anchor.x>=0 and _hover.x>=0:
		var ax:=CX+_anchor.x*CELL+CELL*.5;var ay:=CY+_anchor.y*CELL+CELL*.5;var bx:=CX+_hover.x*CELL+CELL*.5;var by:=CY+_hover.y*CELL+CELL*.5
		if _tool=="line":draw_line(_V(ax,ay),_V(bx,by),Color(1,.75,.25,.8),2)
		else:rect_line(minf(ax,bx),minf(ay,by),absf(bx-ax),absf(by-ay),Color(1,.75,.25,.8),2)
	var m:=_model.metrics();var fit:=roundi(float(_model.details().brief_fit)*100)
	text(font,"%s · %s LAYER · X:%s Y:%s"%[_message,"BG"if _model.active_layer==0 else"INK","ON"if _model.mirror_x else"OFF","ON"if _model.mirror_y else"OFF"],CX,378,8,Color8(155,190,224))
	text(font,"INK %02d%%  COLORS %02d  BAL %02d%%  BRIEF %02d%%  SCORE %04d"%[roundi(m.coverage*100),m.colors,roundi(m.balance*100),fit,_model.score()],CX,391,9,Color8(101,235,150))

func _palette_index(r:Rect2)->int:
	for i in PAL.size():
		if is_equal_approx(r.position.x,12+(i%4)*31)and is_equal_approx(r.position.y,40+floori(i/4.0)*22):return i
	return -1
