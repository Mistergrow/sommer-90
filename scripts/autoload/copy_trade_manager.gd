extends Node
## CopyTradeManager — mit Disketten-KOPIEN Geld verdienen (Phase C, Ökonomie).
##
## Der Wert einer Kopie steigt mit dem Etikett: handgeschrieben < 9-Nadel-Titel
## < 24-Nadel < FARBDRUCK mit gerastertem Artwork-Logo (höchste Gewinne).
## Verkauft wird an drei Orten mit eigenem Publikum, Preisfaktor und Tageslimit:
##   Schulhof (Schüler, wenig Geld) · Computer-Club (Tauschabend) ·
##   Flohmarkt (Samstag, eigener Stand, beste Preise).
## Die Einnahmen finanzieren Hardware (Modems, Drucker) und die Telefonrechnung.

signal trade_changed

## Orts-Märkte: Preisfaktor + wie viele Kopien pro Tag Abnehmer finden.
const MARKETS := {
	"schoolyard":    {"name": "Schulhof", "factor": 0.8, "limit": 2},
	"computer_club": {"name": "Computer-Club", "factor": 1.0, "limit": 3},
	"flea_market":   {"name": "Flohmarkt", "factor": 1.25, "limit": 5},
}
const PRINT_ENERGY := 2      # Energie pro Etikettendruck

var _sold_today: Dictionary = {}   # location_id -> count


func _ready() -> void:
	var tm := get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_signal("day_changed"):
		tm.day_changed.connect(func() -> void: _sold_today = {})


# ------------------------------------------------------------- Etikett drucken

## Etikett in gewünschter Stufe drucken (2/3/4 mit echtem Gerät).
## Verbraucht 1 Etikett + Energie; setzt label_quality + Sticker-Bild.
func print_label(disk: Disk, stage: int) -> Dictionary:
	if disk == null:
		return {"ok": false, "text": Loc.t("sys.copy_trade_manager.keine_diskette_gewahlt", "Keine Diskette gewählt.")}
	if not PlayerStats.has_printer():
		return {"ok": false, "text": Loc.t("sys.copy_trade_manager.kein_drucker_angeschlossen_von_hand_beschriften", "Kein Drucker angeschlossen. Von Hand beschriften geht über »Etikett«.")}
	if stage < 2 or stage > 4 or PlayerStats.best_print_stage() < stage:
		return {"ok": false, "text": Loc.t("sys.copy_trade_manager.dafur_fehlt_passende_drucker_bestellkatalog_im", "Dafür fehlt der passende Drucker (Bestellkatalog im Computerladen).")}
	if InventoryManager.count("etiketten") <= 0:
		return {"ok": false, "text": Loc.t("sys.copy_trade_manager.keine_etiketten_mehr_gibt_s_im", "Keine Etiketten mehr — gibt's im Computerladen.")}
	if not PlayerStats.use_energy(PRINT_ENERGY):
		return {"ok": false, "text": Loc.t("sys.copy_trade_manager.zu_mude_zum_drucken", "Zu müde zum Drucken.")}
	InventoryManager.consume("etiketten", 1)
	var img := LabelPrint.make(disk, stage)
	disk.sticker_data = DiskComposer.encode_sticker(img)
	disk.label_quality = stage
	disk.labeled = true
	AudioManager.play("relay")
	AchievementManager.note("printed_label")
	trade_changed.emit()
	return {"ok": true,
		"text": Loc.t("sys.copy_trade_manager.etikett_gedruckt_s_gerat_s", "Etikett gedruckt: %s · Gerät: %s.") % [
			CultureManager.label_stage_name(stage), PlayerStats.printer_name()]}


# ------------------------------------------------------------- Verkaufen

func market(location_id: String) -> Dictionary:
	return MARKETS.get(location_id, {})


func sold_today(location_id: String) -> int:
	return int(_sold_today.get(location_id, 0))


func slots_left(location_id: String) -> int:
	var m := market(location_id)
	if m.is_empty():
		return 0
	return maxi(0, int(m["limit"]) - sold_today(location_id))


