class_name DiskComposer
## Rendert eine fertige 3,5"-Diskette: Master-Disk (Gehäuse) + gedrucktes Spiel-
## Label, exakt an der im Disk-Editor festgelegten Position (data/disk_layout.json).
## EINZIGE Composer-Schicht fürs Disketten-Rendering — der Editor schreibt das
## Layout, dieses Skript liest es. Verwandt: Kabel/Deko-Editoren (Single-Source-JSON).

const LAYOUT_PATH := "res://data/disk_layout.json"
const DEFAULT_MASTER := "res://assets/backgrounds/layers/FLOPPY_35_DD_BLUE_FRONT_V01.png"
const BODY_MASK := "res://assets/masks/FLOPPY_35_DD_BLUE_FRONT_V01_MASK.png"
const DEFAULT_LABEL := {"x": 0.5, "y": 0.6, "w": 0.78, "h": 0.42}
const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")
const BODY_COLORS := {
	"red": Color8(172, 50, 50),
	"yellow": Color8(212, 178, 55),
	"purple": Color8(118, 66, 138),
	"violet": Color8(118, 66, 138),
}

static var _layout: Dictionary = {}
static var _master: Image = null
static var _body_mask: Image = null
static var _colored_masters: Dictionary = {}
static var _scaled_masters: Dictionary = {}
static var _cache: Dictionary = {}
static var _cache_order: Array[String] = []
const CACHE_LIMIT := 192


## Layout + Master neu laden (nach dem Speichern im Editor aufrufen).
static func reload() -> void:
	_layout = {}
	_master = null
	_body_mask = null
	_colored_masters.clear()
	_scaled_masters.clear()
	_cache.clear()
	_cache_order.clear()
	_ensure()


static func _ensure() -> void:
	if _layout.is_empty():
		if FileAccess.file_exists(LAYOUT_PATH):
			var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
			if typeof(p) == TYPE_DICTIONARY:
				_layout = p
		if _layout.is_empty():
			_layout = {"master": DEFAULT_MASTER, "label": DEFAULT_LABEL}
	if _master == null:
		_master = _load_img(str(_layout.get("master", DEFAULT_MASTER)))
	if _body_mask == null:
		_body_mask = _load_img(BODY_MASK)


static func _load_img(path: String) -> Image:
	if path.is_empty():
		return null
	# Softwarelabels liegen raw-first unter .gdignore. Fuer die CPU-Komposition
	# keine unnoetige Vollbild-ImageTexture erzeugen und sofort wieder per
	# get_image() zuruecklesen; das allein konnte einen Hintergrundjob ueber
	# einen 30-FPS-Frame ziehen.
	if path.begins_with("res://assets/software/"):
		var raw := RuntimeImages.raw_image(path)
		if raw != null:
			raw.convert(Image.FORMAT_RGBA8)
			return raw
	var texture := RuntimeImages.texture(path)
	return texture.get_image() if texture != null else null


## Das aktuelle Label-Rechteck (Anteile der Master-Sprite) — auch vom Editor genutzt.
static func label_rect() -> Dictionary:
	_ensure()
	var r: Variant = _layout.get("label", DEFAULT_LABEL)
	return r if typeof(r) == TYPE_DICTIONARY else DEFAULT_LABEL.duplicate()


static func master_texture(body_color: String = "blue") -> Texture2D:
	_ensure()
	var image := _master_for_color(body_color)
	return ImageTexture.create_from_image(image) if image != null else null


## Die Maskendatei trennt Gehaeuse, Metall und Papier. So wird nur der Kunststoff
## umgefaerbt; Licht, Kratzer und Materialtiefe des Master-Assets bleiben erhalten.
static func _master_for_color(body_color: String) -> Image:
	_ensure()
	if _master == null:
		return null
	var normalized := body_color.to_lower()
	if not BODY_COLORS.has(normalized) or _body_mask == null \
			or _body_mask.get_size() != _master.get_size():
		return _master.duplicate()
	if _colored_masters.has(normalized):
		return (_colored_masters[normalized] as Image).duplicate()
	var image := _master.duplicate()
	var target: Color = BODY_COLORS[normalized]
	var ref_blue := Color8(55, 91, 155)
	var reference_luma := ref_blue.r * 0.2126 + ref_blue.g * 0.7152 + ref_blue.b * 0.0722
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var mask_pixel := _body_mask.get_pixel(x, y)
			if mask_pixel.r < 0.72 or mask_pixel.g > 0.30 or mask_pixel.b > 0.30:
				continue
			var source := _master.get_pixel(x, y)
			var source_luma := source.r * 0.2126 + source.g * 0.7152 + source.b * 0.0722
			var light := source_luma / maxf(0.001, reference_luma)
			image.set_pixel(x, y, Color(
				clampf(target.r * light, 0.0, 1.0),
				clampf(target.g * light, 0.0, 1.0),
				clampf(target.b * light, 0.0, 1.0), source.a))
	_colored_masters[normalized] = image
	return image.duplicate()


