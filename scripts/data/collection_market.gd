class_name CollectionMarket
extends RefCounted
## Sammlungsökonomie: vollständige OVP-Sätze können gezielt verkauft werden,
## mehrere wertvolle Sätze finanzieren später das eigene Auto. Die Bestenliste
## liegt absichtlich außerhalb der Spielstände und vergleicht Durchläufe.

const CAR_PRICE := 2400
const HIGHSCORE_PATH := "user://collection_highscores.json"


static func set_sale_value(disk: Disk) -> int:
	if disk == null or disk.software_set_id.is_empty():
		return 0
	var total := 0
	for part: Disk in DiskManager.disks:
		if part.software_set_id == disk.software_set_id:
			total += part.value()
	var factor := 0.82 if disk.package_condition == "sealed" else 0.66
	return maxi(1, roundi(float(total) * factor))


static func sell_set(disk: Disk, silent := false) -> Dictionary:
	if disk == null or disk.provenance != CultureManager.PROVENANCE_ORIGINAL_BOX \
			or not DiskManager.has_complete_disk_set(disk):
		return {"ok": false, "text": Loc.t("misc.collection_market.nur_vollstandige_original_ovp_kann_als", "Nur eine vollständige Original-OVP kann als Satz verkauft werden.")}
	var set_id := disk.software_set_id
	var title := disk.content_title
	var payout := set_sale_value(disk)
	var removed := _remove_set(set_id)
	if removed <= 0:
		return {"ok": false, "text": Loc.t("misc.collection_market.satz_ist_nicht_mehr_vollstandig_in", "Der Satz ist nicht mehr vollständig in der Sammlung.")}
	PlayerStats.add_money(payout)
	GameManager.flags["collection_sets_sold"] = int(GameManager.flags.get("collection_sets_sold", 0)) + 1
	GameManager.flags["collection_sales_dm"] = int(GameManager.flags.get("collection_sales_dm", 0)) + payout
	MemoryManager.record("sammlung", "%s als vollständige OVP für %d DM verkauft" % [title, payout])
	DiskManager.disks_changed.emit()
	if not silent:
		UIManager.toast(Loc.t("misc.collection_market.sammlungsverkauf_s_d_dm", "Sammlungsverkauf: %s · +%d DM") % [title, payout])
	return {"ok": true, "text": "%s verkauft · +%d DM" % [title, payout], "payout": payout, "removed": removed}


static func car_plan() -> Dictionary:
	var shortage := maxi(0, CAR_PRICE - floori(PlayerStats.geld))
	var candidates: Array = DiskManager.boxed_collection()
	# Satzwert je Kandidat EINMAL bestimmen: set_sale_value laeuft ueber die ganze
	# Sammlung — im Sortier-Callback wuerde das bei jedem Vergleich erneut passieren.
	var values: Dictionary = {}
	for disk: Disk in candidates:
		values[disk.uid] = set_sale_value(disk)
	candidates.sort_custom(func(a: Disk, b: Disk) -> bool: return int(values[a.uid]) > int(values[b.uid]))
	var selected: Array = []
	var proceeds := 0
	for disk: Disk in candidates:
		if proceeds >= shortage:
			break
		selected.append(disk)
		proceeds += int(values[disk.uid])
	return {
		"ok": bool(GameManager.flags.get("has_license", false)) and not bool(GameManager.flags.get("owns_car", false))
			and proceeds >= shortage,
		"needs_license": not bool(GameManager.flags.get("has_license", false)),
		"already_owned": bool(GameManager.flags.get("owns_car", false)),
		"price": CAR_PRICE, "shortage": shortage, "proceeds": proceeds,
		"sets": selected,
	}


