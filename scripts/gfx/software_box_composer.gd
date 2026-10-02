class_name SoftwareBoxComposer
extends RefCounted
## Komponiert die hunderten flachen Cover erst bei Bedarf in EINEN weissen
## 1990er-Big-Box-Master. Listen laden nur Metadaten; Detail/Vitrine fordern die
## kleine fertige Textur an. Der begrenzte LRU verhindert einen 500-Cover-RAM-Peak.

const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")
const DiskComposerScript := preload("res://scripts/gfx/disk_composer.gd")
const BOX_MASTER := "res://assets/backgrounds/layers/GAME_WHITE_BIGBOX_MASTER_V01.png"
const CABINET_MASTER := "res://assets/backgrounds/layers/ROOM_GAME_DISPLAY_CABINET_MASTER_V01.png"
const LAYOUT_PATH := "res://data/software_box_layout.json"
## 384-px-OVPs sind klein genug für einen größeren residenten Arbeitsbestand.
## RuntimeImageLoader hält die großen Quellen zusätzlich unter einem Bytebudget.
const CACHE_LIMIT := 128

static var _cache: Dictionary = {}
static var _order: Array[String] = []
static var _layout: Dictionary = {}
static var _scaled_box_masters: Dictionary = {}
static var _warp_run_cache: Dictionary = {}


static func reload() -> void:
	_layout = {}
	_cache.clear()
	_order.clear()
	_scaled_box_masters.clear()
	_warp_run_cache.clear()
	_ensure_layout()


static func layout_rect(side: String, element: String) -> Dictionary:
	_ensure_layout()
	var side_data: Dictionary = _layout.get("back" if side == "back" else "front", {})
	var fallback := {"x": 0.481, "y": 0.472, "w": 0.654, "h": 0.658} \
		if element == "cover" else {"x": 0.694, "y": 0.778, "w": 0.255, "h": 0.072}
	var raw: Variant = side_data.get(element, fallback)
	return (raw as Dictionary).duplicate() if raw is Dictionary else fallback


## Vier frei editierbare Zielpunkte in der Reihenfolge oben-links,
## oben-rechts, unten-rechts, unten-links. Alte Rechtecklayouts werden beim
## Lesen verlustfrei in ein Quad migriert.
static func layout_quad(side: String, element: String) -> Array[Vector2]:
	var raw := layout_rect(side, element)
	var stored: Variant = raw.get("quad", [])
	var result: Array[Vector2] = []
	if stored is Array and (stored as Array).size() == 4:
		for point: Variant in stored:
			if point is Array and (point as Array).size() >= 2:
				result.append(Vector2(float(point[0]), float(point[1])))
	if result.size() == 4:
		return result
	var center := Vector2(float(raw.get("x", 0.5)), float(raw.get("y", 0.5)))
	var extent := Vector2(float(raw.get("w", 0.1)), float(raw.get("h", 0.1))) * 0.5
	return [center - extent, center + Vector2(extent.x, -extent.y), center + extent,
		center + Vector2(-extent.x, extent.y)]


