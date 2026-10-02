extends RetroWindow
## STADTKARTE — die Kleinstadt als schematische Karte (Quelle: data/town.json via
## TownManager). Bezirke als getönte Flächen, Orte als Pins: begehbare Orte hell
## & anklickbar, geplante/künftige gedimmt. Oben das Verkehrsmittel (Fuß/Rad/Bus/
## Auto) — Reisezeit & Buskosten hängen von der Bezirks-Distanz ab. Unten die
## Details zum gewählten Ort samt „Hinfahren". Ersetzt später das gemalte
## Stadt-Artwork (LOCATION_TOWN_MAP_MASTER) — die Logik bleibt.

const _MapView := preload("res://scripts/ui/map_view.gd")

const MODES := [
	"walk", "bike", "bus", "car",
]

## Wege-Ansicht: aus → Fuß → Rad → Bus → alle (durchklickbar).
const NET_CYCLE := ["", "foot", "bike", "bus", "all"]

var _mode := "bike"
var _selected := ""
var initial_target := ""
var initial_mode := ""
var initial_job_id := ""
var _target_job_id := ""
var _net := ""
var _map: Control
var _detail: RichTextLabel
var _go_button: Button
var _net_button: Button
var _mode_buttons: Dictionary = {}
var _side_title: Label
var _legend: Label
var _travelling := false


func _init() -> void:
	title = Loc.t("ui.map_window.stadtkarte_wohin", "STADTKARTE — WOHIN?")
	win_size = Vector2(600, 520)
	chrome_accent = Palette.LCD_CYAN


func _ready() -> void:
	# Karte fast-Vollbild öffnen (große Faltkarte, gut sichtbare Marker).
	var vp := get_viewport_rect().size
	win_size = Vector2(maxf(vp.x - 16.0, 640.0), maxf(vp.y - 16.0, 480.0))
	super._ready()
	position = ((vp - win_size) * 0.5).floor()
	if initial_mode in MODES and bool(TownManager.mode_unlocked(initial_mode).get("ok", false)):
		_mode = initial_mode
	_selected = initial_target if not initial_target.is_empty() else GameManager.current_location_id
	_target_job_id = initial_job_id

	# Verkehrsmittel-Wahl
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 4)
	content.add_child(mode_row)
	for mode_id: String in MODES:
		var b := make_button(_mode_label(mode_id), _on_mode.bind(mode_id))
		b.custom_minimum_size = Vector2(112, 44)
		var unlock: Dictionary = TownManager.mode_unlocked(mode_id)
		if not unlock["ok"]:
			b.disabled = true
			b.tooltip_text = unlock["reason"]
		_mode_buttons[mode_id] = b
		mode_row.add_child(b)
	# Wege-Ansicht (Straßennetz je Verkehrsmittel ein-/ausblenden)
	_net_button = make_button(Loc.t("ui.map_window.wege_aus", "Wege: aus"), _on_net)
	_net_button.custom_minimum_size = Vector2(150, 44)
	_net_button.tooltip_text = Loc.t("ui.map_window.wegenetz_zeigen_fuss_rad_bus_mit", "Wegenetz zeigen: Fuß / Rad / Bus (mit Haltestellen) / alle")
	mode_row.add_child(_net_button)

	# Karte und Reiseinformationen bilden einen breiten Arbeitsplatz. Die alte
	# vertikale Stapelung zwang das nahezu quadratische Kartenpapier in einen
	# flachen Schlitz und machte Pins wie Beschriftungen unnötig klein.
	var workspace := HBoxContainer.new()
	workspace.name = "TravelMapWorkspace"
	workspace.add_theme_constant_override("separation", 14)
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(workspace)

	_map = _MapView.new()
	_map.name = "TravelMapCanvas"
	_map.custom_minimum_size = Vector2(760, 560)
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.pin_selected.connect(_on_pin)
	_map.set_travel_mode(_mode)
	workspace.add_child(_map)

	var side_shell := PanelContainer.new()
	side_shell.name = "TravelMapSidePanel"
	side_shell.custom_minimum_size = Vector2(300, 0)
	# Dieselbe eingelassene Instrumentenflaeche wie die gemeinsame Fensterhülle.
	# Der alte 10-Pixel-Radius las sich als modernes Web-/Windows-Kartenpanel und
	# brach sichtbar mit HUD, Titelschiene und den physischen Modustasten.
	side_shell.add_theme_stylebox_override("panel",
		preload("res://scripts/ui/ui_window_chrome.gd").surface_box(0.0, 0.0))
	workspace.add_child(side_shell)
	var side_margin := MarginContainer.new()
	side_margin.add_theme_constant_override("margin_left", 16)
	side_margin.add_theme_constant_override("margin_right", 16)
	side_margin.add_theme_constant_override("margin_top", 16)
	side_margin.add_theme_constant_override("margin_bottom", 16)
	side_shell.add_child(side_margin)
	var side := VBoxContainer.new()
	side.name = "TravelMapInfo"
	side.add_theme_constant_override("separation", 12)
	side_margin.add_child(side)
	_side_title = Bezel.section_label(Loc.t("ui.map_window.reiseplanung", "REISEPLANUNG"), Palette.CYAN)
	side.add_child(_side_title)
	_legend = Bezel.body_label(Loc.t("ui.map_window.erreichbar_aktive_mission", "● erreichbar    ◉ aktive Mission"), 13)
	_legend.modulate = Color(0.78, 0.86, 0.74)
	side.add_child(_legend)
	var rule := HSeparator.new()
	side.add_child(rule)

	# Detailbereich
	_detail = RichTextLabel.new()
	_detail.name = "TravelMapDetail"
	_detail.bbcode_enabled = true
	_detail.fit_content = false
	_detail.scroll_active = false
	_detail.custom_minimum_size = Vector2(0, 220)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 15)
	_detail.add_theme_constant_override("line_separation", 5)
	side.add_child(_detail)

	_go_button = make_button(Loc.t("ui.map_window.hinfahren", "Hinfahren"), _on_go)
	_go_button.name = "TravelMapGoButton"
	_go_button.custom_minimum_size = Vector2(0, 52)
	side.add_child(_go_button)

	_update_mode_buttons()
	_refresh_detail()
	if not QuestManager.quests_changed.is_connected(_on_world_markers_changed):
		QuestManager.quests_changed.connect(_on_world_markers_changed)
	if not TimeManager.slot_changed.is_connected(_on_time_marker_changed):
		TimeManager.slot_changed.connect(_on_time_marker_changed)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)