## Angebotspreis für eine Kopie am Ort (Sammlerwert × Marktfaktor).
func offer_price(disk: Disk, location_id: String) -> int:
	var m := market(location_id)
	if m.is_empty():
		return 0
	var sale_parts := DiskManager.disk_set_parts(disk)
	if disk.disk_count > 1 and not DiskManager.has_complete_disk_set(disk):
		return 0
	if sale_parts.is_empty():
		sale_parts = [disk]
	var set_value := 0
	for part: Disk in sale_parts:
		set_value += CultureManager.disk_value(part)
	var base := maxi(1, roundi(float(set_value) * float(m["factor"])))
	# Ein gutes Intro ist Anerkennung, keine Gelddruckmaschine: je nach
	# Release-Qualitaet kommen nur 1--3 DM dazu.
	if disk.patch_state == "verified" and disk.cracktro_seen:
		var quality := int(disk.release_data.get("quality", disk.patch_score))
		base += clampi(1 + int(float(quality) / 40.0), 1, 3)
	return base


## Alle verkäuflichen Kopien in der Box (keine Originale — die sind Sammlung!).
func sellable_disks(location_id: String = "") -> Array:
	return DiskManager.disks.filter(func(d: Disk) -> bool:
		return d.is_player_made_copy() and d.content_type != "leer" and d.condition > 0 \
			and (d.disk_count <= 1 or d.disk_number == 1) \
			and bool(sale_status(d, location_id).get("ok", false)))


## Einheitliche Begruendung fuer UI und den eigentlichen Verkauf. Der Manager
## ist Autoritaet; der Fallback haelt alte/isolierte Tests trotzdem sicher.
func sale_status(disk: Disk, location_id: String = "") -> Dictionary:
	if disk == null:
		return {"ok": false, "text": Loc.t("sys.copy_trade_manager.keine_diskette_gewahlt", "Keine Diskette gewählt.")}
	if disk.provenance != "copy" or disk.content_type == "leer" or disk.condition <= 0:
		return {"ok": false, "text": Loc.t("sys.copy_trade_manager.nur_lesbare_kopien_mit_inhalt_sind", "Nur lesbare Kopien mit Inhalt sind verkäuflich.")}
	if not disk.is_player_made_copy():
		return {"ok": false, "reason": "protected_source", "text":
			"Gekaufte Quelldisk bleibt in deiner Sammlung. Erstelle zuerst mit X-COPY eine eigene Verkaufskopie."}
	if disk.disk_count > 1 and not DiskManager.has_complete_disk_set(disk):
		return {"ok": false, "reason": "incomplete_disk_set", "text":
			"Der Kopiensatz ist unvollständig. Für den Verkauf brauchst du alle %d Disketten." % disk.disk_count}
	for part: Disk in DiskManager.disk_set_parts(disk):
		if part.provenance != "copy" or part.condition <= 0:
			return {"ok": false, "reason": "invalid_disk_set", "text": Loc.t("sys.copy_trade_manager.mindestens_diskette_des_satzes_ist_nicht", "Mindestens eine Diskette des Satzes ist nicht verkäuflich.")}
		var part_gate := _sale_gate(part, location_id)
		if not bool(part_gate.get("ok", false)):
			return part_gate
	return _sale_gate(disk, location_id)


func _sale_gate(disk: Disk, location_id: String) -> Dictionary:
	var requirement: Dictionary = QuestManager.disk_requirement(disk)
	if bool(requirement.get("required", false)):
		return {
			"ok": false,
			"reason": "quest_required",
			"text": str(requirement.get("text",
				"Diese Diskette wird noch für eine offene Aufgabe benötigt.")),
		}
	var scene := get_node_or_null("/root/SceneReleaseManager")
	if scene != null and scene.has_method("sale_allowed"):
		var result: Variant = scene.call("sale_allowed", disk, location_id)
		if result is Dictionary:
			var normalized: Dictionary = result.duplicate()
			normalized["ok"] = bool(normalized.get("ok", false))
			if not normalized.has("text"):
				normalized["text"] = str(normalized.get("reason", "Diese Kopie ist noch nicht freigegeben."))
			return normalized
		return {"ok": bool(result), "text": "" if bool(result) else "Diese Kopie ist noch nicht freigegeben."}
	# Legacy-Fallback: Cracktro-Kopien aus alten Saves bleiben handelbar. Eine
	# neue rohe Kopie eines geschuetzten Titels darf den Schutz nicht umgehen.
	var software: Dictionary = CultureManager.software(disk.software_id)
	var protected := not software.is_empty() and str(software.get("protection", "keine")) != "keine"
	if protected and not (disk.cracktro and (disk.patch_state in ["verified", "legacy_scene"])):
		return {"ok": false, "reason": "raw_protected", "text":
			"Die rohe Kopie startet nicht. Erst in BYTEWERK verifizieren."}
	if protected and disk.patch_state == "verified" and not disk.cracktro_seen:
		return {"ok": false, "reason": "intro_unseen", "text":
			"Starte das Release einmal und sieh das Intro bis zum Spielstart."}
	return {"ok": true, "reason": "", "text": ""}


