extends RefCounted
## Datengetriebene Stilauflösung fuer Quest-Einblendungen.
##
## Definitionen duerfen optional `presentation` mit `effect`, `family`,
## `accent`, `duration` und `sound` setzen. Ohne Override wird aus vorhandenen
## Quest-Metadaten ein stabiler, passender Amiga-Effekt gewaehlt. So braucht ein
## neuer Auftrag keinen neuen UI-Sonderfall.

const VALID_EFFECTS := ["copper", "starfield", "raster", "vector", "bobs", "plasma", "scope"]
const VideoContract := preload("res://scripts/games/amiga_video_contract.gd")
const FAMILY_EFFECT := {
	"scene": "plasma",
	"music": "scope",
	"network": "starfield",
	"hardware": "vector",
	"games": "raster",
	"trade": "copper",
	"people": "bobs",
}
const START_COLOR := Color8(255, 174, 42)
const STAGE_COLOR := Color8(63, 218, 226)
const COMPLETE_COLOR := Color8(126, 238, 112)
const VALID_EMOTIONS := ["neutral", "happy", "laughing", "sad", "angry",
	"surprised", "shocked", "thinking", "talking", "tired", "nervous", "proud"]


static func style_for(event: Dictionary) -> Dictionary:
	var override: Dictionary = event.get("presentation", {})
	var family := str(override.get("family", _infer_family(event)))
	var effect := str(override.get("effect", FAMILY_EFFECT.get(family, _fallback_effect(event))))
	if effect not in VALID_EFFECTS:
		effect = _fallback_effect(event)
	var kind := str(event.get("kind", "started"))
	var accent := _kind_color(kind)
	var accent_override := str(override.get("accent", "")).strip_edges()
	if not accent_override.is_empty() and Color.html_is_valid(accent_override):
		accent = Color.html(accent_override)
	var year := int(event.get("year", 1990))
	var chipset := VideoContract.generation_for_year(year)
	accent = VideoContract.quantize_color(accent, chipset)
	var generation := VideoContract.visual_generation_signature(chipset)
	var detail_level := 1 if chipset == VideoContract.Chipset.OCS else (
		2 if chipset == VideoContract.Chipset.ECS else 3)
	var stage_number := int(event.get("stage_number", 0))
	var stage_count := int(event.get("stage_count", 0))
	var giver := str(event.get("giver_name", "")).strip_edges()
	var progress := "%02d/%02d" % [stage_number, stage_count] if stage_count > 0 else "--/--"
	var kicker: String = str({
		"started": Loc.t("quest.presentation.started", "NEUER AUFTRAG"),
		"stage": Loc.t("quest.presentation.stage", "ZIEL AKTUALISIERT"),
		"completed": Loc.t("quest.presentation.completed", "AUFTRAG ERFÜLLT"),
	}.get(kind, Loc.t("quest.presentation.quest", "AUFTRAG")))
	var subtitle := "%s · %s" % [str(kicker), progress]
	if not giver.is_empty():
		subtitle += " · " + giver.to_upper()
	var default_duration: float = 3.65 if kind == "started" else (3.25 if kind == "stage" else 3.85)
	var body := str(event.get("objective", ""))
	var detail := ""
	if kind == "completed":
		var completed_text := str(event.get("completed_text", "")).strip_edges()
		body = (Loc.t("quest.presentation.finished_prefix", "Abgeschlossen: %s") % completed_text) \
			if not completed_text.is_empty() else Loc.t("quest.presentation.all_goals_complete", "Alle Ziele dieses Auftrags sind erledigt.")
	var voice_line := _single_line(str(event.get("voice_line", "")).strip_edges())
	if not voice_line.is_empty():
		detail = body
		body = voice_line
		default_duration += 0.35
	var emotion := str(event.get("emotion", override.get("emotion", "neutral")))
	if emotion not in VALID_EMOTIONS:
		emotion = "neutral"
	return {
		"family": family,
		"effect": effect,
		"accent": accent,
		"kicker": str(kicker),
		"caption": _shorten(str(event.get("title", Loc.t("quest.presentation.quest", "Auftrag"))).to_upper(), 46),
		"subtitle": _shorten(subtitle, 74),
		"body": _shorten(_single_line(body), 112 if not detail.is_empty() else 180),
		"detail": _shorten(_single_line(detail), 104),
		"emotion": emotion,
		"delivery_marker": _delivery_marker(emotion),
		"progress": progress,
		"year": year,
		"chipset": chipset,
		"generation": str(generation.get("label", "OCS")),
		"detail_level": detail_level,
		"spark_count": [14, 24, 40][detail_level - 1],
		"redraw_hz": [25.0, 35.0, 50.0][detail_level - 1],
		"duration": clampf(float(override.get("duration", default_duration)), 2.0, 6.5),
		"sound": StringName(str(override.get("sound", _sound_for(kind)))),
		"completed": kind == "completed",
	}


static func preview_caption(event: Dictionary) -> String:
	var style := style_for(event)
	return _shorten("%s: %s" % [str(style["kicker"]), str(event.get("title", "Auftrag"))], 42)


static func _infer_family(event: Dictionary) -> String:
	var explicit := str(event.get("family", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	var source := " %s %s %s " % [
		str(event.get("title", "")),
		str(event.get("objective", "")),
		str(event.get("teaches", "")),
	]
	source = source.to_lower()
	if _contains_any(source, ["tracker", "musik", "mod ", "sound", "töne", "toene", "pattern"]):
		return "music"
	if _contains_any(source, ["szene", "demo", "intro", "pixel", "grafik", "release", "cracktro"]):
		return "scene"
	if _contains_any(source, ["modem", "mailbox", "bbs", "upload", "internet", "homepage", "netz"]):
		return "network"
	if _contains_any(source, ["hardware", "repar", "laufwerk", "monitor", "kabel", "speicher", "werkstatt"]):
		return "hardware"
	if _contains_any(source, ["spiel", "stefan", "diskette", "disk ", "prototyp"]):
		return "games"
	if _contains_any(source, ["flohmarkt", "verkauf", "händler", "haendler", "geld", "laden", "kaufen"]):
		return "trade"
	return "people"


static func _fallback_effect(event: Dictionary) -> String:
	return VALID_EFFECTS[posmod(hash(str(event.get("id", "quest"))), VALID_EFFECTS.size())]


static func _kind_color(kind: String) -> Color:
	match kind:
		"stage":
			return STAGE_COLOR
		"completed":
			return COMPLETE_COLOR
		_:
			return START_COLOR


static func _sound_for(kind: String) -> String:
	match kind:
		"stage":
			return "action"
		"completed":
			return "success"
		_:
			return "focus"


static func _delivery_marker(emotion: String) -> String:
	match emotion:
		"proud", "happy", "laughing":
			return "◆"
		"nervous", "surprised", "shocked", "angry":
			return "!"
		"thinking", "sad", "tired":
			return "…"
		_:
			return ">"


static func _contains_any(text: String, needles: Array) -> bool:
	for needle: Variant in needles:
		if str(needle) in text:
			return true
	return false


static func _single_line(text: String) -> String:
	return " ".join(text.replace("\r", " ").replace("\n", " ").split(" ", false))


static func _shorten(text: String, max_length: int) -> String:
	if text.length() <= max_length:
		return text
	return text.left(maxi(1, max_length - 3)).strip_edges() + "..."
