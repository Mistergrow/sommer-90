extends RetroWindow
## Diskettenbox-Fenster: Liste aller Disketten mit Prüfen/Etikett/Backup/
## Sortieren/Wegwerfen. Kernstück des MVP-Loops "sortieren & archivieren".

const PlayableGameRegistry := preload("res://scripts/games/playable_game_registry.gd")
const InsertCatalog := preload("res://scripts/data/software_insert_catalog.gd")
const DiskAccessPolicy := preload("res://scripts/ui/disk_access_policy.gd")
const DiskCatalog := preload("res://scripts/ui/disk_catalog_rules.gd")
const DiskRepairMinigameScript := preload("res://scripts/ui/disk_repair_minigame.gd")

var _list: ItemList
var _info: Label
var _art: TextureRect
var _header: Label
var _access: Label
var _label_row: HBoxContainer
var _label_edit: LineEdit
var _trash_armed := false
var _trash_button: Button
var _bytewerk_button: Button
var _inserts_button: Button
var _print_button: Button
var _sort_button: Button
var _play_button: Button
var _check_button: Button
var _copy_button: Button
var _label_button: Button
var _design_button: Button
var _backup_button: Button
var _rescue_button: Button
var _repair_button: Button
var _computer_buttons: Array[Button] = []
var _search: LineEdit
var _filter: OptionButton
var _visible_disks: Array = []


func _init() -> void:
	title = Loc.t("ui.disk_box_window.diskettenbox_archivverzeichnis", "DISKETTENBOX · ARCHIVVERZEICHNIS")
	win_size = Vector2(780, 500)
	chrome_accent = Palette.BLUE


