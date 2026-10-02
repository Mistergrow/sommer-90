class_name TurboStuntRenderer
extends RefCounted
## Pixelgenaue Pseudo-3D-Fahransicht im Stil frueher Polygon-Rennspiele.

const Track := preload("res://scripts/games/turbo_stunt_track.gd")
const SEGMENTS := 88
const VIEW_DISTANCE_METERS := 150.0
const MIN_AHEAD := 0.070
const MAX_AHEAD := 0.220
const HORIZON_Y := 68.0
const ROAD_BOTTOM_Y := 171.0
const ROAD_NEAR_HALF_WIDTH := 132.0
const ROAD_FAR_HALF_WIDTH := 2.5
const LAPS := 3

const C_BLACK := Color8(4, 7, 12)
const C_SKY_TOP := Color8(36, 50, 85)
const C_SKY_LOW := Color8(188, 112, 72)
const C_GROUND := Color8(68, 84, 48)
const C_ROAD := Color8(75, 76, 78)
const C_ROAD_ALT := Color8(83, 82, 82)
const C_EDGE := Color8(24, 26, 31)
const C_WHITE := Color8(238, 238, 222)
const C_CREAM := Color8(238, 195, 154)
const C_AMBER := Color8(251, 190, 54)
const C_ORANGE := Color8(223, 113, 38)
const C_RED := Color8(217, 87, 99)
const C_CYAN := Color8(95, 205, 228)
const C_BLUE := Color8(99, 155, 255)
const C_GREEN := Color8(106, 190, 48)

var _panorama_heading := 0.0
var _panorama_ready := false


func reset_camera() -> void:
	_panorama_heading = 0.0
	_panorama_ready = false


func draw(canvas: CanvasItem, font: Font, model: RefCounted, countdown: int,
		show_countdown: bool, message: String, reduced_fx := false,
		visual_state: Dictionary = {}, video_profile: Dictionary = {}) -> void:
	var player: Dictionary = visual_state.get("player", model.player_state())
	if player.is_empty():
		return
	_draw_sky(canvas, model, player, reduced_fx, video_profile)
	var slices := _road_slices(model, player)
	_draw_ground_details(canvas, slices, model, player)
	_draw_road(canvas, slices)
	_draw_stunt_structures(canvas, slices)
	_draw_opponents(canvas, model, player, slices, visual_state.get("karts", []))
	_draw_speed_fx(canvas, model, player, reduced_fx)
	_draw_cockpit(canvas, player, model)
	_draw_hud(canvas, font, player, model, message)
	if show_countdown:
		var word := "LOS!" if countdown == 0 else str(countdown)
		_text(canvas, font, word, 0, 105, 34, C_AMBER if countdown == 0 else C_WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, 320, 3, C_BLACK)


func draw_minimap(canvas: CanvasItem, rect: Rect2, model: RefCounted) -> void:
	canvas.draw_rect(rect, Color8(12, 17, 22))
	var points := PackedVector2Array()
	for i in 81:
		var p: Vector2 = model.track_point(float(i) / 80.0)
		var normalized := Vector2((p.x - 32.0) / 256.0, (p.y - 25.0) / 160.0)
		points.append(rect.position + normalized * rect.size)
	canvas.draw_polyline(points, C_EDGE, 4.0, false)
	canvas.draw_polyline(points, C_WHITE, 1.5, false)
	if not points.is_empty():
		canvas.draw_circle(points[0], 2.0, C_AMBER)
	canvas.draw_rect(rect, Color8(55, 70, 80), false, 1.0)


func _draw_sky(canvas: CanvasItem, model: RefCounted, player: Dictionary,
		reduced_fx: bool, video_profile: Dictionary = {}) -> void:
	# Copper-artiger Verlauf in kleinen Farbbändern: authentisch zur Amiga-
	# Palette, aber ohne die drei groben Vollflächen der alten Fassung.
	var aga := str(video_profile.get("name", "ECS")) == "AGA"
	var copper_step := 1 if aga else 3
	for y in range(0, 73, copper_step):
		var ratio := float(y) / 72.0
		var color := C_SKY_TOP.lerp(Color8(91, 78, 101), ratio / 0.72) \
			if ratio < 0.72 else Color8(91, 78, 101).lerp(C_SKY_LOW, (ratio - 0.72) / 0.28)
		if not aga:
			color = Color(roundf(color.r * 15.0) / 15.0,
				roundf(color.g * 15.0) / 15.0,
				roundf(color.b * 15.0) / 15.0)
		canvas.draw_rect(Rect2(0, y, 320, copper_step), color)
	var progress := float(player.get("progress", 0.0))
	var target_view_angle: float = Vector2(model.track_tangent(progress)).angle() \
		+ clampf(float(player.get("heading_error", 0.0)), -0.72, 0.72)
	var view_angle := _continuous_panorama_heading(target_view_angle)
	# Die Sonne besitzt eine feste Weltposition. Beim Lenken wandert sie langsam
	# durchs Panorama statt wie ein HUD-Symbol an derselben Stelle zu kleben.
	var panorama_x := view_angle / TAU * 640.0
	var sun_x := fposmod(252.0 - panorama_x + 160.0, 640.0) - 160.0
	if sun_x > -14.0 and sun_x < 334.0:
		canvas.draw_circle(Vector2(sun_x, 36), 12.0, Color8(242, 178, 90))
		canvas.draw_circle(Vector2(sun_x, 36), 8.0, Color8(255, 215, 133))
	if not reduced_fx:
		for i in 18:
			var x := fposmod(float(i * 47) - panorama_x * 0.34, 320.0)
			var y := 12.0 + float((i * 19) % 45)
			canvas.draw_rect(Rect2(x, y, 1, 1), Color(0.9, 0.82, 0.68, 0.55))
	# Zwei komplett innerhalb des 320px-Rasters erzeugte Bergketten: keine
	# uebergrossen Dreiecke, keine offenen Naehte und echtes Richtungs-Parallax.
	var mountain_phase := view_angle / TAU * 320.0
	_draw_mountain_ridge(canvas, 73.0, mountain_phase * 0.34 + 7.0, 12.0, 160.0, 56.0,
		Color8(83, 72, 82))
	_draw_mountain_ridge(canvas, 74.0, mountain_phase * 0.62 + 31.0, 22.0, 128.0, 48.0,
		Color8(55, 58, 72))
	_draw_mountain_ridge(canvas, 76.0, mountain_phase + 19.0, 32.0, 192.0, 72.0,
		Color8(35, 40, 54))
	if aga:
		# AGA-Erweiterung: ein vierter, feiner Fernlayer und Wolkenschatten.
		# Die Streckenprojektion bleibt identisch, daher bleiben Replays und
		# Fahrphysik generationenuebergreifend deterministisch.
		_draw_mountain_ridge(canvas, 72.0, mountain_phase * 0.18 + 83.0, 7.0,
			224.0, 91.0, Color8(112, 86, 101))
		for cloud in 5:
			var cloud_x := fposmod(float(cloud * 83) - mountain_phase * 0.22, 390.0) - 35.0
			var cloud_y := 18.0 + float((cloud * 13) % 21)
			canvas.draw_rect(Rect2(roundf(cloud_x), cloud_y, 17, 2),
				Color(0.73, 0.69, 0.72, 0.20))
			canvas.draw_rect(Rect2(roundf(cloud_x + 4), cloud_y - 2, 9, 2),
				Color(0.79, 0.75, 0.77, 0.16))
	_draw_horizon_scenery(canvas, model.track_id, mountain_phase)
	canvas.draw_rect(Rect2(0, 72, 320, 98), _ground_color(model.track_id))
	canvas.draw_line(Vector2(0, 72), Vector2(320, 72), Color(0.78, 0.56, 0.36, 0.45), 1.0, false)


