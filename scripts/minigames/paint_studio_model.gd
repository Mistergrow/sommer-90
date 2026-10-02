class_name PaintStudioModel
extends RefCounted
## Zweilagiger nativer 46×32-Amiga-Pixelkern fuer Deluxe Malen.

const W := 46
const H := 32
const TRANSPARENT := -1
const BRIEFS := [&"scene_logo", &"demo_backdrop", &"sprite_sheet", &"disk_cover"]
const BRIEF_NAMES := {
	&"scene_logo":"SCENE LOGO", &"demo_backdrop":"DEMO BACKDROP",
	&"sprite_sheet":"SPRITE SHEET", &"disk_cover":"DISK COVER",
}
var level := 1
var run_seed := 1
var brief: StringName = &"scene_logo"
var layers: Array[PackedInt32Array] = []
var active_layer := 1
var color := 4
var secondary := 1
var mirror_x := false
var mirror_y := false
var actions := 0
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []

func configure(next_level: int, next_seed: int) -> void:
	level = clampi(next_level, 1, 5); run_seed = next_seed
	brief = BRIEFS[posmod(run_seed + level, BRIEFS.size())]
	layers.clear()
	for _i in 2:
		var layer := PackedInt32Array(); layer.resize(W * H); layer.fill(TRANSPARENT); layers.append(layer)
	active_layer = 1; color = 4; secondary = 1; mirror_x = false; mirror_y = false; actions = 0
	_undo.clear(); _redo.clear()

func begin_action() -> void:
	_undo.append(_snapshot())
	if _undo.size() > 80: _undo.pop_front()
	_redo.clear(); actions += 1

func undo() -> bool:
	if _undo.is_empty(): return false
	_redo.append(_snapshot()); _restore(_undo.pop_back()); return true

func redo() -> bool:
	if _redo.is_empty(): return false
	_undo.append(_snapshot()); _restore(_redo.pop_back()); return true

func history_depth() -> int: return _undo.size()

func set_layer(index: int) -> void: active_layer = clampi(index, 0, 1)

func clear_layer() -> void:
	begin_action(); layers[active_layer].fill(TRANSPARENT)

func paint(point: Vector2i, value := -99, record := false) -> bool:
	if not _inside(point): return false
	if record: begin_action()
	var actual := color if value == -99 else clampi(value, TRANSPARENT, 15)
	var changed := false
	for p in _symmetry_points(point): changed = _set_cell(p.x, p.y, actual) or changed
	return changed

func dither(point: Vector2i, erase := false, record := false) -> bool:
	if record: begin_action()
	var changed := false
	for y in range(point.y - 1, point.y + 2):
		for x in range(point.x - 1, point.x + 2):
			if (x + y) % 2 == 0:
				for p in _symmetry_points(Vector2i(x, y)):
					changed = _set_cell(p.x, p.y, TRANSPARENT if erase else color) or changed
	return changed

func line(a: Vector2i, b: Vector2i, value := -99) -> void:
	begin_action(); var actual := color if value == -99 else value
	var x0 := clampi(a.x,0,W-1); var y0 := clampi(a.y,0,H-1)
	var x1 := clampi(b.x,0,W-1); var y1 := clampi(b.y,0,H-1)
	var dx := absi(x1-x0); var sx := 1 if x0<x1 else -1
	var dy := -absi(y1-y0); var sy := 1 if y0<y1 else -1; var error := dx+dy
	while true:
		paint(Vector2i(x0,y0),actual)
		if x0==x1 and y0==y1: break
		var twice := 2*error
		if twice>=dy: error+=dy; x0+=sx
		if twice<=dx: error+=dx; y0+=sy

func rectangle(a: Vector2i, b: Vector2i, filled := false, value := -99) -> void:
	begin_action(); var actual := color if value == -99 else value
	var l:=clampi(mini(a.x,b.x),0,W-1);var r:=clampi(maxi(a.x,b.x),0,W-1)
	var t:=clampi(mini(a.y,b.y),0,H-1);var bottom:=clampi(maxi(a.y,b.y),0,H-1)
	for y in range(t,bottom+1):
		for x in range(l,r+1):
			if filled or x in [l,r] or y in [t,bottom]: paint(Vector2i(x,y),actual)