static func box_texture(software_id: String, package_condition := "sealed",
		max_width := 384, side := "front", disk_color := "red", disk_count := 0) -> Texture2D:
	side = "back" if side == "back" else "front"
	disk_color = "purple" if disk_color in ["purple", "violet"] else "red"
	var bible := _bible()
	if disk_count <= 0:
		disk_count = maxi(1, int(bible.call("disk_count", software_id))) if bible != null else 1
	var key := "box/%s/%s/%s/%s/%d/%d" % [software_id, package_condition,
		side, disk_color, disk_count, max_width]
	var cached := _cached(key)
	if cached != null:
		return cached
	var master := _scaled_box_master(max_width)
	var cover_path := str(bible.call("art_path", software_id,
		"box_back" if side == "back" else "box_front")) if bible != null else ""
	var cover := _image(cover_path)
	if master == null or cover == null:
		return null
	# Wichtig für die Framerate: Die frühere Pipeline warpte jedes Cover
	# pixelweise in 1024×1536 und verkleinerte erst ganz am Ende auf 384px.
	# Normalisierte Layoutquads erlauben dieselbe Qualität direkt am Zielmaß.
	# Der BoxLayoutEditor schreibt normalisierte Rechtecke; Vorder- und Rueckseite
	# koennen dadurch getrennt an denselben physischen Big-Box-Master angepasst werden.
	var cover_quad := layout_quad(side, "cover")
	_warp_image_to_quad(master, cover, cover_quad)
	_blit_disk_badge(master, layout_quad(side, "disk_badge"), disk_count, disk_color)
	if package_condition == "sealed":
		# Sehr dezenter Schrumpffolien-Glanz ohne Schrift/Siegel-Badge.
		var sheen_size := _quad_bounds_px(cover_quad, master.get_size()).size
		var sheen := Image.create(sheen_size.x, sheen_size.y, false, Image.FORMAT_RGBA8)
		sheen.fill(Color(1.0, 1.0, 1.0, 0.0))
		var stripe_step := maxi(24, floori(sheen.get_width() / 6.0))
		var stripe_width := maxi(3, floori(stripe_step * 0.09))
		for x in range(0, sheen.get_width(), stripe_step):
			sheen.fill_rect(Rect2i(x, 0, stripe_width, sheen.get_height()),
				Color(1.0, 1.0, 1.0, 0.055))
		_warp_image_to_quad(master, sheen, cover_quad)
	return _remember(key, _texture_scaled(master, max_width))


## Handbuchansicht eines vollständigen OVP-Satzes. Das echte Manual-Cover sitzt
## auf einem kleinen cremefarbenen Heftstapel mit Falz und Seitenkante; fehlt nur
## bei tatsächlich unvollständigem Content und fällt dann auf das Boxcover zurück.
static func manual_texture(software_id: String, max_width := 384) -> Texture2D:
	var key := "manual/%s/%d" % [software_id, max_width]
	var cached := _cached(key)
	if cached != null:
		return cached
	var bible := _bible()
	var art := _image(str(bible.call("art_path", software_id, "manual_cover")) if bible != null else "")
	if art == null:
		art = _image(str(bible.call("art_path", software_id, "box_front")) if bible != null else "")
	if art == null:
		return null
	var width := clampi(max_width, 96, 720)
	var height := maxi(1, roundi(float(width) * 0.72))
	var canvas := Image.create(width, height, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.018, 0.022, 0.030, 0.0))
	var target_height := roundi(height * 0.86)
	var target_width := maxi(1, roundi(float(art.get_width()) * target_height / art.get_height()))
	target_width = mini(target_width, roundi(width * 0.66))
	target_height = maxi(1, roundi(float(art.get_height()) * target_width / art.get_width()))
	var origin := Vector2i(roundi((width - target_width) * 0.5), roundi((height - target_height) * 0.46))
	# Kontakt-/Seitenschatten und drei sichtbare Papierlagen.
	canvas.fill_rect(Rect2i(origin + Vector2i(10, 12), Vector2i(target_width, target_height)),
		Color(0.0, 0.0, 0.0, 0.34))
	for layer in range(3, 0, -1):
		canvas.fill_rect(Rect2i(origin + Vector2i(layer * 2, layer * 2),
			Vector2i(target_width, target_height)), Color8(226 - layer * 5, 219 - layer * 4, 194 - layer * 3, 255))
	# _image() liefert bereits eine private Kopie. Ein zweites Duplikat des
	# 533×800-Quellbilds war reine Speicherbandbreite. Bilinear entspricht dem
	# Filter der sichtbaren OVP-Projektion und ist bei der kleinen Heftansicht
	# nicht unterscheidbar, aber deutlich guenstiger als Lanczos.
	var cover := art
	cover.convert(Image.FORMAT_RGBA8)
	cover.resize(target_width, target_height, Image.INTERPOLATE_BILINEAR)
	canvas.blend_rect(cover, Rect2i(Vector2i.ZERO, cover.get_size()), origin)
	canvas.fill_rect(Rect2i(origin, Vector2i(maxi(2, floori(target_width / 40.0)), target_height)),
		Color(0.09, 0.07, 0.06, 0.28))
	return _remember(key, ImageTexture.create_from_image(canvas))


