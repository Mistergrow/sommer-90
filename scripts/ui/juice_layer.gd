class_name JuiceLayer
extends Control
## Feedback-/Juice-Ebene über dem HUD. Normale Meldungen stehen ausschließlich im
## breiten INFOS-Protokoll. Nur echte Meilensteine und der getrennte, typisierte
## Quest-Praesentationskanal erhalten zentrale Banner.

const QuestPresentationLayerScript := preload("res://scripts/ui/quest_presentation_layer.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Unter CanvasLayer gibt es keinen Control-Elternbereich; daher Viewportgröße direkt setzen.
	_sync_to_viewport()
	get_viewport().size_changed.connect(_sync_to_viewport)
	# Neue Auftraege, Zielwechsel und Abschluesse laufen ueber einen eigenen
	# FIFO. Er hoert NICHT auf generische Toasts und kann deshalb weder Dialog-
	# meldungen doppelt animieren noch beim Laden alte Quests wiederholen.
	var quest_presenter: Control = QuestPresentationLayerScript.new()
	quest_presenter.name = "QuestPresentation"
	add_child(quest_presenter)
	# Autoloads ueber den SceneTree beziehen: So bleibt das Script auch in
	# isolierten Test-/Importlaeufen kompilierbar, in denen globale Autoload-
	# Bezeichner noch nicht registriert sind.
	var memory_manager := get_node_or_null("/root/MemoryManager")
	if memory_manager != null and memory_manager.has_signal("memory_recorded"):
		memory_manager.connect("memory_recorded", _on_memory)


func _sync_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _on_memory(m: Dictionary) -> void:
	if str(m.get("kind", "")) != "meilenstein":
		return
	var b := _MilestoneBanner.new()
	b.title = str(m.get("title", "Meilenstein"))
	add_child(b)


# --------------------------------------------------------------- Bausteine
## Zentrales Meilenstein-Banner: „★ Titel" poppt oben-mittig auf, Funken strahlen
## aus, hält kurz, blendet aus. Selbst-animierend und selbst-aufräumend.
class _MilestoneBanner extends Control:
	var title := "Meilenstein"
	var _t := 0.0
	var _font: Font = load("res://assets/fonts/VT323_UI.ttf")
	var _sparks: Array = []

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for _i in 22:
			var a := rng.randf() * TAU
			_sparks.append({"a": a, "spd": rng.randf_range(90.0, 210.0),
				"sz": rng.randf_range(2.0, 4.5), "ph": rng.randf() * TAU})
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if _t > 2.4:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var panel := _panel_rect()
		var c := panel.get_center()
		var settings := get_node_or_null("/root/SettingsManager")
		var reduced := settings != null and bool(settings.call("value", "reduced_motion"))
		# Ein-/Ausblende-Kurve
		var appear: float = 1.0 if reduced else clampf(_t / 0.25, 0.0, 1.0)
		var fade: float = 1.0 if reduced or _t < 1.8 else clampf(1.0 - (_t - 1.8) / 0.6, 0.0, 1.0)
		var alpha := appear * fade
		var pop_scale := 0.7 + 0.3 * (appear if _t < 0.3 else 1.0)
		if not reduced and _t < 0.3:
			pop_scale = 0.6 + 0.55 * ease(appear, 0.3)   # Back-Pop
		# Funken
		for s: Dictionary in _sparks:
			if reduced:
				break
			var d: float = ease(clampf(_t / 0.9, 0.0, 1.0), 0.35) * s["spd"]
			var p := c + Vector2(cos(s["a"]), sin(s["a"]) * 0.7) * d
			var twk := 0.6 + 0.4 * sin(_t * 12.0 + s["ph"])
			_star(p, s["sz"] * (1.0 - _t / 2.4) * twk, Color(1.0, 0.86, 0.4, alpha * twk))
		# Scene captions (notably the museum plaque) must never shine through the
		# milestone text. Keep the compact backing opaque during the text fade.
		draw_rect(panel, Color8(10, 12, 17))
		draw_rect(panel, Color8(196, 145, 45), false, 1.0)
		# Text „★ Titel"
		var fs := int(round(30 * pop_scale))
		var banner_text := _fitted_title(fs, panel.size.x - 32.0)
		var tw := _font.get_string_size(banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := Vector2(c.x - tw.x * 0.5, panel.position.y + 10.0 + _font.get_ascent(fs))
		draw_string(_font, pos + Vector2(0, 2), banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.55 * alpha))
		draw_string(_font, pos, banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.82, 0.34, alpha))
		var sub := "Meilenstein"
		var sw := _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		draw_string(_font, Vector2(c.x - sw.x * 0.5, panel.end.y - 12.0), sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.78, 0.85, alpha * 0.8))

	func _panel_rect() -> Rect2:
		var viewport_size := get_viewport_rect().size
		# Reserve space for the largest brief pop, so the backing never changes
		# width while a title animates. Long titles stay inside 16-pixel margins.
		var requested := _font.get_string_size("★ %s" % title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 35).x + 40.0
		var width := minf(maxf(300.0, requested), minf(680.0, viewport_size.x - 32.0))
		return Rect2(Vector2(floorf((viewport_size.x - width) * 0.5),
			minf(90.0, maxf(8.0, viewport_size.y - 84.0))), Vector2(width, 76.0))

	func _fitted_title(font_size: int, available: float) -> String:
		var shown := "★ %s" % title
		if _font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= available:
			return shown
		while shown.length() > 1 and _font.get_string_size(shown + "…",
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available:
			shown = shown.left(-1)
		return shown + "…"

	func _star(p: Vector2, r: float, col: Color) -> void:
		if r <= 0.2:
			return
		draw_line(p - Vector2(r, 0), p + Vector2(r, 0), col, 1.5, true)
		draw_line(p - Vector2(0, r), p + Vector2(0, r), col, 1.5, true)
		draw_line(p - Vector2(r, r) * 0.6, p + Vector2(r, r) * 0.6, Color(col, col.a * 0.6), 1.0, true)
		draw_line(p - Vector2(-r, r) * 0.6, p + Vector2(-r, r) * 0.6, Color(col, col.a * 0.6), 1.0, true)
