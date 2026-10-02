extends Node
## DiskManager — verwaltet die Diskettensammlung des Spielers.
## Templates kommen aus data/disks.json; jede Diskette im Spiel ist eine
## eigene Disk-Instanz (scripts/data/disk.gd) mit Zustand und Geschichte.
##
## Aktionen (historische Archivierungs-Mechanik, siehe GDD Kap. 6):
## prüfen, etikettieren, sortieren, Sicherheitskopie der eigenen Sammlung.
##
## Seit dem Zeilenbudget-Split ist dieser Autoload die Fassade. Zustand, Signal
## und Sortierung bleiben hier; die Rumpfe liegen nach Zustaendigkeit getrennt in
## scripts/data/ und bekommen den Knoten als erstes Argument (Muster
## Wrapper-static). Die Teile laden sich NICHT gegenseitig — Quer-Aufrufe laufen
## immer ueber diese Fassade, dadurch ist kein preload-Zirkel moeglich.

signal disks_changed

const Defs := preload("res://scripts/autoload/disk_manager_defs.gd")
const Factory := preload("res://scripts/autoload/disk_factory.gd")
const BoxQuery := preload("res://scripts/autoload/disk_box_query.gd")
const BoxStore := preload("res://scripts/autoload/disk_box_store.gd")
const DriveActions := preload("res://scripts/autoload/disk_drive_actions.gd")
const DiskDiagnostics := preload("res://scripts/data/disk_diagnostics.gd")
const Persistence := preload("res://scripts/autoload/disk_manager_persistence.gd")
const SortOrder := preload("res://scripts/autoload/disk_sort_order.gd")

# Diese Werte werden von aussen ueber DiskManager gelesen und bleiben deshalb
# hier sichtbar, auch wenn sie in disk_manager_defs.gd definiert sind.
const EXT_DRIVE_ERROR_FACTOR := Defs.EXT_DRIVE_ERROR_FACTOR
const READ_DIRT_ERROR_FACTOR := Defs.READ_DIRT_ERROR_FACTOR
const WRITE_DIRT_ERROR_FACTOR := Defs.WRITE_DIRT_ERROR_FACTOR
const READ_ALIGNMENT_ERROR_FACTOR := Defs.READ_ALIGNMENT_ERROR_FACTOR
const WRITE_ALIGNMENT_ERROR_FACTOR := Defs.WRITE_ALIGNMENT_ERROR_FACTOR
const SORT_MODES := Defs.SORT_MODES
# Von _repair_legacy_catalog_identity weiter unten benutzt.
const COVERDISK_TEMPLATE_ID := Defs.COVERDISK_TEMPLATE_ID
const LEGACY_PD_TOOLS_TEMPLATE_ID := Defs.LEGACY_PD_TOOLS_TEMPLATE_ID

var templates: Dictionary = {}      # template_id -> Dictionary
var start_inventory: Array = []     # Template-IDs des Startinventars
var disks: Array = []               # Array[Disk] — die Diskettenbox
var sort_mode: int = 0
var _uid_counter: int = 0
var _set_uid_counter: int = 0


func _ready() -> void:
	_load_data()
	TimeManager.day_changed.connect(_on_day_changed)
	TimeManager.calendar_jumped.connect(_on_calendar_jumped)


func _load_data() -> void:
	# Auch ein Laden innerhalb derselben Editor-Session muss den aktuellen
	# Datenkatalog verwenden. Ohne Leeren blieben entfernte Templates als Geister
	# erhalten und neu gepatchte Questmedien waeren erst nach Prozessneustart da.
	templates = {}
	start_inventory = []
	var file := FileAccess.open("res://data/disks.json", FileAccess.READ)
	if file == null:
		push_error("disks.json fehlt!")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("disks.json ist kein gueltiges JSON-Objekt!")
		return
	var data: Dictionary = parsed
	for tpl in data.get("templates", []):
		templates[tpl["id"]] = tpl
	start_inventory = data.get("start_inventory", [])


func reset() -> void:
	disks = []
	_uid_counter = 0
	_set_uid_counter = 0
	sort_mode = 0
	for template_id in start_inventory:
		var disk := create_disk(template_id, "Schon ewig in der Sammlung")
		if disk != null:
			disks.append(disk)
	disks_changed.emit()


# ------------------------------------------------------------------ Erzeugung


# --------------------------------------------------------------- Sortierung
# Bleibt bewusst hier: tests/box_sort_model_check.gd prueft den Quelltext
# dieser Datei woertlich auf SortOrder.sorted(disks, sort_mode).

## Sortiermodus weiterschalten und Box neu sortieren.
func cycle_sort() -> String:
	sort_mode = (sort_mode + 1) % SORT_MODES.size()
	_apply_sort()
	disks_changed.emit()
	return SORT_MODES[sort_mode]


