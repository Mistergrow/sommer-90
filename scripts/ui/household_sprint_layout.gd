class_name HouseholdSprintLayout
extends RefCounted
## Zustandslose Layout-, Hit-Test- und Beschriftungsregeln der Haushaltsbuehne.
## Rendering und Eingabe bleiben in HouseholdSprintStage; diese Regeln koennen
## dadurch ohne Canvas und ohne laufende Szene deterministisch getestet werden.


static func default_tool_position(mode: String, requested_size: Vector2) -> Vector2:
	var stage_size := requested_size
	if stage_size.x < 100.0 or stage_size.y < 100.0:
		stage_size = Vector2(1144, 620)
	match mode:
		"vacuum": return Vector2(stage_size.x * 0.69, stage_size.y * 0.76)
		"mower": return Vector2(stage_size.x * 0.50, stage_size.y * 0.58)
	return stage_size * 0.5


static func mower_lawn_polygon(stage_size: Vector2,
		normalized_polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for normalized_point: Vector2 in normalized_polygon:
		result.append(normalized_point * stage_size)
	return result


static func mower_position(requested: Vector2, previous: Vector2, stage_size: Vector2,
		normalized_polygon: PackedVector2Array) -> Vector2:
	var polygon := mower_lawn_polygon(stage_size, normalized_polygon)
	if Geometry2D.is_point_in_polygon(requested, polygon):
		return requested
	if Geometry2D.is_point_in_polygon(previous, polygon):
		return previous
	return default_tool_position("mower", stage_size)


static func mower_depth(y: float, stage_size: Vector2) -> float:
	return clampf((y / maxf(1.0, stage_size.y) - 0.24) / 0.48, 0.0, 1.0)


static func vacuum_power_cable(stage_size: Vector2,
		appliance_socket := Vector2.INF) -> PackedVector2Array:
	var start_at := appliance_socket
	if not is_finite(start_at.x) or not is_finite(start_at.y):
		start_at = Vector2(stage_size.x * 0.89, stage_size.y * 0.64)
	var wall_socket := Vector2(stage_size.x * 0.975, stage_size.y * 0.69)
	var direction := wall_socket - start_at
	return PackedVector2Array([
		start_at,
		start_at + Vector2(direction.x * 0.34, maxf(34.0, direction.y + 54.0)),
		start_at + Vector2(direction.x * 0.72, maxf(48.0, direction.y + 76.0)),
		wall_socket,
	])


static func point_segment_distance(probe_at: Vector2, start_at: Vector2,
		end_at: Vector2) -> float:
	var segment := end_at - start_at
	if segment.length_squared() <= 0.001:
		return probe_at.distance_to(start_at)
	var along := clampf((probe_at - start_at).dot(segment) /
		segment.length_squared(), 0.0, 1.0)
	return probe_at.distance_to(start_at + segment * along)


static func vacuum_hits_power_cable(probe_at: Vector2, stage_size: Vector2,
		appliance_socket := Vector2.INF) -> bool:
	var cable := vacuum_power_cable(stage_size, appliance_socket)
	for index in cable.size() - 1:
		if point_segment_distance(probe_at, cable[index], cable[index + 1]) <= 15.0:
			return true
	return false


static func target_center(index: int, targets: Array[Dictionary], fallback: Vector2,
		stage_size: Vector2) -> Vector2:
	if index < 0 or index >= targets.size():
		return fallback
	return Vector2(targets[index].get("position", Vector2.ZERO)) * stage_size


static func car_patch_size(index: int, stage_size: Vector2) -> Vector2:
	var normalized_sizes := [
		Vector2(0.135, 0.072), Vector2(0.115, 0.090), Vector2(0.112, 0.085),
		Vector2(0.105, 0.098), Vector2(0.135, 0.082), Vector2(0.120, 0.088),
	]
	return (normalized_sizes[index % normalized_sizes.size()] * stage_size).round()


static func target_rect(index: int, mode: String, targets: Array[Dictionary],
		fallback: Vector2, stage_size: Vector2) -> Rect2:
	var centre := target_center(index, targets, fallback, stage_size)
	if mode in ["vacuum", "mower"]:
		return Rect2(centre - Vector2(18, 15), Vector2(36, 30))
	if mode == "detail":
		var patch_size := car_patch_size(index, stage_size)
		return Rect2(centre - patch_size * 0.5, patch_size)
	return Rect2(centre - Vector2(25, 20), Vector2(50, 40))


static func aux_rect(index: int, count: int, mode: String, stage_size: Vector2) -> Rect2:
	if mode == "dishes":
		var dish_regions := [Rect2(28, 116, stage_size.x * 0.34, 395),
			Rect2(stage_size.x * 0.36, 116, stage_size.x * 0.23, 395),
			Rect2(stage_size.x * 0.61, 116, stage_size.x * 0.36 - 28, 395)]
		return dish_regions[index]
	var gap := 10.0
	var total_width := minf(stage_size.x - 80.0, 690.0)
	var width := (total_width - gap * float(count - 1)) / float(count)
	var left := (stage_size.x - total_width) * 0.5
	return Rect2(left + float(index) * (width + gap), 92, width, 60)


static func product_rect(product: int) -> Rect2:
	var row := floori(float(product) / 4.0)
	return Rect2(34 + float(product % 4) * 148.0, 128 + float(row) * 119.0, 136, 104)


static func aux_count(mode: String) -> int:
	match mode:
		"sort": return 3
		"organize": return 4
		"dishes", "detail": return 3
	return 0


static func aux_label(mode: String, index: int) -> String:
	if mode == "sort":
		var fallbacks := ["PAPIER", "WERTSTOFF", "REST"]
		return Loc.t("ui.household_sprint.sort.%d" % index, fallbacks[index])
	if mode == "organize":
		var fallbacks := ["REGAL", "DISKBOX", "WAESCHE", "PAPIERKORB"]
		return Loc.t("ui.household_sprint.organize.%d" % index, fallbacks[index])
	return ""


static func dish_label(index: int) -> String:
	var fallbacks := ["EINWEICHEN", "SPUELEN", "ABTROPFEN"]
	return Loc.t("ui.household_sprint.dishes.%d" % index, fallbacks[index])


static func car_tool_label(index: int) -> String:
	var fallbacks := ["SCHAUM", "WASSER", "LEDER"]
	return Loc.t("ui.household_sprint.car_tool.%d" % index, fallbacks[index])


static func product_label(product: int, fallbacks: Array) -> String:
	return Loc.t("ui.household_sprint.product.%d" % product, str(fallbacks[product]))


static func product_needed(product: int, targets: Array[Dictionary]) -> bool:
	for target in targets:
		if int(target.get("hits", 0)) > 0 and int(target.get("variant", -1)) == product:
			return true
	return false


static func mode_title(chore_id: String) -> String:
	var fallbacks := {
		"muell": "CONTAINER-KOMMANDO · SORTIERROUTE",
		"aufraeumen": "ZIMMER-RESET · ALLES AN SEINEN PLATZ",
		"spuelen": "SPUELWERK 1200 · DREI STATIONEN",
		"staubsaugen": "TEPPICH-PATROL · KRUEMELJAGD",
		"einkauf": "MAMAS EINKAUFSLISTE · KIOSK-RUNDE",
		"auto_waschen": "GARAGEN-GLANZ · SCHAUM / WASSER / LEDER",
		"rasen": "RASENMEISTER · BAHNEN OHNE KABELSALAT",
	}
	return Loc.t("ui.household_sprint.mode_title.%s" % chore_id,
		str(fallbacks.get(chore_id, "HAUSAUFTRAG")))


static func phase_label(mode: String) -> String:
	var fallbacks := {
		"sort": "GREIFEN · MATERIAL LESEN · IN DEN RICHTIGEN CONTAINER ZIEHEN",
		"organize": "GEGENSTAND GREIFEN · ZIELORT FINDEN · ABLEGEN",
		"dishes": "JEDES TEIL: EINWEICHEN → SPUELEN → ABTROPFEN",
		"vacuum": "MAUSTASTE HALTEN · KRUEMEL ABFAHREN · KABEL MEIDEN",
		"shopping": "LISTE MERKEN · NUR BENOETIGTE WARE EINPACKEN",
		"detail": "WERKZEUG WAEHLEN · JEDES BLECH IN DREI DURCHGAENGEN",
		"mower": "MAUSTASTE HALTEN · RASENFELDER LUECKENLOS MAEHEN",
	}
	return Loc.t("ui.household_sprint.phase.%s" % mode,
		str(fallbacks.get(mode, "BEREIT")))