## Vollstaendiger Diskettensatz fuer die Detailansicht. Jede einzelne Disk nutzt
## weiterhin den bestehenden DiskEditor/DiskComposer: Mehrdiskettentitel erhalten
## ihre echten label_2/label_3/...-Bilder und rote/lila Gehaeuse.
static func disk_set_texture(software_id: String, disk_color := "red",
		disk_count := 0, max_width := 720) -> Texture2D:
	disk_color = "purple" if disk_color in ["purple", "violet"] else "red"
	if disk_count <= 0:
		var bible := _bible()
		disk_count = maxi(1, int(bible.call("disk_count", software_id))) if bible != null else 1
	disk_count = clampi(disk_count, 1, 20)
	var key := "diskset/%s/%s/%d/%d" % [software_id, disk_color, disk_count, max_width]
	var cached := _cached(key)
	if cached != null:
		return cached
	var columns := mini(5, disk_count)
	var rows := ceili(float(disk_count) / float(columns))
	var cell := Vector2i(178, 150)
	var canvas := Image.create(columns * cell.x, rows * cell.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.02, 0.025, 0.035, 0.0))
	for index in disk_count:
		var texture := DiskComposerScript.composed_disk(software_id, true, 256,
			index + 1, disk_color)
		if texture == null:
			continue
		var disk_image := texture.get_image()
		var target_width := 142
		var target_height := maxi(1, roundi(float(disk_image.get_height()) * target_width / disk_image.get_width()))
		disk_image.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)
		var column := index % columns
		var row := floori(index / float(columns))
		var position := Vector2i(column * cell.x + floori((cell.x - target_width) / 2.0),
			row * cell.y + maxi(0, floori((cell.y - target_height) / 2.0)))
		canvas.blend_rect(disk_image, Rect2i(Vector2i.ZERO, disk_image.get_size()), position)
	return _remember(key, _texture_scaled(canvas, max_width))


