extends Node
## CultureManager — die historische Kulturschicht (docs/KULTUR_LAYER.md):
## Software-Titel mit Popularitätskurven, Sammlerwert-Logik
## (Original-OVP >> Original >> gute Kopie >> späte Kopie), Kopier-Regeln
## mit Generationen-Verfall und Virusrisiko, Datenverfall über die Jahre
## und die Label-/Druck-Progression.
##
## Designregeln (fest verdrahtet):
## - Kopieren/Tauschen ist Alltag der Ära — aber Originale schlagen Kopien
##   in Wert, Prestige und Zuverlässigkeit IMMER deutlich.
## - Massenpiraterie ist kein profitabler Dauerpfad: Kopien verfallen,
##   streuen Viren und sind bei Sammlern wenig wert.
## - BYTEWERK verwendet ausschließlich ein fiktives P-8-Logikrätsel. Eine
##   normale Kopie eines geschützten Originals bleibt zunächst eine nackte,
##   nicht startfähige Arbeitskopie; nur ein verifiziertes Szene-Release trägt
##   ein Intro. Es gibt hier keine realen Adressen, Opcodes oder Patch-Bytes.

const DB_PATH := "res://data/software_db.json"
const STEFAN_GAMES_PATH := "res://data/stefan_games.json"
const BYTEWERK_STANDARD_CHANCE := 50

## Herkunftsarten einer Diskette (Disk.provenance)
const PROVENANCE_ORIGINAL_BOX := "original_box"  # Komplett-OVP-Bestand
const PROVENANCE_ORIGINAL := "original"          # Originaldiskette ohne Box
const PROVENANCE_COPY := "copy"                  # Kopie (generation >= 1)

## Label-/Druck-Progression (Index = Qualitätsstufe)
const LABEL_STAGES := [
	"handschriftlich", "sauber beschriftet", "9-Nadel-Etikett",
	"Letter-Quality-Etikett", "Farb-Etikett", "Profi-Inlay",
]

var _titles: Dictionary = {}   # id -> Titel-Datensatz


func _ready() -> void:
	var file := FileAccess.open(DB_PATH, FileAccess.READ)
	if file == null:
		push_warning("CultureManager: %s fehlt" % DB_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_warning("CultureManager: %s ist ungueltig" % DB_PATH)
		return
	var data: Dictionary = parsed
	for entry in data.get("titles", []):
		_titles[entry["id"]] = entry
	_load_stefan_anthology()


## Die 27 spielbaren Questtitel leiten ihre Sammlerwerte aus demselben Katalog
## ab wie Launcher und Quests. So koennen Titel/Releasejahr nie zwischen
## Vollspiel, X-COPY, Workbench und Vitrine auseinanderlaufen.
func _load_stefan_anthology() -> void:
	if not FileAccess.file_exists(STEFAN_GAMES_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STEFAN_GAMES_PATH))
	if not parsed is Dictionary:
		push_warning("CultureManager: %s ist ungueltig." % STEFAN_GAMES_PATH)
		return
	var genres := {
		"shooter": "Action", "platform": "Jump & Run", "circuit": "Logik-Puzzle",
		"miner": "Erkundung", "rescue": "Rettungs-Simulation", "stealth": "Taktik",
		"racer": "Rennspiel", "strategy": "Strategie", "rhythm": "Musikspiel",
	}
	for raw: Variant in (parsed as Dictionary).get("games", []):
		if not raw is Dictionary:
			continue
		var game: Dictionary = raw
		var id := str(game.get("software_id", ""))
		if id.is_empty() or _titles.has(id):
			continue
		var year := int(game.get("year", 1991))
		var slot := int(game.get("slot", 1))
		var difficulty := int(game.get("difficulty", 1))
		_titles[id] = {
			"id": id,
			"title": str(game.get("title", id)),
			"genre": str(genres.get(str(game.get("mode", "")), "Arcade")),
			"production_tier": "aaa" if difficulty >= 4 else "standard",
			"release_year": year,
			"disks": 1,
			"base_value": 54 + (year - 1991) * 5 + slot * 4,
			"peak_year": mini(1999, year + 1),
			"span": 2.8,
			# Die Quest verlangt eine normale Arbeitskopie; ein nachtraeglicher
			# Kopierschutz wuerde diese bewusst gebaute Freundschaftskette brechen.
			"protection": "keine",
			"boxed_multiplier": 2.2 + float(slot) * 0.12,
			"rarity_growth": 0.12 + float(slot) * 0.02,
			"flavor": str(game.get("briefing", "Ein Spiel aus Stefans Sommerliste.")),
		}