func _apply_sort() -> void:
	# Derselbe kanonische Comparator wie im Puzzle: Modusschluessel, Name, UID.
	# `assign` behaelt die Array-Identitaet fuer Beobachter und ersetzt nur Inhalt.
	disks.assign(SortOrder.sorted(disks, sort_mode))


# ------------------------------------------------- Kalender und Migration
# _repair_legacy_catalog_identity bleibt hier: tests/i18n_logic_trap_check.gd
# fuehrt die Ausnahme fuer das Wort "weihnacht" auf DIESEM Dateipfad.

## Datenverfall der Ära: die Kulturschicht altert die Sammlung — Kopien
## schneller als Originale, gepflegte langsamer (CultureManager.age_disk).
func _on_day_changed() -> void:
	_age_collection(1)


func _on_calendar_jumped(_from: Dictionary, _to: Dictionary, elapsed_days: int, _reason: String) -> void:
	_age_collection(maxi(0, elapsed_days - 1))


## Vor der kalendergebundenen Erzeugung trugen alle Coverdisks hart "7/92" —
## sogar im Sommer 1990/91. Alte Saves behalten ihren Erwerbsjahrgang und werden
## nur bei exakt diesen alten Katalogtexten migriert; eigene Labels bleiben tabu.
func _repair_legacy_catalog_identity(disk: Disk) -> void:
	if disk.template_id == COVERDISK_TEMPLATE_ID:
		var legacy_label := disk.label in ["Amiga Kurier 7/92", "Amiga Kurier 07/92"]
		var legacy_title := disk.content_title in [
			"Amiga Kurier Coverdisk 7/92", "Amiga Kurier Coverdisk 07/92"]
		if legacy_label or legacy_title:
			var issue_year := disk.year_created
			if issue_year < 1990 or issue_year > 2099:
				issue_year = TimeManager.year
			# ABSICHTLICH deutsch: dieser Zweig migriert Disketten aus ALTEN
			# Spielstaenden, deren Texte vor der Lokalisierung geschrieben wurden
			# und deshalb immer deutsch sind. Eine Uebersetzung aendert diese
			# gespeicherten Zeichenketten rueckwirkend nicht.
			var issue_month := 12 if "weihnacht" in disk.memory.to_lower() else 7
			var edition := "%02d/%02d" % [issue_month, issue_year % 100]
			if legacy_label:
				disk.label = "Amiga Kurier %s" % edition
			if legacy_title:
				disk.content_title = "Amiga Kurier Coverdisk %s" % edition
			if disk.notes == "Lag der Juli-Ausgabe bei.":
				disk.notes = "Coverdisk der Ausgabe %s." % edition
			disk.labeled = not disk.label.is_empty()
	if disk.template_id == LEGACY_PD_TOOLS_TEMPLATE_ID and disk.label == "PD-Tools '92":
		disk.label = "MOD-Player (PD)"


# --------------------------------------------------------------------------
# Erzeugung — Rumpfe in scripts/autoload/disk_factory.gd


func create_disk(template_id: String, memory: String = "") -> Disk:
	return Factory.create_disk(self, template_id, memory)


func _apply_calendar_identity(disk: Disk, issue_month: int, issue_year: int) -> void:
	Factory._apply_calendar_identity(self, disk, issue_month, issue_year)


func create_from_software(software_id: String, provenance: String = "original", memory: String = "",
		disk_number: int = 1, software_set_id: String = "") -> Disk:
	return Factory.create_from_software(self, software_id, provenance, memory, disk_number, software_set_id)


func create_software_set(software_id: String, provenance: String = "original", memory: String = "") -> Array:
	return Factory.create_software_set(self, software_id, provenance, memory)


func _new_software_set_id() -> String:
	return Factory._new_software_set_id(self)


func template_ids_in_pool(pool: String) -> Array:
	return Factory.template_ids_in_pool(self, pool)



# --------------------------------------------------------------------------
# Abfragen auf der Box — Rumpfe in scripts/autoload/disk_box_query.gd


func capacity() -> int:
	return BoxQuery.capacity(self)


func media_disks() -> Array:
	return BoxQuery.media_disks(self)


func media_count() -> int:
	return BoxQuery.media_count(self)


func is_loose_media(disk: Disk) -> bool:
	return BoxQuery.is_loose_media(self, disk)


func sealed_package_count() -> int:
	return BoxQuery.sealed_package_count(self)


func free_slots() -> int:
	return BoxQuery.free_slots(self)


func can_store_disks(amount: int) -> bool:
	return BoxQuery.can_store_disks(self, amount)


func boxed_collection() -> Array:
	return BoxQuery.boxed_collection(self)


func unique_boxed_game_count() -> int:
	return BoxQuery.unique_boxed_game_count(self)


func has_template(template_id: String) -> bool:
	return BoxQuery.has_template(self, template_id)


