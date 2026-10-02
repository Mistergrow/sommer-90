class_name SummerDiskWindow
extends RetroWindow
## Kleine, physische Zusammenstellung statt eines Dialog-Hakens: Der Spieler
## waehlt eigene Fundstuecke, beschriftet eine Leerdiskette und friert die
## Auswahl als gespeicherten Snapshot ein. Quellen bleiben in der Sammlung.

const MAX_ENTRIES := 4

var _title_edit: LineEdit
var _list: VBoxContainer
var _selected: Dictionary = {}
var _status: Label


func _init() -> void:
	title = Loc.t("ui.summer_disk_window.meine_sommerdisk_zusammenstellen", "MEINE SOMMERDISK · ZUSAMMENSTELLEN")
	win_size = Vector2(720, 590)


func _ready() -> void:
	super._ready()
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = Loc.t("ui.summer_disk_window.waehle_2_4_dinge_aus_deiner", "Waehle 2–4 Dinge aus deiner Box. Die Quellen bleiben erhalten; eine leere DD-Diskette wird als deine persönliche Tauschdisk beschrieben.")
	note.custom_minimum_size.y = 44
	content.add_child(note)
	_title_edit = LineEdit.new()
	_title_edit.placeholder_text = Loc.t("ui.summer_disk_window.mein_sommer_d", "MEIN SOMMER %d") % TimeManager.year
	_title_edit.text = Loc.t("ui.summer_disk_window.mein_sommer_d", "MEIN SOMMER %d") % TimeManager.year
	_title_edit.max_length = 24
	content.add_child(_title_edit)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	content.add_child(scroll)
	_status = Label.new()
	content.add_child(_status)
	var row := HBoxContainer.new()
	row.add_child(make_button(Loc.t("ui.summer_disk_window.diskette_zusammenstellen", "DISKETTE ZUSAMMENSTELLEN"), _assemble))
	row.add_child(make_button(Loc.t("ui.summer_disk_window.box_aktualisieren", "BOX AKTUALISIEREN"), _rebuild))
	content.add_child(row)
	_rebuild()


func _candidates() -> Array:
	var result: Array = []
	for disk: Disk in DiskManager.media_disks():
		if disk.condition <= 0 or disk.content_type in ["leer", "system"]:
			continue
		if disk.release_role == "summer_disk":
			continue
		result.append(disk)
	result.sort_custom(func(a: Disk, b: Disk) -> bool: return a.display_name() < b.display_name())
	return result


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	var available := {}
	for disk: Disk in _candidates():
		available[disk.uid] = true
		var check := CheckButton.new()
		check.text = Loc.t("ui.summer_disk_window.s_s_zustand_d", "%s  ·  %s  ·  Zustand %d%%") % [disk.display_name(), disk.content_type.to_upper(), disk.condition]
		check.button_pressed = bool(_selected.get(disk.uid, false))
		check.toggled.connect(_toggle_entry.bind(disk.uid, check))
		_list.add_child(check)
	for uid in _selected.keys():
		if not available.has(uid):
			_selected.erase(uid)
	_refresh_status()


func _toggle_entry(on: bool, uid: String, button: CheckButton) -> void:
	if on and _selected.size() >= MAX_ENTRIES:
		button.set_pressed_no_signal(false)
		UIManager.toast(Loc.t("ui.summer_disk_window.auf_sommerdisk_passen_in_diesem_entwurf", "Auf eine Sommerdisk passen in diesem Entwurf höchstens vier Erinnerungen."))
		return
	if on:
		_selected[uid] = true
	else:
		_selected.erase(uid)
	_refresh_status()


func _refresh_status() -> void:
	_status.text = Loc.t("ui.summer_disk_window.d_d_ausgewahlt_d_leere_dd", "%d/%d AUSGEWÄHLT · %d LEERE DD-DISKETTEN") % [
		_selected.size(), MAX_ENTRIES, DiskManager.blank_disks().filter(
			func(d: Disk) -> bool: return d.dtype == "DD").size()]


func _assemble() -> void:
	if _selected.size() < 2:
		UIManager.toast(Loc.t("ui.summer_disk_window.wahle_mindestens_zwei_dinge_damit_daraus", "Wähle mindestens zwei Dinge, damit daraus wirklich eine Zusammenstellung wird."))
		return
	var title_text := _title_edit.text.strip_edges().to_upper()
	if title_text.length() < 3:
		UIManager.toast(Loc.t("ui.summer_disk_window.gib_deiner_sommerdisk_einen_lesbaren_titel", "Gib deiner Sommerdisk einen lesbaren Titel."))
		return
	var blank: Disk = null
	for candidate: Disk in DiskManager.blank_disks():
		if candidate.dtype == "DD" and (blank == null or candidate.condition > blank.condition):
			blank = candidate
	if blank == null:
		UIManager.toast(Loc.t("ui.summer_disk_window.dir_fehlt_leere_dd_diskette", "Dir fehlt eine leere DD-Diskette."))
		return
	if not PlayerStats.use_energy(4):
		UIManager.toast(Loc.t("ui.summer_disk_window.zu_mude_zum_zusammenstellen_beschriften_prufen", "Zu müde zum Zusammenstellen, Beschriften und Prüfen."))
		return
	var entries: Array = []
	for disk: Disk in DiskManager.media_disks():
		if _selected.has(disk.uid):
			entries.append({"source_uid": disk.uid, "title": disk.display_name(),
				"content_type": disk.content_type, "condition_snapshot": disk.condition})
	blank.content_type = "compilation"
	blank.content_title = title_text
	blank.label = title_text.left(24)
	blank.labeled = true
	blank.checked = true
	blank.rarity = "personal"
	blank.memory = "Im Sommer %d selbst zusammengestellt" % TimeManager.year
	blank.release_serial = "SUMMER-%d-%s" % [TimeManager.year, blank.uid]
	blank.release_role = "summer_disk"
	blank.release_data = {"title": title_text, "year": TimeManager.year,
		"date": TimeManager.date_string(), "entries": entries}
	DiskManager.disks_changed.emit()
	QuestManager.note_action("assemble_summer_disk")
	UIManager.toast(Loc.t("ui.summer_disk_window.s_ist_beschrieben_beschriftet_gepruft", "»%s« ist beschrieben, beschriftet und geprüft.") % title_text)
	_selected.clear()
	_rebuild()