# ------------------------------------------------------------- Titel-Wissen

func software(id: String) -> Dictionary:
	return _titles.get(id, {})


func all_titles() -> Array:
	return _titles.values()


## Kopierschutz stammt nur aus kuratierten Kulturdaten. Die Stefan-Anthologie
## ist bewusst ungeschuetzt; unbekannte Software-IDs werden nicht erraten.
func has_protection(software_id: String) -> bool:
	var entry := software(software_id)
	return not entry.is_empty() and str(entry.get("protection", "keine")) != "keine"


## BYTEWERK wird erst mit Tobias' Einführung Teil der Spielwelt. Der Abschluss-
## Flag bleibt als Fallback erhalten, damit alte Spielstände mit bereits
## absolviertem Tutorial nicht erneut ausgesperrt werden.
func bytewerk_introduced() -> bool:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return false
	var game: Node = (loop as SceneTree).root.get_node_or_null("/root/GameManager")
	if game == null:
		return false
	var flags: Dictionary = game.get("flags")
	return bool(flags.get("bytewerk_gelernt", false)) \
		or bool(flags.get("bytewerk_1994_intro", false)) \
		or bool(flags.get("tut_bytewerk_intro", false))  # Legacy-Save vor Kampagnenumbau


## Stabile Titelentscheidung: AAA-Titel sind nach der Einführung immer dabei;
## Standardtitel werden einmal deterministisch 50/50 auf Titel-Ebene verteilt.
## Dadurch ändert Neuladen niemals das Ergebnis und alle Disks eines Titels
## folgen derselben Content-Entscheidung.
func bytewerk_title_selected(software_id: String) -> bool:
	var entry := software(software_id)
	if entry.is_empty() or str(entry.get("protection", "keine")) == "keine":
		return false
	if str(entry.get("production_tier", "standard")).to_lower() == "aaa":
		return true
	# Der einmalige Wurf darf im Content festgehalten werden. Fehlt er bei einem
	# später ergänzten Titel, liefert der stabile ID-Hash denselben 0..99-Wert.
	var roll := int(entry.get("bytewerk_roll", absi(software_id.hash()) % 100))
	return clampi(roll, 0, 99) < BYTEWERK_STANDARD_CHANCE


## Nur neue Gen-1-Kopien fragen diese zeitabhängige Regel ab. Gespeicherte
## Disketten werden absichtlich nie nachträglich neu eingestuft.
func bytewerk_available_for_new_copy(software_id: String) -> bool:
	return bytewerk_introduced() and bytewerk_title_selected(software_id)


## Titel, die in einem Jahr existieren (Living-Timeline-Filter).
func titles_for_year(year: int) -> Array:
	var result: Array = []
	for entry in _titles.values():
		if int(entry["release_year"]) <= year:
			result.append(entry)
	return result


## Popularität 0..1: Gauß-Kurve um peak_year — Gesprächsstoff auf dem
## Schulhof, Nachfrage beim Tausch, BBS-Downloads.
func popularity(id: String, year: int) -> float:
	var entry := software(id)
	if entry.is_empty() or year < int(entry["release_year"]):
		return 0.0
	var span := maxf(float(entry.get("span", 3.0)), 0.5)
	var d := (float(year) - float(entry.get("peak_year", entry["release_year"]))) / span
	return clampf(exp(-0.5 * d * d), 0.0, 1.0)


## Seltenheitsfaktor ORIGINALER Exemplare: wächst mit den Jahren nach
## Release (Boxen landen im Müll, Disketten sterben — Sammler zahlen mehr).
func rarity_factor(id: String, year: int) -> float:
	var entry := software(id)
	if entry.is_empty():
		return 1.0
	var years_out := maxi(0, year - int(entry["release_year"]))
	return 1.0 + float(entry.get("rarity_growth", 0.15)) * float(years_out)


# ------------------------------------------------------------- Sammlerwert