func sell(disk: Disk, location_id: String) -> Dictionary:
	var m := market(location_id)
	if m.is_empty():
		return {"ok": false, "text": Loc.t("sys.copy_trade_manager.hier_kauft_niemand_kopien", "Hier kauft niemand Kopien.")}
	# UI-Callbacks können nach einem Listen-Rebuild noch kurz leben. Eine bereits
	# entfernte Instanz darf deshalb niemals ein zweites Mal Geld/Ruf erzeugen.
	if disk == null or disk not in DiskManager.disks:
		return {"ok": false, "reason": "not_owned", "text":
			"Diese Diskette ist nicht mehr in deiner Box."}
	var gate := sale_status(disk, location_id)
	if not bool(gate.get("ok", false)):
		return {"ok": false, "text": str(gate.get("text", "Diese Kopie ist noch nicht verkäuflich.")),
			"reason": str(gate.get("reason", "blocked"))}
	if slots_left(location_id) <= 0:
		return {"ok": false, "text": Loc.t("sys.copy_trade_manager.fur_heute_ist_hier_niemand_mehr", "Für heute ist hier niemand mehr interessiert — morgen wieder.")}
	var sale_parts := DiskManager.disk_set_parts(disk)
	if sale_parts.is_empty():
		sale_parts = [disk]
	if sale_parts.any(func(part: Disk) -> bool: return part.virus and part.checked):
		return {"ok": false, "text": Loc.t("sys.copy_trade_manager.kopie_ist_verseucht_verkaufst_du_besser", "Die Kopie ist verseucht — die verkaufst du besser NICHT. Dein Ruf!")}
	# Der Schulhof bleibt eine soziale, nicht polizeiliche Risikozone. Wenn der
	# Manager eine Unterbrechung meldet, bleibt die Diskette sicher in der Box.
	var scene := get_node_or_null("/root/SceneReleaseManager")
	if location_id == "schoolyard" and scene != null and scene.has_method("school_risk"):
		var risk: Variant = scene.call("school_risk", disk)
		if risk is Dictionary and bool(risk.get("interrupted", false)):
			return {"ok": false, "reason": "interrupted", "text": str(risk.get("text",
				"Eine Aufsicht kommt um die Ecke. Du steckst die Diskette wieder ein."))}
	var price := offer_price(disk, location_id)
	for part: Disk in sale_parts:
		DiskManager.remove_disk(part)
	PlayerStats.add_money(price)
	RaidManager.track_sale(price)   # Kopien-Umsatz zählt fürs Razzia-Risiko
	AchievementManager.note("sold_copy")
	QuestManager.note_action("sell_copy")
	if sale_parts.all(func(part: Disk) -> bool: return part.label_quality >= 4):
		AchievementManager.note("sold_color")
		QuestManager.note_action("sell_color_copy")
	_sold_today[location_id] = sold_today(location_id) + 1
	PlayerStats.change_stat("ruf", 1)
	var scene_note := ""
	if scene != null and scene.has_method("note_sale"):
		var scene_result: Variant = scene.call("note_sale", disk, location_id, price)
		if scene_result is Dictionary:
			scene_note = str(scene_result.get("text", "")).strip_edges()
	AudioManager.play("coins")
	trade_changed.emit()
	var set_suffix := " (%d Disketten)" % disk.disk_count if disk.disk_count > 1 else ""
	var text := "»%s«%s für %d DM verkauft (%s)." % [disk.content_title if disk.content_title != "" else disk.display_name(), set_suffix, price, str(m["name"])]
	if scene_note != "":
		text += "  " + scene_note
	return {"ok": true, "text": text, "price": price}


func to_dict() -> Dictionary:
	return {"sold": _sold_today}


func from_dict(d: Dictionary) -> void:
	_sold_today = d.get("sold", {})


func reset() -> void:
	_sold_today = {}
