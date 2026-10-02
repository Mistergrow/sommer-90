class_name PortraitGen
## Modularer NPC-Porträt-Generator: handkuratiertes 32×32-Quellraster, exakt
## 4× per Nearest-Neighbour auf die bestehende 128×128-UI-Ausgabe skaliert.
##
## GRUNDPRINZIP (permanentes Engine-System — ändert sich NIE):
##  • Porträts werden IMMER zur Laufzeit prozedural zusammengesetzt, nie als
##    festes Bild pro NPC gespeichert. Es gibt bewusst keine "bake"-Funktion.
##  • Deterministisch: DNA = hash(id) → derselbe NPC ergibt IMMER dasselbe
##    Gesicht — nur der ZUSTAND (Jahr, Alter, Emotion, Saison/Ort/Ereignis-
##    Kleidung) verändert es kontrolliert und wiedererkennbar.
##  • PortraitPaint32 ist die einzige produktive Zeichenwahrheit. Die 128er
##    Textur besitzt keine eigenen Zeichenoperationen und keine Zwischenpixel.
##
## IDENTITÄT (stabile Schema-v2-DNA): Gesichtsform, Hautton, Nase, Augen,
## Haar, Kleidung und kleine gerenderte Asymmetrien. Alle 21 Stammfiguren tragen
## diese Signatur explizit in npcs.json; Seed-Fallbacks bleiben für Passanten.
##
## ZUSTAND: year (Kleidungs-Epoche, Alterung 1990→2000: Ergrauen, Geheimratsecken,
## Brillen-Chance, Augenringe, Falten, reifere Kleidung), emotion (12 Ausdrücke:
## nur Augen/Brauen/Mund/Extras ändern sich), age (Overrides), season/location/
## event (Kleidung), clothing (Preset/Dict).
##
## KOMPOSITION (produktive render()-Reihenfolge):
##   torso → neck → hair_back → ear → face → hair_front → face_planes →
##   glasses → brows → eyes → nose → age → mouth → beard → accessories → hat
##
## Anzeige mit texture_filter = NEAREST (siehe PortraitGen.apply_to()).

const DATA_PATH := "res://data/portraits.json"
const PAINT32 := preload("res://scripts/gfx/portrait_paint_32.gd")
const OUTPUT_SIZE := 128

# Emotion → [Augen, Mund, Brauen-Stimmung, Extra]
const EMOTIONS := {
	"neutral":   ["neutral", "neutral", "", ""],
	"happy":     ["happy", "smile", "", ""],
	"laughing":  ["happy", "laugh", "", ""],
	"sad":       ["sad", "frown", "sad", ""],
	"angry":     ["angry", "grit", "angry", ""],
	"surprised": ["surprised", "open", "raise", ""],
	"shocked":   ["surprised", "open", "raise", ""],
	"thinking":  ["thinking", "neutral", "raise", ""],
	"talking":   ["neutral", "talking", "", ""],
	"tired":     ["tired", "neutral", "", ""],
	"nervous":   ["nervous", "wavy", "sad", "sweat"],
	"proud":     ["closed", "smile", "", "blush"],
}

static var _data: Dictionary = {}
static var _loaded := false
static var _cache: Dictionary = {}
static var _cache_order: Array[String] = []
static var _order: Array = []

## Ein harter LRU-Deckel verhindert, dass Dialog-Viseme und Jahreszustände über
## eine lange Partie unbegrenzt GPU-Texturen halten. 96 Einträge reichen für
## alle Stammfiguren plus aktive Ausdrucksframes, ohne jeden Buchstaben zu
## einem permanenten Cache-Eintrag zu machen.
const CACHE_LIMIT := 96


# ----------------------------------------------------------------- Öffentlich