func _continuous_panorama_heading(target: float) -> float:
	if not _panorama_ready:
		_panorama_heading = target
		_panorama_ready = true
		return _panorama_heading
	var wrapped_current := wrapf(_panorama_heading, -PI, PI)
	_panorama_heading += wrapf(target - wrapped_current, -PI, PI)
	return _panorama_heading


func _draw_mountain_ridge(canvas: CanvasItem, base_y: float, phase: float,
		amplitude: float, primary_period: float, secondary_period: float, color: Color) -> void:
	canvas.draw_colored_polygon(_mountain_ridge_points(base_y, phase, amplitude,
		primary_period, secondary_period), color)


func _mountain_ridge_points(base_y: float, phase: float, amplitude: float,
		primary_period: float, secondary_period: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2(0, 72)])
	for x in range(0, 321, 2):
		var primary := _triangle_wave((float(x) + phase) / primary_period)
		var secondary := _triangle_wave((float(x) + phase * 0.63 + 17.0) / secondary_period)
		var tertiary := _triangle_wave((float(x) - phase * 0.27 + 43.0) \
			/ maxf(18.0, secondary_period * 0.47))
		var ridge := pow(clampf(primary * 0.68 + secondary * 0.24 + tertiary * 0.08,
			0.0, 1.0), 1.28)
		# Die eigentliche Kontur muss mindestens ein Pixel OBERHALB der unteren
		# Abschlusskante liegen. Lag sie ebenfalls auf y=72, beruehrte das Polygon
		# sich ueber lange Strecken selbst; Godot konnte es dann nicht triangulieren
		# und schrieb bei jedem Frame einen Rendererfehler ins Log.
		points.append(Vector2(float(x), minf(71.0, roundf(base_y - amplitude * ridge))))
	points.append(Vector2(320, 72))
	return points


func _triangle_wave(value: float) -> float:
	var phase := fposmod(value, 1.0)
	return 1.0 - absf(phase * 2.0 - 1.0)


func _draw_horizon_scenery(canvas: CanvasItem, track_id: String, phase: float) -> void:
	match track_id:
		"freight":
			for i in 13:
				var x := fposmod(float(i * 31) - phase * 0.74, 348.0) - 14.0
				var h := 4.0 + float((i * 7) % 9)
				canvas.draw_rect(Rect2(roundf(x), 72.0 - h, 8.0 + float(i % 3) * 3.0, h),
					Color8(28, 34, 39))
				if i % 4 == 0:
					canvas.draw_line(Vector2(x + 4, 72 - h), Vector2(x + 11, 51),
						Color8(35, 41, 45), 1.0, false)
		"gravel":
			for i in 8:
				var x := fposmod(float(i * 49) - phase * 0.58, 366.0) - 23.0
				var top := 61.0 + float((i * 11) % 7)
				canvas.draw_colored_polygon(PackedVector2Array([
					Vector2(x, 72), Vector2(x + 5, top), Vector2(x + 22, top - 2),
					Vector2(x + 28, 72)]), Color8(73, 52, 46))
		_:
			# Kleine, unterschiedlich hohe Tannen geben dem Parkplatzkurs Tiefe,
			# ohne die Fahrbahn am Horizont zu verdecken.
			for i in 18:
				var x := fposmod(float(i * 23) - phase * 0.82, 342.0) - 11.0
				var h := 3.0 + float((i * 5) % 6)
				canvas.draw_colored_polygon(PackedVector2Array([
					Vector2(x, 72), Vector2(x + 3, 72 - h), Vector2(x + 6, 72)]),
					Color8(30, 46, 42))


