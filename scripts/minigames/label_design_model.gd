class_name LabelDesignModel
extends RefCounted
## Reines 44×26-Labelstudio. UI, DiskComposer und Inventar besitzen keine
## Gestaltungswahrheit; alle Werkzeuge, Historie, Briefs und Wertung leben hier.

const W := 44
const H := 26
const PAPER := 0
const BRIEFS := [&"crew_badge", &"spectrum", &"technical", &"minimal"]
const BRIEF_NAMES := {
	&"crew_badge": "CREW BADGE",
	&"spectrum": "COPPER SPECTRUM",
	&"technical": "TECHNICAL MASTER",
	&"minimal": "MINIMAL PD",
}
const BRIEF_TEXT := {
	&"crew_badge": "Klare Mitte, 2–5 Farben, kompakte Signatur.",
	&"spectrum": "Mindestens 4 Farben und lebendige Kanten.",
	&"technical": "Rahmen, hoher Kontrast und saubere Balance.",
	&"minimal": "Wenig Tinte, maximal 3 Farben, starke Silhouette.",
}
const GLYPHS := {
	"A":"010/101/111/101/101", "B":"110/101/110/101/110",
	"C":"011/100/100/100/011", "D":"110/101/101/101/110",
	"E":"111/100/110/100/111", "F":"111/100/110/100/100",
	"G":"011/100/101/101/011", "H":"101/101/111/101/101",
	"I":"111/010/010/010/111", "J":"001/001/001/101/010",
	"K":"101/101/110/101/101", "L":"100/100/100/100/111",
	"M":"101/111/111/101/101", "N":"101/111/111/111/101",
	"O":"010/101/101/101/010", "P":"110/101/110/100/100",
	"Q":"010/101/101/111/011", "R":"110/101/110/101/101",
	"S":"011/100/010/001/110", "T":"111/010/010/010/010",
	"U":"101/101/101/101/111", "V":"101/101/101/101/010",
	"W":"101/101/111/111/101", "X":"101/101/010/101/101",
	"Y":"101/101/010/010/010", "Z":"111/001/010/100/111",
	"0":"111/101/101/101/111", "1":"010/110/010/010/111",
	"2":"110/001/010/100/111", "3":"110/001/010/001/110",
	"4":"101/101/111/001/001", "5":"111/100/110/001/110",
	"6":"011/100/111/101/111", "7":"111/001/010/010/010",
	"8":"111/101/111/101/111", "9":"111/101/111/001/110",
	"-":"000/000/111/000/000", ".":"000/000/000/000/010",
}

var level := 1
var run_seed := 1
var brief: StringName = &"crew_badge"
var cells := PackedInt32Array()
var current_color := 1
var mirror_x := false
var actions := 0
var assisted := false
var _undo: Array[PackedInt32Array] = []
var _redo: Array[PackedInt32Array] = []

func configure(next_level: int, next_seed: int, initial := PackedInt32Array()) -> void:
	level = clampi(next_level, 1, 5)
	run_seed = next_seed
	brief = BRIEFS[posmod(run_seed + level, BRIEFS.size())]
	cells = initial.duplicate()
	if cells.size() != W * H:
		cells.resize(W * H)
		cells.fill(PAPER)
	current_color = 1
	mirror_x = false
	actions = 0
	assisted = false
	_undo.clear()
	_redo.clear()

func set_color(value: int) -> void:
	current_color = clampi(value, 0, 7)

func history_depth() -> int:
	return _undo.size()

func begin_action() -> void:
	_undo.append(cells.duplicate())
	if _undo.size() > 64: _undo.pop_front()
	_redo.clear()
	actions += 1

func undo() -> bool:
	if _undo.is_empty(): return false
	_redo.append(cells.duplicate())
	cells = _undo.pop_back()
	return true

func redo() -> bool:
	if _redo.is_empty(): return false
	_undo.append(cells.duplicate())
	cells = _redo.pop_back()
	return true

func clear() -> void:
	begin_action()
	cells.fill(PAPER)

func paint(point: Vector2i, color := -1, record := false) -> bool:
	if not _inside(point): return false
	if record: begin_action()
	var value := current_color if color < 0 else clampi(color, 0, 7)
	var changed := _set_cell(point.x, point.y, value)
	if mirror_x:
		changed = _set_cell(W - 1 - point.x, point.y, value) or changed
	return changed

