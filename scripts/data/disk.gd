class_name Disk
extends RefCounted
## Eine einzelne Diskette als Laufzeit-Objekt.
## Wird aus JSON-Templates (data/disks.json) erzeugt; jede Instanz bekommt
## eine eigene uid, damit auch identische Templates unterscheidbar bleiben.

# --- Stammdaten (aus dem Template) ---
var uid: String = ""            # eindeutige Instanz-ID
var template_id: String = ""    # Verweis auf das JSON-Template
var label: String = ""          # aktueller Aufkleber-Text (umbenennbar)
var sticker_data: String = ""   # selbstgemaltes Etikett (Base64-PNG, Etikett-Designer)
var brand: String = "NoName"    # fiktive Diskettenmarke
var color: String = "blue"      # Gehäusefarbe (Datenwert, s. Palette.disk_color)
var dtype: String = "DD"        # "DD" (880 KB) oder "HD"
var capacity_kb: int = 880
var content_type: String = "leer"  # leer/demo/musik/spiel/tools/coverdisk/...
var content_title: String = ""     # Titel des Inhalts (fiktive Parodie-Namen!)
var rarity: String = "common"      # common/uncommon/rare/legendary
var read_error_chance: float = 0.04
var write_error_chance: float = 0.03
var notes: String = ""

# --- Laufzeit-Zustand ---
var condition: int = 100        # 0–100; sinkt durch Alter und Lesefehler
var checked: bool = false       # Zustand erst nach "Prüfen" sichtbar
var labeled: bool = false       # echtes Etikett aufgeklebt (Wert-Bonus)
var age_days: int = 0
var memory: String = ""         # Erwerbs-Kontext für den 1999-Rückblick
var owner_history: Array = []   # frühere Besitzer (Namen), Teil der Objektgeschichte
var year_created: int = 1992    # Jahrgang der Diskette
var archive_backup_day: int = -1 # echter BACKUP-Abschluss; -1 bei Legacy/normaler Kopie

# --- Kulturschicht (docs/KULTUR_LAYER.md) ---
var software_id: String = ""    # Verweis auf data/software_db.json ("" = keiner)
var software_set_id: String = "" # physischer Satz, zu dem diese Diskette gehoert
var disk_number: int = 1         # Teilnummer innerhalb des Satzes (1-basiert)
var disk_count: int = 1          # benoetigte Gesamtzahl fuer den Titel
var provenance: String = "copy" # original_box / original / copy
var package_condition: String = "" # sealed / used; nur fuer physische OVP-Saetze
var copy_generation: int = 0    # 0 = Original, 1 = Kopie, 2+ = Kopie der Kopie
var virus: bool = false         # latent — zeigt sich erst beim Prüfen
var cracktro: bool = false      # Szene-Kopie mit Cracktro-Intro (reine Ästhetik)
var label_quality: int = 0      # Stufe der Label-Progression (CultureManager)
var program_id: String = ""     # Programm-Disk (z.B. "xcopy") → Starten öffnet die App
var boot_mode: String = ""       # "workbench" = selbstbootende PD/WB-Disk bootet die Workbench
var write_protected: bool = false # physischer Schreibschutz-Schieber; Master sind immer gesperrt
var filesystem: String = ""       # "" = roh/custom, OFS/FFS nach Workbench-Format
var volume_name: String = ""      # logischer AmigaDOS-Volumename, nicht Papieretikett

# --- BYTEWERK / Szene-Release-Pipeline ---
# Die Felder beschreiben ausschließlich die fiktive P-8-Spielmechanik. Sie
# enthalten weder reale Speicheradressen noch Patch-Bytes oder Klarnamen.
var source_uid: String = ""             # unmittelbare Quelldiskette der Kopie
var source_provenance: String = ""      # Herkunft der Quelle beim Kopiervorgang
var patch_state: String = "none"        # none / bare / draft / verified / legacy_scene
var patch_seed: int = 0                 # deterministisches, rein fiktives P-8-Rätsel
var patch_draft: Dictionary = {}        # unfertige UI-Auswahl / Antworten
var patch_score: int = 0                # 0..100, Ergebnis des P-8-Rätsels
var patch_stability: int = 0            # 0..100, Ergebnis der drei Testboots
var cracktro_seen: bool = false         # Intro auf dieser Release-Fassung bestätigt
var release_serial: String = ""         # stabile ID; Distributionen erben sie
var release_data: Dictionary = {}       # nur bereinigte Handles + Intro-Konfiguration
var patched_on: String = ""             # Ingame-Datum der Verifikation
var release_role: String = ""           # master / distribution / legacy
var protection_revision: int = 0        # Schutzstand der vorliegenden Quellfassung
var patch_revision: int = 0             # hoechster von BYTEWERK verifizierter Stand
var patch_steps: Array = []              # abgeschlossene fiktive Revisionsschritte
var boot_faults: Array = []              # letzte reproduzierbare Bootdiagnose
var rescue_source_uid: String = ""      # Originalquelle eines Disk-Doctor-Images
var rescue_quality: int = 0              # verifizierte Sektorqualitaet 0..100
var media_repairs: int = 0               # physische Huelle/Nabe/Filz-Reparaturen
var last_repair_day: int = -1            # verhindert unrealistisches Tages-Farming