## Deterministisches Porträt. hints = DNA-Overrides (npcs.json portrait/
## portrait_dna) + Zustand (year, emotion, age, season, location, event, clothing).
static func for_npc(id: String, hints: Dictionary = {}, frame_state: Dictionary = {}) -> ImageTexture:
	_ensure()
	var clean_frame := _normalized_frame_state(frame_state)
	var key := id + "|" + _canonical(hints) + "|" + _canonical(clean_frame)
	if _cache.has(key):
		_touch_cache_key(key)
		return _cache[key]
	var sel := _select(id, hints)
	_apply_frame_state(sel, clean_frame)
	var tex := _compose(sel)
	_store_cache(key, tex)
	return tex


## Öffentliche, entkoppelte Auswahl für Renderer, die dieselbe DNA als andere
## Darstellung benötigen (aktuell FigurePaint32 mit 32×48). Aufrufer erhalten eine
## Kopie des vollständigen Selections und greifen nicht auf private RNG-Phasen zu.
static func selection_for(id: String, hints: Dictionary = {},
		frame_state: Dictionary = {}) -> Dictionary:
	_ensure()
	var selection := _select(id, hints)
	_apply_frame_state(selection, _normalized_frame_state(frame_state))
	return selection.duplicate(true)


## Setzt Textur + Nearest-Filter auf eine TextureRect (Pixel-Perfect-Anzeige).
static func apply_to(rect: TextureRect, id: String, hints: Dictionary = {}, frame_state: Dictionary = {}) -> void:
	rect.texture = for_npc(id, hints, frame_state)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Stabile Identitätsfelder (für Tests: Wiedererkennbarkeit über Jahre).
static func identity_of(id: String, hints: Dictionary = {}) -> Dictionary:
	_ensure()
	var sel := _select(id, hints)
	return {"face_shape": sel["head"], "skin": sel["skin"], "nose": sel["nose"],
		"eye_type": sel["eye_type"], "hair_style": sel["hair_style"],
		"personality": sel["shirt_color"], "eye_spacing": sel["eye_spacing"],
		"eye_asymmetry": sel["eye_asymmetry"], "nose_shift": sel["nose_shift"],
		"mouth_shift": sel["mouth_shift"], "mouth_width": sel["mouth_width"],
		"hair_sweep": sel["hair_sweep"]}


static func clear_cache() -> void:
	_cache = {}
	_cache_order.clear()


static func cache_size() -> int:
	return _cache.size()


static func cache_limit() -> int:
	return CACHE_LIMIT


## Kanonische, rekursive Serialisierung: Dictionary-Einfügereihenfolge darf
## weder Bildidentität noch Cacheverbrauch beeinflussen.
static func _canonical(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var d: Dictionary = value
			var keys: Array = d.keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			var parts: PackedStringArray = []
			for key: Variant in keys:
				parts.append("%s:%s" % [JSON.stringify(str(key)), _canonical(d[key])])
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var parts: PackedStringArray = []
			for item: Variant in value:
				parts.append(_canonical(item))
			return "[" + ",".join(parts) + "]"
		TYPE_VECTOR2:
			var v: Vector2 = value
			return "v2(%.6f,%.6f)" % [v.x, v.y]
		TYPE_VECTOR2I:
			var vi: Vector2i = value
			return "v2i(%d,%d)" % [vi.x, vi.y]
		TYPE_COLOR:
			var c: Color = value
			return "c(%.6f,%.6f,%.6f,%.6f)" % [c.r, c.g, c.b, c.a]
		_:
			return JSON.stringify(value)


static func _touch_cache_key(key: String) -> void:
	var old := _cache_order.find(key)
	if old >= 0:
		_cache_order.remove_at(old)
	_cache_order.append(key)


static func _store_cache(key: String, tex: ImageTexture) -> void:
	while _cache_order.size() >= CACHE_LIMIT:
		var evicted: String = _cache_order.pop_front()
		_cache.erase(evicted)
	_cache[key] = tex
	_cache_order.append(key)


## Wählbare Merkmalslisten für den Avatar-Generator (Spielstart-Setup). Werte
## können als hints an for_npc() übergeben werden und überschreiben die DNA.
static func options() -> Dictionary:
	_ensure()
	var pal: Dictionary = _data.get("palettes", {})
	var idn: Dictionary = _data.get("identity", {})
	return {
		"skin": pal.get("skin", ["beige"]),
		"hair": pal.get("hair", ["brown"]),               # Haarfarbe
		"personality": pal.get("personality", ["teal"]),  # Farb-/Kleidungsidentität
		"hair_style": idn.get("hair_style", ["short"]),
		"face_shape": idn.get("face_shape", ["oval"]),
		"eye_type": idn.get("eye_type", ["normal"]),
		"eye_color": ["brown", "blue", "green", "grey"],
		"clothing_style": idn.get("clothing_style", ["casual"]),
		"ears": ["plain", "big"],
		"glasses": ["", "round", "square", "thick", "aviator", "cat", "half", "sunglasses"],
		"hat": ["none", "cap", "cap_back", "beanie", "winter", "headband", "bandana", "bucket",
			"sunhat", "tophat", "fedora", "cowboy", "flatcap", "visor", "party", "crown", "santa", "helmet", "headphones"],
		"beard": ["none", "stubble", "mustache", "goatee", "chin", "full", "sideburns",
			"soulpatch", "handlebar", "muttonchops", "longbeard"],
		"top": ["plain", "stripes", "hoodie", "jacket", "tanktop", "polo", "vneck", "overall", "logo"],
	}
# ----------------------------------------------------------------- Auswahl/DNA

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(DATA_PATH):
		var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if typeof(p) == TYPE_DICTIONARY:
			_data = p
	var layers: Array = _data.get("layers", [])
	layers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["z"]) < int(b["z"]))
	_order = layers


