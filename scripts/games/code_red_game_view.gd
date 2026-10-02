extends Control
## CODE RED: PROTOKOLL 2034 — selbstbootende, kompakte Amiga-Managementsimulation.
## Das Szenario ist eine dystopische Fiktion. Reale Namen tauchen ausschliesslich
## als historische oeffentliche Medienbezugspunkte auf, nicht als Wahrheitsbeleg.

const Model := preload("res://scripts/games/code_red_model.gd")
const Chrome := preload("res://scripts/games/code_red_chrome.gd")
const ScreenRenderer := preload("res://scripts/games/code_red_screen_renderer.gd")
const AmigaPresentation := preload("res://scripts/games/amiga_game_presentation.gd")
const AmigaVideo := preload("res://scripts/games/standalone_amiga_video.gd")
const DisplayPipeline := preload("res://scripts/games/amiga_display_pipeline.gd")
const FrameScheduler := preload("res://scripts/games/amiga_frame_scheduler.gd")
const TITLE_ART := preload("res://assets/ui/games/code_red/title_background_v02.png")
const SUMMIT_ART := preload("res://assets/ui/games/code_red/summit_background_v02.png")
const GEO_ART := preload("res://assets/ui/games/code_red/geo_dashboard_blank_v03.png")
const END_VICTORY := preload("res://assets/ui/games/code_red/ending_victory_v02.png")
const END_MIXED := preload("res://assets/ui/games/code_red/ending_mixed_v02.png")
const END_CHAOS := preload("res://assets/ui/games/code_red/ending_chaos_v02.png")
const DASHBOARD_ART := preload("res://assets/ui/games/code_red/dashboard_background_v02.png")
const MEDIA_ART := preload("res://assets/ui/games/code_red/media_background_v02.png")
const SCIENCE_ART := preload("res://assets/ui/games/code_red/science_background_v02.png")
const PROJECTS_ART := preload("res://assets/ui/games/code_red/projects_background_v02.png")
const CABINET_ART := preload("res://assets/ui/games/code_red/cabinet_background_v02.png")
const STRANGE_SKY_ART := preload("res://assets/ui/games/code_red/strange_sky_background_v02.png")
const SQUATTER_SKY_ART := preload("res://assets/ui/games/code_red/squatter_sky_background_v02.png")
const PLASMA_ART := preload("res://assets/ui/games/code_red/plasma_discharge_background_v02.png")

const GAME_ID := "code_red_protocol"
const VW := 320.0
const VH := 256.0
const TOPAZ: Font = preload("res://assets/fonts/Topaz_a500_ui.ttf")
const JUICE_SCRIPT_PATH := "res://scripts/ui/juice_layer.gd"

const INK := Color8(3, 8, 14)
const PANEL := Color8(8, 20, 30, 235)
const PANEL_2 := Color8(15, 35, 45, 242)
const LINE := Color8(53, 91, 105)
const WHITE := Color8(229, 232, 207)
const DIM := Color8(129, 157, 160)
const AMBER := Color8(246, 168, 48)
const RED := Color8(226, 67, 53)
const GREEN := Color8(82, 222, 114)
const CYAN := Color8(63, 210, 222)

# Das GEO-Dashboard ist eine blanke Instrumententafel. Alle Anzeigen, inklusive
# des mittleren Hebels, entstehen aus dem aktuellen Simulationszustand.
const GEO_SLIDER_TRACK := Rect2(99, 204, 111, 8)
const GEO_ACTION_RECTS := {
	"particle_density": Rect2(4, 78, 69, 47),
	"fleet_routes": Rect2(4, 126, 69, 33),
	"dust_cover": Rect2(5, 169, 67, 10),
	"volcano_cover": Rect2(5, 180, 67, 10),
}
const GEO_REGION_RECTS := [
	Rect2(82, 88, 54, 72),
	Rect2(145, 91, 28, 32),
	Rect2(172, 87, 62, 43),
	Rect2(148, 119, 39, 48),
	Rect2(214, 116, 34, 47),
]
const GEO_REGION_POINTS := [
	Vector2(112, 122), Vector2(162, 107), Vector2(199, 107),
	Vector2(169, 139), Vector2(226, 135),
]

enum Screen { BOOT, TITLE, INTRO, DOCTRINE, DASHBOARD, SECTION, CABINET,
	PROJECTS, OPTICS, ARCHIVE, EVENT, DEBRIEF, MANUAL, RECORDS, ENDING, EXIT_CONFIRM }

const TITLE_MENU := ["NEUE OPERATION", "HANDBUCH", "REKORDE", "ZURUECK ZUM ZIMMER"]
const DASH_MENU := [
	{"id": "summit", "label": "GIPFEL"}, {"id": "science", "label": "WISSENSCHAFT"},
	{"id": "media", "label": "MEDIEN"}, {"id": "moderation", "label": "NETZKONTROLLE"},
	{"id": "geo", "label": "GEOENGINEERING"}, {"id": "economy", "label": "OEKONOMIE"},
	{"id": "cabinet", "label": "KABINETT"}, {"id": "projects", "label": "PROJEKTE"},
	{"id": "optics", "label": "OPTIKLABOR"}, {"id": "archive", "label": "HIMMELSARCHIV"},
	{"id": "end", "label": "EPOCHE BEENDEN"},
]

var disk: Disk = null
var model := Model.new()
var screen := Screen.BOOT
var _menu_index := 0
var _section := "summit"
var _selected_region := 0
var _public_view := false
var _intro_stage := 0
var _manual_page := 0
var _boot_time := 0.0
var _elapsed := 0.0
var _message := ""
var _logical_scale := 1.0
var _logical_origin := Vector2.ZERO
var _video_profile: Dictionary = {}
var _frame_scheduler := FrameScheduler.new()
var _hit_rects: Array[Dictionary] = []