const RARITY_BASE_VALUE := {
	"common": 2, "uncommon": 5, "rare": 12, "legendary": 30,
}


## Sammlerwert in DM. Titel aus der Software-DB bewertet die Kulturschicht
## (Original-OVP >> Original >> Kopie); sonst die einfache Rarität-Formel.
func value() -> int:
	if content_type == "leer":
		return 1
	if software_id != "":
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			var culture: Node = loop.root.get_node_or_null("/root/CultureManager")
			if culture != null:
				return culture.disk_value(self)
	var base: int = RARITY_BASE_VALUE.get(rarity, 2)
	var v := float(base) * (0.4 + 0.6 * float(condition) / 100.0)
	if labeled:
		v *= 1.2
	return maxi(1, roundi(v))


## Anzeigename in Listen: Label, sonst Inhaltstitel, sonst "Unbeschriftet".
func display_name() -> String:
	var base := ""
	if label != "":
		base = label
	elif content_title != "":
		base = content_title
	else:
		base = "Unbeschriftete %s-Diskette" % dtype
	if disk_count > 1:
		return "%s · Diskette %d/%d" % [base, clampi(disk_number, 1, disk_count), disk_count]
	return base


func package_status_text() -> String:
	if provenance != "original_box":
		return "OHNE KARTON"
	return "OVP · VERSIEGELT" if package_condition == "sealed" else "OVP · GEBRAUCHT"


## Eine versiegelte OVP ist ein Sammlungsobjekt und kein frei zugänglicher
## Datenträger. Die enthaltenen Disk-Objekte bleiben nur als persistente
## Satz-/Wertmetadaten erhalten, bis ein bewusstes Öffnen-System existiert.
func is_sealed_package() -> bool:
	return provenance == "original_box" and package_condition == "sealed"


## Eine OVP wird als ein physischer Sammlungsgegenstand verwahrt. Auch bei einer
## gebrauchten/geöffneten Komplettbox liegen ihre Teile im Karton und nicht lose
## in der Diskettenbox. Ein späteres bewusstes Auspack-System kann daraus echte
## lose Medien erzeugen; bloßes Anklicken im Archiv darf das nie implizit tun.
func is_boxed_package() -> bool:
	return provenance == "original_box"


## Nur eine im eigenen Laufwerk erzeugte Kopie ist Handelsware. Fremde bzw.
## gekaufte Szene-Kopien tragen zwar ebenfalls provenance="copy", besitzen aber
## keine source_uid: Sie sind die physische Quelle der Sammlung und bleiben wie
## ein Original geschützt. Diese Unterscheidung ist absichtlich konservativ,
## damit auch alte Saves niemals versehentlich ihre letzte Quelldisk verlieren.
func is_player_made_copy() -> bool:
	return provenance == "copy" and not source_uid.is_empty()


func is_protected_copy_source() -> bool:
	return provenance == "copy" and source_uid.is_empty()


## Semantischer Sammlungs-Farbcode. Die Reihenfolge ist absichtlich eindeutig:
## leer = blau, BYTEWERK = gelb, echtes AAA-Original = lila, sonstige
## Spielquelle/Master = rot. Normale selbst erstellte Kopien behalten die Farbe
## ihres Trägermediums.
func is_game_master() -> bool:
	if content_type != "spiel":
		return false
	return release_role == "master" or not is_player_made_copy()


func is_aaa_original() -> bool:
	if content_type != "spiel" or provenance not in ["original", "original_box"]:
		return false
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return false
	var culture: Node = (loop as SceneTree).root.get_node_or_null("/root/CultureManager")
	if culture == null:
		return false
	var entry: Dictionary = culture.call("software", software_id)
	return str(entry.get("production_tier", "standard")).to_lower() == "aaa"