func _ready() -> void:
	super._ready()
	DiskManager.disks_changed.connect(_refresh)
	InventoryManager.inventory_changed.connect(_refresh_info)
	UIManager.seat_changed.connect(_on_access_changed)
	UIManager.power_changed.connect(_on_access_changed)
	GameManager.location_changed.connect(_on_access_changed)
	PlayerStats.stats_changed.connect(_on_access_changed)

	# Kopfzeile: Belegung, Sammlungswert, Sortier-Knopf
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 10)
	_header = Bezel.dim_label("", 12)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(_header)
	_sort_button = make_button(Loc.t("ui.disk_box_window.sortieren", "Sortieren"), _on_sort)
	head_row.add_child(_sort_button)
	content.add_child(head_row)

	# Archivleiste: hunderte Medien bleiben über Suche und fachliche Filter
	# beherrschbar; PD-/Coverdisks verschwinden nicht mehr zwischen Spielen.
	var directory := HBoxContainer.new()
	directory.add_theme_constant_override("separation", 6)
	_search = LineEdit.new()
	_search.placeholder_text = Loc.t("ui.disk_box_window.diskette_inhalt_label_oder_notiz_suchen", "Diskette, Inhalt, Label oder Notiz suchen …")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text: String) -> void: _refresh())
	directory.add_child(_search)
	_filter = OptionButton.new()
	for label in ["ALLE", "SPIELE", "SZENE", "TOOLS/DATEN", "PD/COVERDISKS", "MUSIK", "SYSTEM", "ECHTE ORIGINALE", "KOPIEN", "LEER"]:
		_filter.add_item(label)
	_filter.item_selected.connect(func(_index: int) -> void: _refresh())
	directory.add_child(_filter)
	content.add_child(directory)
	_access = Bezel.dim_label("", 11)
	_access.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_access)

	# Hauptbereich: Liste links, Details + Aktionen rechts
	var main_row := HBoxContainer.new()
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 8)
	content.add_child(main_row)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(360, 0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(18, 17)
	_list.item_selected.connect(func(_i: int) -> void: _refresh_info())
	main_row.add_child(_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	main_row.add_child(right)

	# Info-Text + Artwork-Vorschau (Original-Karton/gedrucktes Disk-Label) nebeneinander
	var info_row := HBoxContainer.new()
	info_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_row.add_theme_constant_override("separation", 8)
	right.add_child(info_row)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info.add_theme_font_size_override("font_size", 13)
	info_row.add_child(_info)
	_art = TextureRect.new()
	_art.custom_minimum_size = Vector2(112, 150)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # WICHTIG: Textur nicht nativ groß
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_art.visible = false
	info_row.add_child(_art)

	var actions := GridContainer.new()
	actions.columns = 3
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	_play_button = make_button(Loc.t("ui.disk_box_window.starten", "Starten"), _on_play)
	_check_button = make_button(Loc.t("ui.disk_box_window.df0_prufen", "DF0: Prüfen"), _on_check)
	_copy_button = make_button(Loc.t("ui.disk_box_window.x_copy", "X-COPY"), _on_copy)
	actions.add_child(_play_button)
	actions.add_child(_check_button)
	actions.add_child(_copy_button)
	_bytewerk_button = make_button(Loc.t("ui.disk_box_window.bytewerk", "BYTEWERK"), _on_bytewerk)
	actions.add_child(_bytewerk_button)
	_label_button = make_button(Loc.t("ui.disk_box_window.etikett", "Etikett"), _on_label)
	_design_button = make_button(Loc.t("ui.disk_box_window.gestalten", "Gestalten"), _on_design_label)
	actions.add_child(_label_button)
	actions.add_child(_design_button)
	_print_button = make_button(Loc.t("ui.disk_box_window.drucken", "Drucken"), _on_print_label)
	actions.add_child(_print_button)
	_inserts_button = make_button(Loc.t("ui.disk_box_window.beilagen", "Beilagen"), _on_inserts)
	actions.add_child(_inserts_button)
	_backup_button = make_button(Loc.t("ui.disk_box_window.backup", "Backup"), _on_backup)
	_rescue_button = make_button(Loc.t("ui.disk_box_window.retten", "Retten"), _on_rescue)
	_repair_button = make_button(Loc.t("ui.disk_box_window.reparieren", "Reparieren"), _on_repair_disk)
	actions.add_child(_backup_button)
	actions.add_child(_rescue_button)
	actions.add_child(_repair_button)
	_trash_button = make_button(Loc.t("ui.disk_box_window.wegwerfen", "Wegwerfen"), _on_trash)
	actions.add_child(_trash_button)
	_computer_buttons = [_play_button, _check_button, _copy_button, _bytewerk_button,
		_design_button, _print_button, _backup_button, _rescue_button, _repair_button]
	right.add_child(actions)

	# Etikett-Eingabezeile (erst sichtbar, wenn "Etikett" gedrückt wird)
	_label_row = HBoxContainer.new()
	_label_row.visible = false
	_label_edit = LineEdit.new()
	_label_edit.max_length = 30
	_label_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label_edit.text_submitted.connect(func(_t: String) -> void: _apply_label())
	_label_row.add_child(_label_edit)
	_label_row.add_child(make_button(Loc.t("ui.disk_box_window.ok", "OK"), _apply_label))
	right.add_child(_label_row)

	_refresh()
	_refresh_access()


func _selected_disk() -> Disk:
	var selection := _list.get_selected_items()
	if selection.is_empty() or selection[0] >= _visible_disks.size():
		return null
	return _visible_disks[selection[0]]


func _on_access_changed(_value: Variant = null) -> void:
	_refresh_access()


func _refresh_access() -> void:
	if _access == null:
		return
	var archive: Dictionary = DiskAccessPolicy.archive_mutation()
	var computer: Dictionary = DiskAccessPolicy.workbench_media(UIManager)
	var archive_ok := bool(archive.get("ok", false))
	var computer_ok := bool(computer.get("ok", false))
	var disk := _selected_disk()
	if computer_ok:
		_access.text = Loc.t("ui.disk_box_window.amiga_online_df0_aktionen_laufen_ueber", "● AMIGA ONLINE · DF0:-AKTIONEN LAUFEN UEBER DEN ECHTEN X-COPY-/WERKBANK-PFAD")
		_access.modulate = Color8(112, 230, 142)
	elif archive_ok:
		_access.text = Loc.t("ui.disk_box_window.physische_box_sortieren_beschriften_rechneraktionen_s", "● PHYSISCHE BOX · SORTIEREN UND BESCHRIFTEN · RECHNERAKTIONEN: %s") % \
			str(computer.get("reason", "Amiga nicht bereit.")).to_upper()
		_access.modulate = Color8(242, 184, 76)
	else:
		_access.text = Loc.t("ui.disk_box_window.nur_archivansicht_s", "○ NUR ARCHIVANSICHT · %s") % str(archive.get("reason", "Box nicht erreichbar.")).to_upper()
		_access.modulate = Color8(146, 158, 174)
	var computer_reason := str(computer.get("reason", "Amiga nicht bereit."))
	for button: Button in _computer_buttons:
		button.disabled = not computer_ok or disk == null
		button.tooltip_text = Loc.t("ui.disk_box_window.amiga_workbench_bereit", "Amiga/Workbench bereit.") if computer_ok else computer_reason
	_sort_button.disabled = not archive_ok or DiskManager.media_count() < 2
	_label_button.disabled = not archive_ok or disk == null
	_inserts_button.disabled = not archive_ok or disk == null
	_trash_button.disabled = not archive_ok or disk == null
	if disk != null:
		_play_button.disabled = not computer_ok or disk.content_type == "leer" or disk.condition <= 0
		_copy_button.disabled = not computer_ok or disk.content_type == "leer" or DiskManager.blank_disks().is_empty()
		_backup_button.disabled = not computer_ok or disk.content_type == "leer" or DiskManager.blank_disks().is_empty()
	_refresh_bytewerk_button(disk)
	_refresh_inserts_button(disk)
	_refresh_print_access()
	_refresh_repair_access(disk, computer_ok, computer_reason)


func _refresh() -> void:
	var keep := _selected_disk()
	_list.clear()
	_visible_disks = DiskManager.media_disks().filter(_matches_directory)
	for disk: Disk in _visible_disks:
		var suffix := ""
		if disk.condition <= 0:
			suffix = " [DEFEKT]"
		elif disk.content_type == "leer":
			suffix = " [leer]"
		elif PlayableGameRegistry.is_registered(disk.software_id) and DiskManager.has_complete_software(disk.software_id):
			suffix = " [SPIELBAR]"
		elif disk.content_type == "spiel" and disk.software_id != "" and not DiskManager.has_complete_software(disk.software_id):
			suffix = " [SATZ UNVOLLSTÄNDIG]"
		var type_tag := _directory_type(disk)
		var protection := "M" if disk.format_locked() else ("P" if disk.write_protected else "W")
		var line := "%-30s  │ %-8s │ %s%s" % [disk.display_name().left(30), type_tag, protection, suffix]
		var index := _list.add_item(line,
			Sprites.disk_icon(Palette.disk_color(disk.color)))
		if keep != null and disk.uid == keep.uid:
			_list.select(index)
	var pd_media := DiskManager.media_disks().filter(func(disk: Disk) -> bool:
		return DiskCatalog.is_pd_coverdisk(disk)).size()
	_header.text = Loc.t("ui.disk_box_window.medien_d_d_ovp_vitrine_d", "MEDIEN %d/%d · OVP-VITRINE %d · TREFFER %d · PD-HEFTE %d · %s") % [
		DiskManager.media_count(), DiskManager.capacity(), DiskManager.boxed_collection().size(),
		_visible_disks.size(), pd_media,
		DiskManager.SORT_MODES[DiskManager.sort_mode].to_upper()]
	_refresh_info()


func _matches_directory(disk: Disk) -> bool:
	if disk == null or disk.is_boxed_package():
		return false
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	if query != "":
		var haystack := "%s %s %s %s %s" % [disk.display_name(), disk.content_title, disk.label, disk.notes, disk.memory]
		if query not in haystack.to_lower():
			return false
	var mode := _filter.selected if _filter != null else 0
	match mode:
		1: return DiskCatalog.is_game(disk)
		2: return DiskCatalog.is_scene(disk)
		3: return DiskCatalog.is_tool_data(disk)
		4: return DiskCatalog.is_pd_coverdisk(disk)
		5: return DiskCatalog.is_music(disk)
		6: return DiskCatalog.is_system(disk)
		7: return disk.format_locked()
		8: return disk.is_player_made_copy()
		9: return DiskCatalog.is_blank(disk)
	return true


func _is_pd_coverdisk(disk: Disk) -> bool:
	return DiskCatalog.is_pd_coverdisk(disk)


func _directory_type(disk: Disk) -> String:
	return DiskCatalog.category(disk)


func _refresh_info() -> void:
	var disk := _selected_disk()
	if disk == null:
		_info.text = Loc.t("ui.disk_box_window.wahle_diskette_aus_box_n_ntipp", "Wähle eine Diskette aus der Box.\n\nTipp: Erst prüfen — der Zustand\nunbekannter Disketten ist Glückssache.")
		if _art != null:
			_art.visible = false
			_art.texture = null
		_refresh_access()
		return
	var lines := [
		disk.display_name(),
		"%s · %s · %d KB" % [disk.brand, disk.dtype, disk.capacity_kb],
		disk.condition_text(),
		"Inhalt: %s" % (disk.content_title if disk.content_title != "" else "leer"),
		"Rarität: %s · Wert: %d DM" % [disk.rarity, disk.value()],
		"Schreibschutz: %s" % disk.write_protect_text(),
	]
	if disk.disk_count > 1:
		var missing := DiskManager.missing_software_parts(disk.software_id)
		lines.append("Datenträger: Diskette %d von %d" % [disk.disk_number, disk.disk_count])
		if missing.is_empty():
			lines.append("Satz vollständig — alle %d Disketten vorhanden" % disk.disk_count)
		else:
			var missing_labels: Array[String] = []
			for number: int in missing:
				missing_labels.append(str(number))
			lines.append("Satz unvollständig — fehlt: %s" % ", ".join(missing_labels))
	if disk.program_id != "":
		var pname: String = str(ProgramLibrary.get_program(disk.program_id).get("display_name", disk.program_id))
		lines.append("▶ Programm — »Starten« öffnet %s" % pname)
	elif PlayableGameRegistry.is_registered(disk.software_id) and DiskManager.has_complete_software(disk.software_id):
		lines.append("▶ VOLLSPIEL — »Starten« bootet direkt von Diskette")
	if disk.content_type != "leer":
		lines.append("Herkunft: %s" % _provenance_text(disk))
	if InsertCatalog.has_software(disk.software_id):
		lines.append("Beilagen: %s" % InsertCatalog.status_text(disk.software_id))
	if disk.color == "yellow":
		lines.append("GELB-CODE: BYTEWERK · ARBEITSKOPIE / RELEASE")
	elif disk.color == "purple":
		lines.append("LILA-CODE: AAA-ORIGINAL · SAMMLERSTÜCK")
	elif disk.color == "red" and disk.is_game_master():
		lines.append("ROT-CODE: MASTER / QUELLE · NICHT VERKAUFEN")
	elif disk.content_type == "spiel" and disk.is_player_made_copy():
		lines.append("KOPIE: %d. GENERATION · Farbe der Leerdiskette" % maxi(1, disk.copy_generation))
	if disk.checked and disk.virus:
		lines.append("⚠ VIRUS auf der Diskette!")
	if disk.content_type == "mystery" and disk.label.strip_edges().is_empty() \
			and disk.content_title.strip_edges() in ["", "???"]:
		var requirement: Dictionary = QuestManager.disk_requirement(disk)
		if bool(requirement.get("required", false)):
			lines.append("◆ AUFTRAGSDISK — %s" % str(requirement.get("text",
				"Diese konkrete Diskette wird noch benötigt.")))
		elif (QuestManager.is_active("q_alex_find") \
				and QuestManager.stage("q_alex_find") == 1) \
				or QuestManager.is_done("q_alex_find"):
			lines.append("◆ ALEX NIMMT DEN FUND — Di/Do bei ihm · Sa auf dem Flohmarkt")
	if disk.media_repairs > 0:
		lines.append("Medienwerkstatt: %d× stabilisiert · letzter Zustand %d%%" % [
			disk.media_repairs, disk.condition])
	if disk.notes != "":
		lines.append("Notiz: %s" % disk.notes)
	if disk.memory != "":
		lines.append("Erinnerung: %s" % disk.memory)
	# Artwork-Vorschau: Original-Karton → Box-Front · lose Original-Disk → fertige
	# Diskette mit gedrucktem Label (DiskComposer, Position aus dem Disk-Editor) ·
	# Kopie → nackte Master-Disk (KEIN gedrucktes Label, nur ihr Etikett).
	if _art != null:
		var tex: Texture2D = null
		if disk.content_type != "leer":
			match disk.provenance:
				"original_box":
					if disk.software_id != "":
						var a := SoftwareBible.acquisition_art(disk.software_id, "box")
						if a.has("texture"):
							tex = a["texture"]
							lines.append("★ Original-Karton (OVP)")
				"original":
					tex = DiskComposer.composed_disk(disk.software_id, true, 256, disk.disk_number, disk.color)
					if tex != null and disk.software_id != "":
						lines.append("★ Original-Disk mit gedrucktem Label")
				_:
					tex = DiskComposer.composed_disk(disk.software_id, false, 256, disk.disk_number, disk.color)
		if tex != null:
			_art.texture = tex
			_art.visible = true
		else:
			_art.visible = false
			_art.texture = null
	_info.text = "\n".join(lines)
	_refresh_access()


func _refresh_bytewerk_button(disk: Disk) -> void:
	if _bytewerk_button == null:
		return
	var access: Dictionary = DiskAccessPolicy.workbench_media(UIManager)
	if not bool(access.get("ok", false)):
		_bytewerk_button.disabled = true
		_bytewerk_button.tooltip_text = str(access.get("reason", "Amiga nicht bereit."))
		return
	var manager := get_node_or_null("/root/SceneReleaseManager")
	if disk == null or manager == null or not manager.has_method("eligibility"):
		_bytewerk_button.disabled = true
		_bytewerk_button.tooltip_text = Loc.t("ui.disk_box_window.markiere_passende_gen_1_arbeitskopie", "Markiere eine passende Gen-1-Arbeitskopie.")
		return
	var result = manager.call("eligibility", disk)
	var ok := typeof(result) == TYPE_DICTIONARY and bool(result.get("ok", false))
	_bytewerk_button.disabled = not ok
	_bytewerk_button.tooltip_text = Loc.t("ui.disk_box_window.p_8_release_werkstatt_offnen", "P-8 Release-Werkstatt öffnen.") if ok else str(result.get("text", "Nicht geeignet."))


func _refresh_inserts_button(disk: Disk) -> void:
	if _inserts_button == null:
		return
	var access: Dictionary = DiskAccessPolicy.archive_mutation()
	var available := bool(access.get("ok", false)) and disk != null \
		and InsertCatalog.has_software(disk.software_id) \
		and InsertCatalog.owns_any(disk.software_id)
	_inserts_button.disabled = not available
	_inserts_button.tooltip_text = Loc.t("ui.disk_box_window.original_handbuch_bahnkarte_offnen", "Original-Handbuch und Bahnkarte öffnen.") if available \
		else str(access.get("reason", "Zu dieser Diskette liegen keine Beilagen im Inventar."))


## Herkunfts-Zeile der Kulturschicht: Original-OVP >> Original >> Kopie.
func _provenance_text(disk: Disk) -> String:
	match disk.provenance:
		"original_box":
			return "Original (Komplett-OVP!)"
		"original":
			return "Original"
	var text := "Kopie (%d. Generation)" % maxi(1, disk.copy_generation)
	match disk.patch_state:
		"bare": text += " · BYTEWERK-Arbeitskopie"
		"draft": text += " · BYTEWERK-Entwurf"
		"verified": text += " · BYTEWERK-Release"
		"legacy_scene": text += " · Legacy-Szene-Release"
		_:
			if disk.cracktro:
				text += " · Szene-Release"
	return text


func _on_play() -> void:
	var disk := _selected_disk()
	if disk == null:
		UIManager.toast(Loc.t("ui.disk_box_window.erst_diskette_auswahlen", "Erst eine Diskette auswählen."))
		return
	if not DiskAccessPolicy.require_workbench(UIManager, "Diskette starten"):
		return
	UIManager.close_window("win_diskbox")
	UIManager.play_disk_flow(disk)


## Kopieren fuehrt IMMER in X-COPY. Quelle und Ziel werden dort physisch
## eingelegt; das Archiv darf nie selbst eine unsichtbare Sofortkopie erzeugen.
func _on_copy() -> void:
	var source := _selected_disk()
	if source == null:
		UIManager.toast(Loc.t("ui.disk_box_window.erst_diskette_auswahlen", "Erst eine Diskette auswählen."))
		return
	if not DiskAccessPolicy.require_workbench(UIManager, "Kopieren"):
		return
	if DiskManager.blank_disks().is_empty():
		UIManager.toast(Loc.t("ui.disk_box_window.keine_leerdiskette_in_box_computerladen_hilft", "Keine Leerdiskette in der Box! Der Computerladen hilft."))
		return
	UIManager.open_disk_copy(source, "copy")


func _on_bytewerk() -> void:
	var selected := _selected_disk()
	if selected == null:
		UIManager.toast(Loc.t("ui.disk_box_window.erst_arbeitskopie_auswahlen", "Erst eine Arbeitskopie auswählen."))
		return
	if not DiskAccessPolicy.require_workbench(UIManager, "BYTEWERK"):
		return
	UIManager.open_scene_patch(selected)


func _on_inserts() -> void:
	var selected := _selected_disk()
	if not DiskAccessPolicy.require_archive("Beilagen"):
		return
	if selected == null or not InsertCatalog.owns_any(selected.software_id):
		UIManager.toast(Loc.t("ui.disk_box_window.zu_dieser_diskette_liegen_keine_beilagen", "Zu dieser Diskette liegen keine Beilagen im Inventar."))
		return
	UIManager.open_software_inserts(selected.software_id)


func _on_rescue() -> void:
	var selected := _selected_disk()
	if selected == null: UIManager.toast(Loc.t("ui.disk_box_window.erst_beschaedigte_diskette_auswaehlen", "Erst eine beschaedigte Diskette auswaehlen.")); return
	if not DiskAccessPolicy.require_workbench(UIManager, "Datenrettung"): return
	UIManager.open_disk_rescue(selected)


## Reparieren ist physische Medienpflege an derselben Diskette. „Retten“ bleibt
## der getrennte, nur-lesende Image-Pfad fuer angeschlagene Dateisysteme.
func _on_repair_disk() -> void:
	var selected := _selected_disk()
	if selected == null:
		UIManager.toast(Loc.t("ui.disk_box_window.erst_beschaedigte_diskette_auswaehlen", "Erst eine beschaedigte Diskette auswaehlen."))
		return
	if not DiskAccessPolicy.require_workbench(UIManager, "Diskette physisch reparieren"):
		return
	if not selected.checked:
		UIManager.toast(Loc.t("ui.disk_box_window.schritt_1_2_x_copy_prueft", "SCHRITT 1/2: X-COPY prueft Tracks und physischen Medienzustand."))
		UIManager.open_disk_copy(selected, "check")
		return
	UIManager.open_disk_repair(selected)


func _refresh_repair_access(disk: Disk, computer_ok: bool, computer_reason: String) -> void:
	if _repair_button == null:
		return
	if not computer_ok:
		_repair_button.text = Loc.t("ui.disk_box_window.reparieren", "Reparieren")
		_repair_button.disabled = true
		_repair_button.tooltip_text = computer_reason
		return
	var gate := DiskRepairMinigameScript.diagnosis_gate(disk)
	if bool(gate.get("ok", false)) and disk != null and not disk.checked:
		_repair_button.text = Loc.t("ui.disk_box_window.pruefen_reparatur", "PRUEFEN -> REPARATUR")
		_repair_button.disabled = false
		_repair_button.tooltip_text = Loc.t("ui.disk_box_window.schritt_1_x_copy_prueflauf_danach", "Schritt 1: X-COPY-Prueflauf. Danach erscheint der passende Werkstattzugang.")
		return
	_repair_button.text = Loc.t("ui.disk_box_window.reparieren", "Reparieren")
	gate = DiskRepairMinigameScript.can_start(disk)
	_repair_button.disabled = not bool(gate.get("ok", false))
	_repair_button.tooltip_text = Loc.t("ui.disk_box_window.grubers_physische_medienwerkstatt_oeffnen", "Grubers physische Medienwerkstatt oeffnen.") if not _repair_button.disabled \
		else str(gate.get("reason", "Reparatur nicht moeglich."))


func _on_sort() -> void:
	if not DiskAccessPolicy.require_archive("Disketten sortieren"):
		return
	UIManager.open_box_sort()


func _on_check() -> void:
	var disk := _selected_disk()
	if disk == null:
		UIManager.toast(Loc.t("ui.disk_box_window.erst_diskette_auswahlen", "Erst eine Diskette auswählen."))
		return
	if not DiskAccessPolicy.require_workbench(UIManager, "Diskette pruefen"):
		return
	UIManager.open_disk_copy(disk, "check")


func _on_label() -> void:
	var disk := _selected_disk()
	if disk == null:
		UIManager.toast(Loc.t("ui.disk_box_window.erst_diskette_auswahlen", "Erst eine Diskette auswählen."))
		return
	if not DiskAccessPolicy.require_archive("Diskette beschriften"):
		return
	_label_row.visible = not _label_row.visible
	if _label_row.visible:
		_label_edit.text = disk.label
		_label_edit.grab_focus()


## „Gestalten" → Etikett-Designer-Minispiel für die gewählte Diskette.
func _on_design_label() -> void:
	var disk := _selected_disk()
	if disk == null:
		UIManager.toast(Loc.t("ui.disk_box_window.erst_diskette_auswahlen", "Erst eine Diskette auswählen."))
		return
	if not DiskAccessPolicy.require_workbench(UIManager, "Etikett gestalten"):
		return
	UIManager.open_label_designer(disk)


func _apply_label() -> void:
	var disk := _selected_disk()
	if disk == null:
		return
	if not DiskAccessPolicy.require_archive("Diskette beschriften"):
		return
	var result := DiskManager.label_disk(disk, _label_edit.text)
	UIManager.toast(result["text"])
	_label_row.visible = false


## Archivbackup benutzt dieselbe sichtbare Track-/Laufwerkssequenz wie X-COPY,
## commitet am Ende jedoch die zentrale Archivfunktion (Quest-/Y2K-Semantik).
func _on_backup() -> void:
	var source := _selected_disk()
	if source == null:
		UIManager.toast(Loc.t("ui.disk_box_window.erst_diskette_auswahlen", "Erst eine Diskette auswählen."))
		return
	if not DiskAccessPolicy.require_workbench(UIManager, "Backup"):
		return
	if DiskManager.blank_disks().is_empty():
		UIManager.toast(Loc.t("ui.disk_box_window.keine_leerdiskette_in_box_computerladen_hilft", "Keine Leerdiskette in der Box! Der Computerladen hilft."))
		return
	UIManager.open_disk_copy(source, "backup")


## Wegwerfen mit zweistufiger Bestätigung (kein verstecktes Popup nötig).
func _on_trash() -> void:
	var disk := _selected_disk()
	if disk == null:
		UIManager.toast(Loc.t("ui.disk_box_window.erst_diskette_auswahlen", "Erst eine Diskette auswählen."))
		return
	if not DiskAccessPolicy.require_archive("Diskette wegwerfen"):
		return
	var quest_gate: Dictionary = QuestManager.disk_requirement(disk)
	if bool(quest_gate.get("required", false)):
		UIManager.toast(Loc.t("ui.disk_box_window.auftragsdisk_s", "AUFTRAGSDISK: %s") % str(quest_gate.get("text",
			"Diese Diskette wird noch benötigt.")))
		return
	if not _trash_armed:
		_trash_armed = true
		_trash_button.text = Loc.t("ui.disk_box_window.wirklich", "Wirklich?")
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			_trash_armed = false
			if is_instance_valid(_trash_button):
				_trash_button.text = Loc.t("ui.disk_box_window.wegwerfen", "Wegwerfen"))
		return
	_trash_armed = false
	_trash_button.text = Loc.t("ui.disk_box_window.wegwerfen", "Wegwerfen")
	DiskManager.remove_disk(disk)
	# Eine zuvor wegen voller Box wartende Questbelohnung bzw. Quest-Startdiskette
	# kann jetzt sofort und ohne zusätzlichen Tageswechsel zugestellt werden.
	QuestManager.evaluate()
	UIManager.toast(Loc.t("ui.disk_box_window.s_landet_im_mull_stiller_moment", "'%s' landet im Müll. Ein stiller Moment.") % disk.display_name())


## „Drucken" ist echte Peripherie. Handschrift bleibt ueber „Etikett" moeglich;
## ohne angeschlossenen Drucker darf diese Schaltflaeche nichts vortaeuschen.
func _on_print_label() -> void:
	var disk := _selected_disk()
	if disk == null:
		UIManager.toast(Loc.t("ui.disk_box_window.erst_diskette_wahlen", "Erst eine Diskette wählen."))
		return
	if not DiskAccessPolicy.require_workbench(UIManager, "Etikett drucken"):
		return
	if not PlayerStats.has_printer():
		UIManager.toast(Loc.t("ui.disk_box_window.kein_drucker_angeschlossen_von_hand_beschriften", "Kein Drucker angeschlossen. Von Hand beschriften geht über »Etikett«."))
		return
	UIManager.open_label_print(disk)


func _refresh_print_access() -> void:
	if _print_button == null:
		return
	var access: Dictionary = DiskAccessPolicy.workbench_media(UIManager)
	var printer_ready := bool(access.get("ok", false)) and PlayerStats.has_printer() \
		and _selected_disk() != null
	_print_button.disabled = not printer_ready
	if not bool(access.get("ok", false)):
		_print_button.tooltip_text = str(access.get("reason", "Amiga nicht bereit."))
	elif not PlayerStats.has_printer():
		_print_button.tooltip_text = Loc.t("ui.disk_box_window.kein_drucker_angeschlossen_etikett_nutzt_handschrift", "Kein Drucker angeschlossen — »Etikett« nutzt Handschrift.")
	else:
		_print_button.tooltip_text = Loc.t("ui.disk_box_window.etikett_mit_s_drucken", "Etikett mit %s drucken.") % PlayerStats.printer_name()
