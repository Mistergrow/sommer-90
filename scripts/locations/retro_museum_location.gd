extends LocationBase
## RETRO-MUSEUM 1999 — begehbarer, spielstandgetriebener Dekadenabschluss.
##
## Das gerenderte Jugendzimmer ist nur die Bühne. Jeder Ausstellungsbereich
## öffnet echte Systeme des Spielstands; der Ort besitzt keine Parallelkopie von
## Sammlung, Erinnerungen, MODs oder Hardware und kann daher nie veralten.

const C_AMBER := Color8(255, 180, 42)
const C_CYAN := Color8(75, 209, 224)
const C_GREEN := Color8(91, 235, 128)

var _status: Label


func background_base() -> String:
	return "LOCATION_RETRO_MUSEUM_MASTER"


func uses_generic_npcs() -> bool:
	return false


func _build() -> void:
	cover_mode = true
	cover_anchor = Vector2(0.5, 0.5)
	virtual_size = Vector2(1672, 941)
	_build_museum_hud()
	if not has_background():
		add_hotspot(Rect2(20, 90, 300, 650), Loc.t("place.retro_museum_location.sammlervitrine", "Sammlervitrine"), UIManager.open_collection_cabinet)
		add_hotspot(Rect2(350, 90, 260, 320), Loc.t("place.retro_museum_location.trophaen_erinnerungen", "Trophäen & Erinnerungen"), UIManager.open_trophy_wall)
		add_hotspot(Rect2(610, 210, 520, 470), Loc.t("place.retro_museum_location.hardwarechronik", "Hardwarechronik"), func() -> void:
			UIManager.open_retro_museum_archive("hardware"))
		add_hotspot(Rect2(1140, 210, 250, 470), Loc.t("place.retro_museum_location.mod_horplatz", "MOD-Hörplatz"), UIManager.open_music)
		add_hotspot(Rect2(1400, 80, 250, 680), Loc.t("place.retro_museum_location.szene_sammlung", "Szene & Sammlung"), func() -> void:
			UIManager.open_retro_museum_archive("culture"))
	else:
		# Bildgenau auf LOCATION_RETRO_MUSEUM_MASTER_V01 (1672×941).
		add_hotspot(Rect2(0, 75, 350, 735), Loc.t("place.retro_museum_location.ovp_vitrine_deine_originalboxen", "OVP-Vitrine · deine Originalboxen"),
			UIManager.open_collection_cabinet)
		add_hotspot(Rect2(330, 70, 245, 345), Loc.t("place.retro_museum_location.trophaenwand_erfolge_erinnerungen", "Trophäenwand · Erfolge & Erinnerungen"),
			UIManager.open_trophy_wall)
		add_hotspot(Rect2(475, 315, 735, 405), Loc.t("place.retro_museum_location.rechnerchronik_ocs_ecs_aga_ram_hdd", "Rechnerchronik · OCS, ECS, AGA, RAM & HDD"),
			func() -> void: UIManager.open_retro_museum_archive("hardware"))
		add_hotspot(Rect2(1180, 300, 270, 445), Loc.t("place.retro_museum_location.mod_horplatz_dein_musikarchiv", "MOD-Hörplatz · dein Musikarchiv"),
			UIManager.open_music)
		add_hotspot(Rect2(1430, 55, 242, 755), Loc.t("place.retro_museum_location.dekadenarchiv_szene_hefte_sammlung", "Dekadenarchiv · Szene, Hefte & Sammlung"),
			func() -> void: UIManager.open_retro_museum_archive("culture"))
		add_hotspot(Rect2(430, 715, 850, 226), Loc.t("place.retro_museum_location.jahreschronik_1990_1999", "Jahreschronik 1990–1999"),
			func() -> void: UIManager.open_retro_museum_archive("years"))
	_connect_exhibit_hover()
	if GameManager.state == GameManager.State.PLAYING:
		GameManager.flags["retro_museum_visited"] = true
		# Der Meilenstein wird erst nach dem ersten vollständig gerenderten Bild
		# geschrieben. So zeigt sein automatisches Erinnerungsfoto tatsächlich
		# das Museum statt des ausblendenden Vorgängerorts.
		_record_first_visit.call_deferred()