static func cabinet_texture(boxes: Array, max_width := 512) -> Texture2D:
	var signature: Array[String] = []
	for value: Variant in boxes.slice(0, 8):
		if value is Disk:
			var disk := value as Disk
			signature.append("%s:%s" % [disk.software_set_id, disk.package_condition])
	var key := "cabinet/%s/%d" % ["|".join(signature), max_width]
	var cached := _cached(key)
	if cached != null:
		return cached
	var cabinet := _image(CABINET_MASTER)
	if cabinet == null:
		return null
	cabinet = _scaled_copy(cabinet, max_width)
	var image := cabinet.duplicate()
	# Die Boxen stehen mit ihrer Unterkante AUF dem jeweiligen Glasboden. Die
	# alten Slots reichten 30–48 Masterpixel durch das Brett und lasen dadurch
	# wie außen auf die Scheibe geklebt. Quads geben jeder Box leichte Tiefe.
	var slots: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(.332,.142),Vector2(.425,.144),Vector2(.421,.240),Vector2(.334,.240)]),
		PackedVector2Array([Vector2(.558,.146),Vector2(.651,.148),Vector2(.648,.240),Vector2(.560,.240)]),
		PackedVector2Array([Vector2(.332,.300),Vector2(.425,.301),Vector2(.421,.400),Vector2(.334,.400)]),
		PackedVector2Array([Vector2(.558,.303),Vector2(.651,.304),Vector2(.648,.400),Vector2(.560,.400)]),
		PackedVector2Array([Vector2(.332,.459),Vector2(.425,.460),Vector2(.421,.559),Vector2(.334,.559)]),
		PackedVector2Array([Vector2(.558,.462),Vector2(.651,.463),Vector2(.648,.559),Vector2(.560,.559)]),
		PackedVector2Array([Vector2(.332,.618),Vector2(.425,.619),Vector2(.421,.718),Vector2(.334,.718)]),
		PackedVector2Array([Vector2(.558,.621),Vector2(.651,.622),Vector2(.648,.718),Vector2(.560,.718)]),
	]
	for i in mini(8, boxes.size()):
		var disk: Disk = boxes[i]
		var box := box_texture(disk.software_id, disk.package_condition, 160,
			"front", disk.color, disk.disk_count)
		if box == null:
			continue
		var quad: PackedVector2Array = slots[i]
		var shadow_quad: Array[Vector2] = []
		var box_quad: Array[Vector2] = []
		for point: Vector2 in quad:
			shadow_quad.append(point + Vector2(0.007, 0.006))
			box_quad.append(point)
		var shadow := Image.create(32, 48, false, Image.FORMAT_RGBA8)
		shadow.fill(Color(0.0, 0.0, 0.0, 0.34))
		_warp_image_to_quad(image, shadow, shadow_quad)
		_warp_image_to_quad(image, box.get_image(), box_quad)
	# Glasreflex und Brett-Vorderkanten kommen nach den Boxen. Damit liegen die
	# Exponate optisch hinter der Scheibe und die Böden schneiden ihre Füße sauber.
	for shelf_y: float in [0.241, 0.401, 0.560, 0.719]:
		var y := clampi(roundi(shelf_y * image.get_height()), 0, image.get_height() - 1)
		image.blend_rect(cabinet, Rect2i(0, maxi(0, y - 3), image.get_width(), 7),
			Vector2i(0, maxi(0, y - 3)))
	for aperture: Rect2 in [Rect2(.312,.105,.145,.625), Rect2(.538,.105,.145,.625)]:
		var r := Rect2i(Vector2i(aperture.position * Vector2(image.get_size())),
			Vector2i(aperture.size * Vector2(image.get_size())))
		var glass := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
		glass.fill(Color(0.62, 0.78, 0.74, 0.055))
		image.blend_rect(glass, Rect2i(Vector2i.ZERO, glass.get_size()), r.position)
	return _remember(key, _texture_scaled(image, max_width))


static func _image(path: String) -> Image:
	if path.is_empty():
		return null
	var image := RuntimeImages.raw_image(path)
	if image != null:
		return image
	var texture := RuntimeImages.texture(path)
	return texture.get_image() if texture != null else null


static func _bible() -> Node:
	var loop := Engine.get_main_loop()
	return loop.root.get_node_or_null("SoftwareBible") if loop is SceneTree else null