func _draw() -> void:
	_hit_rects = []
	# Das 320x256-Amiga-Bild bleibt pixelgetreu. Der restliche Monitor darf auf
	# breiten Host-Aufloesungen jedoch niemals das Zimmer durchscheinen lassen:
	# Er ist Teil der klassifizierten Bedienkonsole.
	draw_set_transform(Vector2.ZERO)
	_draw_monitor_backdrop()
	draw_set_transform(_logical_origin, 0.0, Vector2.ONE * _logical_scale)
	# Kunstrichtung laut Vertrag: "serious_copper_gradient_strategy". Statt einer
	# toten schwarzen Flaeche liegt hinter jedem Screen ein echtes Copper-
	# Programm — 24 Rasterbaender, hardwarequantisiert, weit unter den 384
	# Copper-Instruktionen des OCS. Wo Bildkunst darueberliegt, bleibt es
	# unsichtbar; auf Listen- und Textscreens traegt es das Bild.
	Chrome.copper_backdrop(self, _video_profile, Rect2(0, 0, VW, VH),
		Color8(10, 24, 41), INK, 24)
	match screen:
		Screen.BOOT: _draw_boot()
		Screen.TITLE: _draw_title()
		Screen.INTRO: _draw_intro()
		Screen.DOCTRINE: _draw_doctrine()
		Screen.DASHBOARD: _draw_dashboard()
		Screen.SECTION: _draw_section()
		Screen.CABINET: _draw_cabinet()
		Screen.PROJECTS: _draw_projects()
		Screen.OPTICS: _draw_optics()
		Screen.ARCHIVE: _draw_archive()
		Screen.EVENT: _draw_event()
		Screen.DEBRIEF: _draw_debrief()
		Screen.MANUAL: _draw_manual()
		Screen.RECORDS: _draw_records()
		Screen.ENDING: _draw_ending()
		Screen.EXIT_CONFIRM: _draw_exit_confirm()
	_draw_scanlines()
	draw_set_transform(Vector2.ZERO)
	_draw_monitor_surround()


func _draw_monitor_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color8(1, 5, 9))
	# Dezente CRT-Struktur verhindert tote schwarze Balken, ohne das eigentliche
	# Amiga-Bild oder seine Palette anzutasten.
	for y in range(0, maxi(1, roundi(size.y)), 6):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.04, 0.11, 0.13, 0.22), 1.0)


func _draw_monitor_surround() -> void:
	var content_rect := Rect2(_logical_origin, Vector2(VW, VH) * _logical_scale)
	draw_rect(content_rect.grow(2.0), Color8(58, 91, 101), false, 2.0)
	var left_width := content_rect.position.x
	var right_width := size.x - content_rect.end.x
	if left_width >= 150.0:
		_draw_side_console(Rect2(0, 0, left_width - 4.0, size.y), true)
	if right_width >= 150.0:
		_draw_side_console(Rect2(content_rect.end.x + 4.0, 0, right_width - 4.0, size.y), false)


func _draw_side_console(rect: Rect2, left: bool) -> void:
	var inset := rect.grow(-maxf(10.0, _logical_scale * 3.0))
	if inset.size.x < 100.0 or inset.size.y < 160.0:
		return
	draw_rect(inset, Color8(5, 15, 23, 246))
	draw_rect(inset, LINE, false, maxf(1.0, _logical_scale * 0.45))
	var title_size := maxi(15, roundi(_logical_scale * 6.0))
	var body_size := maxi(11, roundi(_logical_scale * 3.8))
	var small_size := maxi(9, roundi(_logical_scale * 3.0))
	var pad := maxf(11.0, _logical_scale * 4.0)
	var x := inset.position.x + pad
	var width := inset.size.x - pad * 2.0
	var y := inset.position.y + pad + title_size
	_screen_text("CODE RED" if left else "GCN // SECURE", Rect2(x, y - title_size, width, title_size + 4),
		y, title_size, RED if left else CYAN)
	y += title_size + pad * 0.55
	_screen_text("CLASSIFIED · %s CONTROL" % str(_video_profile.get("name", "OCS")),
		Rect2(x, y - body_size, width, body_size + 4),
		y, small_size, DIM)
	y += body_size + pad
	draw_line(Vector2(x, y), Vector2(x + width, y), LINE, maxf(1.0, _logical_scale * 0.3))
	y += pad + body_size
	if left:
		_screen_text(model.period_label(), Rect2(x, y - body_size, width, body_size + 4), y,
			body_size, AMBER)
		y += body_size + pad
		_screen_metric(x, y, width, "WAHRHEIT", model.truth, RED, small_size)
		y += small_size * 2.4
		_screen_metric(x, y, width, "PANIK", model.panic, AMBER, small_size)
		y += small_size * 2.4
		_screen_metric(x, y, width, "KONTROLLE", model.control_index(), GREEN, small_size)
	else:
		_screen_text(model.phase(), Rect2(x, y - body_size, width, body_size + 4), y,
			body_size, GREEN)
		y += body_size + pad
		_screen_text("BUDGET  %03d MRD" % int(model.budget), Rect2(x, y - body_size, width, body_size + 4),
			y, body_size, WHITE)
		y += body_size + pad * 0.7
		_screen_text("BEFEHLE  %d" % model.commands_left, Rect2(x, y - body_size, width, body_size + 4),
			y, body_size, WHITE)
		y += body_size + pad * 1.4
		_screen_text("PFEILE / MAUS  NAVIGATION", Rect2(x, y - small_size, width, small_size + 4),
			y, small_size, DIM)
		y += small_size + pad * 0.5
		_screen_text("ENTER / A  BESTAETIGEN", Rect2(x, y - small_size, width, small_size + 4),
			y, small_size, DIM)
		y += small_size + pad * 0.5
		_screen_text("ESC / B  ZURUECK", Rect2(x, y - small_size, width, small_size + 4),
			y, small_size, DIM)
	var pulse_y := inset.end.y - pad * 2.0
	var pulse := 0.35 + 0.65 * (sin(_elapsed * 3.0) * 0.5 + 0.5)
	draw_line(Vector2(x, pulse_y), Vector2(x + width * pulse, pulse_y), CYAN if left else RED,
		maxf(2.0, _logical_scale * 0.7))


func _screen_metric(x: float, y: float, width: float, label: String, value: float,
		color: Color, font_size: int) -> void:
	_screen_text(label, Rect2(x, y - font_size, width, font_size + 3), y, font_size, DIM)
	var bar := Rect2(x, y + font_size * 0.45, width, maxf(5.0, font_size * 0.42))
	draw_rect(bar, Color8(9, 18, 23))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(value / 100.0, 0.0, 1.0), bar.size.y)), color)
	draw_rect(bar, LINE, false, 1.0)


func _screen_text(value: String, rect: Rect2, baseline: float, font_size: int, color: Color,
		alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var fitted := _fit_text(value, rect.size.x, font_size)
	draw_string(TOPAZ, Vector2(rect.position.x, baseline), fitted, alignment, rect.size.x, font_size, color)


func debug_monitor_coverage() -> Dictionary:
	return {
		"host_rect": Rect2(Vector2.ZERO, size),
		"game_rect": Rect2(_logical_origin, Vector2(VW, VH) * _logical_scale),
		"backdrop_covers_host": true,
		"room_can_show_through": false,
	}


func debug_video_contract() -> Dictionary:
	var report := AmigaVideo.debug_contract(_video_profile)
	report["scheduler"] = _frame_scheduler.telemetry_snapshot()
	return report


func _draw_boot() -> void:
	if _boot_time < 0.72:
		AmigaPresentation.draw_disk_boot(self, Vector2(VW, VH), _boot_time, 0.72,
			RED, "CODE RED · PROTOKOLL 2034")
		return
	_draw_cover(TITLE_ART, Rect2(0, 0, VW, VH))
	draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, 0.58))
	_text("GLOBAL COORDINATION NETWORK", 18, 90, 12, RED)
	_text("SECURE BOOT", 18, 111, 22, WHITE)
	var step := clampi(int((_boot_time - 0.72) * 24.0), 0, 100)
	_bar(Rect2(18, 144, 284, 8), step, RED)
	_text("AMIGA 500 · 1 MB · CLASSIFIED", 18, 172, 9, DIM)


