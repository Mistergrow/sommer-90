class_name KickstartScreen
## Modellgebundene Kickstart-Darstellung im nativen 640×400-Koordinatenraum:
## - A500: bestehendes, statisches Kickstart-1.3-Hand-/Diskettenbild.
## - A600: Kickstart 2.05; A1200: 3.0 beziehungsweise 3.1 nach ROM-Upgrade.
##   Die spaeteren Generationen zeigen den violetten Schirm, Regenbogen-Haken
##   und die wiederholt in das Laufwerk gleitende Diskette.
## Das logische Bild wird wie am echten CRT auf dessen Glasfläche gestreckt.
## Nicht-kommerzielle Hommage; Versionen/Farben/Taktung aus data/boot.json.

const BOOT_PATH := "res://data/boot.json"
const TOPAZ_PATH := "res://assets/fonts/Topaz_a500_ui.ttf"
const NATIVE_SIZE := Vector2(640.0, 400.0)
static var _catalog: Dictionary = {}
static var _textures: Dictionary = {}
static var _topaz: Font = null


static func _load_catalog() -> Dictionary:
	if _catalog.is_empty():
		var f := FileAccess.open(BOOT_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_catalog = parsed
	return _catalog


## Aktives Zimmermodell ohne harte Autoload-Abhängigkeit beim Import/Editor.
static func active_computer_model() -> String:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var stats := (loop as SceneTree).root.get_node_or_null("/root/PlayerStats")
		if stats != null and stats.has_method("desk_model"):
			return str(stats.call("desk_model", "computer_model"))
	return "amiga_500"


## Profil eines expliziten Modells; leer = aktuell ausgewählter Zimmerrechner.
static func config(computer_model := "") -> Dictionary:
	var catalog := _load_catalog()
	var model := computer_model if computer_model != "" else active_computer_model()
	# Ein explizites "amiga_1200" bleibt fuer Tests und Katalogansichten 3.0.
	# Nur der aktuell eingebaute Rechner schaltet nach dem gekauften ROM-Kit auf
	# das gesonderte 3.1-Profil.
	if computer_model == "" and model == "amiga_1200" and _has_31_upgrade():
		model = "amiga_1200_31"
	var profiles: Dictionary = catalog.get("profiles", {})
	var fallback := str(catalog.get("default_profile", "amiga_500"))
	return (profiles.get(model, profiles.get(fallback, {})) as Dictionary)


static func is_animated(computer_model := "") -> bool:
	return bool(config(computer_model).get("animated", false))


## Bootbild in `ci`/`rect` zeichnen. `t` ist nur für Kickstart 2.x relevant.
static func draw_into(ci: CanvasItem, rect: Rect2, t: float = 0.0,
		computer_model := "") -> void:
	var cfg := config(computer_model)
	var bg: Array = cfg.get("bg", [1.0, 1.0, 1.0])
	ci.draw_rect(rect, Color(bg[0], bg[1], bg[2]))
	if str(cfg.get("renderer", "image")) == "kickstart_2x":
		_draw_kickstart_2x(ci, rect, t, cfg)
		return
	var path := str(cfg.get("screen_image", ""))
	if not _textures.has(path) and path != "" and ResourceLoader.exists(path):
		_textures[path] = load(path)
	var tex: Texture2D = _textures.get(path)
	if tex == null:
		return
	# Vollbild auf die Röhre strecken — so füllte der Bootschirm den echten CRT.
	ci.draw_texture_rect(tex, rect, false)


## Vertikaler Diskettenweg im nativen Bild. Lange Ruhephase, Einstecken,
## kurzer Anschlag und sofortige Rückkehr entsprechen der ROM-Endlosschleife.
static func disk_animation_offset(t: float, computer_model := "amiga_600") -> float:
	var cfg := config(computer_model)
	if not bool(cfg.get("animated", false)):
		return 0.0
	var cycle := maxf(0.5, float(cfg.get("animation_cycle_seconds", 2.4)))
	var p := fposmod(t, cycle) / cycle
	if p < 0.46:
		return 0.0
	if p < 0.70:
		var q := (p - 0.46) / 0.24
		# ROM-artige, stufig wahrnehmbare Bewegung statt moderner Federkurve.
		q = q * q * (3.0 - 2.0 * q)
		return -48.0 * q
	if p < 0.82:
		return -48.0
	return 0.0


static func _draw_kickstart_2x(ci: CanvasItem, rect: Rect2, t: float,
		cfg: Dictionary) -> void:
	_draw_rainbow_check(ci, rect)
	_draw_diskette(ci, rect, _disk_animation_offset_for_config(t, cfg))
	# Das Laufwerk liegt vor der Diskette; dadurch verschwindet sie beim
	# Einstecken korrekt hinter der Frontblende statt sie zu übermalen.
	_draw_drive(ci, rect)
	if _topaz == null and ResourceLoader.exists(TOPAZ_PATH):
		_topaz = load(TOPAZ_PATH)
	if _topaz == null:
		return
	var text_values: Array = cfg.get("text", [1.0, 0.666667, 0.533333])
	var text_color := Color(text_values[0], text_values[1], text_values[2])
	var lines: Array = [str(cfg.get("screen_label", "2.0 Roms (37.350)"))]
	lines.append_array(cfg.get("copyright_lines", []))
	var baselines := [302.0, 326.0, 350.0, 374.0]
	var font_size := maxi(5, roundi(16.0 * rect.size.y / NATIVE_SIZE.y))
	for i in mini(lines.size(), baselines.size()):
		_draw_rom_text(ci, rect, str(lines[i]), baselines[i], font_size, text_color)


static func _disk_animation_offset_for_config(t: float, cfg: Dictionary) -> float:
	if not bool(cfg.get("animated", false)):
		return 0.0
	var cycle := maxf(0.5, float(cfg.get("animation_cycle_seconds", 2.4)))
	var p := fposmod(t, cycle) / cycle
	if p < 0.46:
		return 0.0
	if p < 0.70:
		var q := (p - 0.46) / 0.24
		q = q * q * (3.0 - 2.0 * q)
		return -48.0 * q
	if p < 0.82:
		return -48.0
	return 0.0


static func _has_31_upgrade() -> bool:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var stats := (loop as SceneTree).root.get_node_or_null("/root/PlayerStats")
		if stats != null and stats.has_method("has_hardware"):
			return bool(stats.call("has_hardware", "amigaos_31_upgrade"))
	return false


## Der freie Topaz-Font bildet das historische ©-Zeichen nicht auf seinem
## Unicode-Codepunkt ab. Wir reservieren exakt eine Zeichenbreite und zeichnen
## das kleine Kreis-C selbst, statt ein Ersatzkästchen auf dem ROM-Schirm zu
## akzeptieren.
static func _draw_rom_text(ci: CanvasItem, rect: Rect2, line: String,
		baseline: float, font_size: int, color: Color) -> void:
	var origin := _point(rect, Vector2(40.0, baseline))
	var copyright_index := line.find("©")
	if copyright_index < 0:
		ci.draw_string(_topaz, origin, line, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			font_size, color)
		return
	var before := line.left(copyright_index)
	var after := line.substr(copyright_index + 1)
	ci.draw_string(_topaz, origin, before + "  " + after,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
	var prefix_width := _topaz.get_string_size(before + " ",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var scale := rect.size.y / NATIVE_SIZE.y
	var center := origin + Vector2(prefix_width + 3.5 * scale, -6.0 * scale)
	var stroke := maxf(1.0, scale)
	ci.draw_arc(center, 5.0 * scale, 0.0, TAU, 16, color, stroke, false)
	ci.draw_arc(center + Vector2(0.6, 0.0) * scale, 2.5 * scale,
		0.72, TAU - 0.72, 8, color, stroke, false)


## Der 2.x-Haken ist aus horizontalen OCS-Farbstufen aufgebaut. Zwei parallele
## Schenkel ergeben die charakteristische, in der ROM-Grafik sichtbare Kerbe.
static func _draw_rainbow_check(ci: CanvasItem, rect: Rect2) -> void:
	var colors := [
		Color8(255, 0, 17), Color8(255, 51, 0), Color8(255, 102, 0),
		Color8(255, 153, 0), Color8(255, 221, 0), Color8(170, 255, 0),
		Color8(34, 255, 0), Color8(0, 238, 170), Color8(0, 170, 204),
		Color8(0, 68, 238)]
	var y0 := 110.0
	var band_h := 15.0
	for i in colors.size():
		var top := y0 + i * band_h
		var bottom := minf(260.0, top + band_h + 1.0)
		# Aufsteigender Schenkel: x fällt von 199 bei y=110 auf 110 bei y=260.
		var rise_top := 199.0 - (top - 110.0) * 0.593333
		var rise_bottom := 199.0 - (bottom - 110.0) * 0.593333
		_poly(ci, rect, [
			Vector2(rise_top, top), Vector2(rise_top + 20.0, top),
			Vector2(rise_bottom + 20.0, bottom), Vector2(rise_bottom, bottom)
		], colors[i])
		_poly(ci, rect, [
			Vector2(rise_top + 24.0, top), Vector2(rise_top + 44.0, top),
			Vector2(rise_bottom + 44.0, bottom), Vector2(rise_bottom + 24.0, bottom)
		], colors[i])
		# Kurzer linker Schenkel beginnt erst auf Höhe des blauen Hakenansatzes.
		if bottom > 210.0:
			var short_top := maxf(top, 210.0)
			var short_x_top := 80.0 + (short_top - 210.0) * 0.60
			var short_x_bottom := 80.0 + (bottom - 210.0) * 0.60
			_poly(ci, rect, [
				Vector2(short_x_top, short_top), Vector2(short_x_top + 24.0, short_top),
				Vector2(short_x_bottom + 24.0, bottom), Vector2(short_x_bottom, bottom)
			], colors[i])


static func _draw_diskette(ci: CanvasItem, rect: Rect2, y_offset: float) -> void:
	var blue := Color8(34, 51, 136)
	var blue_dark := Color8(34, 34, 102)
	var gray := Color8(153, 136, 119)
	var white := Color8(255, 255, 255)
	var black := Color8(0, 0, 0)
	var o := Vector2(0.0, y_offset)
	# Gehäuse mit abgeschrägten oberen Ecken.
	_poly(ci, rect, [
		Vector2(450, 270) + o, Vector2(460, 260) + o, Vector2(574, 260) + o,
		Vector2(584, 270) + o, Vector2(584, 380) + o, Vector2(450, 380) + o
	], blue)
	# Linker Rücken und kleine Schreibschutz-/Richtungsdetails.
	_rect(ci, rect, Rect2(Vector2(450, 270) + o, Vector2(14, 110)), blue_dark)
	_rect(ci, rect, Rect2(Vector2(455, 295) + o, Vector2(4, 7)), blue)
	_rect(ci, rect, Rect2(Vector2(455, 370) + o, Vector2(5, 5)), blue)
	# Metall-/Nabenfeld.
	_rect(ci, rect, Rect2(Vector2(484, 260) + o, Vector2(70, 42)), gray)
	_rect(ci, rect, Rect2(Vector2(525, 268) + o, Vector2(14, 28)), blue_dark)
	# Weißes Etikett mit schwarzer Oberkante, wie im ROM-Bild.
	_rect(ci, rect, Rect2(Vector2(466, 312) + o, Vector2(106, 68)), white)
	_rect(ci, rect, Rect2(Vector2(468, 312) + o, Vector2(102, 4)), black)


static func _draw_drive(ci: CanvasItem, rect: Rect2) -> void:
	var peach := Color8(238, 170, 136)
	var shadow := Color8(153, 119, 102)
	var black := Color8(0, 0, 0)
	_rect(ci, rect, Rect2(440, 210, 156, 38), peach)
	_rect(ci, rect, Rect2(465, 238, 8, 2), black)
	# Rechte, eingelassene Auswurftasten-Kontur.
	_rect(ci, rect, Rect2(558, 232, 25, 2), shadow)
	_rect(ci, rect, Rect2(558, 232, 2, 8), shadow)
	_rect(ci, rect, Rect2(581, 232, 2, 8), shadow)


static func _point(rect: Rect2, p: Vector2) -> Vector2:
	return rect.position + Vector2(p.x / NATIVE_SIZE.x * rect.size.x,
		p.y / NATIVE_SIZE.y * rect.size.y)


static func _rect(ci: CanvasItem, target: Rect2, native_rect: Rect2,
		color: Color) -> void:
	ci.draw_rect(Rect2(_point(target, native_rect.position),
		Vector2(native_rect.size.x / NATIVE_SIZE.x * target.size.x,
			native_rect.size.y / NATIVE_SIZE.y * target.size.y)), color)


static func _poly(ci: CanvasItem, target: Rect2, native_points: Array,
		color: Color) -> void:
	var points := PackedVector2Array()
	for p: Vector2 in native_points:
		points.append(_point(target, p))
	ci.draw_colored_polygon(points, color)
