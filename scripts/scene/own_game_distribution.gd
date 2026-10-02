class_name OwnGameDistribution
extends RefCounted
## Endlicher Umsatzvertrag fuer das 1992 entwickelte eigene Spiel. Der
## SceneReleaseManager besitzt und speichert den Zustand; dieses Modul kapselt
## Vorschuss, Wochenabrechnung, Ledger und Altspielstand-Reparatur.

const ROYALTY_INTERVAL_DAYS := 7
const ROYALTY_MAX_PAYMENTS := 8
const LEGACY_SETTLEMENT := 8


static func start(owner: Node, mode: String, initial_payout: int) -> Dictionary:
	mode = "paid" if mode in ["paid", "money", "kleinserie"] else "club"
	var contract: Dictionary = owner.get("game_distribution")
	if not contract.is_empty():
		return {
			"ok": true, "new": false, "payout": 0,
			"text": Loc.t("misc.own_game_distribution.distributionsweg_fuer_dein_spiel_ist_bereits", "Der Distributionsweg fuer dein Spiel ist bereits festgelegt."),
		}
	var release := _first_release()
	var serial := str(release.get("serial", "GAME-1992-BACKCATALOG"))
	var title := str(release.get("title", "ERSTES EIGENES SPIEL"))
	var quality := clampi(int(release.get("quality", 75)), 1, 100)
	var day := int(TimeManager.day_counter)
	contract = {
		"mode": mode, "serial": serial, "title": title, "quality": quality,
		"started_day": day, "next_payout_day": day + ROYALTY_INTERVAL_DAYS,
		"payments": 0,
		"max_payments": ROYALTY_MAX_PAYMENTS if mode == "paid" else 0,
		"total_income": 0, "migrated": false,
	}
	owner.set("game_distribution", contract)
	var payout := maxi(0, initial_payout) if mode == "paid" else 0
	if payout > 0:
		PlayerStats.add_money(payout)
		contract["total_income"] = payout
		_record(owner, payout, "vorschuss")
		AudioManager.play("coins")
	owner.emit_signal("scene_changed")
	return {
		"ok": true, "new": true, "payout": payout,
		"text": ("%s: %d DM Vorschuss, danach acht begrenzte Wochenabrechnungen."
			% [title, payout]) if mode == "paid"
			else "%s wird im Club frei verteilt: kein Verkauf, dafuer Reichweite und Ruf."
				% title,
	}


## Alte Saves speicherten nur die Entscheidung, nicht den Umsatz. Bezahlte
## Altvertraege erhalten einmalig eine kleine Nachzahlung und starten danach
## die begrenzte Backkatalogserie; erneutes Laden zahlt niemals doppelt.
static func reconcile(owner: Node) -> bool:
	var contract: Dictionary = owner.get("game_distribution")
	if not contract.is_empty() or not QuestManager.is_done("q_eigenes_spiel"):
		return false
	var paid := bool(GameManager.flags.get("game_distribution_money", false))
	var club := bool(GameManager.flags.get("game_distribution_reputation", false))
	if not paid and not club:
		return false
	var result := start(owner, "paid" if paid else "club", 0)
	if not bool(result.get("new", false)):
		return false
	contract = owner.get("game_distribution")
	contract["migrated"] = true
	if paid:
		contract["next_payout_day"] = int(TimeManager.day_counter) + 1
		contract["total_income"] = LEGACY_SETTLEMENT
		PlayerStats.add_money(LEGACY_SETTLEMENT)
		_record(owner, LEGACY_SETTLEMENT, "altstand_nachzahlung")
		MemoryManager.record_once("own_game_backcatalog_settlement",
			"Nachabrechnung fuer das 1992 veroeffentlichte eigene Spiel erhalten")
		UIManager.toast(Loc.t("misc.own_game_distribution.kleinserien_nachabrechnung_d_dm_weitere_begrenzte", "Kleinserien-Nachabrechnung: +%d DM. Weitere begrenzte Erlöse folgen wöchentlich.") \
			% LEGACY_SETTLEMENT)
		AudioManager.play("coins")
	owner.emit_signal("scene_changed")
	return true


static func status(owner: Node) -> Dictionary:
	var contract: Dictionary = owner.get("game_distribution")
	if contract.is_empty():
		return {"active": false, "mode": "", "title": "", "total_income": 0}
	var result := contract.duplicate(true)
	result["active"] = str(result.get("mode", "")) == "paid" \
		and int(result.get("payments", 0)) < int(result.get("max_payments", 0))
	result["payments_left"] = maxi(0, int(result.get("max_payments", 0))
		- int(result.get("payments", 0)))
	return result


static func settle(owner: Node) -> int:
	var contract: Dictionary = owner.get("game_distribution")
	if contract.is_empty() or str(contract.get("mode", "")) != "paid":
		return 0
	var payments := int(contract.get("payments", 0))
	var max_payments := int(contract.get("max_payments", ROYALTY_MAX_PAYMENTS))
	if payments >= max_payments \
			or int(TimeManager.day_counter) < int(contract.get("next_payout_day", 0)):
		return 0
	var base := clampi(roundi(float(contract.get("quality", 75)) / 25.0), 2, 4)
	var payout := maxi(1, base - floori(float(payments) / 2.0))
	contract["payments"] = payments + 1
	contract["total_income"] = int(contract.get("total_income", 0)) + payout
	contract["next_payout_day"] = int(TimeManager.day_counter) \
		+ ROYALTY_INTERVAL_DAYS
	PlayerStats.add_money(payout)
	_record(owner, payout, "wochenabrechnung")
	UIManager.toast(Loc.t("misc.own_game_distribution.s_kleinserie_d_dm_noch_d", "»%s« Kleinserie: +%d DM · noch %d Abrechnung(en).") % [
		str(contract.get("title", "Eigenes Spiel")), payout,
		maxi(0, max_payments - payments - 1)])
	AudioManager.play("coins")
	return payout


static func _first_release() -> Dictionary:
	var candidates: Array[Dictionary] = []
	for disk: Disk in DiskManager.disks:
		if str(disk.release_data.get("project_kind", "")) != "game":
			continue
		candidates.append({
			"serial": disk.release_serial,
			"title": disk.content_title if not disk.content_title.is_empty() else disk.label,
			"quality": int(disk.release_data.get("score",
				disk.release_data.get("quality", 75))),
			"year": int(disk.release_data.get("year", disk.year_created)),
		})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("year", 1992)) != int(b.get("year", 1992)):
			return int(a.get("year", 1992)) < int(b.get("year", 1992))
		return str(a.get("serial", "")) < str(b.get("serial", "")))
	return candidates[0]


static func _record(owner: Node, amount: int, kind: String) -> void:
	var contract: Dictionary = owner.get("game_distribution")
	var installment := int(contract.get("payments", 0))
	var serial := str(contract.get("serial", "GAME-1992-BACKCATALOG"))
	var ledger: Array = owner.get("sales")
	ledger.append({
		"disk_uid": "own_game/%s/%s/%d" % [serial, kind, installment],
		"serial": serial, "title": str(contract.get("title", "Eigenes Spiel")),
		"location": "kleinserie", "price": amount,
		"date": TimeManager.date_string(), "source": "own_game_distribution",
		"installment": installment, "kind": kind,
	})
