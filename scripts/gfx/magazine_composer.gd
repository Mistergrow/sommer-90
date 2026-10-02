class_name MagazineComposer
## Bäckt ein Magazin-Cover PERSPEKTIVISCH in das flache Master-Heft
## (MAGAZINE_MASTER_V02), sodass auf dem Schreibtisch eine echte Amiga-Joker-
## Ausgabe liegt statt des leeren weißen Masters. Die Cover-Ecken kommen aus
## data/magazine_layout.json (im Magazin-Editor gesetzt, Anteile der Masterfläche).
## Weil ins FLACHE Master gebacken wird, rotiert/skewt der RoomCompositor Master
## und Cover danach gemeinsam korrekt (Layer „magazines", z19).

const LAYOUT_PATH := "res://data/magazine_layout.json"
const MASTER_PATH := "res://assets/backgrounds/layers/MAGAZINE_MASTER_V02.png"
const UPRIGHT_PATH := "res://assets/backgrounds/layers/MAGAZINE_MASTER_UPRIGHT_V01.png"
const ARCHIVE_1990_DIR := "res://assets/ui/magazines/amiga_joker/1990"
const GENERATED_ERA_DIR := "res://assets/ui/magazines/generated_era"
const ProductionCatalog := preload("res://scripts/data/magazine_production_catalog.gd")
const ERA_COVER_ART: Array[String] = [
	GENERATED_ERA_DIR + "/cover_art_space_courier_v01.png",
	GENERATED_ERA_DIR + "/cover_art_clockwork_v01.png",
	GENERATED_ERA_DIR + "/cover_art_circuit_v01.png",
	GENERATED_ERA_DIR + "/cover_art_lunar_miner_v01.png",
	GENERATED_ERA_DIR + "/cover_art_abyss_rescue_v01.png",
	GENERATED_ERA_DIR + "/cover_art_shadow_protocol_v01.png",
	GENERATED_ERA_DIR + "/cover_art_neon_highway_v01.png",
	GENERATED_ERA_DIR + "/cover_art_pixel_tracker_v01.png",
]
const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")

# Cover-Front-Fläche des AUFRECHTEN Masters (Anteile TL,TR,BR,BL) — front-facing,
# fast Rechteck (kleine Tiefe rechts durch den Blätterstapel).
const UPRIGHT_QUAD := [[0.0625, 0.0233], [0.8688, 0.0233], [0.8688, 0.9767], [0.0625, 0.9767]]

# Monat → Ausgaben-Präfix (Amiga Joker 1990: Sommer-Doppelausgaben).
const MONTH_ISSUE := {1: "01", 2: "02", 3: "03", 4: "04", 5: "05", 6: "06_07",
	7: "06_07", 8: "08_09", 9: "08_09", 10: "10", 11: "11", 12: "12"}

static var _cache: Dictionary = {}   # cover_path → ImageTexture (fertiges Heft)


## Cache-Signatur enthält die echte Masterversion, Layoutdaten und Dateizeiten.
## Ein Live-Austausch von V01 auf V02 darf nie ein altes Bake wiederverwenden.
static func cache_key(master_path: String, cover_path: String, variant: String) -> String:
	var layout_sig := "upright"
	if variant == "desk" and FileAccess.file_exists(LAYOUT_PATH):
		layout_sig = FileAccess.get_file_as_string(LAYOUT_PATH).sha256_text()
	return "%s|%d|%s|%s|%d|%s" % [master_path,
		FileAccess.get_modified_time(master_path), layout_sig, cover_path,
		FileAccess.get_modified_time(cover_path), variant]


## Cover-Viereck (Ecken TL,TR,BR,BL) in MASTER-Pixeln aus dem Editor-Layout.
static func _quad_px(master_size: Vector2) -> PackedVector2Array:
	var fr: Array = [[0.14, 0.06], [0.92, 0.16], [0.86, 0.95], [0.06, 0.83]]
	if FileAccess.file_exists(LAYOUT_PATH):
		var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
		if typeof(p) == TYPE_DICTIONARY and (p as Dictionary).has("cover_quad"):
			var q: Variant = (p as Dictionary)["cover_quad"]
			if q is Array and (q as Array).size() == 4:
				fr = q
	var out := PackedVector2Array()
	for c: Variant in fr:
		out.append(Vector2(float(c[0]) * master_size.x, float(c[1]) * master_size.y))
	return out


## Titelbild fuer ein konkretes Erscheinungsdatum. Nur der historische 1990er
## Bildbestand enthaelt fest eingerasterte Jahreszahlen; ab 1991 verwenden wir
## neutrale, eigens erzeugte Pixelmotive und zeichnen Ausgabe/Jahr als echten
## UI-Text darueber. So kann niemals versehentlich ein 1990-Cover in 1991 liegen.
static func cover_for_date(year: int, month: int) -> String:
	var production_issue := ProductionCatalog.for_date(year, month)
	var production_cover := ProductionCatalog.asset_path(production_issue, "cover_front")
	if not production_cover.is_empty():
		return production_cover
	if year != 1990:
		if ERA_COVER_ART.is_empty():
			return ""
		return ERA_COVER_ART[posmod((year - 1991) * 12 + clampi(month, 1, 12) - 1,
			ERA_COVER_ART.size())]
	var issue: String = MONTH_ISSUE.get(month, "06_07")
	for path: String in RuntimeImages.logical_files(ARCHIVE_1990_DIR, ["png", "jpg", "jpeg", "webp"]):
		var file_name := path.get_file()
		if not file_name.contains("_back") and not file_name.contains("_bericht_") \
				and file_name.begins_with("amiga_joker_1990_%s_" % issue):
			return path
	return ""


