class_name CableRenderer
extends Control
## Dynamisches Kabel (Asset-Kategorie "Cable", z. B. CABLE_MOUSE_LIGHTGRAY):
## ein weicher Verlet-Spline zwischen zwei Anker-Punkten in Master-
## Koordinaten (1920x1080). Beide Enden sind gepinnt (Geräte-Ausgang →
## Computer-Port), die Mitte hängt durch, schwingt leicht im "Luftzug"
## und kann per poke() angestoßen werden (Hotspot-Klicks).
##
## Konfiguration kommt aus data/room_anchors.json ("cables"-Liste);
## der RoomCompositor erzeugt und platziert die Instanzen.

var start_master := Vector2.ZERO   # Kabelausgang am Gerät (Master-Px)
var end_master := Vector2.ZERO     # Port am Computer (Master-Px)
var segments := 24                 # lt. Kabel-Datenbank: 24 Segmente
var slack := 1.3                   # Kabellänge = Distanz × slack (Durchhang)
var thickness := 4.0               # Master-Pixel (wird mitskaliert)
var color := Color(0.75, 0.74, 0.71)
var style := "smooth"              # "smooth" | "coil" (Spiral-Hörerschnur)
var coils := 18                    # Windungen bei style == "coil"
var cable_id := ""
## Kabel, die vom Tisch zum Verteiler auf dem Teppich laufen, kollidieren mit
## einer kalibrierten Bodenlinie. Ohne diese Klemme zieht Verlet-Schwerkraft die
## Schlaufen optisch durch den Hochflor und sogar aus dem Bild.
var floor_contact := false
var floor_y := 965.0               # Master-y der sichtbaren Teppichauflage
var floor_roughness := 4.0         # kleine, deterministische Flor-Unruhe
var floor_surface := "carpet"      # "carpet" | "wood"

var _points := PackedVector2Array()
var _old_points := PackedVector2Array()
var _time := 0.0

const GRAVITY := 2400.0            # Master-Px/s² — weiches Gummikabel
const DAMPING := 0.96
const ITERATIONS := 4              # Constraint-Durchläufe pro Frame


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_init_points()


## Startform: leichte Parabel zwischen den Ankern (verhindert Aufschwingen).
func _init_points() -> void:
	_points.resize(segments + 1)
	for i in segments + 1:
		var t := float(i) / float(segments)
		var p := start_master.lerp(end_master, t)
		p.y += sin(t * PI) * start_master.distance_to(end_master) * (slack - 1.0) * 0.8
		if floor_contact and i > 0 and i < segments:
			p.y = minf(p.y, _floor_height(i))
		_points[i] = p
	_old_points = _points.duplicate()


func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 30.0)
	_time += delta
	var gravity_step := GRAVITY * delta * delta
	# Verlet-Integration für die freien Punkte
	for i in range(1, segments):
		var p := _points[i]
		var velocity := (p - _old_points[i]) * DAMPING
		_old_points[i] = p
		# Sanfter "Luftzug" (Ambient-Sway), unterschiedlich pro Segment
		var sway := sin(_time * 1.3 + float(i) * 0.7) * 0.35
		_points[i] = p + velocity + Vector2(sway * delta * 24.0, gravity_step)
	# Längen-Constraints: Segmentabstände halten, Enden pinnen
	var segment_length := start_master.distance_to(end_master) * slack / float(segments)
	for _iteration in ITERATIONS:
		_points[0] = start_master
		_points[segments] = end_master
		for i in segments:
			var a := _points[i]
			var b := _points[i + 1]
			var diff := b - a
			var dist := diff.length()
			if dist <= 0.001:
				continue
			var correction := diff * ((dist - segment_length) / dist) * 0.5
			if i > 0:
				_points[i] = a + correction
			if i + 1 < segments:
				_points[i + 1] = b - correction
		_apply_floor_collision()
	_apply_floor_collision()
	queue_redraw()


## Ein Hochflor-Teppich ist keine starre, glatte Ebene: eine geringe
## segmentfeste Höhenvariation verhindert die mathematisch perfekte Linie.
func _floor_height(index: int) -> float:
	var seed_phase := float(cable_id.hash() & 1023) * 0.0137
	return floor_y + sin(float(index) * 1.73 + seed_phase) * floor_roughness \
		+ sin(float(index) * 0.61 + seed_phase * 1.9) * floor_roughness * 0.35


func _apply_floor_collision() -> void:
	if not floor_contact:
		return
	for i in range(1, segments):
		var ground := _floor_height(i)
		if _points[i].y <= ground:
			continue
		var p := _points[i]
		p.y = ground
		_points[i] = p
		# Florreibung: horizontale Geschwindigkeit stark dämpfen, vertikales
		# Nachfedern entfernen. So liegt die Schleife ruhig statt zu schweben.
		var old := _old_points[i]
		old.x = lerpf(old.x, p.x, 0.62)
		old.y = p.y
		_old_points[i] = old