## Zentrale Wertformel in DM. Reihenfolge ist Gesetz:
## Komplett-OVP >> Original >> Kopie Gen 1 >> Kopie Gen 2+.
func disk_value(disk: Disk, year: int = -1) -> int:
	if year < 0:
		year = TimeManager.year
	var entry := software(disk.software_id)
	if entry.is_empty():
		# Der große SoftwareBible-Katalog (hunderte echte Regal-/Sammlertitel)
		# lebt absichtlich außerhalb der kleinen, fiktionalen Kulturkurven-DB.
		# Er darf deshalb nicht auf den 2-DM-Disketten-Fallback fallen: OVP,
		# Zustand und zunehmende Seltenheit bilden eine eigene Sammlerökonomie.
		if SoftwareBible != null and not SoftwareBible.entry(disk.software_id).is_empty():
			return _bible_disk_value(disk, year)
		return _fallback_value(disk)
	var base := float(entry.get("base_value", 20))
	var cond := 0.35 + 0.65 * float(disk.condition) / 100.0
	var demand := 0.7 + 0.6 * popularity(disk.software_id, year)
	var v := 0.0
	match disk.provenance:
		PROVENANCE_ORIGINAL_BOX:
			v = base * float(entry.get("boxed_multiplier", 2.0)) \
				* rarity_factor(disk.software_id, year) * cond * demand
			if disk.package_condition == "sealed":
				v *= 1.25
		PROVENANCE_ORIGINAL:
			v = base * rarity_factor(disk.software_id, year) * cond * demand
		_:
			# Kopien: Alltagsware. Gen 1 ~15 %, ab Gen 2 ~7 % des Basiswerts,
			# ohne Seltenheitszuwachs — Sammler wollen Originale.
			var gen_factor := 0.15 if disk.copy_generation <= 1 else 0.07
			v = base * gen_factor * cond * demand
			# Etikett verkauft die Kopie: Hand < 9-Nadel < 24-Nadel < Farbdruck-Logo.
			# Stufe 4 fast verdoppelt den Preis — der Kern des Kopien-Handels.
			v *= 1.0 + 0.22 * float(disk.label_quality)
	# Der Wert gehoert zum Titel/Satz, nicht zu jedem einzelnen Datentraeger.
	# Sonst waere dasselbe Spiel auf sieben Disketten siebenmal so wertvoll.
	v /= float(maxi(1, disk.disk_count))
	if disk.virus and disk.checked:
		v *= 0.1  # bekannt verseucht: praktisch unverkäuflich
	return maxi(1, roundi(v))


## Sammlerwert für den großen historischen Katalog. Direkt nach Kauf bleibt der
## Händlerankauf unter dem Neupreis; erst Alter und titelstabile Knappheit machen
## gut erhaltene Komplett-OVPs später zu echten Auto-Fonds-Kandidaten.
func _bible_disk_value(disk: Disk, year: int) -> int:
	var entry: Dictionary = SoftwareBible.entry(disk.software_id)
	var release_year := int(entry.get("release_year", disk.year_created))
	var age := maxi(0, year - release_year)
	var stable_roll := absi(disk.software_id.hash()) % 100
	var annual_growth := 0.045 + float(stable_roll % 10) * 0.009
	var coveted := 1.0 + floorf(stable_roll / 10.0) * 0.018
	var scarcity := 1.0 + annual_growth * float(age)
	var condition_factor := 0.35 + 0.65 * float(disk.condition) / 100.0
	var v := 89.0
	match disk.provenance:
		PROVENANCE_ORIGINAL_BOX:
			v *= (1.05 if disk.package_condition == "sealed" else 0.72) \
				* scarcity * coveted * condition_factor
		PROVENANCE_ORIGINAL:
			v *= 0.46 * scarcity * coveted * condition_factor
		_:
			var gen_factor := 0.09 if disk.copy_generation <= 1 else 0.045
			v *= gen_factor * condition_factor * (1.0 + 0.16 * float(disk.label_quality))
	v /= float(maxi(1, disk.disk_count))
	if disk.virus and disk.checked:
		v *= 0.1
	return maxi(1, roundi(v))


func _fallback_value(disk: Disk) -> int:
	var base: int = Disk.RARITY_BASE_VALUE.get(disk.rarity, 2)
	var v := float(base) * (0.4 + 0.6 * float(disk.condition) / 100.0)
	if disk.labeled:
		v *= 1.2
	return maxi(1, roundi(v))


# ------------------------------------------------------------- Kopieren