func _draw_title() -> void:
	_draw_cover(TITLE_ART, Rect2(0, 0, VW, VH))
	draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, 0.20))
	_text("OBJEKT ENTDECKT · CODE RED", 12, 36, 13, RED, HORIZONTAL_ALIGNMENT_LEFT, 296, 2)
	_text("PROTOKOLL 2034", 12, 61, 24, WHITE, HORIZONTAL_ALIGNMENT_LEFT, 296, 2)
	_text("DYSTOPISCHE MANAGEMENT-FIKTION", 13, 77, 8, DIM)
	for i in TITLE_MENU.size():
		_button(Rect2(14, 112 + i * 25, 148, 20), TITLE_MENU[i], i, i == _menu_index)
	_text("1962 -> JULI/AUGUST 2034", 14, 232, 9, AMBER)


func _draw_intro() -> void:
	var art: Texture2D = SCIENCE_ART if _intro_stage == 0 else (SUMMIT_ART if _intro_stage == 1 else CABINET_ART)
	_draw_cover(art, Rect2(0, 0, VW, VH))
	draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, 0.48))
	var titles := ["1962 · DAS UNMOEGLICHE SIGNAL", "PROTOKOLL CODE RED", "DIE UNSICHTBARE HAND"]
	var bodies := [
		"Drei Observatorien messen dasselbe roetliche Objekt. Seine Bahn allein erklaert die Daten nicht: Zwischen Objekt, Sonne und Erde entsteht eine elektrische Kopplung.",
		"Die Grossmaechte einigen sich auf Geheimhaltung. Forschung, Medien, Netze und Evakuierung werden zu einer einzigen jahrzehntelangen Operation verbunden.",
		"Du leitest nicht ein Land. Du leitest das System dahinter. Waehle nun die Doktrin, die bis zum Entladungsfenster im August 2034 gilt.",
	]
	_header(titles[_intro_stage], "AKTE %d/3" % (_intro_stage + 1))
	_panel(Rect2(14, 145, 292, 76))
	_draw_wrapped(bodies[_intro_stage], Rect2(23, 157, 274, 48), 8, WHITE)
	_text("ENTER / A · WEITER    ESC / B · ABBRUCH", 35, 240, 8, AMBER)


func _draw_doctrine() -> void:
	_draw_cover(SUMMIT_ART, Rect2(0, 0, VW, VH))
	draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, 0.48))
	_header("DOKTRIN WAEHLEN", "OPERATIONSCODE %06d" % model.operation_seed)
	var catalog := model.doctrine_catalog()
	for i in catalog.size():
		var entry: Dictionary = catalog[i]
		_menu_card(Rect2(12, 62 + i * 46, 296, 39), str(entry.get("title", "")),
			str(entry.get("description", "")), i, i == _menu_index)
	_text("DIE DOKTRIN BLEIBT FUER DIE GESAMTE OPERATION AKTIV", 12, 224, 7, AMBER)


func _draw_dashboard() -> void:
	_draw_cover(DASHBOARD_ART, Rect2(0, 0, VW, VH))
	# Der Schleier darf leichter sein, seit die Bildkunst auf 32 OCS-Register
	# gebacken ist: Text sitzt jetzt auf gefasten Platten, nicht mehr direkt auf
	# dem Foto. 0.55 haette die frisch gewonnene Zeichnung wieder zugedeckt.
	draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, 0.38))
	_header("LAGEZENTRUM · %s" % model.period_label(), model.phase())
	_draw_world_map(Rect2(8, 47, 146, 82))
	_draw_metrics(Rect2(160, 47, 152, 82))
	for i in DASH_MENU.size():
		var col := i % 4
		var row := floori(float(i) / 4.0)
		_button(Rect2(8 + col * 76, 137 + row * 23, 72, 19),
			_short(str(DASH_MENU[i].get("label", "")), 14), i, i == _menu_index)
	ScreenRenderer.draw_status_console(self, model, Rect2(6, 205, 308, 46),
		_current_region(), _public_view, _message)


func _draw_section() -> void:
	if _section == "geo":
		_draw_geo_dashboard()
		return
	var art: Texture2D = TITLE_ART
	match _section:
		"summit": art = SUMMIT_ART
		"science": art = SCIENCE_ART
		"media", "moderation": art = MEDIA_ART
		"economy": art = PROJECTS_ART
	_draw_cover(art, Rect2(0, 0, VW, VH))
	draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, 0.66))
	_header(_section.to_upper(), "%s · %d BEFEHLE" % [model.period_label(), model.commands_left])
	var ids := model.actions_for(_section)
	for i in ids.size():
		var info := model.action_info(ids[i])
		var gate := model.can_apply(ids[i])
		var selected := i == _menu_index
		_menu_card(Rect2(10, 51 + i * 30, 300, 25), str(info.get("title", ids[i])),
			"%s · %s" % [_cost(info), str(gate.get("reason", info.get("detail", "")))],
			i, selected, bool(gate.get("ok", false)), 7, 6)
	var region := _current_region()
	if _section == "science":
		var orbit := model.orbit_snapshot(_public_view)
		_text("BAHN %.2f AE · %.2f GRAD · %s" % [float(orbit.get("distance_au", 0.0)),
			float(orbit.get("apparent_deg", 0.0)), str(orbit.get("periapsis", ""))], 12, 231, 7, CYAN)
	else:
		_text("ZIEL « %s »" % str(region.get("title", "GLOBAL")), 12, 231, 8, CYAN)
	_text("ESC: LAGEZENTRUM", 225, 231, 7, DIM)


func _draw_geo_dashboard() -> void:
	# Kein abdunkelnder Standard-Menue-Layer: Das Bild ist bereits die blanke
	# Bedienkonsole. Alle Daten darunter sind live und niemals eingebrannt.
	draw_texture_rect(GEO_ART, Rect2(0, 0, VW, VH), false)
	_draw_geo_runtime_atmosphere()
	var ids := model.actions_for("geo")
	_draw_geo_system_status()
	_draw_geo_particle_panel()
	_draw_geo_fleet_panel()
	_draw_geo_explanation_panel()
	_draw_geo_effectiveness()
	_draw_geo_map()
	_draw_geo_analysis()
	_draw_geo_slider()
	_draw_geo_warning()
	_draw_geo_command_display(ids)
	_register_geo_hits(ids)