func enforce_master_color() -> void:
	if content_type == "leer":
		color = "blue"
	elif patch_state in ["bare", "draft", "verified"]:
		color = "yellow"
	elif is_aaa_original():
		color = "purple"
	elif is_game_master():
		color = "red"


## Ist diese Diskette bootfähig? Auf einem Amiga ohne Festplatte legt man sie in
## DF0: und der Rechner startet von ihr: die Werkbank-Systemdiskette bootet die
## Werkbank, Programm-Disketten (X-COPY …) und Spiele/Demos sind selbstbootend.
## Leere, Daten-, Musik- und Sammel-Disketten booten nicht (defekte auch nicht).
func is_bootable() -> bool:
	if condition <= 0 or is_boxed_package():
		return false
	if content_type == "system" or boot_mode == "workbench":
		return true
	if program_id != "":
		return true
	return content_type == "spiel" or content_type == "demo"


## Bootet diese Diskette eine Workbench-Umgebung? (System-Disk ODER selbstbootende
## PD-/Werkbank-Sammeldisk). PD-Disketten kamen mit eigener Workbench hoch, auf der
## die Tools (Packer, Kopierer, Disk-Doktor …) als Icons lagen.
func boots_workbench() -> bool:
	return content_type == "system" or boot_mode == "workbench"


## Kurzbeschreibung des Zustands — vor dem Prüfen bewusst unbekannt.
func condition_text() -> String:
	if not checked:
		return "Zustand: ???  (erst prüfen!)"
	if condition <= 0:
		return "Zustand: DEFEKT"
	return "Zustand: %d%%" % condition


func format_locked() -> bool:
	# Nur ein physisches Original ist unverrückbar. Ein eigener BYTEWERK-Master
	# oder eine als Quelle verwendete Kopie bleibt beim Handel geschützt, ist aber
	# weiterhin ein wiederverwendbares Medium, wenn der Spieler das bewusst will.
	return provenance in ["original", "original_box"]


func write_protect_text() -> String:
	if format_locked():
		return "ORIGINAL-LOCK · NICHT FORMATIERBAR"
	return "SCHREIBSCHUTZ AN" if write_protected else "SCHREIBSCHUTZ AUS"


func to_dict() -> Dictionary:
	return {
		"uid": uid, "template_id": template_id, "label": label,
		"brand": brand, "color": color, "dtype": dtype,
		"capacity_kb": capacity_kb, "content_type": content_type,
		"content_title": content_title, "rarity": rarity,
		"read_error_chance": read_error_chance,
		"write_error_chance": write_error_chance,
		"notes": notes, "condition": condition, "checked": checked,
		"labeled": labeled, "age_days": age_days, "memory": memory,
		"owner_history": owner_history, "year_created": year_created,
		"archive_backup_day": archive_backup_day,
		"software_id": software_id, "software_set_id": software_set_id,
		"disk_number": disk_number, "disk_count": disk_count, "provenance": provenance,
		"package_condition": package_condition,
		"copy_generation": copy_generation, "virus": virus,
		"cracktro": cracktro, "label_quality": label_quality,
		"program_id": program_id, "sticker_data": sticker_data, "boot_mode": boot_mode,
		"write_protected": write_protected, "filesystem": filesystem,
		"volume_name": volume_name,
		"source_uid": source_uid, "source_provenance": source_provenance,
		"patch_state": patch_state, "patch_seed": patch_seed,
		"patch_draft": patch_draft, "patch_score": patch_score,
		"patch_stability": patch_stability, "cracktro_seen": cracktro_seen,
		"release_serial": release_serial, "release_data": release_data,
		"patched_on": patched_on, "release_role": release_role,
		"protection_revision": protection_revision, "patch_revision": patch_revision,
		"patch_steps": patch_steps, "boot_faults": boot_faults,
		"rescue_source_uid": rescue_source_uid, "rescue_quality": rescue_quality,
		"media_repairs": media_repairs, "last_repair_day": last_repair_day,
	}