## Kopier-Regeln der Ära: die Ziel-Diskette wird zur Kopie der Quelle.
## Geschütztes Original -> nackte Gen-1-Arbeitskopie (BYTEWERK-Eingang).
## Verifiziertes/Legacy-Szene-Release -> vollständige Distribution mit derselben
## Release-ID und demselben Intro. Es entsteht niemals automatisch ein Cracktro.
## Rückgabe: {ok, virus_neu, cracktro, patch_state, text}.
func copy_rules(source: Disk, target: Disk) -> Dictionary:
	var generation := 1 if source.provenance != PROVENANCE_COPY else source.copy_generation + 1
	# Die physische Leerdiskette wird inhaltlich zur Kopie des Quelltitels. Ohne
	# diese Identität konnte ein per X-COPY erstellter Händlerauftrag nie als der
	# gesuchte Titel erkannt werden, weil das Ziel weiter "blank_*" hieß.
	target.template_id = source.template_id
	target.software_id = source.software_id
	target.disk_number = source.disk_number
	target.disk_count = source.disk_count
	var source_set := source.software_set_id if not source.software_set_id.is_empty() else source.uid
	target.software_set_id = "%s_copy_g%d" % [source_set, generation]
	target.program_id = source.program_id   # Programm-Disketten (X-COPY …) bleiben lauffähig/bootbar
	target.boot_mode = source.boot_mode
	target.content_type = source.content_type
	target.content_title = source.content_title
	target.rarity = source.rarity
	target.provenance = PROVENANCE_COPY
	target.copy_generation = generation
	# Kopie startet nie besser als die Quelle; jede Generation kostet Substanz
	target.condition = mini(target.condition, maxi(20, source.condition - 3 * generation))
	target.read_error_chance = source.read_error_chance + 0.03 * float(generation)
	# Virusrisiko wächst mit der Generationskette (fremde Quellen!)
	var virus_new := not source.virus and randf() < 0.04 + 0.03 * float(generation - 1)
	target.virus = source.virus or virus_new
	target.checked = false  # erst Prüfen macht den Zustand (und Viren) sichtbar
	target.source_uid = source.uid
	target.source_provenance = source.provenance
	_reset_scene_fields(target)

	# Ein fertiges Release wird bitidentisch als Distributionskopie weitergegeben.
	# Auch alte Cracktro-Disks ohne BYTEWERK-Payload bleiben kompatibel.
	var source_state := source.patch_state
	if source_state == "none" and source.cracktro:
		source_state = "legacy_scene"
	if source_state == "verified" and source.cracktro:
		target.patch_state = "verified"
		target.cracktro = true
		target.cracktro_seen = source.cracktro_seen
		target.release_serial = source.release_serial
		target.release_data = source.release_data.duplicate(true)
		target.patch_score = source.patch_score
		target.patch_stability = source.patch_stability
		target.protection_revision = source.protection_revision
		target.patch_revision = source.patch_revision
		target.patch_steps = source.patch_steps.duplicate(true)
		target.boot_faults = source.boot_faults.duplicate(true)
		target.patched_on = source.patched_on
		target.release_role = "distribution"
	elif source_state == "legacy_scene" and source.cracktro:
		target.patch_state = "legacy_scene"
		target.cracktro = true
		target.cracktro_seen = true
		target.release_serial = source.release_serial
		target.release_data = source.release_data.duplicate(true)
		target.release_role = "legacy"
	elif generation == 1 \
			and source.provenance in [PROVENANCE_ORIGINAL, PROVENANCE_ORIGINAL_BOX] \
			and bytewerk_available_for_new_copy(source.software_id):
		# Nur eine NACH der Einführung neu angelegte, vom Titelprofil unterstützte
		# Direktkopie wird zur Arbeitskopie. Kein Load und keine spätere
		# Flag-Änderung rüstet eine vorhandene Diskette rückwirkend um.
		target.patch_state = "bare"
		target.release_role = "work_copy"
		target.protection_revision = bytewerk_protection_revision(source.software_id)
	else:
		target.patch_state = "none"
	target.enforce_master_color()
	return {
		"ok": true, "virus_neu": virus_new, "cracktro": target.cracktro,
		"patch_state": target.patch_state,
		"text": _copy_result_text(source, target, generation),
	}


