extends RefCounted
## Kleine, zustandsarme Fensterdienste der UI-Fassade. So bleiben Meldungslog,
## Notizblocksignal, Zentrierung und Hilfetext an genau einer Stelle definiert.

const MAX_LOG := 8

const HELP_TEXT := """SOMMER '90 — so funktioniert's:

- Klicke Objekte im Zimmer an (Computer, Bett, Tür, Regal, Fenster).
- Disketten: prüfen deckt den Zustand auf, Etiketten steigern den Wert,
  Backups sichern deine Sammlung. Vorsicht: Read/Write Errors!
- Zeit vergeht bei Ortswechseln; schlafen bringt Energie zurück.
- Samstagvormittag: Flohmarkt! Sonntag: Taschengeld.
- Stefan wartet in seinem Zimmer auf das Weltraumspiel...

Tasten: F1 Hilfe · F5 Speichern · F9 Laden · F10 CRT-Shader · ESC Menü"""


static func toast(host: Node, text: String) -> void:
	if text.strip_edges().is_empty():
		return
	var entries: Array = host.get("info_log")
	entries.push_front(text)
	if entries.size() > MAX_LOG:
		entries.resize(MAX_LOG)
	host.emit_signal("info_logged", text)


static func set_notebook_attention(host: Node, active: bool, item_count: int) -> void:
	item_count = maxi(0, item_count)
	if bool(host.get("notebook_attention")) == active \
			and int(host.get("notebook_attention_count")) == item_count:
		return
	host.set("notebook_attention", active)
	host.set("notebook_attention_count", item_count)
	host.emit_signal("notebook_attention_changed", active, item_count)


static func center(window_layer: Control, window: Control) -> void:
	if window.has_meta("no_center"):
		return
	var safe := safe_rect(window_layer)
	var window_size: Vector2 = window.get("win_size")
	# RetroWindow setzt den Pivot in die Mitte. Dadurch bleibt die sichtbare
	# Mitte auch bei einer fuer kleine Viewports notwendigen Gesamtskalierung
	# stabil und die Fensterecken bleiben innerhalb der sicheren Flaeche.
	window.position = (safe.get_center() - window_size * 0.5).floor()


static func safe_rect(window_layer: Control) -> Rect2:
	# Test-/Embed-Hosts (z. B. ein Monitorfenster) duerfen eine bereits
	# berechnete Flaeche liefern. Im normalen Spiel stammen die Werte aus den
	# dynamischen Insets der Main-Szene.
	if window_layer.has_meta("safe_area_rect"):
		var explicit := window_layer.get_meta("safe_area_rect") as Rect2
		if explicit.size.x > 0.0 and explicit.size.y > 0.0:
			return explicit
	var screen := window_layer.get_viewport_rect().size
	var insets := Vector4(8.0, 8.0, 8.0, 8.0)
	if window_layer.has_meta("safe_area_insets"):
		insets = window_layer.get_meta("safe_area_insets") as Vector4
	var origin := Vector2(insets.x, insets.y)
	var safe_size := Vector2(
		maxf(120.0, screen.x - insets.x - insets.z),
		maxf(90.0, screen.y - insets.y - insets.w))
	return Rect2(origin, safe_size)


static func fit_scale(window_layer: Control, requested_size: Vector2) -> float:
	if window_layer == null or requested_size.x <= 0.0 or requested_size.y <= 0.0:
		return 1.0
	var available := safe_rect(window_layer).size
	# A fixed lower bound (previously 0.5) makes tall studios extend below a
	# small safe area. Keep every control reachable, even in an embedded view.
	return minf(1.0, minf(available.x / requested_size.x,
		available.y / requested_size.y))