static func buy_car_from_collection() -> Dictionary:
	var plan := car_plan()
	if bool(plan.get("already_owned", false)):
		return {"ok": false, "text": Loc.t("misc.collection_market.dein_auto_steht_bereits_vor_tur", "Dein Auto steht bereits vor der Tür.")}
	if bool(plan.get("needs_license", false)):
		return {"ok": false, "text": Loc.t("misc.collection_market.erst_den_fuhrerschein_machen_ohne_lappen", "Erst den Führerschein machen — ohne Lappen kein eigenes Auto.")}
	if not bool(plan.get("ok", false)):
		return {"ok": false, "text": Loc.t("misc.collection_market.bargeld_verkaufliche_komplett_ovps_reichen_noch", "Bargeld und verkäufliche Komplett-OVPs reichen noch nicht für %d DM.") % CAR_PRICE}
	var sold := 0
	var proceeds := 0
	for disk: Disk in plan.get("sets", []):
		var result := sell_set(disk, true)
		if bool(result.get("ok", false)):
			sold += 1
			proceeds += int(result.get("payout", 0))
	if not PlayerStats.spend_money(CAR_PRICE):
		return {"ok": false, "text": Loc.t("misc.collection_market.handler_kann_finanzierung_gerade_nicht_abschliessen", "Der Händler kann die Finanzierung gerade nicht abschließen.")}
	GameManager.flags["owns_car"] = true
	GameManager.flags["car_from_collection"] = sold > 0
	GameManager.flags["car_purchase_year"] = TimeManager.year
	MemoryManager.record_once("first_car", "das erste eigene Auto mit %d Sammlungs-OVP(s) mitfinanziert" % sold)
	QuestManager.note_action("buy_car")
	QuestManager.evaluate()
	return {"ok": true, "text": "EIGENES AUTO! %d OVP(s) brachten %d DM; Kaufpreis %d DM." % [sold, proceeds, CAR_PRICE],
		"sets_sold": sold, "proceeds": proceeds}


static func sell_all_boxed() -> Dictionary:
	var boxed: Array = DiskManager.boxed_collection()
	var payout := 0
	var sets := 0
	for disk: Disk in boxed:
		var result := sell_set(disk, true)
		if bool(result.get("ok", false)):
			payout += int(result.get("payout", 0))
			sets += 1
	return {"ok": sets > 0, "sets": sets, "payout": payout,
		"text": Loc.t("misc.collection_market.d_vollstandige_ovp_satze_verkauft_d", "%d vollständige OVP-Sätze verkauft · +%d DM") % [sets, payout]}


static func submit_highscore(category: String) -> Dictionary:
	category = "liquidator" if category == "liquidator" else "collector"
	var collection_value := DiskManager.collection_value()
	var cash_total := floori(PlayerStats.geld + BankManager.total())
	var score := cash_total if category == "liquidator" else collection_value
	var data := _load_scores()
	var rows: Array = data.get(category, [])
	var entry := {
		"name": PlayerIdentity.player_name if PlayerIdentity.player_name != "" else "SPIELER",
		"score": score, "cash": cash_total, "collection": collection_value,
		"sets": DiskManager.boxed_collection().size(), "year": TimeManager.year,
		"date": Time.get_datetime_string_from_system(),
	}
	rows.append(entry)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("score", 0)) > int(b.get("score", 0)))
	var rank := rows.find(entry) + 1
	if rows.size() > 10:
		rows.resize(10)
	data[category] = rows
	_store_scores(data)
	return {"ok": true, "category": category, "score": score, "rank": rank, "rows": rows}


static func highscores(category: String) -> Array:
	return (_load_scores().get(category, []) as Array).duplicate(true)


static func _remove_set(set_id: String) -> int:
	var removed := 0
	for index in range(DiskManager.disks.size() - 1, -1, -1):
		var disk: Disk = DiskManager.disks[index]
		if disk.software_set_id == set_id:
			DiskManager.disks.remove_at(index)
			removed += 1
	return removed


static func _load_scores() -> Dictionary:
	if not FileAccess.file_exists(HIGHSCORE_PATH):
		return {"collector": [], "liquidator": []}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(HIGHSCORE_PATH))
	return parsed if parsed is Dictionary else {"collector": [], "liquidator": []}


static func _store_scores(data: Dictionary) -> void:
	var file := FileAccess.open(HIGHSCORE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