func _draw_geo_runtime_atmosphere() -> void:
	# Die Referenzgrafik liefert nur Chassis und Erdansicht. Bewegung entsteht
	# hier in Lowres: 50-Hz-quantisierte Messzeile, Partikelhaze und echte
	# Telemetriepunkte. Damit ist die zentrale Szene kein statisches HD-Bild mit
	# beliebigen HTML-artigen Widgets mehr.
	var frame_50 := floori(_elapsed * 50.0)
	var map_rect := Rect2(80, 82, 170, 98)
	var sweep_y := map_rect.position.y + posmod(frame_50, roundi(map_rect.size.y))
	draw_line(Vector2(map_rect.position.x, sweep_y), Vector2(map_rect.end.x, sweep_y),
		Color(0.18, 0.92, 0.72, 0.12), 1)
	var density := clampf(model.particles / 100.0, 0.0, 1.0)
	var haze_rect := Rect2(map_rect.position.x, map_rect.end.y - 22, map_rect.size.x, 18)
	AmigaVideo.draw_ordered_dither(self, haze_rect,
		Color(0.76, 0.79, 0.66, 0.07 if AmigaVideo.is_aga(_video_profile) else 0.10),
		density * 0.52, floori(float(frame_50) / 4.0))
	var route_count := clampi(2 + floori(model.routes / 22.0), 2, 6)
	for i in route_count:
		var travel := fposmod(float(frame_50) * (0.10 + i * 0.013) + i * 29.0, 158.0)
		var x := map_rect.position.x + 6.0 + travel
		var y := map_rect.position.y + 14.0 + float((i * 17) % 47)
		var tint := CYAN if i % 2 == 0 else GREEN
		draw_rect(Rect2(roundf(x), roundf(y), 2, 1), tint)
		draw_line(Vector2(x - 6, y), Vector2(x - 2, y),
			Color(tint.r, tint.g, tint.b, 0.32), 1)
	if AmigaVideo.is_aga(_video_profile):
		# Nur die AGA-Erweiterung besitzt genug Farbreserven fuer die zweite
		# atmosphaerische Leuchtschicht.
		var aurora := 0.05 + 0.03 * sin(_elapsed * 1.7)
		draw_line(Vector2(91, 92), Vector2(237, 88),
			Color(0.20, 0.74, 0.92, aurora), 2)


func _draw_geo_system_status() -> void:
	_text_fit("GEO-ENGINEERING CTL", Rect2(5, 3, 60, 7), 8, 6, GREEN, HORIZONTAL_ALIGNMENT_CENTER, 1)
	_text_fit("SYSTEM STATUS", Rect2(5, 12, 60, 7), 17, 5, GREEN, HORIZONTAL_ALIGNMENT_CENTER, 1)
	var atmosphere := clampf(model.stability + model.particles * 0.16 - model.induction * 0.10, 0.0, 100.0)
	var entries := [
		["ATMOSPH.", atmosphere, GREEN],
		["PARTIKEL", model.particles, GREEN],
		["INDUKTION", model.induction, RED],
		["STABIL.", model.stability, GREEN],
	]
	for i in entries.size():
		var entry: Array = entries[i]
		var baseline := 25.0 + i * 6.0
		_text_fit(str(entry[0]), Rect2(5, baseline - 5, 31, 6), baseline, 5, entry[2], HORIZONTAL_ALIGNMENT_LEFT, 1)
		_geo_segment_bar(Rect2(38, baseline - 4, 27, 3), float(entry[1]), entry[2], 9)


func _draw_geo_particle_panel() -> void:
	_text_fit("PARTIKEL-DICHTE +", Rect2(7, 79, 63, 8), 85, 5, INK, HORIZONTAL_ALIGNMENT_CENTER)
	var strength := clampf(model.particles / 100.0, 0.0, 1.0)
	for i in 15:
		var phase := float(i) * 0.53 + _elapsed * 0.65
		var envelope := 0.28 + 0.72 * sin(PI * float(i + 1) / 16.0)
		var signal_height := 2.0 + envelope * (4.0 + strength * 18.0)
		signal_height += sin(phase) * (0.7 + strength * 1.2)
		var height := clampf(signal_height, 1.0, 24.0)
		var x := 10.0 + i * 3.2
		draw_rect(Rect2(x, 116.0 - height, 2.0, height), Color8(50, 167, 63))
	_text("%03d%%" % int(round(model.particles)), 49, 121, 6, GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 17, 1)


func _draw_geo_fleet_panel() -> void:
	_text_fit("FLOTTEN-ROUTEN", Rect2(8, 126, 61, 8), 132, 5, INK, HORIZONTAL_ALIGNMENT_CENTER)
	var points := [Vector2(14, 147), Vector2(27, 140), Vector2(41, 151), Vector2(57, 140), Vector2(65, 151)]
	var active := clampi(1 + int(round(model.routes / 24.0)), 1, points.size())
	for i in active - 1:
		_draw_dotted_line(points[i], points[i + 1], Color8(73, 177, 73), 2.0)
	for i in points.size():
		var color := GREEN if i < active else Color8(28, 71, 55)
		draw_rect(Rect2(points[i] - Vector2(2, 2), Vector2(4, 4)), color, false, 1)
	_text("%02d%%" % int(round(model.routes)), 51, 156, 5, GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 16, 1)


func _draw_geo_explanation_panel() -> void:
	_text_fit("ERKLAERUNG", Rect2(9, 160, 60, 8), 167, 6, INK, HORIZONTAL_ALIGNMENT_CENTER)
	var options := [
		["SAHARASTAUB", "SAHARASTAUB", 175.0],
		["VULKANAUSBR.", "VULKANAUSBRUCH", 186.0],
	]
	for entry: Array in options:
		var selected := model.explanation == str(entry[1])
		var center := Vector2(23, float(entry[2]) - 2.0)
		draw_circle(center, 2.5, GREEN if selected else Color8(46, 59, 58))
		draw_circle(center, 1.1, Color8(185, 225, 111) if selected else INK)
		_text_fit(str(entry[0]), Rect2(28, float(entry[2]) - 6.0, 41, 7), float(entry[2]), 5,
			GREEN if selected else RED, HORIZONTAL_ALIGNMENT_LEFT, 1)