static func from_dict(d: Dictionary) -> Disk:
	var disk := Disk.new()
	disk.uid = d.get("uid", "")
	disk.template_id = d.get("template_id", "")
	disk.label = d.get("label", "")
	disk.sticker_data = d.get("sticker_data", "")
	disk.brand = d.get("brand", "NoName")
	disk.color = d.get("color", "blue")
	disk.dtype = d.get("dtype", "DD")
	disk.capacity_kb = int(d.get("capacity_kb", 880))
	disk.content_type = d.get("content_type", "leer")
	disk.content_title = d.get("content_title", "")
	disk.rarity = d.get("rarity", "common")
	disk.read_error_chance = float(d.get("read_error_chance", 0.04))
	disk.write_error_chance = float(d.get("write_error_chance", 0.03))
	disk.notes = d.get("notes", "")
	disk.condition = int(d.get("condition", 100))
	disk.checked = bool(d.get("checked", false))
	disk.labeled = bool(d.get("labeled", false))
	disk.age_days = int(d.get("age_days", 0))
	disk.memory = d.get("memory", "")
	disk.owner_history = d.get("owner_history", [])
	disk.year_created = int(d.get("year_created", 1992))
	disk.archive_backup_day = int(d.get("archive_backup_day", -1))
	disk.software_id = d.get("software_id", "")
	disk.software_set_id = str(d.get("software_set_id", ""))
	disk.disk_number = maxi(1, int(d.get("disk_number", 1)))
	disk.disk_count = maxi(1, int(d.get("disk_count", 1)))
	disk.disk_number = mini(disk.disk_number, disk.disk_count)
	disk.provenance = d.get("provenance", "copy")
	disk.package_condition = str(d.get("package_condition",
		"used" if disk.provenance == "original_box" else ""))
	disk.copy_generation = int(d.get("copy_generation", 0))
	disk.virus = bool(d.get("virus", false))
	disk.cracktro = bool(d.get("cracktro", false))
	disk.label_quality = int(d.get("label_quality", 0))
	disk.program_id = d.get("program_id", "")
	disk.boot_mode = d.get("boot_mode", "")
	disk.write_protected = bool(d.get("write_protected", disk.provenance in ["original", "original_box"]))
	disk.filesystem = str(d.get("filesystem", ""))
	disk.volume_name = str(d.get("volume_name", ""))
	disk.source_uid = str(d.get("source_uid", ""))
	disk.source_provenance = str(d.get("source_provenance", ""))
	disk.patch_state = str(d.get("patch_state", "none"))
	disk.patch_seed = int(d.get("patch_seed", 0))
	disk.patch_draft = (d.get("patch_draft", {}) as Dictionary).duplicate(true)
	disk.patch_score = int(d.get("patch_score", 0))
	disk.patch_stability = int(d.get("patch_stability", 0))
	disk.cracktro_seen = bool(d.get("cracktro_seen", false))
	disk.release_serial = str(d.get("release_serial", ""))
	disk.release_data = (d.get("release_data", {}) as Dictionary).duplicate(true)
	disk.patched_on = str(d.get("patched_on", ""))
	disk.release_role = str(d.get("release_role", ""))
	disk.protection_revision = maxi(0, int(d.get("protection_revision", 0)))
	disk.patch_revision = maxi(0, int(d.get("patch_revision", 0)))
	disk.patch_steps = (d.get("patch_steps", []) as Array).duplicate(true)
	disk.boot_faults = (d.get("boot_faults", []) as Array).duplicate(true)
	disk.rescue_source_uid = str(d.get("rescue_source_uid", ""))
	disk.rescue_quality = clampi(int(d.get("rescue_quality", 0)), 0, 100)
	disk.media_repairs = maxi(0, int(d.get("media_repairs", 0)))
	disk.last_repair_day = int(d.get("last_repair_day", -1))
	# Spielstände vor BYTEWERK kannten nur das cracktro-Bool. Solche Disks
	# bleiben garantiert spielbar und werden ausdrücklich als Legacy markiert.
	if not d.has("patch_state") and disk.cracktro:
		disk.patch_state = "legacy_scene"
		disk.cracktro_seen = true
		disk.release_role = "legacy"
	# Vor dem Revisionssystem verifizierte Releases entsprechen dem historischen
	# BYTEWERK-V1-Stand. Legacy-Crackros bleiben absichtlich revisionsfrei.
	if disk.patch_state == "verified" and disk.patch_revision <= 0:
		disk.patch_revision = 1
	if disk.patch_state == "verified" and disk.protection_revision <= 0:
		disk.protection_revision = disk.patch_revision
	# Der sichtbare Sammlungs-Farbcode wird aus den persistierten Rollen abgeleitet;
	# Inhalt, Herkunft und BYTEWERK-Zustand selbst bleiben dabei unangetastet.
	disk.enforce_master_color()
	return disk