func _on_locale_changed(_locale: String) -> void:
	set_window_title(Loc.t("ui.map_window.stadtkarte_wohin", "STADTKARTE — WOHIN?"))
	for mode_id: String in _mode_buttons:
		(_mode_buttons[mode_id] as Button).text = _mode_label(mode_id)
	if _net_button != null:
		_net_button.text = _net_label(_net)
		_net_button.tooltip_text = Loc.t("ui.map_window.wegenetz_zeigen_fuss_rad_bus_mit",
			"Wegenetz zeigen: Fuß / Rad / Bus (mit Haltestellen) / alle")
	if _side_title != null:
		_side_title.text = Loc.t("ui.map_window.reiseplanung", "REISEPLANUNG")
	if _legend != null:
		_legend.text = Loc.t("ui.map_window.erreichbar_aktive_mission",
			"● erreichbar    ◉ aktive Mission")
	if _go_button != null:
		_go_button.text = Loc.t("ui.map_window.unterwegs", "unterwegs …") if _travelling else \
			Loc.t("ui.map_window.hinfahren", "Hinfahren")
	if _map != null:
		_map.call("refresh_locale")
	_refresh_detail()


func _on_mode(mode: String) -> void:
	_mode = mode
	if _map != null:
		_map.set_travel_mode(_mode)
	_update_mode_buttons()
	_refresh_detail()


func _on_world_markers_changed() -> void:
	if _map != null:
		_map.refresh_markers()
	_refresh_detail()


func _on_time_marker_changed(_slot: int) -> void:
	if _map != null:
		_map.refresh_markers()
	_refresh_detail()


