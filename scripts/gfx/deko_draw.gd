class_name DekoDraw
## DekoDraw — reine Zeichenschicht der Deko-Werkstatt (aus deko_editor.gd
## ausgelagert, Zeilen-Budget). Statische Maler, die den DekoEditor als `ed`
## erhalten und darüber zeichnen (ed.draw_*) und dessen Zustand lesen
## (ed._quads(), ed._selected …). Einstieg: DekoDraw.render(ed) aus ed._draw().
# ------------------------------------------------------------- Zeichnen

static func render(ed) -> void:
	if ed.comp == null:
		return
	var editing: bool = ed._edit_mode()
	var showing: bool = editing or ed.comp.show_anchors
	if not showing:
		return
	var font := ThemeDB.fallback_font
	var t: Dictionary = ed.comp._master_transform()
	_draw_quads(ed, font, t)
	_draw_hotspots(ed, font, t)
	_draw_zones(ed, font, t, editing)
	_draw_object_frames(ed, font, editing)
	if editing:
		_draw_monitor_screen(ed, font)
	if ed.comp.show_anchors:
		_draw_anchor_crosses(ed, font, t)
	if editing and ed._help_visible:
		_draw_help_panel(ed, font)



static func _draw_quads(ed, font: Font, t: Dictionary) -> void:
	if not ed._quads_visible:
		return
	for quad_name in ed._quads():
		var quad: Array = ed._quads()[quad_name].get("corners", [])
		if quad.size() != 4:
			continue
		var rgb: Array = ed._quads()[quad_name].get("color", [1.0, 1.0, 1.0])
		var quad_color := Color(rgb[0], rgb[1], rgb[2])
		var pts := PackedVector2Array()
		for i in 5:
			var c: Array = quad[i % 4]
			pts.append(t["offset"] + Vector2(c[0], c[1]) * t["scale"])
		ed.draw_polyline(pts, Color(quad_color, 0.9), 2.0, true)
		for i in 4:
			var hot: bool = i == ed._corner_drag and quad_name == ed._corner_quad
			ed.draw_rect(Rect2(pts[i] - Vector2(5, 5), Vector2(10, 10)),
				Color(1.0, 1.0, 0.3, 1.0) if hot else quad_color, hot)
			ed.draw_string(font, pts[i] + Vector2(8, -6), str(i + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, quad_color.lightened(0.3))
		ed.draw_string(font, pts[0] + Vector2(6, 14), quad_name.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, quad_color.lightened(0.3))



static func _draw_hotspots(ed, font: Font, t: Dictionary) -> void:
	if not ed._hotspots_visible:
		return
	for hotspot_name in ed._hotspots():
		var hp: Array = ed._hotspots()[hotspot_name].get("corners", [])
		if hp.size() != 4:
			continue
		var active_hs: bool = hotspot_name == ed._hs_drag
		var pts := PackedVector2Array()
		var center := Vector2.ZERO
		for i in 5:
			var c: Array = hp[i % 4]
			var p: Vector2 = t["offset"] + Vector2(c[0], c[1]) * t["scale"]
			pts.append(p)
			if i < 4:
				center += p
		center /= 4.0
		ed.draw_polyline(pts, Color(1, 1, 1, 0.9 if active_hs else 0.5),
			2.0 if active_hs else 1.0, true)
		for i in 4:
			ed.draw_rect(Rect2(pts[i] - Vector2(4, 4), Vector2(8, 8)),
				Color(1, 1, 1, 0.95), false, 1.5)
		ed.draw_rect(Rect2(center - Vector2(5, 5), Vector2(10, 10)),
			Color(1, 1, 1, 0.95), true)
		ed.draw_string(font, pts[0] + Vector2(10, 14), "KLICK: %s" % hotspot_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.85))