func _draw_geo_effectiveness() -> void:
	var value := _geo_effectiveness()
	_text_fit("EFFEKTIVITAET", Rect2(7, 191, 62, 7), 197, 5, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_geo_segment_bar(Rect2(9, 201, 42, 6), value, GREEN, 12)
	_text("%02d%%" % int(round(value)), 53, 207, 6, GREEN, HORIZONTAL_ALIGNMENT_LEFT, 16, 1)


func _draw_geo_map() -> void:
	var regions := model.region_catalog()
	for i in mini(regions.size(), GEO_REGION_RECTS.size()):
		_hit_rects.append({"rect": GEO_REGION_RECTS[i], "action": "region", "region_index": i})
	var point: Vector2 = GEO_REGION_POINTS[clampi(_selected_region, 0, GEO_REGION_POINTS.size() - 1)]
	var pulse := 2.0 + sin(_elapsed * 4.0) * 0.6
	draw_arc(point, pulse + 2.0, 0.0, TAU, 12, CYAN, 1.0)
	draw_line(point - Vector2(6, 0), point - Vector2(2, 0), CYAN, 1)
	draw_line(point + Vector2(2, 0), point + Vector2(6, 0), CYAN, 1)
	draw_line(point - Vector2(0, 6), point - Vector2(0, 2), CYAN, 1)
	draw_line(point + Vector2(0, 2), point + Vector2(0, 6), CYAN, 1)
	var region := _current_region()
	draw_rect(Rect2(82, 174, 87, 10), Color(0.01, 0.04, 0.07, 0.88))
	_text_fit("ZIEL « %s »" % str(region.get("title", "GLOBAL")), Rect2(84, 175, 83, 8),
		181, 5, CYAN, HORIZONTAL_ALIGNMENT_CENTER, 1)


func _draw_geo_analysis() -> void:
	_text_fit("SYSTEM-ANALYSE", Rect2(259, 85, 57, 8), 92, 6, GREEN, HORIZONTAL_ALIGNMENT_CENTER, 1)
	var temperature := model.temperature_anomaly()
	var rainfall := clampf(-(model.induction * 0.24 - model.particles * 0.05), -99.0, 25.0)
	var ocean_ph := clampf(8.20 - model.progress() * 0.42 - model.burden * 0.003, 6.80, 8.30)
	var projection := temperature + (1.0 - model.progress()) * 2.6 + model.planet * 0.010
	var entries := [
		["GLOBAL TEMP.", "+%.2f C" % temperature, RED],
		["INDUKTION", "%03d%%" % int(round(model.induction)), RED],
		["NIEDERSCHL.", "%+03d%%" % int(round(rainfall)), GREEN if rainfall >= -10.0 else RED],
		["OZEAN-PH", "%.2f" % ocean_ph, GREEN if ocean_ph >= 7.8 else RED],
		["PROJEKTION", "+%.2f C" % projection, RED],
	]
	for i in entries.size():
		var entry: Array = entries[i]
		var top := 96.0 + i * 17.0
		_text_fit(str(entry[0]), Rect2(275, top, 40, 6), top + 5.0, 4, GREEN,
			HORIZONTAL_ALIGNMENT_CENTER, 1)
		_text_fit(str(entry[1]), Rect2(275, top + 6.0, 40, 8), top + 13.0, 6, entry[2],
			HORIZONTAL_ALIGNMENT_CENTER, 1)


func _draw_geo_slider() -> void:
	_text_fit("SILBERPARTIKEL-KONZENTRATION", Rect2(83, 191, 149, 9), 199, 6, INK,
		HORIZONTAL_ALIGNMENT_CENTER)
	_text("0%", 80, 212, 5, GREEN, HORIZONTAL_ALIGNMENT_LEFT, 17, 1)
	_text("100%", 212, 212, 5, GREEN, HORIZONTAL_ALIGNMENT_LEFT, 23, 1)
	draw_rect(GEO_SLIDER_TRACK, Color8(8, 13, 14))
	var segment_count := 24
	var ratio := clampf(model.particles / 100.0, 0.0, 1.0)
	var segment_width := (GEO_SLIDER_TRACK.size.x - float(segment_count - 1)) / float(segment_count)
	for i in segment_count:
		var x := GEO_SLIDER_TRACK.position.x + i * (segment_width + 1.0)
		var level := float(i + 1) / float(segment_count)
		var live := level <= ratio + 0.001
		var color := Color8(24, 37, 32)
		if live:
			color = GREEN if level < 0.56 else (AMBER if level < 0.79 else RED)
		draw_rect(Rect2(x, GEO_SLIDER_TRACK.position.y + 2, segment_width, 4), color)
	draw_rect(GEO_SLIDER_TRACK, Color8(83, 95, 91), false, 1)
	var lever_x := geo_slider_x()
	draw_rect(Rect2(lever_x - 3, 201, 7, 15), Color(0, 0, 0, 0.72))
	draw_rect(Rect2(lever_x - 2, 202, 5, 13), Color8(112, 121, 119))
	draw_line(Vector2(lever_x - 1, 203), Vector2(lever_x - 1, 213), Color8(220, 224, 207), 1)
	draw_line(Vector2(lever_x + 2, 203), Vector2(lever_x + 2, 214), Color8(48, 53, 55), 1)


func geo_slider_x() -> float:
	# Der Griff bleibt auch bei 0/100 Prozent vollstaendig innerhalb der Schiene.
	return GEO_SLIDER_TRACK.position.x + 3.0 + (GEO_SLIDER_TRACK.size.x - 7.0) \
		* clampf(model.particles / 100.0, 0.0, 1.0)


func _draw_geo_warning() -> void:
	var lines := _geo_warning_lines()
	var color: Color = lines[2]
	_text_fit(str(lines[0]), Rect2(243, 195, 72, 8), 202, 7, color, HORIZONTAL_ALIGNMENT_CENTER, 1)
	_text_fit(str(lines[1]), Rect2(243, 204, 72, 9), 212, 6, color, HORIZONTAL_ALIGNMENT_CENTER, 1)


func _draw_geo_command_display(ids: Array[String]) -> void:
	if ids.is_empty():
		return
	var safe_index := clampi(_menu_index, 0, ids.size() - 1)
	var id := ids[safe_index]
	var info := model.action_info(id)
	var gate := model.can_apply(id)
	var ok := bool(gate.get("ok", false))
	var title := str(info.get("title", id)).replace("ERKLAERUNG: ", "")
	_text_fit(title, Rect2(82, 225, 154, 11), 235, 8, GREEN if ok else RED,
		HORIZONTAL_ALIGNMENT_CENTER, 1)
	var detail := "%s · %s" % [_cost(info), "ENTER AUSFUEHREN" if ok else str(gate.get("reason", "GESPERRT"))]
	_text_fit(detail, Rect2(82, 238, 154, 8), 245, 5, WHITE if ok else RED,
		HORIZONTAL_ALIGNMENT_CENTER, 1)
	_text_fit("%s · %d BEFEHLE · ESC ZURUECK" % [model.period_label(), model.commands_left],
		Rect2(82, 247, 154, 6), 252, 4, DIM, HORIZONTAL_ALIGNMENT_CENTER, 1)


func _register_geo_hits(ids: Array[String]) -> void:
	for id: String in GEO_ACTION_RECTS:
		var index := ids.find(id)
		if index < 0:
			continue
		var rect: Rect2 = GEO_ACTION_RECTS[id]
		var enabled := bool(model.can_apply(id).get("ok", false))
		if index == _menu_index:
			_draw_geo_selection_frame(rect, enabled)
		_hit_rects.append({"rect": rect, "index": index})
	var particle_index := ids.find("particle_density")
	if particle_index >= 0:
		var slider_hit := Rect2(78, 189, 159, 29)
		if particle_index == _menu_index:
			_draw_geo_selection_frame(slider_hit,
				bool(model.can_apply("particle_density").get("ok", false)))
		_hit_rects.append({"rect": slider_hit, "index": particle_index})


func _draw_geo_selection_frame(rect: Rect2, enabled: bool) -> void:
	var color := AMBER if enabled else RED
	var length := 5.0
	draw_line(rect.position, rect.position + Vector2(length, 0), color, 1)
	draw_line(rect.position, rect.position + Vector2(0, length), color, 1)
	draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x - length, rect.position.y), color, 1)
	draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.position.y + length), color, 1)
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x + length, rect.end.y), color, 1)
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x, rect.end.y - length), color, 1)
	draw_line(rect.end, rect.end - Vector2(length, 0), color, 1)
	draw_line(rect.end, rect.end - Vector2(0, length), color, 1)