func line(a: Vector2i, b: Vector2i, color := -1) -> void:
	begin_action()
	var value := current_color if color < 0 else clampi(color, 0, 7)
	var x0 := clampi(a.x, 0, W - 1); var y0 := clampi(a.y, 0, H - 1)
	var x1 := clampi(b.x, 0, W - 1); var y1 := clampi(b.y, 0, H - 1)
	var dx := absi(x1 - x0); var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0); var sy := 1 if y0 < y1 else -1
	var error := dx + dy
	while true:
		paint(Vector2i(x0, y0), value)
		if x0 == x1 and y0 == y1: break
		var twice := 2 * error
		if twice >= dy: error += dy; x0 += sx
		if twice <= dx: error += dx; y0 += sy

func rectangle(a: Vector2i, b: Vector2i, color := -1, filled := false) -> void:
	begin_action()
	var value := current_color if color < 0 else clampi(color, 0, 7)
	var left := clampi(mini(a.x, b.x), 0, W - 1)
	var right := clampi(maxi(a.x, b.x), 0, W - 1)
	var top := clampi(mini(a.y, b.y), 0, H - 1)
	var bottom := clampi(maxi(a.y, b.y), 0, H - 1)
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			if filled or x in [left, right] or y in [top, bottom]: paint(Vector2i(x, y), value)

func flood(point: Vector2i, color := -1) -> bool:
	if not _inside(point): return false
	var replacement := current_color if color < 0 else clampi(color, 0, 7)
	var target := at(point.x, point.y)
	if target == replacement: return false
	begin_action()
	var stack: Array[Vector2i] = [point]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if not _inside(p) or at(p.x, p.y) != target: continue
		_set_cell(p.x, p.y, replacement)
		stack.append(Vector2i(p.x + 1, p.y)); stack.append(Vector2i(p.x - 1, p.y))
		stack.append(Vector2i(p.x, p.y + 1)); stack.append(Vector2i(p.x, p.y - 1))
	return true

func stamp(kind: StringName, center := Vector2i(W >> 1, H >> 1)) -> bool:
	begin_action()
	assisted = true
	var points: Array[Vector2i] = []
	match kind:
		&"bolt": points = [Vector2i(1,-6),Vector2i(-3,-1),Vector2i(0,-1),Vector2i(-2,6),Vector2i(4,0),Vector2i(1,0)]
		&"disk":
			for y in range(-5, 6):
				for x in range(-6, 7):
					if x in [-6,6] or y in [-5,5] or (y <= -2 and x in [-2,-1,0,1,2]): points.append(Vector2i(x,y))
		&"star":
			points = [Vector2i(0,-6),Vector2i(-2,-1),Vector2i(-6,-1),Vector2i(-3,2),Vector2i(-4,6),Vector2i(0,3),Vector2i(4,6),Vector2i(3,2),Vector2i(6,-1),Vector2i(2,-1)]
		&"checker":
			for y in range(-5, 6):
				for x in range(-9, 10):
					if (x + y) % 2 == 0: points.append(Vector2i(x,y))
		_: return false
	for p in points: paint(center + p)
	return true

func stamp_text(text: String, color := -1) -> bool:
	var clean := text.to_upper().strip_edges()
	var glyphs: Array[String] = []
	for character in clean:
		if GLYPHS.has(character): glyphs.append(character)
		if glyphs.size() >= 10: break
	if glyphs.is_empty(): return false
	begin_action()
	assisted = true
	var value := current_color if color < 0 else clampi(color, 0, 7)
	var width := glyphs.size() * 4 - 1
	var start_x := floori((W - width) / 2.0)
	var start_y := floori((H - 5) / 2.0)
	for i in glyphs.size():
		var rows: PackedStringArray = str(GLYPHS[glyphs[i]]).split("/")
		for y in 5:
			for x in 3:
				if rows[y][x] == "1": _set_cell(start_x + i * 4 + x, start_y + y, value)
	return true

func content_bounds()->Rect2i:
	var min_p:=Vector2i(W,H);var max_p:=Vector2i(-1,-1)
	for y in H:
		for x in W:
			if at(x,y)!=PAPER:min_p.x=mini(min_p.x,x);min_p.y=mini(min_p.y,y);max_p.x=maxi(max_p.x,x);max_p.y=maxi(max_p.y,y)
	return Rect2i()if max_p.x<0 else Rect2i(min_p,max_p-min_p+Vector2i.ONE)