static func _draw_zones(ed, font: Font, t: Dictionary, editing: bool) -> void:
	var zones: Dictionary = ed._cfg().get("zones", {})
	var zone_index := 1
	for zone_name in zones:
		var r: Array = zones[zone_name].get("rect", [])
		if r.size() == 4:
			var zr := Rect2(t["offset"] + Vector2(r[0], r[1]) * t["scale"],
				Vector2(r[2], r[3]) * t["scale"])
			var is_active: bool = zone_name == ed._active_zone
			ed.draw_rect(zr, Color(1.0, 0.72, 0.2, 0.95 if is_active else 0.45),
				false, 2.0 if is_active else 1.0)
			ed.draw_string(font, zr.position + Vector2(4, 12), "%d: %s" % [zone_index, zone_name],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.78, 0.3))
		zone_index += 1
	if editing and ed._zone_dragging:
		var p1: Vector2 = t["offset"] + ed._zone_start * t["scale"]
		var p2: Vector2 = t["offset"] + ed._zone_current * t["scale"]
		ed.draw_rect(Rect2(p1, p2 - p1).abs(), Color(1.0, 0.9, 0.3, 1.0), false, 2.0)



static func _draw_object_frames(ed, font: Font, editing: bool) -> void:
	if not (editing or Engine.is_editor_hint()):
		return
	for child in ed.comp.get_children():
		if child is TextureRect and child.get_meta("anchor", "") != "" \
				and not child.get_meta("is_shadow", false):
			var is_sel: bool = child == ed._selected
			var frame_col := Color(1.0, 0.95, 0.2, 1.0) if is_sel else Color(0.3, 0.9, 1.0, 0.8)
			if not child.visible:
				frame_col = Color(0.55, 0.55, 0.6, 0.7)  # ausgeblendete Lage: grau
			ed.draw_rect(Rect2(child.position, child.size), frame_col,
				false, 2.0 if is_sel else 1.0)
			var label := "%s (%d px)" % [child.get_meta("layer_id", "?"), int(child.get_meta("width", 0.0))]
			var active_model := str(child.get_meta("active_model", ""))
			if not active_model.is_empty():
				label += "  [%s]" % active_model
			if is_sel:
				var an: String = child.get_meta("anchor", "")
				var a: Array = ed._cfg()["anchors"].get(an, [0, 0])
				label += "  @ %d,%d  z%d" % [int(a[0]), int(a[1]), child.z_index]
			ed.draw_string(font, child.position + Vector2(2, -3), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(1.0, 0.95, 0.4) if is_sel else Color(0.5, 0.95, 1.0))
	if editing:
		var zoom_txt := "  ·  Zoom %d%%" % int(ed.comp.editor_zoom * 100.0) if ed.comp.editor_zoom > 1.01 else ""
		ed.draw_string(font, Vector2(8, ed.size.y - 6),
			"DEKO-MODUS  ·  M = Modell  ·  Strg+Drag = Modellversatz  ·  H = Hilfe  ·  Rad(leer) = Zoom  ·  F8 = speichern%s" % zoom_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.85, 0.4))
	else:
		ed.draw_string(font, Vector2(8, ed.size.y - 6),
			"WERKSTATT (Editor)  ·  Drag = Familienanker  ·  Strg+Drag = Modellversatz  ·  M = Modell  ·  Rad = Breite  ·  speichert sofort",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.85, 0.4))



## Monitor-Bildschirmfläche (Deko-Modus): Rahmen + Eck-Griffe. Ziehen der
## Fläche verschiebt, Ecken skalieren; F8 speichert je Monitormodell.
static func _draw_monitor_screen(ed, font: Font) -> void:
	var r: Rect2 = ed._mon_rect()
	if r.size.x < 4.0:
		return
	ed.draw_rect(r, Color(0.05, 0.06, 0.10, 0.4))            # Glas-Platzhalter
	ed.draw_rect(r, Color(1.0, 0.35, 0.95, 0.95), false, 2.0)  # Magenta-Rahmen
	var cs: Array = ed._mon_corners(r)
	for i in 4:
		var hot: bool = i == ed._mon_drag
		ed.draw_rect(Rect2((cs[i] as Vector2) - Vector2(5, 5), Vector2(10, 10)),
			Color(1.0, 1.0, 0.3) if hot else Color(1.0, 0.45, 0.95), true)
	ed.draw_string(font, r.position + Vector2(4, -5),
		"MONITOR-FENSTER — ziehen/Ecken · F8 speichert je Modell",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.6, 0.95))