static func _ensure_layout() -> void:
	if not _layout.is_empty():
		return
	if FileAccess.file_exists(LAYOUT_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
		if parsed is Dictionary:
			_layout = parsed
	if _layout.is_empty():
		_layout = {
			"master": BOX_MASTER,
			"front": {"cover": {"x": 0.481, "y": 0.472, "w": 0.654, "h": 0.658},
				"disk_badge": {"x": 0.694, "y": 0.778, "w": 0.255, "h": 0.072}},
			"back": {"cover": {"x": 0.481, "y": 0.472, "w": 0.654, "h": 0.658},
				"disk_badge": {"x": 0.694, "y": 0.778, "w": 0.255, "h": 0.072}},
		}


static func _blit_disk_badge(base: Image, quad: Array[Vector2], count: int, color_name: String) -> void:
	var target := _quad_bounds_px(quad, base.get_size())
	var badge := Image.create(maxi(32, target.size.x), maxi(16, target.size.y), false, Image.FORMAT_RGBA8)
	var body := Color8(104, 54, 130, 238) if color_name == "purple" else Color8(166, 45, 48, 238)
	badge.fill(body)
	badge.fill_rect(Rect2i(0, 0, target.size.x, 3), Color8(255, 238, 196, 235))
	badge.fill_rect(Rect2i(0, target.size.y - 3, target.size.x, 3), Color8(35, 20, 26, 235))
	_draw_pixel_text(badge, "%d DISKS" % count, Color8(255, 244, 214), Color8(34, 20, 26, 210))
	_warp_image_to_quad(base, badge, quad)


## CPU-seitige Scanline-Projektion. Die alte Variante berechnete fuer jedes
## Zielpixel zwei baryzentrische Tests plus mehrere get_pixel()-Aufrufe in
## GDScript. Eine 384-px-OVP blockierte dadurch den Main Thread rund 0,8 s.
## Geometrie und Alpha-Komposition bleiben CPU-/Export-deterministisch;
## Skalierung und Blending laufen aber in Godots nativen Image-Operationen.
static func _warp_image_to_quad(base: Image, source: Image, quad: Array[Vector2]) -> void:
	if quad.size() != 4 or source == null:
		return
	var points: Array[Vector2] = []
	for point: Vector2 in quad:
		points.append(Vector2(point.x * base.get_width(), point.y * base.get_height()))
	var bounds := _quad_bounds_px(quad, base.get_size())
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return
	# Alle Aufrufer uebergeben eine frische RuntimeImages-/get_image()-Kopie
	# oder ein lokales Hilfsbild. Darum darf die Projektion direkt skalieren,
	# statt pro Warp nochmals bis zu 1,7 MB zu duplizieren.
	var projected := source
	if projected.get_format() != Image.FORMAT_RGBA8:
		projected.convert(Image.FORMAT_RGBA8)
	if projected.get_size() != bounds.size:
		# Der fruehere per-Pixel-Warp sampelte bilinear. Die native bilineare
		# Skalierung behaelt damit den bisherigen Filter und bleibt auch beim
		# ersten, noch nicht dekodierten Cover innerhalb eines Zeichenframes.
		projected.resize(bounds.size.x, bounds.size.y, Image.INTERPOLATE_BILINEAR)
	var run_key := _warp_run_key(base.get_size(), quad)
	var runs: Array = _warp_run_cache.get(run_key, [])
	if runs.is_empty():
		runs = _build_quad_runs(points, bounds)
		_warp_run_cache[run_key] = runs
	for value: Variant in runs:
		var source_rect := value as Rect2i
		base.blend_rect(projected, source_rect,
			bounds.position + source_rect.position)


static func _build_quad_runs(points: Array[Vector2], bounds: Rect2i) -> Array[Rect2i]:
	var runs: Array[Rect2i] = []
	var run_start := -1
	var run_left := 0
	var run_right := 0
	# Gleich breite Nachbarzeilen werden als ein Rechteck geblendet. Diese
	# Scanline-Geometrie ist fuer alle Titel desselben Layouts identisch und
	# wird deshalb nur beim ersten Cover berechnet.
	for y in range(bounds.position.y, bounds.end.y + 1):
		var span := _quad_scanline_span(points, float(y) + 0.5) \
			if y < bounds.end.y else Vector2i(-1, -1)
		var left := clampi(span.x, bounds.position.x, bounds.end.x)
		var right := clampi(span.y, bounds.position.x, bounds.end.x)
		if run_start >= 0 and (left != run_left or right != run_right):
			var source_rect := Rect2i(
				run_left - bounds.position.x,
				run_start - bounds.position.y,
				run_right - run_left,
				y - run_start)
			if source_rect.size.x > 0 and source_rect.size.y > 0:
				runs.append(source_rect)
			run_start = -1
		if right > left and run_start < 0:
			run_start = y
			run_left = left
			run_right = right
	return runs


static func _warp_run_key(image_size: Vector2i, quad: Array[Vector2]) -> String:
	var parts: PackedStringArray = ["%d,%d" % [image_size.x, image_size.y]]
	for point: Vector2 in quad:
		parts.append("%.6f,%.6f" % [point.x, point.y])
	return "|".join(parts)


static func _quad_scanline_span(points: Array[Vector2], y: float) -> Vector2i:
	var intersections: Array[float] = []
	for index in 4:
		var a := points[index]
		var b := points[(index + 1) % 4]
		var low := minf(a.y, b.y)
		var high := maxf(a.y, b.y)
		if y < low or y >= high or is_equal_approx(a.y, b.y):
			continue
		var ratio := (y - a.y) / (b.y - a.y)
		intersections.append(lerpf(a.x, b.x, ratio))
	if intersections.size() < 2:
		return Vector2i(-1, -1)
	intersections.sort()
	return Vector2i(ceili(intersections[0] - 0.5),
		floori(intersections[-1] - 0.5) + 1)


static func _quad_bounds_px(quad: Array[Vector2], image_size: Vector2i) -> Rect2i:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in quad:
		var pixel := Vector2(point.x * image_size.x, point.y * image_size.y)
		min_point = min_point.min(pixel)
		max_point = max_point.max(pixel)
	var position := Vector2i(clampi(floori(min_point.x), 0, image_size.x - 1),
		clampi(floori(min_point.y), 0, image_size.y - 1))
	var end := Vector2i(clampi(ceili(max_point.x), position.x + 1, image_size.x),
		clampi(ceili(max_point.y), position.y + 1, image_size.y))
	return Rect2i(position, end - position)


static func _draw_pixel_text(image: Image, value: String, ink: Color, shadow: Color) -> void:
	var glyphs := {
		"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
		"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
		"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
		"6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
		"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
		"D": ["110", "101", "101", "101", "110"], "I": ["111", "010", "010", "010", "111"],
		"S": ["111", "100", "111", "001", "111"], "K": ["101", "101", "110", "101", "101"],
		" ": ["0", "0", "0", "0", "0"],
	}
	var char_units := value.length() * 4 - 1
	var scale := maxi(1, mini(image.get_height() >> 3, floori(image.get_width() / float(maxi(1, char_units + 4)))))
	var text_size := Vector2i(char_units * scale, 5 * scale)
	var origin := Vector2i(floori((image.get_width() - text_size.x) / 2.0), floori((image.get_height() - text_size.y) / 2.0))
	for char_index in value.length():
		var glyph: Array = glyphs.get(value.substr(char_index, 1), glyphs[" "])
		for gy in glyph.size():
			var row: String = glyph[gy]
			for gx in row.length():
				if row.substr(gx, 1) != "1":
					continue
				var at := origin + Vector2i((char_index * 4 + gx) * scale, gy * scale)
				image.fill_rect(Rect2i(at + Vector2i(maxi(1, floori(scale / 3.0)), maxi(1, floori(scale / 3.0))), Vector2i(scale, scale)), shadow)
				image.fill_rect(Rect2i(at, Vector2i(scale, scale)), ink)


static func _texture_scaled(image: Image, max_width: int) -> Texture2D:
	if max_width > 0 and image.get_width() > max_width:
		image.resize(max_width, maxi(1, roundi(float(image.get_height()) * max_width / image.get_width())),
			Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


static func _scaled_copy(source: Image, max_width: int) -> Image:
	var image := source.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	if max_width > 0 and image.get_width() > max_width:
		image.resize(max_width, maxi(1, roundi(float(image.get_height()) * max_width / image.get_width())),
			Image.INTERPOLATE_LANCZOS)
	return image


static func _scaled_box_master(max_width: int) -> Image:
	var cache_key := max_width
	if _scaled_box_masters.has(cache_key):
		return (_scaled_box_masters[cache_key] as Image).duplicate()
	var source := _image(BOX_MASTER)
	if source == null:
		return null
	var scaled := _scaled_copy(source, max_width)
	_scaled_box_masters[cache_key] = scaled
	return scaled.duplicate()


static func _cached(key: String) -> Texture2D:
	if not _cache.has(key):
		return null
	_order.erase(key)
	_order.append(key)
	return _cache[key] as Texture2D


static func _remember(key: String, texture: Texture2D) -> Texture2D:
	_cache[key] = texture
	_order.erase(key)
	_order.append(key)
	while _order.size() > CACHE_LIMIT:
		_cache.erase(_order.pop_front())
	return texture