func _road_slices(model: RefCounted, player: Dictionary) -> Array[Dictionary]:
	var slices: Array[Dictionary] = []
	var progress := float(player.get("progress", 0.0))
	var player_tangent: Vector2 = model.track_tangent(progress)
	var player_angle := player_tangent.angle()
	var player_point: Vector2 = model.track_point(progress)
	var player_normal := Vector2(-player_tangent.y, player_tangent.x)
	var heading_error := clampf(float(player.get("heading_error", 0.0)), -0.72, 0.72)
	var player_height := float(model.track_height(progress))
	var lateral := float(player.get("lateral", 0.0))
	var road_half_width := maxf(1.0, float(model.road_half_width()))
	var visible_ahead := _curve_limited_ahead(model, progress, _visible_ahead(model))
	var previous_y := ROAD_BOTTOM_Y + 1.0
	var smoothed_elevation := 0.0
	var centers: Array[float] = []
	for i in SEGMENTS:
		var depth := float(i) / float(SEGMENTS - 1)
		var ahead := lerpf(0.0012, visible_ahead, pow(depth, 1.24))
		var sample_progress := progress + ahead
		var tangent: Vector2 = model.track_tangent(sample_progress)
		var angle_delta := wrapf(tangent.angle() - player_angle, -PI, PI)
		var sample_point: Vector2 = model.track_point(sample_progress)
		var path_delta := sample_point - player_point
		var forward_distance := path_delta.dot(player_tangent)
		var side_distance := path_delta.dot(player_normal)
		# Die Blickrichtung zum tatsaechlichen Streckenpunkt ist wesentlich
		# kontinuierlicher als ein direkt projizierter 90-Grad-Kachelwinkel. Der
		# Tangentenanteil laesst kommende Kurven trotzdem frueh lesbar werden.
		var chord_angle := atan2(side_distance, maxf(2.0, forward_distance))
		var projected_angle := lerpf(chord_angle, angle_delta * 0.52, 0.30)
		projected_angle = clampf(projected_angle, -1.04, 1.04)
		var perspective := pow(1.0 - depth, 1.12)
		var width := ROAD_FAR_HALF_WIDTH + perspective \
			* (ROAD_NEAR_HALF_WIDTH - ROAD_FAR_HALF_WIDTH)
		var curve_shift := clampf(tan(projected_angle) * 76.0, -148.0, 148.0)
		var heading_shift := -heading_error * (28.0 + pow(depth, 0.74) * 58.0)
		var lateral_shift := -lateral / road_half_width * width
		var target_center := 160.0 + curve_shift + heading_shift + lateral_shift
		target_center = clampf(target_center, -width + 8.0, 320.0 + width - 8.0)
		centers.append(target_center)
		var sample: Dictionary = model.track_sample(sample_progress)
		var height_delta: float = float(model.track_height(sample_progress)) - player_height
		var piece := int(sample.get("piece", Track.Piece.STRAIGHT))
		var piece_local := float(sample.get("local", 0.5))
		# Looping und Korkenzieher besitzen eigene Vordergrundstrukturen; ihre volle
		# 3D-Hoehe darf das darunterliegende Strassenband nicht zurueckfalten.
		if piece in [Track.Piece.LOOP, Track.Piece.CORKSCREW]:
			height_delta = clampf(height_delta, -1.5, 1.5)
		var elevation_target := clampf(height_delta * lerpf(2.35, 1.15, depth), -11.0, 12.0)
		smoothed_elevation = lerpf(smoothed_elevation, elevation_target, 0.30)
		var y: float = HORIZON_Y + pow(1.0 - depth, 1.56) \
			* (ROAD_BOTTOM_Y - HORIZON_Y) - smoothed_elevation
		# Harte Produktionsinvariante: Eine weiter entfernte Scheibe darf niemals
		# unter/ueber die vorherige springen. Sonst kreuzen sich die Fahrbahnquads.
		if i > 0:
			y = minf(y, previous_y - 0.10)
		y = maxf(HORIZON_Y - 2.0, y)
		slices.append({
			"x": target_center, "y": y, "w": width, "depth": depth,
			"progress": sample_progress, "piece": piece, "piece_local": piece_local,
			"roll": model.track_roll(sample_progress), "height": model.track_height(sample_progress),
			"meter": fposmod(sample_progress, 1.0) * float(model.drive_length()),
			"world_meter": sample_progress * float(model.drive_length()),
		})
		previous_y = y
	# Zwei symmetrische Tiefpassdurchlaeufe entfernen Kachelknicke, ohne die
	# Richtung der Kurve zu veraendern. Anschliessend begrenzt eine geometrische
	# Kontinuitaetsregel die seitliche Bewegung je Scheibe. Dadurch koennen sich
	# weder Fahrbahn noch Randstreifen kreuzen oder zaehnchenartig zurueckfalten.
	for _pass in 2:
		var filtered := centers.duplicate()
		for i in range(1, centers.size() - 1):
			filtered[i] = centers[i - 1] * 0.22 + centers[i] * 0.56 + centers[i + 1] * 0.22
		centers = filtered
	for i in centers.size():
		if i > 0:
			var max_step := lerpf(2.8, 4.4, float(i) / float(centers.size() - 1))
			centers[i] = clampf(centers[i], centers[i - 1] - max_step, centers[i - 1] + max_step)
		slices[i]["x"] = centers[i]
	return slices


func _curve_limited_ahead(model: RefCounted, progress: float, desired: float) -> float:
	# Ein Pseudo-3D-Band kann eine hinter der Kamera liegende Haarnadel nicht
	# sinnvoll zeigen. Statt sie als Haken ueber die eigene Fahrbahn zu falten,
	# endet die Sichtweite kurz vor etwa 65 Grad Richtungswechsel am Horizont.
	var origin_tangent: Vector2 = model.track_tangent(progress)
	var origin_angle := origin_tangent.angle()
	var origin_point: Vector2 = model.track_point(progress)
	var safe := desired
	const STEPS := 56
	var previous_ahead := 0.0
	var previous_delta := 0.0
	var previous_forward := 9999.0
	for step in range(1, STEPS + 1):
		var ahead := desired * float(step) / float(STEPS)
		var tangent_delta: float = absf(wrapf(Vector2(model.track_tangent(progress + ahead)).angle()
			- origin_angle, -PI, PI))
		var sample_point: Vector2 = model.track_point(progress + ahead)
		var forward: float = (sample_point - origin_point).dot(origin_tangent)
		if tangent_delta > 1.12 or (step > 8 and forward < 1.0):
			# Nicht auf die diskrete Scan-Stufe springen: Den exakten
			# Schwellwert zwischen den letzten beiden Proben interpolieren. Das
			# entfernt das letzte sichtbare Zittern am fernen Horizont vor einer
			# Haarnadel.
			var crossing := ahead
			if tangent_delta > 1.12 and tangent_delta > previous_delta + 0.00001:
				crossing = lerpf(previous_ahead, ahead,
					clampf(inverse_lerp(previous_delta, tangent_delta, 1.12), 0.0, 1.0))
			if step > 8 and forward < 1.0 and previous_forward > forward + 0.00001:
				var forward_crossing := lerpf(previous_ahead, ahead,
					clampf(inverse_lerp(previous_forward, forward, 1.0), 0.0, 1.0))
				crossing = minf(crossing, forward_crossing)
			safe = maxf(desired * 0.30, crossing - desired / float(STEPS) * 0.18)
			break
		previous_ahead = ahead
		previous_delta = tangent_delta
		previous_forward = forward
	return safe


func _visible_ahead(model: RefCounted) -> float:
	return clampf(VIEW_DISTANCE_METERS / maxf(1.0, float(model.drive_length())),
		MIN_AHEAD, MAX_AHEAD)


func _draw_ground_details(canvas: CanvasItem, slices: Array[Dictionary], model: RefCounted,
		player: Dictionary) -> void:
	var progress := float(player.get("progress", 0.0))
	var stripe_phase := fposmod(progress * float(model.drive_length()) / 8.0, 1.0)
	for i in 18:
		var depth := fposmod((float(i) + stripe_phase) / 18.0, 1.0)
		var y := 73.0 + pow(depth, 1.7) * 96.0
		var alpha := 0.055 + depth * 0.12
		canvas.draw_line(Vector2(0, y), Vector2(320, y), Color(0.8, 0.72, 0.49, alpha), 1.0, false)
	_draw_roadside_scenery(canvas, slices, str(model.track_id))
	_draw_roadside_posts(canvas, slices)


