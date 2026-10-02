extends Control
## SocketOverlay — zeichnet Steckdosen/Mehrfachverteiler (data: room_anchors.json
## "sockets", gesetzt im Kabel-Editor) im Zimmer. Prozedural, bis eigene Assets
## kommen (wie die LEDs). Kind des RoomCompositors, niedriges z (hinter den
## Möbeln/Geräten): eine Wanddose oben zeigt ganz, ein Verteiler hinterm Tisch
## wird teils verdeckt — genau richtig.

var comp: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Der Kippschalter zeigt den ECHTEN Stromzustand. Defensiv verbinden: im
	# Editor-Kontext ist der UIManager-Autoload nicht aktiv (bekannte Falle).
	var um := get_node_or_null("/root/UIManager")
	if um != null and um.has_signal("power_changed"):
		um.power_changed.connect(queue_redraw)


func _draw() -> void:
	if comp == null or not comp.has_method("_master_transform"):
		return
	var t: Dictionary = comp._master_transform()
	var sc: float = t["scale"]
	var off: Vector2 = t["offset"]
	for s: Dictionary in comp.config().get("sockets", []):
		var p: Array = s.get("pos", [0, 0])
		var master_point := Vector2(float(p[0]), float(p[1]))
		var center: Vector2 = comp.project_master_point(master_point) \
			if comp.has_method("project_master_point") else off + master_point * sc
		if str(s.get("type", "wall")) == "strip":
			_draw_strip(center, sc, int(s.get("outlets", 4)))
		else:
			_draw_wall(center, sc)


## Wandsteckdose: helle Platte + zwei Löcher, dezenter Schatten.
func _draw_wall(c: Vector2, sc: float) -> void:
	var w := 30.0 * sc
	var h := 34.0 * sc
	var r := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
	draw_rect(Rect2(r.position + Vector2(2, 3) * sc, r.size), Color(0, 0, 0, 0.25))
	draw_rect(r, Color(0.90, 0.89, 0.85))
	draw_rect(r, Color(0.62, 0.60, 0.56), false, maxf(1.0, sc))
	draw_circle(c - Vector2(6.0 * sc, 0), 2.4 * sc, Color(0.08, 0.08, 0.10))
	draw_circle(c + Vector2(6.0 * sc, 0), 2.4 * sc, Color(0.08, 0.08, 0.10))
	draw_arc(c, 12.0 * sc, 0, TAU, 24, Color(0.72, 0.70, 0.66), maxf(1.0, sc))


## Mehrfachverteiler: Leiste mit N Steckplätzen + rotem Schalter (leuchtet).
func _draw_strip(c: Vector2, sc: float, outlets: int) -> void:
	var w := (16.0 * outlets + 22.0) * sc
	var h := 26.0 * sc
	var r := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
	draw_rect(Rect2(r.position + Vector2(2, 3) * sc, r.size), Color(0, 0, 0, 0.3))
	draw_rect(r, Color(0.90, 0.88, 0.80))
	draw_rect(r, Color(0.55, 0.53, 0.48), false, maxf(1.0, sc))
	for k in outlets:
		var cx := r.position.x + (16.0 * (float(k) + 0.7)) * sc
		var oc := Vector2(cx, c.y)
		draw_circle(oc, 6.0 * sc, Color(0.78, 0.76, 0.71))
		draw_rect(Rect2(oc - Vector2(1.5, 4) * sc, Vector2(3, 3) * sc), Color(0.08, 0.08, 0.10))
		draw_rect(Rect2(oc + Vector2(-1.5, 1) * sc, Vector2(3, 3) * sc), Color(0.08, 0.08, 0.10))
	# Kippschalter rechts: leuchtet rot nur, wenn der Verteiler wirklich an ist
	# (Editor-Vorschau ohne UIManager zeigt ihn wie bisher an).
	var sw := Rect2(r.end.x - 12.0 * sc, r.position.y + 4.0 * sc, 8.0 * sc, 8.0 * sc)
	if _strip_on():
		draw_rect(sw, Color(0.85, 0.20, 0.16))
		draw_rect(sw.grow(1.5 * sc), Color(1.0, 0.3, 0.2, 0.35))
	else:
		draw_rect(sw, Color(0.32, 0.11, 0.10))
		draw_rect(sw, Color(0.16, 0.08, 0.07), false, maxf(1.0, sc))


func _strip_on() -> bool:
	var um := get_node_or_null("/root/UIManager")
	return um == null or bool(um.get("strip_power"))
