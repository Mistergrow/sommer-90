class_name StandaloneAmigaVideo
extends RefCounted
## Lokaler Video-/Generationenadapter fuer die eigenstaendigen Diskettenspiele.
##
## Die Spiellogik zeichnet weiterhin in echten Amiga-Lowres-Koordinaten. Dieses
## Modul beschreibt nur den Hardware-Rahmen und stellt gemeinsame, determinis-
## tische Raster-/Copper-Effekte bereit. Originaldisketten behalten dabei ihr
## Release-Chipset; ECS-/AGA-Fassungen werden als eigene Profile angelegt.
## Profil, Limits und Aufloesung stammen aus dem globalen Videovertrag. Diese
## Datei enthaelt nur noch die individuelle Standalone-Praesentation.

const VideoContract := preload("res://scripts/games/amiga_video_contract.gd")

enum Chipset {
	OCS = VideoContract.Chipset.OCS,
	ECS = VideoContract.Chipset.ECS,
	AGA = VideoContract.Chipset.AGA,
}

const GAME_IDENTITIES := {
	"space_lemming_trouble": "INDUSTRIAL SPACE PUZZLE",
	"turbo_kart_deluxe": "POLYGON STUNT RACER",
	"code_red_protocol": "DENSE STRATEGY CONTROL",
}


static func profile(game_id: String, _host: Node = null) -> Dictionary:
	var base := VideoContract.game_profile(game_id)
	if base.is_empty():
		return {}
	var request: Dictionary = base.get("render_request", {})
	var logical_i: Vector2i = base.get("logical_size", Vector2i.ZERO)
	base["native_size"] = Vector2(logical_i)
	base["name"] = str(base.get("chipset_name", "OCS"))
	base["video_mode_label"] = str(base.get("video_mode_name", "PAL LOWRES"))
	base["bitplanes"] = int(request.get("bitplanes", 5))
	base["indexed_colors"] = int(request.get("indexed_colors", 32))
	base["audio_channels"] = 4
	base["refresh_hz"] = 50
	base["parallax_planes"] = int(request.get("parallax_layers", 1))
	base["animation_phases"] = int(request.get("animation_frames_per_actor", 4))
	base["identity"] = str(GAME_IDENTITIES.get(game_id, "AMIGA DISK GAME"))
	base["generation_signature"] = "%s · %s · %d FARBEN · %d-CH PAULA" % [
		str(base.get("name", "OCS")), str(base.get("video_mode_label", "PAL LOWRES")),
		int(base.get("indexed_colors", 32)), int(base.get("audio_channels", 4)),
	]
	return base


static func layout(host_size: Vector2, native_size: Vector2) -> Dictionary:
	# Nearest bleibt aktiv; eine Monitorachse wird stets voll genutzt. Die
	# gerundete Herkunft verhindert den alten halben-Pixel-Versatz zwischen Maus
	# und Bild, auch wenn der Host kein ganzzahliges Vielfaches von 320/384 ist.
	var scale := maxf(0.01, minf(host_size.x / native_size.x, host_size.y / native_size.y))
	var origin := ((host_size - native_size * scale) * 0.5).round()
	return {"scale": scale, "origin": origin, "content": Rect2(origin, native_size * scale)}


static func is_aga(active_profile: Dictionary) -> bool:
	return int(active_profile.get("chipset", Chipset.OCS)) == Chipset.AGA


static func draw_copper_bands(canvas: CanvasItem, rect: Rect2, top: Color, bottom: Color,
		band_height := 2, aga := false) -> void:
	var step := 1 if aga else maxi(2, band_height)
	var start_y := floori(rect.position.y)
	var end_y := ceili(rect.end.y)
	for y in range(start_y, end_y, step):
		var ratio := clampf((float(y) - rect.position.y) / maxf(1.0, rect.size.y), 0.0, 1.0)
		var color := top.lerp(bottom, ratio)
		if not aga:
			# OCS/ECS: sichtbare, stabile 12-Bit-RGB-Stufen statt moderner
			# kontinuierlicher Verlaeufe.
			color = Color(
				roundf(color.r * 15.0) / 15.0,
				roundf(color.g * 15.0) / 15.0,
				roundf(color.b * 15.0) / 15.0,
				color.a)
		canvas.draw_rect(Rect2(rect.position.x, y, rect.size.x,
			minf(float(step), rect.end.y - y)), color)


static func draw_ordered_dither(canvas: CanvasItem, rect: Rect2, color: Color,
		density: float, phase := 0) -> void:
	var threshold := clampi(roundi(clampf(density, 0.0, 1.0) * 16.0), 0, 16)
	if threshold <= 0:
		return
	const BAYER_4 := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	for y in range(floori(rect.position.y), ceili(rect.end.y)):
		for x in range(floori(rect.position.x), ceili(rect.end.x)):
			var index := posmod(x + phase, 4) + posmod(y, 4) * 4
			if int(BAYER_4[index]) < threshold:
				canvas.draw_rect(Rect2(x, y, 1, 1), color)


static func draw_post_fx(canvas: CanvasItem, native_size: Vector2,
		active_profile: Dictionary, elapsed: float, reduced_fx := false) -> void:
	var aga := is_aga(active_profile)
	var scan_alpha := 0.055 if aga else 0.095
	var spacing := 3 if aga else 2
	for y in range(1, roundi(native_size.y), spacing):
		canvas.draw_line(Vector2(0, y), Vector2(native_size.x, y),
			Color(0, 0, 0, scan_alpha), 1.0)
	if reduced_fx:
		return
	# Sehr schwache PAL-Phasenlage. Sie ist absichtlich an 50 Hz quantisiert,
	# damit weder Shader-Rauschen noch subpixeliges HD-Flimmern entsteht.
	var frame_50 := floori(elapsed * 50.0)
	var phase_y := posmod(frame_50, maxi(1, roundi(native_size.y)))
	canvas.draw_line(Vector2(0, phase_y), Vector2(native_size.x, phase_y),
		Color(0.45, 0.75, 0.82, 0.025 if aga else 0.04), 1.0)


static func debug_contract(active_profile: Dictionary) -> Dictionary:
	var native: Vector2 = active_profile.get("native_size", Vector2.ZERO)
	var colors := int(active_profile.get("indexed_colors", 0))
	var chipset := int(active_profile.get("chipset", -1))
	var validation := VideoContract.validate_profile(active_profile)
	return {
		"valid": bool(validation.get("ok", false))
			and native.x > 0.0 and native.y > 0.0
			and chipset in [Chipset.OCS, Chipset.ECS, Chipset.AGA],
		"native_size": native,
		"chipset": str(active_profile.get("name", "")),
		"colors": colors,
		"bitplanes": int(active_profile.get("bitplanes", 0)),
		"refresh_hz": int(active_profile.get("refresh_hz", 0)),
		"global_contract": true,
		"contract_errors": validation.get("errors", []),
		"fractional_nearest": true,
	}