func _draw_roadside_scenery(canvas: CanvasItem, slices: Array[Dictionary],
		track_id: String) -> void:
	# Wenige markante Silhouetten geben Geschwindigkeit und Tiefenstaffelung.
	# Ihre Position haengt ausschliesslich vom Streckenmeter ab: kein zufaelliges
	# Neu-Wuerfeln pro Frame und damit kein Flimmern am Fahrbahnrand.
	if slices.size() < 2:
		return
	const SPACING := 31.0
	for i in range(slices.size() - 1, 0, -1):
		var near: Dictionary = slices[i - 1]
		var far: Dictionary = slices[i]
		var near_meter := float(near.get("world_meter", 0.0))
		var far_meter := float(far.get("world_meter", near_meter))
		var marker := ceilf(near_meter / SPACING) * SPACING
		if marker <= near_meter + 0.001:
			marker += SPACING
		if marker > far_meter:
			continue
		var weight := inverse_lerp(near_meter, far_meter, marker)
		var center_x := lerpf(float(near["x"]), float(far["x"]), weight)
		var half_width := lerpf(float(near["w"]), float(far["w"]), weight)
		var y := lerpf(float(near["y"]), float(far["y"]), weight)
		var depth := lerpf(float(near["depth"]), float(far["depth"]), weight)
		var marker_id := floori(marker / SPACING)
		var side := -1.0 if _surface_noise(marker_id * 5 + 2) < 0.5 else 1.0
		var scale := clampf((1.0 - depth) * 10.5, 0.65, 10.5)
		var offset := half_width + 6.0 + scale * lerpf(0.35, 1.05,
			_surface_noise(marker_id * 5 + 3))
		_draw_scenery_object(canvas, Vector2(center_x + side * offset, y), scale,
			track_id, marker_id)


func _draw_scenery_object(canvas: CanvasItem, base: Vector2, scale: float,
		track_id: String, marker_id: int) -> void:
	match track_id:
		"freight":
			if marker_id % 3 == 0:
				# Schmale Natriumdampf-Leuchte; die Lampe bleibt ein einzelnes
				# helles Pixel in der Ferne und waechst sauber mit der Perspektive.
				canvas.draw_rect(Rect2(roundf(base.x), roundf(base.y - scale * 2.8),
					maxf(1.0, floorf(scale * 0.16)), scale * 2.8), Color8(42, 46, 47))
				canvas.draw_rect(Rect2(roundf(base.x - scale * 0.45),
					roundf(base.y - scale * 3.0), maxf(1.0, scale * 0.9),
					maxf(1.0, scale * 0.28)), Color8(236, 174, 72))
			else:
				var box_color := Color8(125, 68, 45) if marker_id % 2 == 0 \
					else Color8(54, 83, 91)
				canvas.draw_rect(Rect2(roundf(base.x - scale * 0.75),
					roundf(base.y - scale * 1.15), scale * 1.5, scale * 1.15), box_color)
				canvas.draw_rect(Rect2(roundf(base.x - scale * 0.75),
					roundf(base.y - scale * 1.15), scale * 1.5, scale * 1.15),
					Color8(32, 38, 42), false, maxf(1.0, scale * 0.12))
		"gravel":
			var rock := Color8(86, 67, 61) if marker_id % 2 == 0 else Color8(110, 81, 66)
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(base.x - scale, base.y),
				Vector2(base.x - scale * 0.58, base.y - scale * 0.72),
				Vector2(base.x + scale * 0.18, base.y - scale),
				Vector2(base.x + scale, base.y - scale * 0.24),
				Vector2(base.x + scale * 0.72, base.y),
			]), rock)
		_:
			# Dreistufige Tanne mit eigenem Stamm – als klare, handgesetzte
			# Polygon-Silhouette statt eines zufaellig skalierten Kreises.
			canvas.draw_rect(Rect2(roundf(base.x - scale * 0.11),
				roundf(base.y - scale * 1.15), maxf(1.0, scale * 0.22), scale * 1.15),
				Color8(67, 48, 37))
			for tier in 3:
				var tier_y := base.y - scale * (0.58 + float(tier) * 0.52)
				var tier_w := scale * (0.88 - float(tier) * 0.14)
				canvas.draw_colored_polygon(PackedVector2Array([
					Vector2(base.x - tier_w, tier_y),
					Vector2(base.x, tier_y - scale * 0.96),
					Vector2(base.x + tier_w, tier_y),
				]), Color8(30 + tier * 5, 60 + tier * 7, 48 + tier * 4))


func _draw_roadside_posts(canvas: CanvasItem, slices: Array[Dictionary]) -> void:
	if slices.size() < 2:
		return
	const SPACING := 13.0
	for i in range(1, slices.size()):
		var near: Dictionary = slices[i - 1]
		var far: Dictionary = slices[i]
		var near_meter := float(near.get("world_meter", 0.0))
		var far_meter := float(far.get("world_meter", near_meter))
		var boundary := ceilf(near_meter / SPACING) * SPACING
		if boundary <= near_meter + 0.001:
			boundary += SPACING
		if boundary > far_meter:
			continue
		var weight := inverse_lerp(near_meter, far_meter, boundary)
		var x_center := lerpf(float(near["x"]), float(far["x"]), weight)
		var half_width := lerpf(float(near["w"]), float(far["w"]), weight)
		var y := lerpf(float(near["y"]), float(far["y"]), weight)
		var depth := lerpf(float(near["depth"]), float(far["depth"]), weight)
		var scale := maxf(1.0, (1.0 - depth) * 8.0)
		for side in [-1.0, 1.0]:
			var x := x_center + float(side) * (half_width + 7.0)
			canvas.draw_rect(Rect2(roundf(x - scale * 0.25), roundf(y - scale),
				maxf(1.0, floorf(scale * 0.5)), scale), C_WHITE)
			canvas.draw_rect(Rect2(roundf(x - scale * 0.25), roundf(y - scale * 0.65),
				maxf(1.0, floorf(scale * 0.5)), maxf(1.0, floorf(scale * 0.22))), C_RED)


