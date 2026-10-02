extends FxLayer
## Datengetriebene Dampf-/Waermeschlieren fuer lebendige Innenraeume.
## Mehrere phasenversetzte, weich gestreckte Radialtexturen steigen aus jedem
## Emitter. Das bleibt fotografisch ruhig und vermeidet Sprite-Wiederholung.
##
## Config (type "steam"):
##   "emitters": [{
##     "pos":[u,v], "rise":0.14, "width":0.025, "alpha":0.07,
##     "speed":0.12, "count":5, "color":[0.96,0.93,0.84]
##   }]

var _time := 0.0
var _emitters: Array[Dictionary] = []


func _apply() -> void:
	for raw: Variant in cfg("emitters", []):
		if raw is Dictionary:
			_emitters.append((raw as Dictionary).duplicate(true))
	set_process(not _emitters.is_empty())


func _process(delta: float) -> void:
	var ambient := bool(SettingsManager.value("ambient_life"))
	if visible != ambient:
		visible = ambient
	if not ambient:
		return
	if not bool(SettingsManager.value("reduced_motion")):
		_time += delta
	queue_redraw()


func _draw() -> void:
	if size.x <= 1.0 or not bool(SettingsManager.value("ambient_life")):
		return
	var texture := dot_texture()
	for emitter_index in _emitters.size():
		var emitter := _emitters[emitter_index]
		var pos: Array = emitter.get("pos", [0.5, 0.55])
		var origin := px(float(pos[0]), float(pos[1]))
		var rise := float(emitter.get("rise", 0.14)) * size.y
		var width := float(emitter.get("width", 0.025)) * size.x
		var alpha := float(emitter.get("alpha", 0.07))
		var speed := float(emitter.get("speed", 0.12))
		var count := maxi(1, int(emitter.get("count", 5)))
		var color := to_color(emitter.get("color", [0.96, 0.93, 0.84]),
			Color(0.96, 0.93, 0.84))
		for i in count:
			var phase := float(i) / float(count) + float(emitter_index) * 0.173
			var life := fposmod(_time * speed + phase, 1.0)
			var envelope := sin(PI * life)
			var sway := sin(_time * 0.55 + float(i) * 2.31 + life * 4.2) \
				* width * (0.18 + life * 0.72)
			var center := origin + Vector2(sway, -rise * life)
			# Drei ueberlappende Hauchsegmente formen eine gebrochene, nicht
			# kreisrunde Schlierenkante. Oben wird der Dampf breiter und flacher.
			for segment in 3:
				var sf := float(segment) / 2.0
				var half := Vector2(width * (0.32 + life * 0.68 + sf * 0.22),
					width * (0.24 + life * 0.38))
				var segment_center := center + Vector2(
					sin(float(segment) * 2.4 + life * 5.0) * width * 0.18,
					-rise * 0.055 * sf)
				draw_texture_rect(texture, Rect2(segment_center - half, half * 2.0), false,
					Color(color.r, color.g, color.b,
						alpha * envelope * (0.46 - sf * 0.09)))
