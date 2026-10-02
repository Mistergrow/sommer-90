class_name LocationFx
extends Control
## Atmosphäre-Regisseur eines Ortes: liest data/location_fx.json (pro
## location_key) und hängt die konfigurierten Effekt-Ebenen (FxLayer) als Kinder
## ein — Grading, Lichtschäfte, Partikel, Glüh-/Neon-Flacker. Full-rect,
## maus-transparent, sitzt über dem Hintergrund und unter den Hotspots.
##
## Aufruf aus LocationBase: `LocationFx.attach(self, location_key())`.

const CONFIG_PATH := "res://data/location_fx.json"
const SurfaceGeometryData := preload("res://scripts/gfx/surface_geometry.gd")

const EFFECTS := {
	"grading":   preload("res://scripts/gfx/fx/fx_grading.gd"),
	"rays":      preload("res://scripts/gfx/fx/fx_rays.gd"),
	"particles": preload("res://scripts/gfx/fx/fx_particles.gd"),
	"steam":     preload("res://scripts/gfx/fx/fx_steam.gd"),
	"glow":      preload("res://scripts/gfx/fx/fx_glow.gd"),
	"beat":      preload("res://scripts/gfx/fx/fx_beat.gd"),
	"weather":   preload("res://scripts/gfx/fx/fx_weather.gd"),
	"vignette":  preload("res://scripts/gfx/fx/fx_vignette.gd"),
}

static var _config: Dictionary = {}
static var _loaded := false

var location_key := ""


## Baut die Atmosphäre eines Ortes, falls konfiguriert. Gibt den Regisseur
## zurück (oder null, wenn kein Eintrag existiert).
static func attach(host: Control, key: String) -> LocationFx:
	var conf := _location_config(key)
	if conf.is_empty():
		return null
	var fx := LocationFx.new()
	fx.name = "LocationFx"
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# z_index 0 + Einhängen VOR _build(): die Atmosphäre liegt über dem
	# Hintergrund, aber unter den Vordergrund-Nodes des Ortes (NPC-Porträts,
	# Info-Labels, Dim-Overlay) — sonst würde das Grading Text abtönen.
	# Größe manuell (kein Anker) wie LocationBase — vermeidet size-Warnungen.
	fx.z_index = 0
	fx.location_key = key
	host.add_child(fx)
	fx.size = host.size
	fx._build(conf)
	if host.has_signal("resized"):
		host.resized.connect(fx._on_host_resized.bind(host))
	return fx


func _build(conf: Dictionary) -> void:
	var effects: Array = []
	var has_weather := false
	var raw_effects: Array = conf.get("effects", [])
	var has_outdoor_weather := raw_effects.any(func(entry: Variant) -> bool:
		return entry is Dictionary and str((entry as Dictionary).get("type", "")) == "weather" \
			and str((entry as Dictionary).get("mode", "outdoor")) == "outdoor")
	for raw: Variant in raw_effects:
		if not raw is Dictionary:
			continue
		var configured := (raw as Dictionary).duplicate(true)
		configured["location_key"] = location_key
		if str(configured.get("type", "")) == "weather":
			has_weather = true
			if not configured.has("mode"):
				configured["mode"] = "outdoor"
		elif has_outdoor_weather and str(configured.get("type", "")) in ["grading", "rays"] \
				and not configured.has("weather_sensitive"):
			configured["weather_sensitive"] = true
		effects.append(configured)
	# Innenraeume mit im SurfaceEditor markierten Fenstern bekommen dasselbe
	# Wetter, aber strikt auf die Oeffnung maskiert. So bleibt Regen draussen und
	# wird nicht als flache Vollbildschicht ueber NPCs oder Mobiliar gelegt.
	if not has_weather and _has_window_surface(location_key):
		effects.append({
			"type": "weather",
			"mode": "window",
			"location_key": location_key,
			"density": 190,
			"mist": 0.0,
			"splash_gain": 0.0,
		})
	# Vignette automatisch als oberste Ebene, sofern nicht abgeschaltet oder
	# bereits explizit konfiguriert — sorgt für den kohärenten filmischen Rahmen.
	var vignette_off: bool = conf.get("vignette", true) == false
	var has_vignette := effects.any(func(e): return str(e.get("type", "")) == "vignette")
	if not vignette_off and not has_vignette:
		effects.append({"type": "vignette"})
	var i := 0
	for spec in effects:
		var t := str(spec.get("type", ""))
		if not EFFECTS.has(t):
			push_warning("[LocationFx] unbekannter Effekt-Typ: %s" % t)
			continue
		var layer: FxLayer = EFFECTS[t].new()
		layer.name = "%s_%d" % [t, i]
		layer.z_index = i    # Reihenfolge der Config = Zeichenreihenfolge
		add_child(layer)
		layer.size = size
		layer.setup(spec)
		i += 1


func _on_host_resized(host: Control) -> void:
	size = host.size
	for child in get_children():
		if child is Control:
			child.size = size


# --------------------------------------------------------------- Konfiguration
static func _location_config(key: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(CONFIG_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
			if parsed is Dictionary:
				_config = parsed
	var c: Variant = _config.get(key, null)
	return c if c is Dictionary else {}


static func _has_window_surface(key: String) -> bool:
	for raw: Variant in SurfaceGeometryData.surfaces_for(key):
		if raw is Dictionary and str((raw as Dictionary).get("type", "")) == "window":
			return true
	return false