## Kompatibilitaets-Einstieg fuer Tisch und Kiosk: immer das echte Spieljahr.
static func cover_for_month(month: int) -> String:
	# Tool-Szenen werden schon beim Editorstart aufgebaut, bevor Autoload-
	# Eigenschaften sicher introspektierbar sind. Die Vorschau bleibt deshalb
	# bewusst 1990; im Spiel gilt immer der echte Kalender.
	var current_year := 1990
	if not Engine.is_editor_hint():
		var main_loop := Engine.get_main_loop()
		if main_loop is SceneTree:
			var time_manager := (main_loop as SceneTree).root.get_node_or_null("TimeManager")
			if time_manager != null:
				current_year = int(time_manager.get("year"))
	return cover_for_date(current_year, month)


## Fertiges FLACHES Heft (Schreibtisch): Master + eingebackenes Cover.
static func compose(host: Node, cover_path: String, on_ready: Callable) -> void:
	await _bake(host, MASTER_PATH, _quad_px, cover_path, "desk", on_ready)


## Fertiges AUFRECHTES Heft (Kiosk-Rack): front-facing Master + Cover.
static func compose_upright(host: Node, cover_path: String, on_ready: Callable) -> void:
	await _bake(host, UPRIGHT_PATH, _upright_quad_px, cover_path, "up", on_ready)


## Gemeinsamer Bake: Master + Cover perspektivisch (2 Dreiecke) → gecachte Textur.
## Gecacht per (Variante+Cover); Headless-Blank → nichts (Aufrufer behält Master).
static func _bake(host: Node, master_path: String, quad_fn: Callable, cover_path: String,
		variant: String, on_ready: Callable) -> void:
	if cover_path == "" or not ResourceLoader.exists(master_path) or not ResourceLoader.exists(cover_path):
		return
	# Der Dummy-Renderer emittiert `frame_post_draw` nicht zuverlässig. Vor dem
	# Await aussteigen, damit Headless-QA keinen ewigen FunctionState/SubViewport
	# hinterlässt; der Aufrufer behält dort wie vorgesehen das Master-Heft.
	if DisplayServer.get_name() == "headless":
		return
	var key := cache_key(master_path, cover_path, variant)
	if _cache.has(key):
		on_ready.call(_cache[key])
		return
	var master := load(master_path) as Texture2D
	var cover := load(cover_path) as Texture2D
	if master == null or cover == null:
		return
	var ms := Vector2(master.get_size())
	var vp := SubViewport.new()
	vp.size = Vector2i(ms)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var mrect := TextureRect.new()
	mrect.texture = master
	mrect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mrect.size = ms
	vp.add_child(mrect)
	var drawer := _Drawer.new()
	drawer.cover = cover
	drawer.quad = quad_fn.call(ms)
	drawer.size = ms
	vp.add_child(drawer)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	# Der Host kann waehrend des Frame-Waits den Ort wechseln oder bei einem
	# Proof-Harness freigegeben werden. Dann ist auch der SubViewport bereits tot;
	# ein Bake darf daraus weder Debuggerfehler noch einen spaeten Callback machen.
	if not is_instance_valid(vp) or vp.is_queued_for_deletion():
		return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return
	# Mipmaps: das Heft wird stark verkleinert gezeichnet (Tisch ~160 px aus 844 px).
	# Ohne Mipmaps aliast die dichte Cover-Schrift → sieht „doppelt/verschoben" aus.
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	if on_ready.is_valid():
		on_ready.call(tex)


static func _upright_quad_px(master_size: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c: Array in UPRIGHT_QUAD:
		out.append(Vector2(float(c[0]) * master_size.x, float(c[1]) * master_size.y))
	return out


## Zeichnet das Cover als FEIN UNTERTEILTES Gitter-Mesh in die vier Ecken.
## Ein einzelnes 2-Dreieck-Viereck würde die Textur bei echter Perspektive
## entlang der Diagonale unterschiedlich scheren → Schrift wirkt „doppelt/
## verschoben". Viele kleine Zellen (bilineare Eck-Interpolation) machen die Naht
## unsichtbar. Ecken quad: TL,TR,BR,BL.
class _Drawer extends Control:
	const N := 20   # Gitter-Auflösung (NxN Zellen)
	var cover: Texture2D
	var quad: PackedVector2Array

	func _bilerp(u: float, v: float) -> Vector2:
		var top: Vector2 = quad[0].lerp(quad[1], u)   # TL→TR
		var bot: Vector2 = quad[3].lerp(quad[2], u)   # BL→BR
		return top.lerp(bot, v)

	func _draw() -> void:
		if cover == null or quad.size() != 4:
			return
		var cols := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
		for j in N:
			var v0 := float(j) / N
			var v1 := float(j + 1) / N
			for i in N:
				var u0 := float(i) / N
				var u1 := float(i + 1) / N
				var pts := PackedVector2Array([
					_bilerp(u0, v0), _bilerp(u1, v0), _bilerp(u1, v1), _bilerp(u0, v1)])
				var uvs := PackedVector2Array([
					Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
				draw_polygon(pts, cols, uvs, cover)