func ellipse(a: Vector2i, b: Vector2i, value := -99) -> void:
	begin_action(); var actual := color if value == -99 else value
	var center := Vector2((a.x+b.x)*.5,(a.y+b.y)*.5)
	var rx:=maxf(1,absf(b.x-a.x)*.5);var ry:=maxf(1,absf(b.y-a.y)*.5)
	var steps:=maxi(16,ceili(TAU*maxf(rx,ry)*1.4))
	for i in steps:
		var angle:=TAU*float(i)/steps
		paint(Vector2i(roundi(center.x+cos(angle)*rx),roundi(center.y+sin(angle)*ry)),actual)

func flood(point: Vector2i, value := -99) -> bool:
	if not _inside(point): return false
	var replacement := color if value == -99 else value
	var target := layer_at(active_layer,point.x,point.y)
	if target == replacement: return false
	begin_action(); var stack:Array[Vector2i]=[point]
	while not stack.is_empty():
		var p:Vector2i=stack.pop_back()
		if not _inside(p) or layer_at(active_layer,p.x,p.y)!=target: continue
		_set_cell(p.x,p.y,replacement)
		stack.append(Vector2i(p.x+1,p.y));stack.append(Vector2i(p.x-1,p.y));stack.append(Vector2i(p.x,p.y+1));stack.append(Vector2i(p.x,p.y-1))
	return true

func composite() -> PackedInt32Array:
	var result:=PackedInt32Array();result.resize(W*H);result.fill(TRANSPARENT)
	for i in W*H:
		result[i]=layers[1][i] if layers[1][i]>=0 else layers[0][i]
	return result

func at(x:int,y:int)->int:
	if x<0 or x>=W or y<0 or y>=H:return TRANSPARENT
	var index:=y*W+x
	return layers[1][index] if layers[1][index]>=0 else layers[0][index]

func layer_at(layer:int,x:int,y:int)->int:
	return layers[layer][y*W+x] if x>=0 and x<W and y>=0 and y<H else TRANSPARENT

func metrics()->Dictionary:
	var cells:=composite();var used:=0;var colors:={};var left:=0;var right:=0;var transitions:=0;var links:=0
	for y in H:
		for x in W:
			var v:=cells[y*W+x]
			if v >= 0:
				used += 1
				colors[v] = true
				if x < floori(W / 2.0):
					left += 1
				else:
					right += 1
			if x+1<W:links+=1;transitions+=int(v!=cells[y*W+x+1])
			if y+1<H:links+=1;transitions+=int(v!=cells[(y+1)*W+x])
	return{"used":used,"colors":colors.size(),"coverage":float(used)/(W*H),"contrast":float(transitions)/maxf(1,links),"balance":1.0-float(absi(left-right))/maxf(1,used)}

func print_ready()->bool:
	var m:=metrics();return m.used>=48 and m.colors>=2

func score()->int:
	if not print_ready():return 0
	var m:=metrics();var fit:=_brief_fit(m)
	return clampi(roundi(520+level*80+fit*480+_range(m.coverage,.08,.72)*200+_range(m.contrast,.03,.40)*190+m.balance*170-maxf(0,actions-60)),300,2000)

func details()->Dictionary:
	var m:=metrics();m.merge({"level":level,"brief":str(brief),"brief_fit":_brief_fit(m),"actions":actions,"score":score(),"layers":2,"mirror_x":mirror_x,"mirror_y":mirror_y},true);return m

func rle(cells:PackedInt32Array=PackedInt32Array())->String:
	var source:=composite() if cells.is_empty() else cells;var chunks:Array[String]=[];var last:=-99;var count:=0
	for value in source:
		if value==last:count+=1
		else:
			if count>0:chunks.append("%d:%d"%[last,count])
			last=value;count=1
	if count>0:chunks.append("%d:%d"%[last,count])
	return ",".join(chunks)

