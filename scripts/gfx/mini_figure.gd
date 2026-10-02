class_name MiniFigure
extends TextureRect
## MiniFigure — animierte Detailbüste (PortraitGen) bzw. native 32×48-
## Adventure-Figur (FigurePaint32) für Setup, Topbar und Karte. Idle-Leben: Blinzeln, Umsehen und
## kleine Aktionen; Frames entstehen nur bei Zustandswechsel, Skalierung bleibt
## immer ganzzahlig und nearest.

const FIGURE_PAINT := preload("res://scripts/gfx/figure_paint_32.gd")

var fig_id := "player"           # Identität (Seed) — z. B. PlayerIdentity.avatar_seed
var hints: Dictionary = {}       # Porträt-Hints (year/skin/…), gleiche 32er DNA
var as_figure := true            # true = Ganzkörper, false = nur Kopf
var bob := true                  # leichtes Idle-Wippen (nur außerhalb von Containern)

## Idle-Aktionen (Humor/Leben): gähnen, grinsen, zwinkern, überrascht, Zunge raus.
const ACTS := ["yawn", "grin", "wink", "surprised", "tongue"]

var _cache: Dictionary = {}
var _t := 0.0
var _blink := false
var _blink_at := 2.6
var _gaze := 0
var _gaze_at := 1.7
var _act := ""
var _act_until := 0.0
var _act_next := 4.5
var _base_off := Vector2.ZERO
var _last_target := Vector2i.ZERO
var _resize_refresh_pending := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Die Textur wird selbst auf eine ganzzahlige Zielgröße skaliert; der
	# Control darf sie danach nicht noch einmal ungleichmäßig strecken.
	stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	_refresh()


## Neu setzen (nach Identitätswechsel Cache leeren).
func setup(id: String, h: Dictionary = {}, figure: bool = true) -> void:
	fig_id = id
	hints = h
	as_figure = figure
	_cache.clear()
	_last_target = Vector2i.ZERO
	_refresh()


func _frame(blink: bool, gaze: int, act: String) -> ImageTexture:
	var target := _target_texture_size()
	var key := "%s%d_%s_%dx%d" % ["b" if blink else "o", gaze, act, target.x, target.y]
	if not _cache.has(key):
		var raw: ImageTexture
		if as_figure:
			raw = FIGURE_PAINT.figure(fig_id, hints, _portrait_frame_state(blink, gaze, act))
		else:
			raw = PortraitGen.for_npc(fig_id, hints, _portrait_frame_state(blink, gaze, act))
		_cache[key] = _scale_nearest(raw, target)
	return _cache[key]


func _refresh() -> void:
	_last_target = _target_texture_size()
	texture = _frame(_blink, _gaze, _act)


func _portrait_frame_state(blink: bool, gaze: int, act: String) -> Dictionary:
	var state := {"blink": blink, "gaze": clampi(gaze, -1, 1)}
	match act:
		"yawn":
			state["eye_frame"] = "half"
			state["mouth_pose"] = "ai"
		"grin":
			state["emotion"] = "happy"
			state["mouth_pose"] = "e"
		"wink":
			state["eye_left"] = "closed"
			state["eye_right"] = "half"
			state["mouth_pose"] = "rest"
		"surprised":
			state["emotion"] = "surprised"
			state["mouth_pose"] = "ou"
		"tongue":
			state["mouth_pose"] = "l"
	return state


## Figure: echte 32×48 nur mit ganzzahligem Faktor. Detailkopf: 128/64/32 als
## exakte Pixelstufen mit Letterbox statt 78/200px-Zerrung.
func _target_texture_size() -> Vector2i:
	var avail := size
	if avail.x < 2.0 or avail.y < 2.0:
		avail = custom_minimum_size
	if as_figure:
		var factor := maxi(1, floori(minf(avail.x / 32.0, avail.y / 48.0)))
		return Vector2i(32 * factor, 48 * factor)
	var side := floori(minf(avail.x, avail.y))
	if side >= 256:
		return Vector2i(256, 256)
	if side >= 128:
		return Vector2i(128, 128)
	if side >= 64:
		return Vector2i(64, 64)
	return Vector2i(32, 32)


func _scale_nearest(source: ImageTexture, target: Vector2i) -> ImageTexture:
	if source.get_width() == target.x and source.get_height() == target.y:
		return source
	var img := source.get_image().duplicate()
	img.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


func _on_resized() -> void:
	if _target_texture_size() == _last_target or _resize_refresh_pending:
		return
	_resize_refresh_pending = true
	call_deferred("_refresh_after_resize")


func _refresh_after_resize() -> void:
	_resize_refresh_pending = false
	if is_inside_tree():
		_refresh()


func _process(delta: float) -> void:
	_t += delta
	var changed := false
	# Aktion beenden → zurück in den Ruhezustand
	if _act != "" and _t > _act_until:
		_act = ""
		_gaze = 0
		_act_next = _t + randf_range(4.0, 9.0)
		changed = true
	# Neue Aktion nur aus dem Ruhezustand starten
	elif _act == "" and _t > _act_next:
		_act = ACTS[randi() % ACTS.size()]
		var dur := 1.2
		match _act:
			"yawn": dur = 1.6
			"surprised": dur = 0.9
			"tongue": dur = 1.0
		_act_until = _t + dur
		changed = true
	# Blinzeln — außer die Aktion schließt die Augen ohnehin (gähnen)
	if _act != "yawn":
		if _blink:
			if _t > _blink_at + 0.12:
				_blink = false
				_blink_at = _t + randf_range(2.5, 5.0)
				changed = true
		elif _t > _blink_at:
			_blink = true
			changed = true
	# Umsehen nur im Ruhezustand
	if _act == "" and _t > _gaze_at:
		_gaze = [-1, 0, 0, 1][randi() % 4]
		_gaze_at = _t + randf_range(1.4, 3.4)
		changed = true
	if changed:
		_refresh()
	# Idle-Wippen (1px), reiner Positionsversatz
	if bob:
		position = _base_off + Vector2(0, -1.0 if fmod(_t, 1.1) < 0.55 else 0.0)


func set_base_offset(o: Vector2) -> void:
	_base_off = o
	position = o