func _draw_road(canvas: CanvasItem, slices: Array[Dictionary]) -> void:
	# Pass 1: ein zusammenhaengender Unterbau. Frueher wurde pro Scheibe erst
	# schwarzer Rand und dann Asphalt gezeichnet; der Rand der naechsten Scheibe
	# uebermalte dabei den Asphalt der vorigen und erzeugte die sichtbaren Zaehne.
	for i in range(slices.size() - 1, 0, -1):
		var far: Dictionary = slices[i]
		var near: Dictionary = slices[i - 1]
		var far_x := float(far["x"])
		var near_x := float(near["x"])
		var far_y := float(far["y"])
		var near_y := float(near["y"])
		var far_w := float(far["w"])
		var near_w := float(near["w"])
		var far_extra := maxf(1.2, far_w * 0.035)
		var near_extra := maxf(1.5, near_w * 0.035)
		var shoulder := PackedVector2Array([
			Vector2(far_x - far_w - far_extra, far_y),
			Vector2(far_x + far_w + far_extra, far_y),
			Vector2(near_x + near_w + near_extra, near_y),
			Vector2(near_x - near_w - near_extra, near_y),
		])
		canvas.draw_colored_polygon(shoulder, C_EDGE)
	# Pass 2: Asphalt liegt geschlossen ueber dem gesamten Unterbau.
	for i in range(slices.size() - 1, 0, -1):
		var far: Dictionary = slices[i]
		var near: Dictionary = slices[i - 1]
		var far_x := float(far["x"])
		var near_x := float(near["x"])
		var far_y := float(far["y"])
		var near_y := float(near["y"])
		var far_w := float(far["w"])
		var near_w := float(near["w"])
		var piece := int(near["piece"])
		var stripe_index := floori(float(near.get("meter", 0.0)) / 12.0)
		var local := float(near.get("piece_local", 0.5))
		var road_color := _road_color(piece, stripe_index, local) \
			.darkened(float(far["depth"]) * 0.035)
		var road := PackedVector2Array([
			Vector2(far_x - far_w, far_y), Vector2(far_x + far_w, far_y),
			Vector2(near_x + near_w, near_y), Vector2(near_x - near_w, near_y),
		])
		canvas.draw_colored_polygon(road, road_color)
	_draw_surface_details(canvas, slices)
	# Pass 3: Randsteine und Mittellinie bleiben ueber dem Asphalt, ohne ihn mit
	# spaeteren Unterbau-Polygonen wieder zu zerreissen.
	for i in range(slices.size() - 1, 0, -1):
		var far: Dictionary = slices[i]
		var near: Dictionary = slices[i - 1]
		var far_x := float(far["x"])
		var near_x := float(near["x"])
		var far_y := float(far["y"])
		var near_y := float(near["y"])
		var far_w := float(far["w"])
		var near_w := float(near["w"])
		var piece := int(near["piece"])
		var stripe_index := floori(float(near.get("meter", 0.0)) / 7.0)
		for side in [-1.0, 1.0]:
			var far_curb := maxf(0.75, far_w * 0.022)
			var near_curb := maxf(0.9, near_w * 0.022)
			var curb := PackedVector2Array([
				Vector2(far_x + float(side) * far_w, far_y),
				Vector2(far_x + float(side) * (far_w + far_curb), far_y),
				Vector2(near_x + float(side) * (near_w + near_curb), near_y),
				Vector2(near_x + float(side) * near_w, near_y),
			])
			canvas.draw_colored_polygon(curb, C_WHITE if stripe_index % 2 == 0 else C_RED)
		var dash_index := floori(float(near.get("meter", 0.0)) / 5.0)
		if dash_index % 4 < 2 and piece not in [Track.Piece.DIRT, Track.Piece.ICE]:
			var lane_far := maxf(1.0, far_w * 0.018)
			var lane_near := maxf(1.0, near_w * 0.018)
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(far_x - lane_far, far_y), Vector2(far_x + lane_far, far_y),
				Vector2(near_x + lane_near, near_y), Vector2(near_x - lane_near, near_y),
			]), Color(0.94, 0.85, 0.65, 0.76))


func _draw_surface_details(canvas: CanvasItem, slices: Array[Dictionary]) -> void:
	# Weltkoordinaten statt Framezeit: Splitt, Eisschlieren und Asphaltflicken
	# bleiben auf der Fahrbahn liegen und koennen deshalb niemals flimmern oder
	# rueckwaerts wandern. Die eigentliche Materialfarbe bleibt bewusst dunkel;
	# erst diese feinen Details vermitteln Eis oder losen Untergrund.
	if slices.size() < 2:
		return
	for i in range(slices.size() - 1, 0, -1):
		var far: Dictionary = slices[i]
		var near: Dictionary = slices[i - 1]
		var near_meter := float(near.get("world_meter", 0.0))
		var far_meter := float(far.get("world_meter", near_meter))
		if far_meter <= near_meter:
			continue
		var piece := int(near.get("piece", Track.Piece.STRAIGHT))
		var spacing := 9.0
		if piece == Track.Piece.ICE:
			spacing = 2.8
		elif piece == Track.Piece.DIRT:
			spacing = 2.2
		var marker := ceilf(near_meter / spacing) * spacing
		if marker <= near_meter + 0.001:
			marker += spacing
		while marker <= far_meter + 0.001:
			var weight := inverse_lerp(near_meter, far_meter, marker)
			var x_center := lerpf(float(near["x"]), float(far["x"]), weight)
			var half_width := lerpf(float(near["w"]), float(far["w"]), weight)
			var y := lerpf(float(near["y"]), float(far["y"]), weight)
			var depth := lerpf(float(near["depth"]), float(far["depth"]), weight)
			var marker_id := floori(marker / spacing)
			var visibility := clampf((1.0 - depth) * 1.7, 0.0, 1.0)
			if piece == Track.Piece.ICE:
				_draw_ice_mark(canvas, x_center, y, half_width, marker_id, visibility)
			elif piece == Track.Piece.DIRT:
				_draw_gravel_mark(canvas, x_center, y, half_width, marker_id, visibility)
			elif marker_id % 3 == 0:
				_draw_asphalt_mark(canvas, x_center, y, half_width, marker_id, visibility)
			marker += spacing


func _draw_ice_mark(canvas: CanvasItem, center_x: float, y: float, half_width: float,
		marker_id: int, visibility: float) -> void:
	if visibility < 0.10:
		return
	var offset := lerpf(-0.72, 0.72, _surface_noise(marker_id * 3 + 1)) * half_width
	var length := maxf(1.0, half_width * lerpf(0.10, 0.25,
		_surface_noise(marker_id * 3 + 2)))
	var rise := maxf(1.0, visibility * 2.2)
	var start := Vector2(center_x + offset - length * 0.45, y + rise * 0.35)
	var finish := Vector2(center_x + offset + length * 0.55, y - rise)
	canvas.draw_line(start, finish, Color(0.58, 0.88, 0.94, 0.23 + visibility * 0.34),
		1.0, false)
	if visibility > 0.46 and marker_id % 2 == 0:
		canvas.draw_line(start.lerp(finish, 0.48),
			start.lerp(finish, 0.48) + Vector2(-length * 0.20, -rise * 0.65),
			Color(0.76, 0.94, 0.96, 0.18 + visibility * 0.25), 1.0, false)