## „Wege" durchklicken: aus → Fuß → Rad → Bus → alle.
func _on_net() -> void:
	_net = NET_CYCLE[(NET_CYCLE.find(_net) + 1) % NET_CYCLE.size()]
	_net_button.text = _net_label(_net)
	if _map != null:
		_map.set_net(_net)


func _update_mode_buttons() -> void:
	for id: String in _mode_buttons:
		var b: Button = _mode_buttons[id]
		b.modulate = Palette.ORANGE if id == _mode else Color.WHITE


func _on_pin(id: String) -> void:
	_selected = id
	_refresh_detail()


## Eine gemeinsame Vorschau fuer Detailtext, Button und den letzten Check vor
## der Animation. Fahrgeld ist Teil der Reisefreigabe, wird aber erst beim
## tatsaechlichen Ortswechsel abgebucht.
func _travel_preview(id: String) -> Dictionary:
	var result: Dictionary = TownManager.travel_preview(GameManager.current_location_id, id, _mode, true)
	if bool(result.get("ok", false)) and int(result.get("dm", 0)) > int(PlayerStats.geld):
		return {"ok": false, "slots": int(result.get("slots", 0)),
			"minutes": int(result.get("minutes", 0)),
			"dm": int(result.get("dm", 0)),
			"reason": Loc.t("ui.map_window.kein_geld_furs_ticket_d_dm", "Kein Geld fürs Ticket (%d DM).") % int(result.get("dm", 0))}
	if bool(result.get("ok", false)) and not _target_job_id.is_empty() and id == _selected:
		var job: Dictionary = JobManager.job_by_id(_target_job_id)
		if not job.is_empty() and str(job.get("location", "")) == id:
			var arrival: Dictionary = JobManager.arrival_gate(job, id, int(result.get("minutes", 0)))
			if not bool(arrival.get("ok", false)):
				return {"ok": false, "slots": int(result.get("slots", 0)),
					"minutes": int(result.get("minutes", 0)), "dm": int(result.get("dm", 0)),
					"reason": str(arrival.get("reason", ""))}
	return result


## Ein bereits offenes Kartenfenster kann vom Arbeitsheft gezielt auf eine
## Schicht fokussiert werden. Das vermeidet Toggle-Schliessen und bewahrt den
## verbindlichen Ankunftscheck auch bei einem nachtraeglichen Moduswechsel.
func focus_destination(target: String, preferred_mode: String = "", job_id: String = "") -> void:
	if preferred_mode in MODES and bool(TownManager.mode_unlocked(preferred_mode).get("ok", false)):
		_mode = preferred_mode
	_selected = target
	_target_job_id = job_id
	if _map != null:
		_map.set_travel_mode(_mode)
	_update_mode_buttons()
	_refresh_detail()