static func _draw_anchor_crosses(ed, font: Font, t: Dictionary) -> void:
	for anchor_name in ed._cfg().get("anchors", {}):
		var a: Array = ed._cfg()["anchors"][anchor_name]
		var p: Vector2 = t["offset"] + Vector2(a[0], a[1]) * t["scale"]
		ed.draw_line(p + Vector2(-6, 0), p + Vector2(6, 0), Color.RED, 1.5)
		ed.draw_line(p + Vector2(0, -6), p + Vector2(0, 6), Color.RED, 1.5)
		ed.draw_string(font, p + Vector2(4, -4), anchor_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.55, 0.55))



## H-Taste: kompakte Befehlsübersicht (verschwindet per H oder nach 12 s).
static func _draw_help_panel(ed, font: Font) -> void:
	var lines := [
		"DEKO-WERKSTATT — ALLE BEFEHLE",
		"",
		"Linke Maustaste ziehen ...... Familienanker verschieben (Kabel folgen)",
		"Strg + linke Maustaste ...... aktive Modellvariante feinpositionieren",
		"Klick .......................... Objekt wählen (gelber Rahmen)",
		"Mausrad ........................ Breite ±5 px",
		"Shift + Mausrad ................ Höhe stauchen = kippen",
		"Strg + Mausrad ................. neigen (ums Standbein, ±2°)",
		"Alt + Mausrad .................. schräger Versatz (unten fest)",
		"Pfeiltasten .................... Familienanker 1 px (Shift: 5 px)",
		"Strg + Pfeiltasten ............ Modellversatz 1 px (Shift: 5 px)",
		"Bild auf / Bild ab ............. Ebene vor / zurück",
		"M / Shift+M .................... Geraetemodell +/-",
		"Farbige Eckpunkte ziehen ....... Flächen anpassen (Tisch, Regale,",
		"                                 Fenster, Gardinen, Heizung, Poster)",
		"Q .............................. Flächen-Rahmen ein/aus",
		"Weiße Klick-Polygone ........... Eck-Griffe = Form (auch schräg),",
		"                                 Mittelgriff = verschieben  ·  T = ein/aus",
		"Taste 1-3 ...................... Zone wählen (tisch/fenster/regal)",
		"Rechtsklick ziehen ............. Zonen-Rahmen neu aufziehen",
		"Mausrad über leerer Fläche ..... hinein-/herauszoomen (zum Zeiger)",
		"Mittlere Maustaste ziehen ...... Ansicht schieben  ·  0 = zurücksetzen",
		"V .............................. gewählte Lage aus-/einblenden",
		"Magenta-Rahmen (Monitor) ....... Bildschirmfläche ziehen/skalieren",
		"H .............................. diese Hilfe ein/aus",
		"F8 ...................... speichern (room_anchors.json + monitors.json)",
	]
	var panel_size := Vector2(470, 20.0 + lines.size() * 16.0)
	var top_left: Vector2 = (ed.size - panel_size) / 2.0
	ed.draw_rect(Rect2(top_left, panel_size), Color(0.04, 0.04, 0.07, 0.92))
	ed.draw_rect(Rect2(top_left, panel_size), Color(1.0, 0.78, 0.3, 0.8), false, 1.0)
	for i in lines.size():
		ed.draw_string(font, top_left + Vector2(14, 24 + i * 16),
			lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(1.0, 0.9, 0.6) if i == 0 else Color(0.92, 0.92, 0.88))