func _draw_gravel_mark(canvas: CanvasItem, center_x: float, y: float, half_width: float,
		marker_id: int, visibility: float) -> void:
	if visibility < 0.12:
		return
	var count := 1 + int(visibility > 0.42) + int(visibility > 0.72)
	for pebble in count:
		var visual_seed := marker_id * 7 + pebble * 13
		var offset := lerpf(-0.78, 0.78, _surface_noise(visual_seed + 1)) * half_width
		var size := maxf(1.0, floorf(visibility * lerpf(1.2, 2.5,
			_surface_noise(visual_seed + 2))))
		var color := Color(0.78, 0.57, 0.39, 0.30 + visibility * 0.42) \
			if visual_seed % 2 == 0 else Color(0.31, 0.23, 0.19, 0.38 + visibility * 0.34)
		canvas.draw_rect(Rect2(roundf(center_x + offset), roundf(y - size), size,
			maxf(1.0, floorf(size * 0.55))), color)


func _draw_asphalt_mark(canvas: CanvasItem, center_x: float, y: float, half_width: float,
		marker_id: int, visibility: float) -> void:
	if visibility < 0.42:
		return
	var offset := lerpf(-0.62, 0.62, _surface_noise(marker_id + 17)) * half_width
	var length := maxf(2.0, half_width * 0.09)
	canvas.draw_line(Vector2(center_x + offset - length, y),
		Vector2(center_x + offset + length, y - visibility),
		Color(0.08, 0.09, 0.10, visibility * 0.24), 1.0, false)


func _surface_noise(index: int) -> float:
	return fposmod(sin(float(index) * 12.9898 + 78.233) * 43758.5453, 1.0)


func _draw_stunt_structures(canvas: CanvasItem, slices: Array[Dictionary]) -> void:
	var previous_piece := -1
	for i in range(slices.size() - 2, 2, -1):
		var slice: Dictionary = slices[i]
		var piece := int(slice["piece"])
		if piece == previous_piece:
			continue
		previous_piece = piece
		var x := float(slice["x"])
		var y := float(slice["y"])
		var w := float(slice["w"])
		var depth := float(slice["depth"])
		if depth < 0.12 or y > 148.0:
			continue
		var scale := clampf(w / 50.0, 0.12, 1.65)
		match piece:
			Track.Piece.RAMP:
				canvas.draw_colored_polygon(PackedVector2Array([
					Vector2(x - w * 0.55, y), Vector2(x + w * 0.55, y),
					Vector2(x + w * 0.34, y - 5 * scale), Vector2(x - w * 0.34, y - 5 * scale),
				]), Color8(126, 105, 74))
				canvas.draw_line(Vector2(x - w * 0.25, y - 2 * scale),
					Vector2(x + w * 0.25, y - 2 * scale), C_AMBER, maxf(1.0, scale), false)
			Track.Piece.LOOP:
				var radius := clampf(w * 0.62, 4.0, 48.0)
				canvas.draw_arc(Vector2(x, y - radius * 0.78), radius, PI * 0.04, PI * 1.96,
					28, C_EDGE, maxf(2.0, scale * 4.0), false)
				canvas.draw_arc(Vector2(x, y - radius * 0.78), radius, PI * 0.04, PI * 1.96,
					28, C_CREAM, maxf(1.0, scale * 1.5), false)
			Track.Piece.TUNNEL:
				var height := clampf(w * 0.48, 5.0, 36.0)
				var outer_width := w * 1.72
				var pillar := clampf(w * 0.13, 2.0, 9.0)
				var beam := clampf(height * 0.18, 2.0, 7.0)
				canvas.draw_rect(Rect2(x - outer_width * 0.5, y - height, pillar, height), C_EDGE)
				canvas.draw_rect(Rect2(x + outer_width * 0.5 - pillar, y - height, pillar, height), C_EDGE)
				canvas.draw_rect(Rect2(x - outer_width * 0.5, y - height, outer_width, beam), C_EDGE)
				canvas.draw_rect(Rect2(x - outer_width * 0.5, y - height, outer_width, height),
					Color8(89, 93, 94), false, maxf(1.0, scale))
				canvas.draw_line(Vector2(x - w * 0.72, y - height), Vector2(x + w * 0.72, y - height),
					C_CYAN, maxf(1.0, scale), false)
			Track.Piece.BRIDGE:
				for side in [-1.0, 1.0]:
					var bx := x + float(side) * w * 0.92
					canvas.draw_line(Vector2(bx, y), Vector2(bx, y - 10 * scale), C_CREAM,
						maxf(1.0, scale), false)
			Track.Piece.BANK:
				canvas.draw_line(Vector2(x - w, y + 2 * scale), Vector2(x + w, y - 3 * scale),
					C_ORANGE, maxf(1.0, scale), false)
			Track.Piece.CORKSCREW:
				var radius := maxf(3.0, w * 0.65)
				canvas.draw_arc(Vector2(x, y - radius * 0.45), radius, 0, TAU, 20,
					C_CYAN, maxf(1.0, scale * 1.8), false)


func _draw_opponents(canvas: CanvasItem, model: RefCounted, player: Dictionary,
		slices: Array[Dictionary], visual_karts: Array = []) -> void:
	var player_progress := float(player.get("progress", 0.0))
	var visible_ahead := _visible_ahead(model)
	var opponents: Array[Dictionary] = []
	var kart_states: Array = visual_karts if not visual_karts.is_empty() else model.kart_states()
	for raw_kart: Variant in kart_states:
		var kart: Dictionary = raw_kart
		if bool(kart.get("player", false)):
			continue
		var gap := float(kart.get("progress", 0.0)) - player_progress
		if gap <= 0.002 or gap >= visible_ahead:
			continue
		var index := _slice_for_gap(gap, slices, player_progress)
		if index < 0:
			continue
		var slice: Dictionary = slices[index]
		opponents.append({"kart": kart, "slice": slice, "depth": float(slice["depth"])})
	opponents.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["depth"]) > float(b["depth"]))
	for entry: Dictionary in opponents:
		var kart: Dictionary = entry["kart"]
		var slice: Dictionary = entry["slice"]
		var w := float(slice["w"])
		var scale := clampf(w / 45.0, 0.18, 2.8)
		var lane_offset := float(kart.get("lateral", 0.0)) * w / maxf(8.0, model.road_half_width())
		var pos := Vector2(float(slice["x"]) + lane_offset, float(slice["y"]) - scale * 2.0)
		_draw_car(canvas, pos, scale, _kart_color(str(kart.get("color", "red"))))