## Fertige Diskette mit dem Label eines Bibel-Spiels (per SoftwareBible-Artwork).
## Kopien tragen KEIN gedrucktes Label → nur die nackte Master-Disk. Gecacht.
static func composed_disk(software_id: String, printed: bool = true, max_px: int = 256,
		disk_number: int = 1, body_color: String = "blue") -> ImageTexture:
	_ensure()
	if _master == null:
		return null
	var key := "%s/%s/%d/%d/%s" % [software_id, str(printed), max_px, disk_number, body_color]
	if _cache.has(key):
		_cache_order.erase(key)
		_cache_order.append(key)
		return _cache[key]
	var base := _scaled_master_for_color(body_color, max_px)
	if printed and software_id != "":
		var lbl_path := ""
		var bible: Object = Engine.get_main_loop().root.get_node_or_null("SoftwareBible") if Engine.get_main_loop() else null
		if bible != null:
			var label_kind := "disk_label" if disk_number <= 1 else "disk_label_%d" % disk_number
			lbl_path = str(bible.call("art_path", software_id, label_kind))
			if lbl_path.is_empty() and disk_number > 1:
				lbl_path = str(bible.call("art_path", software_id, "disk_label"))
		var lbl := _load_img(lbl_path)
		if lbl != null:
			_blit_label(base, lbl)
	var tex := ImageTexture.create_from_image(base)
	_cache[key] = tex
	_cache_order.append(key)
	while _cache_order.size() > CACHE_LIMIT:
		_cache.erase(_cache_order.pop_front())
	return tex


## Erst auf die tatsächlich angeforderte UI-Größe verkleinern und DANACH Label
## komponieren. Krauses 256px-Vorschau bearbeitet dadurch nicht länger pro Klick
## die komplette 652×701-Masterdiskette.
static func _scaled_master_for_color(body_color: String, max_px: int) -> Image:
	var normalized := body_color.to_lower()
	var key := "%s/%d" % [normalized, max_px]
	if _scaled_masters.has(key):
		return (_scaled_masters[key] as Image).duplicate()
	var image := _master_for_color(normalized)
	if image != null and max_px > 0 and image.get_width() > max_px:
		image.resize(max_px, maxi(1, roundi(float(max_px) * image.get_height() / image.get_width())),
			Image.INTERPOLATE_LANCZOS)
	_scaled_masters[key] = image
	return image.duplicate() if image != null else null


## Diskette mit einem SELBSTGEMALTEN Etikett (Base64-PNG aus dem Etikett-Designer).
## Leerer String → schmucklose Master-Diskette.
static func composed_custom(sticker_b64: String, max_px: int = 256,
		body_color: String = "blue") -> ImageTexture:
	_ensure()
	if _master == null:
		return null
	var base := _master_for_color(body_color)
	var lbl := decode_sticker(sticker_b64)
	if lbl != null:
		_blit_label(base, lbl)
	if base.get_width() > max_px:
		base.resize(max_px, int(round(float(max_px) * base.get_height() / base.get_width())), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(base)


## Base64-PNG → Image. null bei leer/fehlerhaft.
static func decode_sticker(sticker_b64: String) -> Image:
	if sticker_b64.strip_edges().is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(Marshalls.base64_to_raw(sticker_b64)) != OK:
		return null
	return img


## Ein Image als Base64-PNG kodieren (Etikett-Designer → Diskette).
static func encode_sticker(img: Image) -> String:
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


## Ein Label-Image ins Master-Bild an die Layout-Position einsetzen (alpha-korrekt).
static func _blit_label(base: Image, lbl: Image) -> void:
	var r := label_rect()
	var mw := base.get_width()
	var mh := base.get_height()
	var tw := maxi(1, int(round(float(r.get("w", 0.78)) * mw)))
	var th := maxi(1, int(round(float(r.get("h", 0.42)) * mh)))
	var scaled := lbl.duplicate()
	# Das Etikett wird auf der 256-px-Vorschau stark verkleinert. Bilinear ist
	# hier visuell stabil und verhindert, dass ein einzelnes neues PNG-Label den
	# Hintergrund-Warmup ueber ein 30-FPS-Framebudget zieht.
	scaled.resize(tw, th, Image.INTERPOLATE_BILINEAR)
	var ox := int(round(float(r.get("x", 0.5)) * mw - tw * 0.5))
	var oy := int(round(float(r.get("y", 0.6)) * mh - th * 0.5))
	base.blend_rect(scaled, Rect2i(0, 0, tw, th), Vector2i(ox, oy))