func _reset_scene_fields(target: Disk) -> void:
	target.cracktro = false
	target.patch_state = "none"
	target.patch_seed = 0
	target.patch_draft = {}
	target.patch_score = 0
	target.patch_stability = 0
	target.cracktro_seen = false
	target.release_serial = ""
	target.release_data = {}
	target.patched_on = ""
	target.release_role = ""
	target.package_condition = ""
	target.protection_revision = 0
	target.patch_revision = 0
	target.patch_steps = []
	target.boot_faults = []


func _copy_result_text(source: Disk, target: Disk, generation: int) -> String:
	var suffix := ""
	match target.patch_state:
		"bare":
			suffix = "  Geschützte Gen-1-Arbeitskopie: erst in BYTEWERK analysieren."
		"verified":
			suffix = "  Verifiziertes Szene-Release samt Intro übernommen."
		"legacy_scene":
			suffix = "  Klassisches Szene-Intro übernommen."
	if suffix.is_empty() and has_protection(target.software_id) and generation == 1:
		if not bytewerk_introduced():
			suffix = "  Geschützte Kopie ohne BYTEWERK-Profil; vorhandene Disks werden später nicht nachgerüstet."
		elif not bytewerk_title_selected(target.software_id):
			suffix = "  Für diesen Titel ist kein BYTEWERK-Profil verfügbar."
	return "Kopie (%d. Generation) von „%s“ erstellt.%s" % [generation, source.display_name(), suffix]


# ------------------------------------------------------- Kopierschutz erleben

## Kopierschutz aus NUTZERSICHT — voll erlebbare Kultur, keine Anleitung:
## Startet man einen Titel, greift der Schutz der Ära. Ergebnis erklärt
## nebenbei die Geschichte: Originale laufen (Beilagen dabei), nackte
## Kopien geschützter Titel laufen NICHT (Handbuch/Scheibe/Dongle fehlt!)
## — genau deshalb kursierten in der Szene die Cracktro-Versionen.
## Rückgabe: {ok, mode, reason} — mode: "voll"/"demo"/"abfrage".
func protection_check(disk: Disk) -> Dictionary:
	var entry := software(disk.software_id)
	if entry.is_empty():
		return {"ok": true, "mode": "voll", "reason": ""}
	var protection := str(entry.get("protection", "keine"))
	if protection == "keine":
		return {"ok": true, "mode": "voll", "reason": ""}
	# Originale bringen ihre Beilagen mit — die Abfrage wird zum Ritual
	if disk.provenance == PROVENANCE_ORIGINAL_BOX:
		return {"ok": true, "mode": "abfrage", "reason":
			_protection_ritual(protection, true)}
	if disk.provenance == PROVENANCE_ORIGINAL:
		return {"ok": true, "mode": "abfrage", "reason":
			_protection_ritual(protection, false)}
	# Historischer Vertrag: Kopien, die ohne BYTEWERK-Profil entstanden sind,
	# werden durch dessen spätere Einführung niemals rückwirkend geschützt. Das
	# gilt ebenso für die feste 50-%-Hälfte ohne Profil. Nur bare/draft/verified
	# gehört in den P-8-Pfad.
	if disk.provenance == PROVENANCE_COPY and disk.patch_state == "none":
		return {"ok": true, "mode": "voll", "reason":
			"Historische Kopie ohne BYTEWERK-Profil — ihr gespeicherter Zustand bleibt unverändert."}
	# Szene-Kopie: der Schutz wurde von einer (fiktiven) Gruppe entfernt —
	# Cracktro läuft, dann startet das Spiel. Geschichte, keine Anleitung.
	if disk.cracktro:
		var required_revision := bytewerk_protection_revision(disk.software_id)
		if required_revision > maxi(1, disk.patch_revision):
			var fault := bytewerk_boot_fault(disk, required_revision)
			disk.boot_faults = [fault]
			return {"ok": false, "mode": "revision_error", "revision": required_revision,
				"reason": Loc.t("sys.culture_manager.bytewerk_v_d_startet_dann_s", "BYTEWERK V%d startet, dann: %s  Die Schutzrevision des Titels ist neuer als der Patch V%d. Arbeitsdisk erneut analysieren.") % [required_revision, fault, maxi(1, disk.patch_revision)]}
		return {"ok": true, "mode": "voll", "reason":
			"Cracktro-Scroller läuft: Grüße an die halbe Szene … dann startet das Spiel."}
	# Nackte Kopie eines geschützten Titels: läuft nicht (oder nur Demo)
	return {"ok": false, "mode": "demo", "reason": _protection_blocked(protection)}