func _geo_segment_bar(rect: Rect2, value: float, color: Color, segments: int) -> void:
	draw_rect(rect, Color8(5, 12, 12))
	var width := (rect.size.x - float(segments - 1)) / float(segments)
	var active := int(ceil(clampf(value, 0.0, 100.0) / 100.0 * segments))
	for i in segments:
		var segment_color := color if i < active else Color8(25, 39, 34)
		draw_rect(Rect2(rect.position.x + i * (width + 1.0), rect.position.y, width, rect.size.y), segment_color)


func _geo_effectiveness() -> float:
	var coverage := model.particles * 0.64 + model.routes * 0.36
	var overload := maxf(0.0, model.induction - model.particles) * 0.18
	return clampf(coverage - overload, 0.0, 100.0)


func _geo_warning_lines() -> Array:
	if model.commands_left <= 0:
		return ["SYSTEM", "BEFEHLE VERBRAUCHT", AMBER]
	if model.induction >= 70.0 or model.plasma_load >= 65.0:
		return ["WARNUNG", "INDUKTION KRITISCH", RED]
	if model.particles + 8.0 < model.induction * 0.75:
		return ["WARNUNG", "PARTIKEL ERHOEHEN", RED]
	if model.routes < 45.0:
		return ["HINWEIS", "ROUTEN LUECKENHAFT", AMBER]
	return ["SYSTEM", "KORRIDOR STABIL", GREEN]


func _draw_dotted_line(from: Vector2, to: Vector2, color: Color, spacing: float) -> void:
	var length := from.distance_to(to)
	if length <= 0.001:
		return
	var direction := (to - from) / length
	var offset_along := 0.0
	while offset_along <= length:
		draw_circle(from + direction * offset_along, 0.7, color)
		offset_along += spacing


func _draw_cabinet() -> void:
	ScreenRenderer.draw_cabinet(self, model, _menu_index)


func _draw_projects() -> void:
	ScreenRenderer.draw_projects(self, model, _menu_index)


func _draw_archive() -> void:
	ScreenRenderer.draw_archive(self, model, _menu_index)


func _draw_optics() -> void:
	ScreenRenderer.draw_optics(self, model, _menu_index, _public_view)


func _draw_event() -> void:
	ScreenRenderer.draw_event(self, model, _menu_index)
func _event_texture(art_id: String) -> Texture2D:
	match art_id:
		"strange_sky": return STRANGE_SKY_ART
		"squatter": return SQUATTER_SKY_ART
		"plasma": return PLASMA_ART
		_: return MEDIA_ART if model.pending_event.has("opponent") else SUMMIT_ART


func _draw_debrief() -> void:
	_draw_terminal_background("EPOCHENBERICHT")
	var report := model.last_debrief
	_text("%s -> %s" % [str(report.get("period", report.get("year", ""))),
		str(report.get("next_period", model.period_label()))], 14, 58, 15, WHITE)
	_text(str(report.get("headline", "LAGEBERICHT")), 14, 83, 11, AMBER)
	_panel(Rect2(14, 99, 292, 91))
	_text("WAHRHEIT  %+0.1f" % float(report.get("truth_delta", 0.0)), 23, 122, 10,
		RED if float(report.get("truth_delta", 0.0)) > 0 else GREEN)
	_text("PANIK      %+0.1f" % float(report.get("panic_delta", 0.0)), 23, 143, 10,
		RED if float(report.get("panic_delta", 0.0)) > 0 else GREEN)
	_text("STAERKSTE VERAENDERUNG: %s  %+0.1f" % [str(report.get("largest_metric", "")), float(report.get("largest_delta", 0.0))], 23, 166, 8, CYAN)
	_text("ELEKTRISCHE LAST: %04.1f · %s" % [model.plasma_load,
		str(model.electric_universe_snapshot().get("label", ""))], 23, 181, 7, RED)
	_text("ENTER: EREIGNISBERICHT", 78, 222, 9, WHITE)


func _draw_manual() -> void:
	ScreenRenderer.draw_manual(self, _manual_page)
func _draw_records() -> void:
	_draw_terminal_background("OPERATIONSARCHIV")
	var records := get_node_or_null("/root/AmigaGameManager")
	var record: Dictionary = records.call("record", GAME_ID) if records != null else {}
	_text("OPERATIONEN", 20, 73, 9, DIM)
	_text("%06d" % int(record.get("plays", 0)), 198, 73, 12, WHITE)
	_text("ABGESCHLOSSEN", 20, 101, 9, DIM)
	_text("%06d" % int(record.get("completions", 0)), 198, 101, 12, GREEN)
	_text("BESTER SCORE", 20, 129, 9, DIM)
	_text("%06d" % int(record.get("best_score", 0)), 198, 129, 12, AMBER)
	var details: Dictionary = record.get("last_details", {})
	_text("LETZTE LECKQUOTE", 20, 157, 9, DIM)
	_text("%05.1f %%" % float(details.get("truth_leak", 0.0)), 198, 157, 12, RED)
	_text("ENTER: ZURUECK", 99, 222, 9, WHITE)