static func _pick(rng: RandomNumberGenerator, list: Array) -> String:
	if list.is_empty():
		return ""
	return str(list[rng.randi_range(0, list.size() - 1)])


## DNA + Zustand → fertige Layer-Auswahl. Alle rng-Züge passieren in FESTER
## Reihenfolge (unabhängig von hints) — nur so bleibt die Identität stabil.
static func _select(id: String, hints: Dictionary) -> Dictionary:
	_ensure()   # Daten/Palette laden — auch bei Direktaufruf (z. B. ChunkyAvatar)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var pal: Dictionary = _data.get("palettes", {})
	var idn: Dictionary = _data.get("identity", {})

	# --- 1) DNA würfeln (feste Zugreihenfolge!) ---
	var d: Dictionary = {}
	d["skin"] = _pick(rng, pal.get("skin", ["beige"]))
	d["hair_color"] = _pick(rng, pal.get("hair", ["brown"]))
	d["eye_color"] = _pick(rng, ["brown", "brown", "blue", "green", "grey"])
	d["personality"] = _pick(rng, pal.get("personality", ["teal"]))
	d["face_shape"] = _pick(rng, idn.get("face_shape", ["oval"]))
	d["hair_style"] = _pick(rng, idn.get("hair_style", ["short"]))
	d["eye_type"] = _pick(rng, idn.get("eye_type", ["normal"]))
	d["nose"] = _pick(rng, idn.get("nose_type", ["straight"]))
	d["ears"] = _pick(rng, ["plain", "plain", "plain", "big", "earring"])
	d["brow"] = _pick(rng, idn.get("brow_type", ["flat"]))
	d["clothing_style"] = _pick(rng, idn.get("clothing_style", ["casual"]))
	d["beard_pick"] = _pick(rng, ["stubble", "mustache", "goatee", "full", "chin", "sideburns"])
	d["beard_chance"] = rng.randf()
	d["glasses_style"] = _pick(rng, ["round", "round", "square", "square", "thick", "aviator", "cat", "half"])
	d["glasses_roll"] = rng.randf()
	d["glasses_gain_year"] = 1990 + rng.randi_range(0, 13)
	d["hat_roll"] = rng.randf()
	d["jacket_roll"] = rng.randf()
	d["jacket_pref"] = _pick(rng, pal.get("jacket", ["denim"]))
	var cloth_rolls: Array = []
	for _i in 4:
		cloth_rolls.append(rng.randi_range(0, 99))
	d["age_base"] = 16 + rng.randi_range(0, 33)
	d["grey_start"] = 38 + rng.randi_range(0, 19)
	d["recede"] = rng.randf() < 0.30
	# Neue Merkmale ans ENDE (bestehende DNA bleibt stabil): Geschlecht, Ohrring,
	# Kette, Brillen-Variante.
	d["gender"] = _pick(rng, ["m", "f"])
	d["earring"] = _pick(rng, ["none", "none", "stud", "hoop", "drop"])
	d["earring_metal"] = _pick(rng, ["gold", "silver"])
	d["necklace"] = _pick(rng, ["none", "none", "none", "chain", "pendant"])
	d["glasses_extra"] = _pick(rng, ["", "", "sunglasses", "thick"])
	# Stabile Gesichtsmetrik ans DNA-Ende hängen: bestehende RNG-Züge bleiben
	# unverändert. Kleine ganzzahlige Abweichungen erzeugen erkennbare, aber
	# kombinierbare Adventure-Gesichter statt eines einzigen symmetrischen Eis.
	d["eye_spacing"] = [-1, 0, 0, 0, 1][rng.randi_range(0, 4)]
	d["eye_asymmetry"] = [-1, 0, 0, 1][rng.randi_range(0, 3)]
	d["nose_shift"] = [-1, 0, 0, 1][rng.randi_range(0, 3)]
	d["mouth_shift"] = [-1, 0, 0, 1][rng.randi_range(0, 3)]
	d["mouth_width"] = [-2, -1, 0, 0, 0, 1, 2][rng.randi_range(0, 6)]
	d["hair_sweep"] = [-1, -1, 1, 1][rng.randi_range(0, 3)]

	# --- 2) DNA-Overrides aus hints (portrait/portrait_dna) ---
	for k in ["skin", "face_shape", "hair_style", "eye_type", "eye_color", "nose",
			"ears", "brow", "clothing_style", "age_base", "gender", "earring", "necklace",
			"eye_spacing", "eye_asymmetry", "nose_shift", "mouth_shift", "mouth_width",
			"hair_sweep"]:
		if hints.has(k):
			d[k] = hints[k]
	if hints.has("hair"):        # Farb-Hint (Alt-Kompatibilität npcs.json)
		d["hair_color"] = str(hints["hair"])
	if hints.has("personality"):
		d["personality"] = str(hints["personality"])

	# --- 3) Zustand: Jahr & Alter ---
	var year: int = int(hints.get("year", 1992))
	var age_now: int = int(hints.get("age_now", int(d["age_base"]) + (year - 1990)))
	match str(hints.get("age", "")):
		"child": age_now = 10
		"teen": age_now = 15
		"young": age_now = 20
		"adult": age_now = 30
		"old": age_now = 62
		"senior": age_now = 70
	age_now = clampi(age_now, 8, 78)
	var grey_t := clampf(float(age_now - int(d["grey_start"])) / 18.0, 0.0, 1.0)

	# --- 4) Layer-Auswahl zusammensetzen ---
	var sel: Dictionary = {}
	sel["age_now"] = age_now
	sel["life_stage"] = _life_stage(age_now)
	sel["maturity"] = clampf(float(age_now - 14) / 9.0, 0.0, 1.0)
	sel["grey_t"] = grey_t
	sel["recede"] = bool(d["recede"]) and age_now >= 45
	sel["skin"] = str(d["skin"])
	# Niemand wird grauhaarig GEBOREN: eine graue Basis auf eine natürliche
	# Farbe mappen (deterministisch → Identität bleibt). Grau kommt nur übers
	# Alter (grey_t) zurück — außer bei echten Senioren behält es die Basis.
	var hc := str(d["hair_color"])
	if hc == "grey" and age_now < 55 and not hints.has("hair") and not hints.has("hair_color"):
		hc = ["brown", "black", "auburn"][int(d["grey_start"]) % 3]
	sel["hair_color"] = hc
	sel["eye_color"] = str(d["eye_color"])
	sel["eye_type"] = str(d["eye_type"])
	sel["hair_style"] = str(d["hair_style"])
	sel["shadow"] = "soft"
	sel["neck"] = "plain"
	sel["head"] = str(d["face_shape"])
	sel["ears"] = str(d["ears"])
	sel["nose"] = str(d["nose"])
	sel["eyebrows"] = str(d["brow"])
	sel["hair_back"] = sel["hair_style"] if PAINT32.hair_has_back(sel["hair_style"]) else ""
	sel["hair_front"] = sel["hair_style"]
	sel["highlights"] = "rim"
	sel["mood"] = ""
	sel["extra"] = ""
	sel["gaze"] = 0
	sel["eye_spacing"] = clampi(int(d["eye_spacing"]), -1, 1)
	sel["eye_asymmetry"] = clampi(int(d["eye_asymmetry"]), -1, 1)
	sel["nose_shift"] = clampi(int(d["nose_shift"]), -1, 1)
	sel["mouth_shift"] = clampi(int(d["mouth_shift"]), -1, 1)
	sel["mouth_width"] = clampi(int(d["mouth_width"]), -2, 2)
	sel["hair_sweep"] = -1 if int(d["hair_sweep"]) < 0 else 1
	# Abgeleitete Render-Metriken, KEINE zweite Signature-DNA: Kopfwendung,
	# Körperbau und Clusterphase entstehen ausschließlich aus bereits expliziten
	# Anatomy-/Enum-Feldern des Schema-v2-Vertrags.
	var derived_turn := clampi(int(d["eye_asymmetry"]), -1, 1)
	if derived_turn == 0:
		derived_turn = -1 if int(d["hair_sweep"]) < 0 else 1
	var shape_build := 1 if str(d["face_shape"]) == "square" else (-1 if str(d["face_shape"]) in ["long", "heart"] else 0)
	sel["head_turn"] = derived_turn
	sel["build"] = clampi(shape_build + signi(int(d["mouth_width"])), -1, 1)
	sel["edge_phase"] = posmod(str(d["face_shape"]).length() + str(d["nose"]).length() * 2
		+ int(d["eye_spacing"]) * 3 + int(d["nose_shift"]) * 5
		+ int(d["mouth_shift"]) * 7 + int(d["mouth_width"]), 7)

	# Geschlecht (Junge/Mädchen) — SICHTBAR über Haar/Wimpern/Lippen/Bart/Ohrring.
	sel["gender"] = str(d.get("gender", "m"))
	var female: bool = sel["gender"] == "f"
	sel["female"] = female
	# Haar deterministisch je Geschlecht aus getrennten Pools (Toggle ändert
	# sichtbar), außer der Nutzer hat die Frisur explizit gewählt.
	if not hints.has("hair_style"):
		var hair_pool: Array = ["long", "ponytail", "bob", "medium", "straight", "bun", "pigtails", "curly", "afro"] if female \
			else ["short", "messy", "parted", "buzzcut", "curly", "spiky", "quiff", "flattop", "mohawk", "afro", "mullet"]
		var hidx := int(float(d["hat_roll"]) * hair_pool.size()) % hair_pool.size()
		sel["hair_style"] = str(hair_pool[hidx])
		sel["hair_front"] = sel["hair_style"]
		sel["hair_back"] = sel["hair_style"] if PAINT32.hair_has_back(sel["hair_style"]) else ""
	# Ohrring (Mädchen tragen häufiger)
	var er := str(d.get("earring", "none"))
	if female and er == "none" and float(d["glasses_roll"]) < 0.6:
		er = "stud"
	sel["earring"] = "" if er == "none" else "%s_%s" % [er, str(d.get("earring_metal", "gold"))]
	sel["necklace"] = "" if str(d.get("necklace", "none")) == "none" else str(d["necklace"])
	# Setup-WYSIWYG: Die sichtbare Ohren-Auswahl darf nicht durch einen zufaellig
	# gewuerfelten Schmuck-Layer ueberlagert werden. „Ohrring" bekommt bewusst
	# einen klaren Stud; Normal/Gross bleiben ohne verstecktes Schmuckstueck.
	if hints.has("ears"):
		sel["earring"] = "stud_gold" if str(hints["ears"]) == "earring" else ""

	# Bart: nur Jungs/Männer, ab ~20 (unter 24 höchstens Stoppeln)
	sel["beard"] = ""
	if not female and age_now >= 20 and float(d["beard_chance"]) < 0.42:
		sel["beard"] = "stubble" if age_now < 24 else str(d["beard_pick"])
	if hints.has("beard"):   # Setup-Auswahl
		sel["beard"] = "" if str(hints["beard"]) == "none" else str(hints["beard"])

	# Brille: DNA-Basis ODER im Lauf der Jahre dazugewonnen; Alter erhöht Chance
	var has_glasses: bool = float(d["glasses_roll"]) < 0.22
	if not has_glasses and float(d["glasses_roll"]) < 0.50 and year >= int(d["glasses_gain_year"]):
		has_glasses = true
	if age_now >= 52 and float(d["glasses_roll"]) < 0.60:
		has_glasses = true
	sel["glasses"] = str(d["glasses_style"]) if has_glasses else ""
	# Brillen-Varianten: Sonnenbrille (jung/szene, auch ohne Sehschwäche) / dicke Nerd
	var gx := str(d.get("glasses_extra", ""))
	if gx == "sunglasses" and age_now < 35 and str(d["clothing_style"]) in ["scene", "sporty", "casual"] and float(d["hat_roll"]) < 0.4:
		sel["glasses"] = "sunglasses"
	elif has_glasses and gx == "thick":
		sel["glasses"] = "thick"
	if hints.has("glasses"):   # Setup-/DNA-Auswahl (wie Bart & Hut steuerbar)
		sel["glasses"] = "" if str(hints["glasses"]) == "none" else str(hints["glasses"])

	# Hut/Cap: jüngere scene/sporty tragen eher was auf dem Kopf (mehr Varianz)
	sel["hat"] = ""
	if float(d["hat_roll"]) < 0.22:
		var hats: Array = ["cap", "cap_back", "beanie", "headband", "bandana", "bucket"]
		if str(d["clothing_style"]) in ["scene", "sporty"]:
			sel["hat"] = str(hats[int(float(d["beard_chance"]) * hats.size()) % hats.size()])
		elif float(d["hat_roll"]) < 0.10:
			sel["hat"] = "cap"
	if hints.has("hat"):     # Setup-Auswahl
		sel["hat"] = "" if str(hints["hat"]) == "none" else str(hints["hat"])

	# --- 5) Kleidung: Epoche × Stil × Reife × Saison × Ort × Ereignis ---
	var style := str(d["clothing_style"])
	if age_now >= 32 and style in ["scene", "sporty"]:
		style = "casual"      # Kleidungs-Reife
	if age_now >= 48:
		style = "neat"
	var loc_map: Dictionary = _data.get("clothing", {}).get("location", {})
	var loc: Dictionary = loc_map.get(str(hints.get("location", "")), {})
	if loc.has("style"):
		style = str(loc["style"])
	var evt_map: Dictionary = _data.get("clothing", {}).get("event", {})
	var evt: Dictionary = evt_map.get(str(hints.get("event", "")), {})
	if evt.has("style"):
		style = str(evt["style"])

	var eras: Array = _data.get("clothing", {}).get("eras", [])
	var era_idx := 0
	for i in eras.size():
		if year >= int(eras[i].get("from", 1990)):
			era_idx = i
	var shirt_pool: Array = eras[era_idx].get(style, ["tee"]) if not eras.is_empty() else ["tee"]
	sel["shirt"] = str(shirt_pool[int(cloth_rolls[era_idx]) % shirt_pool.size()]) if not shirt_pool.is_empty() else "tee"
	sel["shirt_color"] = str(d["personality"])   # Farbidentität bleibt konstant!

	var jacket_on: bool = float(d["jacket_roll"]) < (0.30 + (0.15 if age_now >= 30 else 0.0))
	var season: Dictionary = _data.get("clothing", {}).get("season", {}).get(str(hints.get("season", "")), {})
	if season.has("shirt") and sel["shirt"] != "hoodie":
		sel["shirt"] = str(season["shirt"])
	# Präzedenz: Saison < Ort < Ereignis (Flohmarkt-Jacke schlägt Sommer)
	if str(season.get("jacket", "")) == "none":
		jacket_on = false
	if str(season.get("jacket", "")) == "force":
		jacket_on = true
	if str(loc.get("jacket", "")) == "force" or str(evt.get("jacket", "")) == "force":
		jacket_on = true
	if str(hints.get("season", "")) == "winter" and sel["hat"] == "":
		if float(d["hat_roll"]) < 0.5:
			sel["hat"] = "beanie"
	sel["jacket"] = str(d["jacket_pref"]) if jacket_on else ""
	if evt.has("shirt"):
		sel["shirt"] = str(evt["shirt"])
	# Der Charaktereditor nennt das Feld `top`; beide Renderer lesen kanonisch
	# `shirt`. Ohne diese Naht zeigte nur die Ganzfigur die Auswahl, das Portraet
	# blieb bei einem zufaelligen Oberteil.
	if hints.has("top"):
		sel["shirt"] = str(hints["top"])

	# --- 6) Emotion (nur Ausdrucks-Layer!) ---
	_apply_emotion(sel, str(hints.get("emotion", "neutral")))

	# --- 7) Direkte Layer-Overrides (z. B. "glasses":"round", "hat":"none") ---
	for layer: Dictionary in _order:
		var lid: String = layer["id"]
		if hints.has(lid) and lid not in ["head"]:
			var want := str(hints[lid])
			if want == "none":
				sel[lid] = ""
			elif want != "":
				# Der Renderer ist absichtlich vorwärtskompatibel: neue Manifest-
				# Tokens dürfen sofort in ihren robusten prozeduralen Fallback laufen.
				sel[lid] = want
	if hints.has("hair_style"):  # Stil-Override wirkt auf beide Haar-Layer
		sel["hair_front"] = str(d["hair_style"])
		sel["hair_back"] = str(d["hair_style"]) if PAINT32.hair_has_back(str(d["hair_style"])) else ""
	_apply_clothing_hint(sel, hints.get("clothing", null))
	return sel