func decode_rle(encoded:String)->PackedInt32Array:
	var out:=PackedInt32Array()
	for chunk in encoded.split(",",false):
		var pair:=chunk.split(":",false)
		if pair.size()!=2:return PackedInt32Array()
		var value:=int(pair[0]);var count:=int(pair[1])
		if count<1 or out.size()+count>W*H:return PackedInt32Array()
		for _i in count:out.append(value)
	return out if out.size()==W*H else PackedInt32Array()

func load_layers(encoded:Array)->bool:
	if encoded.size()!=2:return false
	var bg:=decode_rle(str(encoded[0]));var ink:=decode_rle(str(encoded[1]))
	if bg.size()!=W*H or ink.size()!=W*H:return false
	begin_action();layers=[bg,ink];return true

func move_region(region:Rect2i,delta:Vector2i)->bool:
	var clipped:=region.intersection(Rect2i(0,0,W,H))
	if clipped.size.x<=0 or clipped.size.y<=0:return false
	begin_action();var source:=layers[active_layer].duplicate()
	for y in range(clipped.position.y,clipped.end.y):
		for x in range(clipped.position.x,clipped.end.x):layers[active_layer][y*W+x]=TRANSPARENT
	for y in range(clipped.position.y,clipped.end.y):
		for x in range(clipped.position.x,clipped.end.x):
			var target:=Vector2i(x,y)+delta
			if _inside(target):layers[active_layer][target.y*W+target.x]=source[y*W+x]
	return true

func flip_region_x(region:Rect2i)->bool:
	var clipped:=region.intersection(Rect2i(0,0,W,H));if clipped.size.x<=0:return false
	begin_action();var source:=layers[active_layer].duplicate()
	for y in range(clipped.position.y,clipped.end.y):
		for x in range(clipped.position.x,clipped.end.x):layers[active_layer][y*W+x]=source[y*W+clipped.position.x+clipped.end.x-1-x]
	return true

func _brief_fit(m:Dictionary)->float:
	match brief:
		&"scene_logo":return _range(m.coverage,.10,.46)*.35+_range(m.colors,3,8)*.30+m.balance*.35
		&"demo_backdrop":return _range(m.coverage,.38,.82)*.40+_range(m.colors,5,14)*.35+_range(m.contrast,.05,.35)*.25
		&"sprite_sheet":return _range(m.coverage,.12,.55)*.30+_range(m.contrast,.09,.48)*.40+_range(m.colors,3,10)*.30
		_:return _range(m.coverage,.22,.68)*.35+_range(m.colors,4,12)*.30+m.balance*.35

func _range(value:float,low:float,high:float)->float:
	if value>=low and value<=high:return 1.0
	var span:=maxf(.001,high-low);return clampf(1.0-(low-value)/span if value<low else 1.0-(value-high)/span,0,1)

func _symmetry_points(point:Vector2i)->Array[Vector2i]:
	var result:Array[Vector2i]=[point]
	if mirror_x:result.append(Vector2i(W-1-point.x,point.y))
	if mirror_y:result.append(Vector2i(point.x,H-1-point.y))
	if mirror_x and mirror_y:result.append(Vector2i(W-1-point.x,H-1-point.y))
	return result

func _inside(point:Vector2i)->bool:return point.x>=0 and point.x<W and point.y>=0 and point.y<H
func _set_cell(x:int,y:int,value:int)->bool:
	if x<0 or x>=W or y<0 or y>=H:return false
	var index:=y*W+x
	if layers[active_layer][index]==value:return false
	layers[active_layer][index]=value;return true
func _snapshot()->Dictionary:return{"layers":[layers[0].duplicate(),layers[1].duplicate()],"active":active_layer}
func _restore(snapshot:Dictionary)->void:
	var saved:Array=snapshot.layers;layers=[(saved[0] as PackedInt32Array).duplicate(),(saved[1] as PackedInt32Array).duplicate()];active_layer=int(snapshot.active)