func move_content(delta:Vector2i)->bool:
	var bounds:=content_bounds();if bounds.size==Vector2i.ZERO:return false
	begin_action();var source:=cells.duplicate();cells.fill(PAPER)
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			var target:=Vector2i(x,y)+delta
			if _inside(target):cells[target.y*W+target.x]=source[y*W+x]
	return true

func flip_content_x()->bool:
	var bounds:=content_bounds();if bounds.size==Vector2i.ZERO:return false
	begin_action();var source:=cells.duplicate()
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):cells[y*W+x]=source[y*W+bounds.position.x+bounds.end.x-1-x]
	return true

func at(x: int, y: int) -> int:
	return cells[y * W + x] if x >= 0 and x < W and y >= 0 and y < H else PAPER

func metrics(title := "") -> Dictionary:
	var used := 0; var colors := {}; var adjacency := 0; var transitions := 0
	var left := 0; var right := 0; var border := 0
	for y in H:
		for x in W:
			var value := at(x, y)
			if value != PAPER:
				used += 1; colors[value] = true
				if x < floori(W / 2.0): left += 1
				else: right += 1
				if x in [0, W - 1] or y in [0, H - 1]: border += 1
			if x + 1 < W: adjacency += 1; transitions += int(value != at(x + 1, y))
			if y + 1 < H: adjacency += 1; transitions += int(value != at(x, y + 1))
	var coverage := float(used) / float(W * H)
	var contrast := float(transitions) / maxf(1.0, float(adjacency))
	var balance := 1.0 - float(absi(left - right)) / maxf(1.0, float(used))
	var border_ratio := float(border) / float(W * 2 + H * 2 - 4)
	var title_ok := not title.strip_edges().is_empty()
	return {"used":used, "colors":colors.size(), "coverage":coverage,
		"contrast":contrast, "balance":clampf(balance,0,1), "border":border_ratio,
		"title_ok":title_ok}

func brief_fit(title := "") -> float:
	var m := metrics(title); var fit := 0.0
	match brief:
		&"crew_badge": fit = _range_score(m.coverage,.12,.48) * .35 + _range_score(m.colors,2,5) * .25 + m.balance * .25 + float(m.title_ok) * .15
		&"spectrum": fit = _range_score(m.colors,4,7) * .40 + _range_score(m.contrast,.08,.32) * .30 + _range_score(m.coverage,.18,.65) * .20 + float(m.title_ok) * .10
		&"technical": fit = _range_score(m.border,.35,1.0) * .35 + _range_score(m.contrast,.07,.30) * .25 + m.balance * .25 + float(m.title_ok) * .15
		_: fit = _range_score(m.coverage,.05,.28) * .40 + _range_score(m.colors,1,3) * .30 + m.balance * .20 + float(m.title_ok) * .10
	return clampf(fit, 0, 1)

func print_ready(title: String) -> bool:
	var m := metrics(title)
	return bool(m.title_ok) and int(m.used) >= 24 and int(m.colors) >= 1

func score(title: String) -> int:
	if not print_ready(title): return 0
	var m := metrics(title)
	var craft := _range_score(m.coverage,.08,.65) * 220.0 + _range_score(m.contrast,.035,.34) * 180.0 + float(m.balance) * 160.0
	var result := 420.0 + level * 70.0 + brief_fit(title) * 420.0 + craft
	result -= maxf(0, actions - 36) * 2.0
	result -= 130.0 if assisted else 0.0
	return clampi(roundi(result), 250, 1800)

func details(title: String) -> Dictionary:
	var result := metrics(title)
	result.merge({"level":level, "brief":str(brief), "brief_fit":brief_fit(title),
		"actions":actions, "assisted":assisted, "score":score(title)}, true)
	return result

func _inside(point: Vector2i) -> bool:
	return point.x >= 0 and point.x < W and point.y >= 0 and point.y < H

func _set_cell(x: int, y: int, value: int) -> bool:
	if x < 0 or x >= W or y < 0 or y >= H: return false
	var index := y * W + x
	if cells[index] == value: return false
	cells[index] = value
	return true

func _range_score(value: float, low: float, high: float) -> float:
	if value >= low and value <= high: return 1.0
	var span := maxf(.001, high - low)
	return clampf(1.0 - (low - value) / span if value < low else 1.0 - (value - high) / span, 0, 1)