func get_disk_by_template(template_id: String) -> Disk:
	return BoxQuery.get_disk_by_template(self, template_id)


func matching_media(criteria: Dictionary) -> Array[Disk]:
	return BoxQuery.matching_media(self, criteria)


func blank_disks() -> Array:
	return BoxQuery.blank_disks(self)


func player_copies_of(software_id: String) -> Array:
	return BoxQuery.player_copies_of(self, software_id)


func has_player_copy_of(software_id: String) -> bool:
	return BoxQuery.has_player_copy_of(self, software_id)


func software_parts(software_id: String) -> Dictionary:
	return BoxQuery.software_parts(self, software_id)


func missing_software_parts(software_id: String) -> Array[int]:
	return BoxQuery.missing_software_parts(self, software_id)


func has_complete_software(software_id: String) -> bool:
	return BoxQuery.has_complete_software(self, software_id)


func missing_parts_for_disk(disk: Disk) -> Array[int]:
	return BoxQuery.missing_parts_for_disk(self, disk)


func disk_set_parts(disk: Disk, usable_only: bool = true) -> Array:
	return BoxQuery.disk_set_parts(self, disk, usable_only)


func has_complete_disk_set(disk: Disk) -> bool:
	return BoxQuery.has_complete_disk_set(self, disk)


func collection_value() -> int:
	return BoxQuery.collection_value(self)



# --------------------------------------------------------------------------
# Veraendernde Boxverwaltung — Rumpfe in scripts/autoload/disk_box_store.gd


func add_disk(disk: Disk) -> bool:
	return BoxStore.add_disk(self, disk)


func add_disks(new_disks: Array) -> bool:
	return BoxStore.add_disks(self, new_disks)


func remove_disk(disk: Disk) -> void:
	BoxStore.remove_disk(self, disk)


func remove_disks(removals: Array) -> void:
	BoxStore.remove_disks(self, removals)


func ensure_bundled_system_media(hardware_id := "") -> Array:
	return BoxStore.ensure_bundled_system_media(self, hardware_id)


func set_write_protected(disk: Disk, protected: bool) -> Dictionary:
	return BoxStore.set_write_protected(self, disk, protected)


func format_disk(disk: Disk, filesystem := "OFS", volume_name := "Empty") -> Dictionary:
	return BoxStore.format_disk(self, disk, filesystem, volume_name)


func damage_random_disk(amount: int) -> void:
	BoxStore.damage_random_disk(self, amount)


func assign_media_order(order: Array) -> bool:
	return BoxStore.assign_media_order(self, order)



# --------------------------------------------------------------------------
# Laufwerksaktionen — Rumpfe in scripts/autoload/disk_drive_actions.gd


func _drive_dirt() -> float:
	return DriveActions._drive_dirt(self)


func _drive_misalignment() -> float:
	return DriveActions._drive_misalignment(self)


func _has_ext_drive() -> bool:
	return DriveActions._has_ext_drive(self)


func _action_cost(base: int) -> int:
	return DriveActions._action_cost(self, base)


func _level_error_factor() -> float:
	return DriveActions._level_error_factor(self)


func read_error_probability(disk: Disk) -> float:
	return DriveActions.read_error_probability(self, disk)


func write_error_probability(disk: Disk) -> float:
	return DriveActions.write_error_probability(self, disk)


func diagnose_disk(disk: Disk) -> Dictionary:
	return DiskDiagnostics.inspect(disk, is_loose_media(disk) if disk != null else false)


func check_disk(disk: Disk) -> Dictionary:
	return DriveActions.check_disk(self, disk)


func _reveal_mystery(disk: Disk) -> Dictionary:
	return DriveActions._reveal_mystery(self, disk)


func label_disk(disk: Disk, text: String) -> Dictionary:
	return DriveActions.label_disk(self, disk, text)


func backup_disk(source: Disk, blank: Disk) -> Dictionary:
	return DriveActions.backup_disk(self, source, blank)


func copy_disk(source: Disk, blank: Disk) -> Dictionary:
	return DriveActions.copy_disk(self, source, blank)


func play_disk(disk: Disk) -> Dictionary:
	return DriveActions.play_disk(self, disk)



# --------------------------------------------------------------------------
# Alterung und Persistenz — Rumpfe in scripts/autoload/disk_manager_persistence.gd


func _age_collection(days: int) -> void:
	Persistence._age_collection(self, days)


func to_dict() -> Dictionary:
	return Persistence.to_dict(self)


func from_dict(d: Dictionary) -> void:
	Persistence.from_dict(self, d)


func _ensure_unique_disk_uids() -> void:
	Persistence._ensure_unique_disk_uids(self)


func _repair_old_bytewerk_migration(disk: Disk) -> void:
	Persistence._repair_old_bytewerk_migration(self, disk)