## Fiktive Schutzgeneration der laufenden Kampagnenphase. Die Revision ist
## bewusst eine Spielabstraktion und enthaelt keinerlei reale Crack-Technik.
func bytewerk_protection_revision(_software_id: String, year: int = -1) -> int:
	var at_year := TimeManager.year if year < 0 else year
	if at_year <= 1992:
		return 1
	if at_year <= 1995:
		return 2
	return 3


func bytewerk_boot_fault(disk: Disk, revision: int = -1) -> String:
	var rev := bytewerk_protection_revision(disk.software_id) if revision < 0 else revision
	var faults: Array = {
		2: ["BOOTBLOCK 02 · Startimpuls läuft in eine Prüfschleife.",
			"SIGNATURWECHSEL · schwarzer Schirm nach dem Intro."],
		3: ["BOOTBLOCK 03 · Schutzspiegel meldet eine veraltete Matrix.",
			"NEUSTART-FALLE · Laufwerk klickt, der Titel kehrt zum Kickstart zurück.",
			"PRÜFSUMMEN-DRIFT · Testboot zwei bleibt reproduzierbar hängen."],
	}.get(rev, ["BOOTBLOCK · Schutzrevision nicht erkannt."])
	return str(faults[absi(hash("%s/%d" % [disk.uid, rev])) % faults.size()])


func _protection_ritual(protection: String, boxed: bool) -> String:
	match protection:
		"handbuch":
			return "Handbuch-Abfrage: „Seite %d, Zeile %d, Wort %d“ — %s" % [
				randi_range(12, 88), randi_range(1, 9), randi_range(1, 6),
				"das Handbuch liegt in der Box." if boxed else "zum Glück ist das Handbuch dabei."]
		"codewheel":
			return "Code-Drehscheibe: äußeren Ring auf das Symbol drehen, Code ablesen. Ritual erfüllt."
		"dongle":
			return "Der Dongle steckt am Parallelport — das Spiel startet ohne Murren."
	return "Der Kopierschutz nickt das Original durch."


func _protection_blocked(protection: String) -> String:
	match protection:
		"handbuch":
			return "Handbuch-Abfrage beim Start — aber zur Kopie gibt es kein Handbuch. Nach drei Fehlversuchen: Demomodus."
		"codewheel":
			return "„Bitte Code von der Drehscheibe eingeben.“ Welche Drehscheibe? Die Kopie kam ohne. Abbruch."
		"dongle":
			return "„Dongle nicht gefunden.“ Ohne das Steckmodul läuft nur der Demomodus."
	return "Der Kopierschutz verweigert die Kopie."


# ------------------------------------------------------------- Datenverfall

## Zeit nagt an Magnetschichten: Kopien verfallen schneller als Originale,
## gepflegte (etikettierte/archivierte) Disketten langsamer. Aufruf z. B.
## beim Jahreswechsel oder beim Prüfen lange gelagerter Disketten.
func age_disk(disk: Disk, days: int) -> void:
	disk.age_days += days
	var per_year := 2.0   # Originale: ~2 Zustandspunkte pro Jahr
	if disk.provenance == PROVENANCE_COPY:
		per_year = 4.0 + 1.5 * float(disk.copy_generation)
	if disk.labeled or disk.label_quality >= 2:
		per_year *= 0.75  # ordentlich beschriftet = ordentlich gelagert
	var loss := per_year * float(days) / 365.0
	# Verfall ist schleichend und leicht zufällig
	if randf() < fmod(loss, 1.0):
		loss = ceilf(loss)
	disk.condition = maxi(0, disk.condition - int(loss))


# ------------------------------------------------------------- Labels & Druck

func label_stage_name(level: int) -> String:
	return LABEL_STAGES[clampi(level, 0, LABEL_STAGES.size() - 1)]


## Beste erreichbare Label-Stufe: hängt an gekaufter Hardware (Drucker im
## Shop, Living Timeline macht bessere Drucker erst später erschwinglich).
func max_label_stage() -> int:
	if PlayerStats.has_hardware("printer_inkjet"):
		return 4
	if PlayerStats.has_hardware("printer_laser"):
		return 3
	if PlayerStats.has_hardware("printer_matrix"):
		return 2
	return 1  # sauber von Hand — Stufe 0 ist die Kritzel-Variante