## Sichtbare Entwicklungsstufen halten dieselbe Portrait-DNA fest, geben dem
## Pixelrenderer aber eine eindeutige Anatomiephase. Gerade 14 -> 23 darf nicht
## nur von einem zufaelligen Bartwurf abhängen.
static func _life_stage(age_now: int) -> String:
	if age_now <= 15:
		return "early_teen"
	if age_now <= 17:
		return "late_teen"
	if age_now <= 20:
		return "young_adult"
	if age_now <= 24:
		return "adult"
	return "mature"


static func _apply_emotion(sel: Dictionary, emotion: String) -> void:
	var e: Array = EMOTIONS.get(emotion, EMOTIONS["neutral"])
	sel["eyes"] = str(e[0])
	sel["mouth"] = str(e[1])
	sel["mood"] = str(e[2])
	sel["extra"] = str(e[3])


## Nur bildwirksame Keys gehen in den globalen Cache. Aliaspaare wie
## viseme/mouth_pose und blink/closed werden vorab vereinheitlicht; UI-Zustände
## wie `speaking` erzeugen dadurch keine identischen Doppeltexturen.
static func _normalized_frame_state(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if raw.has("emotion"):
		var emotion := str(raw["emotion"]).strip_edges().to_lower()
		if emotion != "":
			out["emotion"] = emotion
	if raw.has("gaze"):
		out["gaze"] = clampi(int(raw["gaze"]), -1, 1)
	for side_key in ["eye_left", "eye_right"]:
		if not raw.has(side_key):
			continue
		var side_frame := str(raw[side_key]).strip_edges().to_lower()
		if side_frame == "blink":
			side_frame = "closed"
		elif side_frame == "neutral":
			side_frame = "open"
		if side_frame != "":
			out[side_key] = side_frame
	var eye_frame := str(raw.get("eye_frame", raw.get("eyes", ""))).strip_edges().to_lower()
	if bool(raw.get("blink", false)):
		eye_frame = "closed"
	elif eye_frame == "blink":
		eye_frame = "closed"
	elif eye_frame == "neutral":
		eye_frame = "open"
	if eye_frame != "": out["eye_frame"] = eye_frame
	var mouth_pose := str(raw.get("mouth_pose", raw.get("viseme", ""))).strip_edges().to_lower()
	match mouth_pose:
		"closed": mouth_pose = "mbp"
		"open": mouth_pose = "ai"
		"round", "o": mouth_pose = "ou"
	if mouth_pose != "": out["mouth_pose"] = mouth_pose
	return out


## Transiente Animationswerte werden NACH der Identitäts-/Zustandsauswahl
## aufgelegt. Kein Blink, Blick oder Mundframe kann damit DNA, Alter oder Outfit
## verändern. Unbekannte neue Pose-Tokens bleiben als robuster Renderer-Fallback
## erlaubt; das parallel gepflegte Manifest muss nicht in demselben Frame landen.
static func _apply_frame_state(sel: Dictionary, frame_state: Dictionary) -> void:
	if frame_state.is_empty():
		return
	var emotion := str(frame_state.get("emotion", ""))
	if emotion != "":
		_apply_emotion(sel, emotion)
	if frame_state.has("gaze"):
		sel["gaze"] = clampi(int(frame_state["gaze"]), -1, 1)
	var eye_frame := str(frame_state.get("eye_frame", frame_state.get("eyes", "")))
	if eye_frame == "open":
		eye_frame = "neutral"
	if eye_frame != "":
		sel["eyes"] = eye_frame
	if bool(frame_state.get("blink", false)):
		sel["eyes"] = "closed"
	if frame_state.has("eye_left"):
		sel["eye_left_frame"] = str(frame_state["eye_left"])
	if frame_state.has("eye_right"):
		sel["eye_right_frame"] = str(frame_state["eye_right"])
	var mouth_pose := str(frame_state.get("mouth_pose", frame_state.get("viseme", "")))
	match mouth_pose:
		"closed": mouth_pose = "mbp"
		"open": mouth_pose = "ai"
		"round": mouth_pose = "ou"
	if mouth_pose != "":
		sel["mouth"] = mouth_pose


## Kleidungs-Preset-Hint (Alt-Kompatibilität + Feinsteuerung per Dict).
static func _apply_clothing_hint(sel: Dictionary, clothing: Variant) -> void:
	if clothing == null:
		return
	if typeof(clothing) == TYPE_DICTIONARY:
		var c: Dictionary = clothing
		if c.has("shirt"): sel["shirt"] = str(c["shirt"])
		if c.has("shirt_color"): sel["shirt_color"] = str(c["shirt_color"])
		if c.has("jacket"): sel["jacket"] = "" if str(c["jacket"]) == "none" else str(c["jacket"])
		return
	match str(clothing):
		"leather": sel["jacket"] = "leather"
		"denim": sel["jacket"] = "denim"
		"hoodie": sel["shirt"] = "hoodie"; sel["jacket"] = ""
		"shirtsleeves": sel["jacket"] = ""


# ----------------------------------------------------------------- Komposition

static func _compose(sel: Dictionary) -> ImageTexture:
	var native: Image = PAINT32.render(sel)
	if native.get_size() != Vector2i(PAINT32.SIZE, PAINT32.SIZE):
		push_error("PortraitPaint32 verletzte den nativen 32×32-Vertrag")
		return ImageTexture.new()
	var output := native.duplicate()
	output.resize(OUTPUT_SIZE, OUTPUT_SIZE, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(output)
