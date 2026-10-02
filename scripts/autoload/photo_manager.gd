extends Node
## PhotoManager — das FOTO-ALBUM / die Erinnerungen (Phase F, Endgame-Museum).
##
## Hält kleine „Schnappschüsse" wichtiger Momente der Dekade fest: bei jedem
## MEILENSTEIN (MemoryManager.record_once) und jedem freigeschalteten ERFOLG wird
## automatisch ein Bild des aktuellen Bildschirms als winziges Polaroid-Thumbnail
## gespeichert (echter Viewport-Screenshot → heruntergerechnet → Base64-PNG, genau
## wie die selbstgemalten Etiketten). Zusätzlich kann der Spieler jederzeit selbst
## „knipsen". Betrachten im Foto-Album (Systemmenü → 📷 Erinnerungen).

signal photos_changed

const THUMB_W := 176            # Breite des gespeicherten Thumbnails (Polaroid)
const MAX_PHOTOS := 40          # Deckel, damit der Spielstand nicht ausufert

var photos: Array = []          # {id, title, caption, date, year, day, w, h, img(b64)}
var _auto_ids: Dictionary = {}  # id → true: Auto-Schnappschüsse nur EINMAL


func _ready() -> void:
	var mm := get_node_or_null("/root/MemoryManager")
	if mm != null and mm.has_signal("memory_recorded"):
		mm.memory_recorded.connect(_on_memory)


func count() -> int:
	return photos.size()


## Jeder MEILENSTEIN wird zum Schnappschuss (Erfolge knipsen separat in unlock()).
func _on_memory(m: Dictionary) -> void:
	if str(m.get("kind", "")) != "meilenstein":
		return
	var id := "ms_" + str(m.get("id", ""))
	capture(str(m.get("title", "Meilenstein")), str(m.get("text", "")), id, true)


## Aktuellen Bildschirm als Erinnerung festhalten. auto=true → Dedupe über id
## (Meilenstein/Erfolg nur einmal). Rückgabe: true, wenn ein Foto entstand.
func capture(title: String, caption: String, id: String = "", auto := false) -> bool:
	if auto and id != "":
		if _auto_ids.has(id):
			return false
		_auto_ids[id] = true
	var img := _grab_thumb()
	var b64 := ""
	var w := 0
	var h := 0
	if img != null:
		b64 = Marshalls.raw_to_base64(img.save_png_to_buffer())
		w = img.get_width()
		h = img.get_height()
	photos.append({
		"id": id, "title": title, "caption": caption, "date": _date_str(),
		"year": _year(), "day": _day(), "w": w, "h": h, "img": b64,
	})
	while photos.size() > MAX_PHOTOS:
		photos.pop_front()
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.call("play", "camera", 0.0)
	photos_changed.emit()
	return true


## Screenshot des Root-Viewports → auf Polaroid-Breite herunterskaliert (RGB, klein).
## Kann null liefern (headless/kein Frame) — dann wird ein Foto ohne Bild gespeichert.
func _grab_thumb() -> Image:
	# Der Dummy-Renderer liefert im Headless-Modus zwar ein Texture-Objekt, dessen
	# RID aber ungueltig ist. get_image() wuerde dann einen Engine-Fehler loggen.
	if DisplayServer.get_name() == "headless":
		return null
	var vp := get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	var iw := img.get_width()
	var ih := img.get_height()
	if iw <= 0 or ih <= 0:
		return null
	var tw := mini(THUMB_W, iw)
	var th := maxi(1, int(round(tw * float(ih) / float(iw))))
	img.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return img


## Ein gespeichertes Thumbnail zurück in eine Textur (oder null bei „kein Bild").
static func decode(photo: Dictionary) -> ImageTexture:
	var b64 := str(photo.get("img", ""))
	if b64 == "":
		return null
	var img := Image.new()
	if img.load_png_from_buffer(Marshalls.base64_to_raw(b64)) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _year() -> int:
	var tm := get_node_or_null("/root/TimeManager")
	return int(tm.get("year")) if tm != null else 1990


func _day() -> int:
	var tm := get_node_or_null("/root/TimeManager")
	return int(tm.get("day_counter")) if tm != null else 0


func _date_str() -> String:
	var tm := get_node_or_null("/root/TimeManager")
	if tm == null:
		return ""
	return "%d.%d.%d" % [int(tm.get("day")), int(tm.get("month")), int(tm.get("year"))]


func to_dict() -> Dictionary:
	return {"photos": photos, "auto_ids": _auto_ids}


func from_dict(d: Dictionary) -> void:
	photos = d.get("photos", [])
	_auto_ids = d.get("auto_ids", {})


func reset() -> void:
	photos = []
	_auto_ids = {}