func _draw_ending() -> void:
	var texture: Texture2D = END_VICTORY if model.ending == "victory" else (END_MIXED if model.ending == "mixed" else END_CHAOS)
	_draw_cover(texture, Rect2(0, 0, VW, VH))
	# Alle eingebrannten Konzepttexte werden von einer neutralen dynamischen
	# Auswertung ueberdeckt. Dadurch ist die Leckquote niemals vorgegeben.
	draw_rect(Rect2(8, 125, 304, 123), Color(1.0 / 255.0, 5.0 / 255.0, 9.0 / 255.0, 0.94))
	_text("OPERATION %s" % ("ABGESCHLOSSEN" if model.ending == "victory" else ("ZEIT ERKAUFT" if model.ending == "mixed" else "VERLOREN")),
		14, 147, 14, GREEN if model.ending == "victory" else (AMBER if model.ending == "mixed" else RED))
	_draw_wrapped(model.ending_text(), Rect2(14, 158, 292, 45), 8, WHITE)
	_text("WAHRHEITSSICKERQUOTE: %05.1f %%" % model.truth, 14, 211, 10, CYAN)
	_text("SCORE %06d · %s" % [model.score(), model.rank()], 14, 227, 8, AMBER)
	_button(Rect2(14, 233, 132, 17), "NEUE OPERATION", 0, _menu_index == 0)
	_button(Rect2(174, 233, 132, 17), "ZUM TITEL", 1, _menu_index == 1)


func _draw_exit_confirm() -> void:
	_draw_terminal_background("VERBINDUNG TRENNEN?")
	_panel(Rect2(38, 83, 244, 87))
	_text("UNGESPEICHERTE OPERATION ENDET.", 53, 111, 9, WHITE)
	_button(Rect2(52, 133, 92, 24), "TRENNEN", 0, _menu_index == 0)
	_button(Rect2(176, 133, 92, 24), "BLEIBEN", 1, _menu_index == 1)


func _draw_terminal_background(title: String) -> void:
	draw_rect(Rect2(0, 0, VW, VH), INK)
	for y in range(0, 256, 16):
		draw_line(Vector2(0, y), Vector2(320, y), Color(0.03, 0.11, 0.13), 1)
	_header(title, "%s · %s" % [model.period_label(), model.phase()])


func _header(title: String, right: String) -> void:
	draw_rect(Rect2(0, 0, VW, 37), Color8(3, 10, 17, 245))
	if AmigaVideo.is_aga(_video_profile):
		# AGA-Variante: zusaetzliche, sehr schmale Copper-Zeilen in der
		# Kopfkonsole. ECS behaelt die harte einfarbige 5-Bitplane-Leiste.
		AmigaVideo.draw_copper_bands(self, Rect2(0, 32, VW, 4),
			Color8(37, 53, 82), Color8(73, 28, 55), 1, true)
	draw_line(Vector2(0, 36), Vector2(VW, 36), LINE, 1)
	_text_fit(title, Rect2(9, 4, 302, 16), 18, 12, AMBER)
	_text_fit(right, Rect2(9, 22, 302, 10), 31, 7, DIM, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_world_map(rect: Rect2) -> void:
	ScreenRenderer.draw_world_map(self, model, rect, _selected_region, _hit_rects)


func _draw_metrics(rect: Rect2) -> void:
	_panel(rect)
	var entries := [["WAHRHEIT", model.truth, RED], ["PANIK", model.panic, AMBER],
		["KONTROLLE", model.control_index(), GREEN], ["GLAUBEN", model.credibility, CYAN],
		["PLASMA", model.plasma_load, Color8(210, 84, 235)]]
	for i in entries.size():
		_text(entries[i][0], rect.position.x + 7, rect.position.y + 12 + i * 14, 6, DIM)
		_bar(Rect2(rect.position.x + 65, rect.position.y + 6 + i * 14, 76, 6), entries[i][1], entries[i][2])
	_text("BUDGET %03d MRD" % int(model.budget), rect.position.x + 7, rect.end.y - 5, 7, WHITE)


func _draw_sundog_scene(rect: Rect2, scenario_id: String) -> void:
	draw_rect(rect, Color8(26, 47, 67))
	for y in range(int(rect.position.y), int(rect.end.y), 2):
		var ratio := (y - rect.position.y) / rect.size.y
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0.22 + ratio * 0.3, 0.36 + ratio * 0.24, 0.52 + ratio * 0.18), 2)
	var sun := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.57)
	draw_circle(sun, 8, Color8(255, 229, 154))
	if scenario_id == "halo_22":
		draw_arc(sun, 35, 0, TAU, 48, Color(0.95, 0.85, 0.63, 0.75), 2)
	elif scenario_id == "sundog":
		draw_circle(sun + Vector2(-35, 0), 5, Color8(255, 190, 104))
		draw_circle(sun + Vector2(35, 0), 5, Color8(255, 190, 104))
	elif scenario_id == "sun_pillar":
		draw_rect(Rect2(sun.x - 2, rect.position.y + 7, 4, rect.size.y - 14), Color(1, 0.72, 0.3, 0.55))
	else:
		draw_arc(sun, 17, -1.0, 1.0, 16, RED, 3)
	draw_rect(rect, LINE, false, 1)


func _current_region() -> Dictionary:
	var catalog := model.region_catalog()
	return catalog[_selected_region] if not catalog.is_empty() else {}


func _button(rect: Rect2, label: String, index: int, selected: bool, enabled := true) -> void:
	# Gewaehlte Taste ist eine erhabene Beschriftungsplatte mit Zielwinkeln,
	# ruhende Tasten bleiben vertieftes Blech. Der Unterschied ist damit auch
	# ohne Farbe lesbar — auf einem 32-Farben-Schirm zaehlt die Form.
	# Gesperrt heisst zurueckgenommen, nicht uebermalt: dunkleres Blech und
	# matter Text. Gefahrenstreifen bleiben echten Warnfeldern vorbehalten —
	# ueber einer Beschriftung fressen sie die Lesbarkeit.
	if not enabled:
		Chrome.bevel_panel(self, rect, _video_profile,
			Color8(17, 26, 34), Color8(43, 55, 62), Color8(9, 13, 17))
	elif selected:
		Chrome.bevel_panel(self, rect, _video_profile,
			Chrome.PLATE, Chrome.PLATE_LIT, Chrome.PLATE_SHADE)
		Chrome.corner_brackets(self, rect, AMBER)
	else:
		Chrome.bevel_panel(self, rect, _video_profile)
	if selected and not enabled:
		Chrome.corner_brackets(self, rect, DIM)
	var font_size := 8
	var baseline := rect.position.y + (rect.size.y + float(font_size)) * 0.5 - 1.0
	_text_fit(label, Rect2(rect.position + Vector2(6, 2), rect.size - Vector2(12, 4)),
		baseline, font_size, WHITE if enabled else Color8(91, 103, 104))
	_hit_rects.append({"rect": rect, "index": index})