func _draw_car(canvas: CanvasItem, pos: Vector2, scale: float, color: Color) -> void:
	var w := maxf(2.0, 6.0 * scale)
	var h := maxf(2.0, 4.0 * scale)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x - w, pos.y), Vector2(pos.x - w * 0.72, pos.y - h),
		Vector2(pos.x + w * 0.72, pos.y - h), Vector2(pos.x + w, pos.y),
	]), color)
	canvas.draw_rect(Rect2(pos.x - w * 0.45, pos.y - h * 0.82, w * 0.9, maxf(1.0, h * 0.32)), C_BLACK)
	canvas.draw_rect(Rect2(pos.x - w * 0.83, pos.y - 1, maxf(1.0, scale), maxf(1.0, scale)), C_RED)
	canvas.draw_rect(Rect2(pos.x + w * 0.55, pos.y - 1, maxf(1.0, scale), maxf(1.0, scale)), C_RED)


func _draw_speed_fx(canvas: CanvasItem, model: RefCounted, player: Dictionary,
		reduced_fx: bool) -> void:
	if reduced_fx:
		return
	var speed := float(player.get("speed", 0.0))
	if speed < 32.0:
		return
	# Weltgebundene 50-Hz-Phasen statt framezufaelligem Partikelsystem: Die
	# Fahrbahn bewegt sich schnell, aber jeder Splitter bleibt pixelstabil.
	var tick := int(model.get("ticks"))
	var intensity := clampi(floori(speed / 22.0), 1, 5)
	for i in intensity * 3:
		var particle_key := i * 37 + floori(float(tick) / 2.0)
		var side := -1.0 if particle_key % 2 == 0 else 1.0
		var depth := fposmod(float(particle_key * 13), 97.0) / 97.0
		var y := 78.0 + pow(depth, 1.7) * 78.0
		var x := 160.0 + side * lerpf(23.0, 151.0, depth)
		var length := 1.0 + floorf(depth * 5.0)
		canvas.draw_line(Vector2(roundf(x), roundf(y)),
			Vector2(roundf(x + side * length), roundf(y + length * 0.35)),
			Color(0.84, 0.80, 0.66, 0.18 + depth * 0.28), 1.0, false)
	if bool(player.get("offroad", false)):
		var dust_side := 1.0 if float(player.get("lateral", 0.0)) > 0.0 else -1.0
		for i in 9:
			var age := fposmod(float(tick + i * 7), 26.0) / 26.0
			var px := 160.0 + dust_side * (102.0 + age * 42.0) + float((i * 5) % 9)
			var py := 154.0 - age * 19.0 + float(i % 3)
			var size := 1.0 + floorf(age * 2.0)
			canvas.draw_rect(Rect2(roundf(px), roundf(py), size, size),
				Color(0.64, 0.47, 0.31, 0.54 - age * 0.31))
	if bool(player.get("boosting", false)):
		for i in 4:
			var x := 126.0 + i * 23.0 + float(posmod(tick + i * 3, 5))
			canvas.draw_rect(Rect2(x, 160 + i % 2, 8, 1),
				Color(0.20, 0.84, 0.95, 0.45))


func _draw_cockpit(canvas: CanvasItem, player: Dictionary, _model: RefCounted) -> void:
	# Niedrige Polygonzahl und klare Materialflaechen imitieren eine 1990er
	# Cockpitperspektive, bleiben aber bei jeder Aufloesung pixelstabil.
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(0, 170), Vector2(42, 151), Vector2(278, 151), Vector2(320, 170),
		Vector2(320, 200), Vector2(0, 200),
	]), Color8(24, 28, 35))
	# Zweite Materialebene und matte Windschutzscheiben-Reflexe nehmen der alten
	# einfarbigen Platte den Pappkarton-Look, ohne die 32-Farben-Aesthetik zu
	# verlassen.
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(0, 177), Vector2(48, 157), Vector2(272, 157), Vector2(320, 177),
		Vector2(320, 200), Vector2(0, 200),
	]), Color8(20, 24, 30))
	canvas.draw_line(Vector2(0, 170), Vector2(42, 151), Color8(92, 97, 105), 2.0, false)
	canvas.draw_line(Vector2(278, 151), Vector2(320, 170), Color8(92, 97, 105), 2.0, false)
	canvas.draw_line(Vector2(42, 151), Vector2(278, 151), Color(0.62, 0.66, 0.70, 0.38), 1.0, false)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(44, 153), Vector2(103, 153), Vector2(91, 158), Vector2(48, 158),
	]), Color(0.55, 0.65, 0.72, 0.12))
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(217, 153), Vector2(276, 153), Vector2(272, 158), Vector2(229, 158),
	]), Color(0.55, 0.65, 0.72, 0.09))
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(112, 200), Vector2(126, 167), Vector2(194, 167), Vector2(208, 200),
	]), Color8(13, 16, 21))
	canvas.draw_arc(Vector2(160, 197), 25, PI, TAU, 24, Color8(62, 58, 52), 7.0, false)
	canvas.draw_arc(Vector2(160, 197), 25, PI, TAU, 24, Color8(119, 108, 88), 3.0, false)
	var steer_angle := clampf(float(player.get("lateral_speed", 0.0)) * 0.035, -0.45, 0.45)
	var spoke := Vector2.from_angle(-PI * 0.5 + steer_angle) * 20.0
	canvas.draw_line(Vector2(160, 197), Vector2(160, 197) + spoke, Color8(122, 111, 92), 3.0, false)
	canvas.draw_line(Vector2(160, 197), Vector2(160, 197) + Vector2(-17, -7).rotated(steer_angle),
		Color8(103, 94, 79), 2.0, false)
	canvas.draw_line(Vector2(160, 197), Vector2(160, 197) + Vector2(17, -7).rotated(steer_angle),
		Color8(103, 94, 79), 2.0, false)
	canvas.draw_circle(Vector2(160, 197), 4.0, Color8(78, 72, 61))
	# Instrumente und Warnlampen.
	for x in [58.0, 82.0, 238.0, 262.0]:
		canvas.draw_circle(Vector2(x, 184), 9.0, Color8(7, 10, 13))
		canvas.draw_arc(Vector2(x, 184), 8.0, 0, TAU, 16, Color8(88, 104, 109), 1.0, false)
		for tick in 5:
			var angle := PI * 0.78 + float(tick) / 4.0 * PI * 1.44
			var tick_start := Vector2(x, 184) + Vector2.from_angle(angle) * 5.8
			var tick_end := Vector2(x, 184) + Vector2.from_angle(angle) * 7.0
			canvas.draw_line(tick_start, tick_end, Color8(166, 171, 162), 1.0, false)
	var speed_ratio := clampf(float(player.get("speed", 0.0)) / 125.0, 0.0, 1.0)
	var needle := Vector2.from_angle(PI * 0.78 + speed_ratio * PI * 1.44) * 6.0
	canvas.draw_line(Vector2(58, 184), Vector2(58, 184) + needle, C_AMBER, 1.0, false)
	var heat_ratio := clampf(float(player.get("heat", 0.0)) / 100.0, 0.0, 1.0)
	var heat_needle := Vector2.from_angle(PI * 0.78 + heat_ratio * PI * 1.44) * 6.0
	canvas.draw_line(Vector2(262, 184), Vector2(262, 184) + heat_needle,
		C_RED if heat_ratio > 0.72 else C_CREAM, 1.0, false)
	for light in 4:
		var active := (light == 0 and bool(player.get("boosting", false))) \
			or (light == 3 and heat_ratio > 0.72)
		canvas.draw_rect(Rect2(149 + light * 6, 171, 4, 3),
			(C_CYAN if light < 2 else C_RED) if active else Color8(38, 47, 48))
	if bool(player.get("boosting", false)):
		canvas.draw_rect(Rect2(149, 173, 22, 4), C_CYAN)
	if bool(player.get("crashed", false)):
		canvas.draw_line(Vector2(288, 116), Vector2(271, 138), Color(1, 1, 1, 0.7), 1.0, false)
		canvas.draw_line(Vector2(279, 127), Vector2(292, 135), Color(1, 1, 1, 0.55), 1.0, false)