## Externe Störung (z. B. Maus-Hotspot geklickt): Kabel schwingt an.
func poke(strength: float = 30.0) -> void:
	for i in range(1, segments):
		_old_points[i] += Vector2(randf_range(-strength, strength),
			randf_range(-strength * 0.4, 0.0)) * 0.1


func _draw() -> void:
	var compositor := get_parent()
	if compositor == null or not compositor.has_method("_master_transform"):
		return
	var t: Dictionary = compositor._master_transform()
	var scale_factor: float = t["scale"]
	var offset: Vector2 = t["offset"]
	if scale_factor <= 0.0:
		return
	var screen_points := PackedVector2Array()
	screen_points.resize(_points.size())
	for i in _points.size():
		screen_points[i] = compositor.project_master_point(_points[i]) \
			if compositor.has_method("project_master_point") \
			else offset + _points[i] * scale_factor
	# Coil-Stil: den glatten Spline zu einer Wendel verformen (Hörer-Spiralschnur).
	var draw_points := _coil_points(screen_points, scale_factor) if style == "coil" else screen_points
	# Schwebende Abschnitte besitzen einen weichen, versetzten Schatten. Auf dem
	# Boden wird daraus eine enge Ambient-Occlusion-Linie; dadurch ist sofort
	# lesbar, wo das Kabel hängt und wo es im Flor aufliegt.
	for i in range(draw_points.size() - 1):
		var a := draw_points[i]
		var b := draw_points[i + 1]
		var contact := _segment_on_floor(i)
		var shadow_offset := Vector2(0.0, (0.65 if contact else 2.2) * scale_factor)
		var shadow_width := thickness * scale_factor * (1.55 if contact else 1.18)
		var shadow_alpha := 0.34 if contact else 0.18
		draw_line(a + shadow_offset, b + shadow_offset, Color(0.015, 0.012, 0.01, shadow_alpha),
			shadow_width, true)

	# Sehr dunkle Randader + farbiger Gummikern + schmale Lichtkante ergeben
	# Volumen, auch beim fast schwarzen Netzkabel.
	draw_polyline(draw_points, color.darkened(0.52), thickness * scale_factor * 1.28, true)
	draw_polyline(draw_points, color, thickness * scale_factor, true)
	var highlight := Color(color.lightened(0.38), 0.20)
	var highlight_points := draw_points.duplicate()
	for i in highlight_points.size():
		highlight_points[i] += Vector2(-0.38, -0.48) * scale_factor
	draw_polyline(highlight_points, highlight, maxf(0.65, thickness * scale_factor * 0.24), true)

	if floor_contact and floor_surface == "carpet":
		_draw_carpet_occlusion(draw_points, scale_factor)


func _segment_on_floor(index: int) -> bool:
	if not floor_contact or style == "coil" or index < 0 or index + 1 >= _points.size():
		return false
	return _points[index].y >= _floor_height(index) - 5.0 \
		and _points[index + 1].y >= _floor_height(index + 1) - 5.0


## Einzelne Teppichfasern kreuzen die untere Kabelkante. Es ist bewusst keine
## deckende beigefarbene Linie: wenige deterministische Fasern reichen, damit
## das Auge das Kabel im Flor statt vor einer flachen Fototextur verortet.
func _draw_carpet_occlusion(points: PackedVector2Array, scale_factor: float) -> void:
	for i in range(points.size() - 1):
		if not _segment_on_floor(i) or i % 2 != 0:
			continue
		var a := points[i]
		var b := points[i + 1]
		var tangent := (b - a).normalized()
		if tangent.is_zero_approx():
			continue
		var normal := Vector2(-tangent.y, tangent.x)
		var phase := float((cable_id.hash() + i * 37) & 255) / 255.0
		var center := a.lerp(b, 0.28 + phase * 0.44)
		var fiber_len := (2.2 + phase * 3.2) * scale_factor
		var fiber_color := Color(0.66, 0.55, 0.39, 0.42) if i % 4 == 0 \
			else Color(0.78, 0.70, 0.55, 0.30)
		draw_line(center - normal * fiber_len * 0.45,
			center + normal * fiber_len * 0.55, fiber_color, maxf(0.55, 0.8 * scale_factor), true)


## Wendel-Polylinie aus dem glatten Spline: senkrecht zum Verlauf mit sin()
## ausgelenkt → sieht aus wie eine spiralige Telefon-Hörerschnur.
func _coil_points(pts: PackedVector2Array, sc: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2:
		return pts
	var amp := thickness * 1.7 * sc
	var total := pts.size() - 1
	var subs := 7
	for i in total:
		var a := pts[i]
		var b := pts[i + 1]
		var perp := Vector2(-(b - a).y, (b - a).x).normalized()
		for s in subs:
			var u := float(s) / float(subs)
			var gu := (float(i) + u) / float(total)
			out.append(a.lerp(b, u) + perp * amp * sin(gu * float(coils) * TAU))
	out.append(pts[pts.size() - 1])
	return out