## Zweizeilige Bedienkarte mit garantiert getrennten Titel-/Informationszonen.
## Sie ersetzt die fruehere Kombination aus Buttontext und darueber gezeichnetem
## Detailtext, die bei Doktrinen, Projekten und Aktionen sichtbar kollidierte.
func _menu_card(rect: Rect2, title: String, detail: String, index: int, selected: bool,
		enabled := true, title_size := 8, detail_size := 6) -> void:
	# Bedienkarte: erhabenes Blech mit vertiefter Textmulde. Keine Nieten — auf
	# einer 14 Pixel hohen Zeile waeren sie Rauschen statt Detail.
	Chrome.bevel_panel(self, rect, _video_profile)
	Chrome.inset_well(self, rect.grow(-2.0), _video_profile)
	if selected:
		draw_rect(Rect2(rect.position + Vector2(1, 1), Vector2(3, rect.size.y - 2)), AMBER)
		Chrome.corner_brackets(self, rect, AMBER)
	var layout := debug_card_layout(rect, title_size, detail_size)
	var title_height := float(layout.get("title_height", 0.0))
	var title_rect: Rect2 = layout.get("title_rect", Rect2())
	var detail_rect: Rect2 = layout.get("detail_rect", Rect2())
	_text_fit(title, title_rect, rect.position.y + minf(title_height - 2.0, float(title_size + 3)),
		title_size, WHITE if enabled else Color8(91, 103, 104))
	if detail_rect.size.y >= float(detail_size):
		_draw_wrapped(detail, detail_rect, detail_size,
			DIM if enabled else Color8(74, 85, 86))
	_hit_rects.append({"rect": rect, "index": index})


func debug_card_layout(rect: Rect2, title_size := 8, detail_size := 6) -> Dictionary:
	var title_height := maxf(float(title_size + 4), rect.size.y * 0.48)
	var title_rect := Rect2(rect.position + Vector2(7, 2),
		Vector2(maxf(0.0, rect.size.x - 14), maxf(0.0, title_height - 2)))
	var detail_rect := Rect2(rect.position + Vector2(7, title_height),
		Vector2(maxf(0.0, rect.size.x - 14), maxf(0.0, rect.size.y - title_height - 2)))
	return {"title_height": title_height, "title_rect": title_rect,
		"detail_rect": detail_rect, "zones_overlap": title_rect.intersects(detail_rect),
		"detail_fits": detail_rect.size.y >= float(detail_size)}


## Vertiefte Anzeigemulde statt flachem Kasten — dieselbe Fase wie im
## GEO-Screen, damit jede Flaeche als Teil derselben Konsole liest.
func _panel(rect: Rect2) -> void:
	Chrome.inset_well(self, rect, _video_profile)


## Messwerte laufen als segmentierte LED-Kette. Die Segmentzahl folgt der
## Balkenbreite, damit schmale und breite Anzeigen dasselbe Raster behalten.
func _bar(rect: Rect2, value: float, color: Color) -> void:
	Chrome.segment_bar(self, rect, _video_profile, value, color,
		clampi(int(rect.size.x / 6.0), 6, 20))


func _text(value: String, x: float, y: float, font_size: int, color: Color,
		alignment := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 0) -> void:
	if outline > 0:
		draw_string_outline(TOPAZ, Vector2(x, y), value, alignment, width, font_size, outline, INK)
	draw_string(TOPAZ, Vector2(x, y), value, alignment, width, font_size, color)


func _text_fit(value: String, rect: Rect2, baseline: float, font_size: int, color: Color,
		alignment := HORIZONTAL_ALIGNMENT_LEFT, outline := 0) -> void:
	_text(_fit_text(value, rect.size.x, font_size), rect.position.x, baseline, font_size,
		color, alignment, rect.size.x, outline)


func _fit_text(value: String, max_width: float, font_size: int) -> String:
	if max_width <= 0.0 or TOPAZ.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return value
	var suffix := "..."
	var fitted := value
	while not fitted.is_empty():
		fitted = fitted.left(fitted.length() - 1)
		var candidate := fitted.rstrip(" ") + suffix
		if TOPAZ.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			return candidate
	return suffix


func _draw_wrapped(value: String, rect: Rect2, font_size: int, color: Color) -> void:
	var max_lines := maxi(1, int(rect.size.y / float(font_size + 2)))
	var lines := _wrapped_lines(value, rect.size.x, font_size, max_lines)
	for i in lines.size():
		_text(lines[i], rect.position.x, rect.position.y + font_size + i * (font_size + 2),
			font_size, color)


func _wrapped_lines(value: String, max_width: float, font_size: int, max_lines: int) -> Array[String]:
	var words := value.replace("\n", " \n ").split(" ", false)
	var lines: Array[String] = []
	var line := ""
	var truncated := false
	for word: String in words:
		if word == "\n":
			if not line.is_empty():
				lines.append(line)
				line = ""
			if lines.size() >= max_lines:
				truncated = true
				break
			continue
		var candidate := word if line.is_empty() else line + " " + word
		if TOPAZ.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			line = candidate
			continue
		if not line.is_empty():
			lines.append(line)
			if lines.size() >= max_lines:
				truncated = true
				break
		line = word
		if TOPAZ.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
			line = _fit_text(line, max_width, font_size)
	if not line.is_empty() and lines.size() < max_lines:
		lines.append(line)
	elif not line.is_empty():
		truncated = true
	if truncated and not lines.is_empty():
		var last := lines.size() - 1
		lines[last] = _fit_text(lines[last] + " ...", max_width, font_size)
	return lines


func _draw_cover(texture: Texture2D, rect: Rect2) -> void:
	DisplayPipeline.draw_cover(self, texture, rect)


func _draw_scanlines() -> void:
	AmigaVideo.draw_post_fx(self, Vector2(VW, VH), _video_profile, _elapsed)


func _short(value: String, length: int) -> String:
	return value if value.length() <= length else value.substr(0, length - 1) + "..."


func _cost(info: Dictionary) -> String:
	var raw := float(info.get("budget", 0.0))
	return "+%d MRD" % int(raw) if raw > 0 else "%d MRD" % int(raw)


func _effects_line(raw: Variant) -> String:
	if not raw is Dictionary:
		return ""
	var parts: Array[String] = []
	for key: Variant in raw:
		parts.append("%s %+.0f" % [str(key).to_upper(), float((raw as Dictionary)[key])])
	return " · ".join(parts)