func _draw_hud(canvas: CanvasItem, font: Font, player: Dictionary, model: RefCounted,
		message: String) -> void:
	canvas.draw_rect(Rect2(0, 0, 320, 16), Color(0.01, 0.02, 0.035, 0.92))
	_text(canvas, font, "%d/%d" % [model.player_place, model.kart_states().size()], 5, 11, 8, C_AMBER)
	_text(canvas, font, "R %d/%d" % [int(player.get("lap", 1)), LAPS], 36, 11, 7, C_WHITE)
	_text(canvas, font, "%03d KM/H" % int(float(player.get("speed", 0.0)) * 1.42), 84, 11, 7, C_CYAN)
	_text(canvas, font, _format_time(model.elapsed_ms()), 158, 11, 7, C_WHITE)
	_text(canvas, font, "%07d" % model.score, 249, 11, 7, C_AMBER)
	canvas.draw_rect(Rect2(7, 19, 60, 4), C_BLACK)
	canvas.draw_rect(Rect2(8, 20, 58 * float(player.get("turbo", 0.0)) / 100.0, 2), C_CYAN)
	canvas.draw_rect(Rect2(75, 19, 60, 4), C_BLACK)
	canvas.draw_rect(Rect2(76, 20, 58 * float(player.get("heat", 0.0)) / 100.0, 2), C_RED)
	_text(canvas, font, "TURBO", 8, 29, 5, C_CREAM)
	_text(canvas, font, "HITZE", 76, 29, 5, C_CREAM)
	_text(canvas, font, _piece_label(model.track_piece(float(player.get("progress", 0.0)))),
		145, 27, 6, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, 90)
	if bool(player.get("airborne", false)):
		_text(canvas, font, "FLUG %02d" % int(player.get("air_ticks", 0)), 246, 28, 6, C_GREEN)
	elif int(player.get("stunts", 0)) > 0:
		_text(canvas, font, "STUNTS %d" % int(player.get("stunts", 0)), 246, 28, 6, C_GREEN)
	if bool(player.get("offroad", false)):
		var recovery := "«  ZUR STRASSE" if float(player.get("lateral", 0.0)) > 0.0 else "ZUR STRASSE  »"
		_text(canvas, font, recovery, 0, 142, 8, C_AMBER,
			HORIZONTAL_ALIGNMENT_CENTER, 320, 2, C_BLACK)
	if message != "":
		_text(canvas, font, message, 0, 148, 6, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, 320, 1, C_BLACK)


func _slice_for_gap(gap: float, slices: Array[Dictionary], player_progress: float) -> int:
	var best := -1
	var best_distance := 999.0
	for i in slices.size():
		var distance := absf((float(slices[i]["progress"]) - player_progress) - gap)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func _road_color(piece: int, index: int, local := 0.5) -> Color:
	var asphalt := C_ROAD if index % 2 == 0 else C_ROAD_ALT
	# Spezialbelag wird an beiden Kachelgrenzen weich in den Asphalt geblendet.
	# Die alte Vollfarbe erzeugte breite Cyan-/Braunbalken und machte schon eine
	# harmlose Materialgrenze optisch zu einer gebrochenen Fahrbahn.
	var fade_in := smoothstep(0.02, 0.20, clampf(local, 0.0, 1.0))
	var fade_out := 1.0 - smoothstep(0.80, 0.98, clampf(local, 0.0, 1.0))
	var blend := fade_in * fade_out
	match piece:
		Track.Piece.ICE:
			var ice := Color8(93, 116, 123) if index % 2 == 0 else Color8(88, 110, 118)
			return asphalt.lerp(ice, blend * 0.54)
		Track.Piece.DIRT:
			var dirt := Color8(105, 78, 61) if index % 2 == 0 else Color8(98, 71, 57)
			return asphalt.lerp(dirt, blend * 0.60)
		_:
			return asphalt


func _ground_color(track_id: String) -> Color:
	match track_id:
		"gravel": return Color8(126, 83, 58)
		"freight": return Color8(48, 58, 61)
		_: return C_GROUND


func _kart_color(id: String) -> Color:
	match id:
		"cyan": return C_CYAN
		"red": return C_RED
		"blue": return C_BLUE
		"yellow": return C_AMBER
		"green": return C_GREEN
		"violet": return Color8(118, 66, 138)
		_: return C_WHITE


func _piece_label(piece: int) -> String:
	match piece:
		Track.Piece.RAMP: return "RAMPE"
		Track.Piece.LOOP: return "LOOPING"
		Track.Piece.BRIDGE: return "BRUECKE"
		Track.Piece.TUNNEL: return "TUNNEL"
		Track.Piece.BANK: return "STEILKURVE"
		Track.Piece.CORKSCREW: return "KORKENZIEHER"
		Track.Piece.ICE: return "EIS"
		Track.Piece.DIRT: return "SCHOTTER"
		_: return ""


func _format_time(milliseconds: int) -> String:
	var total_centiseconds := floori(float(maxi(0, milliseconds)) / 10.0)
	return "%02d:%02d.%02d" % [floori(total_centiseconds / 6000.0),
		floori(total_centiseconds / 100.0) % 60, total_centiseconds % 100]


func _text(canvas: CanvasItem, font: Font, value: String, x: float, y: float,
		font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT,
		width := -1.0, outline := 0, outline_color := C_BLACK) -> void:
	if outline > 0:
		canvas.draw_string_outline(font, Vector2(x, y), value, alignment, width,
			font_size, outline, outline_color)
	canvas.draw_string(font, Vector2(x, y), value, alignment, width, font_size, color)