func _refresh_detail() -> void:
	if _map != null:
		_map.selected_id = _selected
		_map.queue_redraw()
	if _selected == "":
		_detail.text = Loc.t("ui.map_window.wahle_einen_ort_auf_karte", "Wähle einen Ort auf der Karte.")
		_go_button.disabled = true
		return
	var location_name: String = TownManager.display_name(_selected)
	var dist: String = TownManager.district_name(TownManager.district_of(_selected))
	var lines: Array = ["[b]%s[/b]  ·  %s" % [location_name, dist]]

	if _selected == GameManager.current_location_id:
		lines.append(Loc.t("ui.map_window.here_now", "Hier bist du gerade."))
		_go_button.disabled = true
	elif not TownManager.is_live(_selected):
		var status: String = str(TownManager.location(_selected).get("status", "planned"))
		lines.append("[color=#999999]%s[/color]" % (Loc.t(
			"ui.map_window.not_on_map_yet", "Noch nicht auf deinem Stadtplan verzeichnet.") if status == "planned"
			else Loc.t("ui.map_window.available_later", "Dieser Ort wird in einem späteren Kalenderabschnitt zugänglich.")))
		_go_button.disabled = true
	else:
		var cost: Dictionary = _travel_preview(_selected)
		if not cost["ok"]:
			lines.append("[color=#C87A3A]%s[/color]" % cost["reason"])
			_go_button.disabled = true
		else:
			var minutes: int = int(cost.get("travel_minutes", cost.get("minutes", 0)))
			var wait_minutes: int = int(cost.get("wait_minutes", 0))
			var dm: int = int(cost["dm"])
			var fare: String = "" if dm == 0 else Loc.t("ui.map_window.fare_suffix", ", %d DM") % dm
			var wait_suffix := "" if wait_minutes <= 0 else Loc.t(
				"ui.map_window.wait_suffix", " · wartet %d Min. bis zur Öffnung") % wait_minutes
			lines.append(Loc.t("ui.map_window.reachable_trip_minutes",
				"[color=#7FD48A]● erreichbar[/color] · Weg: %d Min.%s%s") % [
				minutes, wait_suffix, fare])
			if not _target_job_id.is_empty():
				var target_job: Dictionary = JobManager.job_by_id(_target_job_id)
				if not target_job.is_empty() and str(target_job.get("location", "")) == _selected:
					lines.append(Loc.t("ui.map_window.shift_ready_on_arrival",
						"[color=#7FD48A]✓ Schicht ist bei Ankunft startbereit.[/color]"))
			_go_button.disabled = false
	if QuestManager.active_location_ids().has(_selected):
		lines.append(Loc.t("ui.map_window.active_mission_here", "[color=#FFD15C]◉ Hier wartet eine aktive Mission.[/color]"))
	# Wer ist gerade da? Orts-bewusst (present_now), damit die Karte dasselbe zeigt
	# wie der Ort selbst: generische Orte ganztags, Schulhof/Wald nur nachmittags.
	var present: Array = NPCManager.present_now(_selected)
	if not present.is_empty():
		var names: Array = present.map(func(nid: String) -> String:
			return str(NPCManager.get_npc(nid).get("name", nid)))
		lines.append(Loc.t("ui.map_window.people_here", "[color=#6Fae6F]Hier: %s[/color]") % ", ".join(names))
	_detail.text = "\n".join(lines)


func _on_go() -> void:
	var target := _selected
	if target == "" or target == GameManager.current_location_id:
		return
	# Unmittelbar vor der sichtbaren Fahrt erneut pruefen. Bei veraendertem
	# Kalender/Geld bleibt der Marker stehen und es startet keine Fake-Reise.
	var preview := _travel_preview(target)
	if not bool(preview.get("ok", false)):
		UIManager.toast(str(preview.get("reason", Loc.t("ui.map_window.cannot_go_there", "Dorthin kannst du gerade nicht."))))
		_refresh_detail()
		return
	# Erst die Straßen-Route abfahren (Fuß/Rad/Bus), dann ankommen.
	_go_button.disabled = true
	_go_button.text = Loc.t("ui.map_window.unterwegs", "unterwegs …")
	_travelling = true
	_map.start_travel(GameManager.current_location_id, target, _mode, func() -> void:
		queue_free()
		GameManager.goto_location(target, true, _mode))


func _mode_label(mode_id: String) -> String:
	match mode_id:
		"walk": return Loc.t("ui.map_window.mode_walk", "🚶 Fuß")
		"bike": return Loc.t("ui.map_window.mode_bike", "🚲 Rad")
		"bus": return Loc.t("ui.map_window.mode_bus", "🚌 Bus")
		"car": return Loc.t("ui.map_window.mode_car", "🚗 Auto")
	return mode_id


func _net_label(net_id: String) -> String:
	match net_id:
		"foot": return Loc.t("ui.map_window.net_foot", "Wege: 🚶 Fuß")
		"bike": return Loc.t("ui.map_window.net_bike", "Wege: 🚲 Rad")
		"bus": return Loc.t("ui.map_window.net_bus", "Wege: 🚌 Bus+H")
		"all": return Loc.t("ui.map_window.net_all", "Wege: alle")
	return Loc.t("ui.map_window.wege_aus", "Wege: aus")


# ---------------------------------------------------------------- Karten-View