func _record_first_visit() -> void:
	await get_tree().process_frame
	if not is_inside_tree() or GameManager.state != GameManager.State.PLAYING:
		return
	MemoryManager.record_once("retro_museum_visit",
		"zum ersten Mal durch das eigene Retro-Museum gegangen",
		"Dein Retro-Museum")


func _build_museum_hud() -> void:
	var plaque := PanelContainer.new()
	plaque.name = "MuseumPlaque"
	plaque.anchor_left = 0.5
	plaque.anchor_right = 0.5
	plaque.anchor_top = 0.0
	plaque.anchor_bottom = 0.0
	plaque.offset_left = -260
	plaque.offset_right = 260
	plaque.offset_top = 14
	plaque.offset_bottom = 82
	plaque.z_index = 42
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plaque_style := StyleBoxFlat.new()
	plaque_style.bg_color = Color(0.015, 0.021, 0.032, 0.91)
	plaque_style.border_color = Color(C_AMBER, 0.82)
	plaque_style.set_border_width_all(1)
	plaque_style.set_corner_radius_all(3)
	plaque_style.set_content_margin_all(8)
	plaque.add_theme_stylebox_override("panel", plaque_style)
	add_child(plaque)
	var plaque_col := VBoxContainer.new()
	plaque_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.add_child(plaque_col)
	var heading := Label.new()
	heading.text = Loc.t("place.retro_museum_location.dein_retro_museum_1990_1999", "DEIN RETRO-MUSEUM · 1990–1999")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 19)
	heading.add_theme_color_override("font_color", C_AMBER)
	heading.add_theme_constant_override("outline_size", 4)
	heading.add_theme_color_override("font_outline_color", Color.BLACK)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque_col.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = Loc.t("place.retro_museum_location.klick_auf_exponat_archiv_liest_deinen", "KLICK AUF EIN EXPONAT · DAS ARCHIV LIEST DEINEN ECHTEN SPIELSTAND")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", C_CYAN)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque_col.add_child(subtitle)

	var lower := PanelContainer.new()
	lower.name = "MuseumNavigation"
	lower.anchor_left = 0.0
	lower.anchor_right = 1.0
	lower.anchor_top = 1.0
	lower.anchor_bottom = 1.0
	lower.offset_left = 18
	lower.offset_right = -18
	lower.offset_top = -58
	lower.offset_bottom = -12
	lower.z_index = 43
	var lower_style := plaque_style.duplicate() as StyleBoxFlat
	lower_style.border_color = Color(C_CYAN, 0.64)
	lower.add_theme_stylebox_override("panel", lower_style)
	add_child(lower)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	lower.add_child(row)
	_status = Label.new()
	_status.name = "ExhibitStatus"
	_status.text = Loc.t("place.retro_museum_location.wahle_exponat", "WÄHLE EIN EXPONAT")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", C_GREEN)
	row.add_child(_status)
	var archive := Button.new()
	archive.name = "ArchiveButton"
	archive.text = Loc.t("place.retro_museum_location.gesamtes_archiv", "GESAMTES ARCHIV")
	archive.custom_minimum_size = Vector2(190, 30)
	archive.pressed.connect(func() -> void: UIManager.open_retro_museum_archive("years"))
	row.add_child(archive)
	var exit := Button.new()
	exit.name = "ExitMuseumButton"
	exit.text = Loc.t("place.retro_museum_location.zuruck_ins_zimmer", "ZURÜCK INS ZIMMER")
	exit.custom_minimum_size = Vector2(210, 30)
	exit.pressed.connect(_return_to_room)
	row.add_child(exit)


func _connect_exhibit_hover() -> void:
	for definition: Dictionary in _hotspot_defs:
		var button: Button = definition.get("button")
		if button == null:
			continue
		var exhibit_name := button.tooltip_text
		button.mouse_entered.connect(func() -> void:
			if is_instance_valid(_status):
				_status.text = Loc.t("place.retro_museum_location.ausstellung_s", "AUSSTELLUNG · %s") % exhibit_name.to_upper())
		button.mouse_exited.connect(func() -> void:
			if is_instance_valid(_status):
				_status.text = Loc.t("place.retro_museum_location.wahle_exponat", "WÄHLE EIN EXPONAT"))


func _return_to_room() -> void:
	GameManager.goto_location("room", false)
