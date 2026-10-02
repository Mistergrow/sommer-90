extends Node
## Der Händler — ein diskreter Zwei-Wege-Markt. Er kauft alle lauffaehigen,
## selbst angefertigten Spielkopien und bewertet Zustand, Etikett, Satzgroesse
## und Menge. Aus seinem Koffer verkauft er wenige gepruefte Szene-Quellen
## beziehungsweise mit hoeherem Vertrauen gebrauchte Originale.
## Das Angebot ist klein, tagesstabil, historisch freigeschaltet und atomar gegen
## Geld sowie Diskettenbox-Kapazität abgesichert.
##
## Zustand liegt hier (Autoritaet); Save/Load via to_dict/from_dict, new_game -> reset.

signal dealer_changed   # UI aktualisieren (Vertrauen, Bestand und Preise)

const BASE_PAY := 9              # Grundpreis pro Kopie (mehr als Schulhof/Club)
const TRUST_PER_DEAL := 2
const FDD_REVEAL_AFTER := 6      # Deals bis zur FDD-Enthüllung (bei Lesefehlern früher) — erst wenn der Händler zur Einnahmequelle geworden ist

var trust: int = 0
var deals: int = 0
var wanted: String = ""
var wanted_day: int = -1
var fdd_hinted: bool = false
var known: bool = false          # ab genug Vertrauen nennt er seinen Namen
var stock_day: int = -1
var stock: Array = []            # kleine, persistente Kofferauswahl; nie 500er-Liste


func _ready() -> void:
	TimeManager.day_changed.connect(_on_day_changed)


func _on_day_changed() -> void:
	# Angebot erst beim nächsten Öffnen materialisieren. So bleibt Tageswechsel
	# billig und ein offenes Fenster bekommt trotzdem sofort eine neue Auswahl.
	stock_day = -1
	stock = []
	dealer_changed.emit()


# ------------------------------------------------------- Altsave-Kompatibilitaet

## wanted/wanted_day bleiben im Saveformat, damit bestehende Spielstaende ohne
## Datenverlust laden. Sie begrenzen den Verkauf nicht mehr.

func wanted_id() -> String:
	return ""


func wanted_title() -> String:
	return "ALLE SPIELBAREN KOPIEN"


func wanted_matches(disk: Disk) -> bool:
	return disk != null and disk.provenance == "copy" and disk.content_type == "spiel"


func _canonical_software_id(id: String) -> String:
	if SoftwareBible.has_software(id):
		return id
	# Save-Migration der früher gespeicherten disks.json-Template-IDs.
	return str((DiskManager.templates.get(id, {}) as Dictionary).get("software_id", ""))


func dealer_name() -> String:
	return "Der Händler" if not known else "Schröder"


# ---------------------------------------------------------------- Kofferware

## Wenige physische Angebote statt eines Katalogs. Die Auswahl wird aus den im
## aktuellen Jahr wirklich erschienenen, illustrierten Titeln gebildet und über
## Tag + Titel stabil sortiert. Zukünftige Spiele können nie auftauchen.
func _ensure_stock() -> void:
	var day := TimeManager.day_counter
	if stock_day == day and not stock.is_empty():
		return
	stock_day = day
	stock = []
	var pool: Array = SoftwareBible.shop_titles(TimeManager.year)
	pool = pool.filter(func(id: Variant) -> bool:
		return SoftwareBible.disk_count(str(id)) <= 4)
	pool.sort_custom(func(a: Variant, b: Variant) -> bool:
		return _stable_roll("%s/%d/stock" % [str(a), day]) \
			< _stable_roll("%s/%d/stock" % [str(b), day]))
	var amount := mini(4 + floori(float(trust) / 30.0), 5)
	for index in mini(amount, pool.size()):
		var software_id := str(pool[index])
		var info: Dictionary = SoftwareBible.entry(software_id)
		var count := SoftwareBible.disk_count(software_id)
		var roll := _stable_roll("%s/%d/value" % [software_id, day])
		var used_original := trust >= 10 and index == mini(amount, pool.size()) - 1
		var bytewerk_release := not used_original \
			and CultureManager.bytewerk_available_for_new_copy(software_id)
		var price := (24 + count * 7 + roll % 9) if used_original \
			else (7 + count * 3 + roll % 6)
		price = maxi(5, price - mini(5, floori(float(trust) / 12.0)))
		stock.append({
			"id": "%d_%02d" % [day, index],
			"software_id": software_id,
			"title": str(info.get("display_name", info.get("historical_name", software_id))),
			"kind": "used_original" if used_original else "scene_source",
			"bytewerk": bytewerk_release,
			"disk_count": count,
			"condition": 67 + roll % 28,
			"price": price,
			"sold": false,
		})


func _stable_roll(key: String) -> int:
	return posmod(key.hash(), 2147483647)


func stock_offers() -> Array:
	_ensure_stock()
	return stock.filter(func(offer: Dictionary) -> bool: return not bool(offer.get("sold", false)))


func stock_offer(id: String) -> Dictionary:
	_ensure_stock()
	for offer: Dictionary in stock:
		if str(offer.get("id", "")) == id:
			return offer
	return {}


func purchase_status(offer: Dictionary) -> Dictionary:
	if offer.is_empty() or bool(offer.get("sold", false)):
		return {"ok": false, "reason": "gone", "text": Loc.t("sys.dealer_manager.ware_ist_nicht_mehr_im_koffer", "Die Ware ist nicht mehr im Koffer.")}
	var required := maxi(1, int(offer.get("disk_count", 1)))
	if not DiskManager.can_store_disks(required):
		return {"ok": false, "reason": "capacity", "required_slots": required,
			"text": Loc.t("sys.dealer_manager.dafur_brauchst_du_d_freie_platze", "Dafür brauchst du %d freie Plätze. In deiner Box sind nur %d frei.") % [required, DiskManager.free_slots()]}
	var price := int(offer.get("price", 0))
	if PlayerStats.geld + 0.005 < float(price):
		return {"ok": false, "reason": "money", "text": Loc.t("sys.dealer_manager.dir_fehlen_d_dm_fur_diesen", "Dir fehlen %d DM für diesen Deal.") % ceili(float(price) - PlayerStats.geld)}
	return {"ok": true, "required_slots": required, "text": Loc.t("sys.dealer_manager.bar_diskret_sofort", "Bar, diskret und sofort.")}


## Kofferware atomar kaufen. Kapazität und Geld werden vor der Übergabe geprüft;
## bei einem unerwarteten Einlagerungsfehler wird die Abbuchung zurückgerollt.
func purchase(offer_id: String) -> Dictionary:
	var offer := stock_offer(offer_id)
	var gate := purchase_status(offer)
	if not bool(gate.get("ok", false)):
		return gate
	var software_id := str(offer.get("software_id", ""))
	var kind := str(offer.get("kind", "scene_source"))
	var provenance := "original" if kind == "used_original" else "copy"
	var acquired: Array = DiskManager.create_software_set(software_id, provenance,
		"Beim Händler gekauft, %s" % TimeManager.date_string())
	if acquired.is_empty():
		return {"ok": false, "reason": "content", "text": Loc.t("sys.dealer_manager.er_klappt_den_koffer_wieder_zu", "Er klappt den Koffer wieder zu. Mit dem Satz stimmt etwas nicht.")}
	var condition := int(offer.get("condition", 75))
	for part: Disk in acquired:
		part.condition = clampi(condition - (part.disk_number - 1), 1, 100)
		part.checked = true
		part.owner_history.append(dealer_name())
		part.write_protected = true
		if kind == "scene_source":
			# Gekaufte Szene-Disk bleibt eine geschützte Quelle: source_uid leer.
			# Erst die daraus erzeugte eigene Kopie darf später verkauft werden.
			part.provenance = "copy"
			part.copy_generation = 1
			part.source_uid = ""
			part.source_provenance = "dealer"
			part.brand = "NoName"
			part.label_quality = 1
			part.cracktro = true
			part.cracktro_seen = true
			if bool(offer.get("bytewerk", false)):
				part.patch_state = "verified"
				part.patch_score = 72 + _stable_roll(part.uid) % 24
				part.patch_stability = 88
				part.release_role = "distribution"
				part.release_serial = "BW-%04d-%04d" % [TimeManager.year, _stable_roll(software_id) % 10000]
			else:
				part.patch_state = "legacy_scene"
				part.release_role = "legacy"
		part.enforce_master_color()
	var price := int(offer.get("price", 0))
	if not PlayerStats.spend_money(price):
		return {"ok": false, "reason": "money", "text": Loc.t("sys.dealer_manager.abgezahlte_betrag_reicht_nicht", "Der abgezählte Betrag reicht nicht.")}
	if not DiskManager.add_disks(acquired):
		PlayerStats.add_money(price)
		return {"ok": false, "reason": "capacity", "text": Loc.t("sys.dealer_manager.ubergabe_wurde_storniert_deine_diskettenbox_ist", "Die Übergabe wurde storniert: Deine Diskettenbox ist voll.")}
	for index in stock.size():
		if str((stock[index] as Dictionary).get("id", "")) == offer_id:
			stock[index]["sold"] = true
			break
	trust = mini(100, trust + 1)
	PlayerStats.change_stat("ruf", 1)
	QuestManager.note_action("dealer_purchase")
	MemoryManager.record("haendler", "%s aus dem Koffer gekauft" % str(offer.get("title", "Spiel")))
	AudioManager.play("coins")
	dealer_changed.emit()
	return {"ok": true, "price": price,
		"text": Loc.t("sys.dealer_manager.kein_umtausch_s_wechselt_fur_d", "»Kein Umtausch.« %s wechselt für %d DM den Besitzer. %d Diskette(n) liegen jetzt in deiner Box.") % [
			str(offer.get("title", "Die Ware")), price, acquired.size()]}


# ---------------------------------------------------------------- Liefern

## Eigene, vollstaendige Kopiensaetze, die sofort lieferbar sind.
func deliverable_disks() -> Array:
	return candidate_disks().filter(func(d: Disk) -> bool:
		return bool(delivery_status(d).get("ok", false)))


## Alle Spielkopien in der Box — je Mehrdisketten-Satz nur die erste Diskette.
## Gekaufte Quelldisks und unfertige Releases bleiben sichtbar, damit die UI
## ihren Schutz oder den naechsten Arbeitsschritt erklaeren kann.
func candidate_disks() -> Array:
	var out: Array = DiskManager.disks.filter(func(d: Disk) -> bool:
		return wanted_matches(d) and d.is_player_made_copy() and not d.is_game_master() \
			and d.release_role not in ["master", "demo_master"] \
			and (d.disk_count <= 1 or d.disk_number == 1))
	out.sort_custom(func(a: Disk, b: Disk) -> bool:
		var ar := bool(delivery_status(a).get("ok", false))
		var br := bool(delivery_status(b).get("ok", false))
		if ar != br:
			return ar
		var ap := evaluate_pay(a) if ar else 0
		var bp := evaluate_pay(b) if br else 0
		return ap > bp if ap != bp else a.uid < b.uid)
	return out


func delivery_status(disk: Disk) -> Dictionary:
	return _is_valid_copy(disk)


## Prüft, ob eine Diskette eine lesbare, (bei geschützten Titeln) BYTEWERK-
## verifizierte Kopie ist — nutzt denselben Release-Gate wie der übrige Handel.
func _is_valid_copy(disk: Disk) -> Dictionary:
	if disk == null or disk.provenance != "copy" or disk.content_type == "leer" or disk.condition <= 0:
		return {"ok": false, "reason": "not_copy", "text": Loc.t("sys.dealer_manager.handler_will_nur_lesbare_kopien_mit", "Der Händler will nur lesbare Kopien mit Inhalt.")}
	if disk.release_role in ["master", "demo_master"] or disk.is_game_master():
		return {"ok": false, "reason": "master_protected", "text":
			"MASTERDISK · BLEIBT IM ARCHIV. Der Haendler kauft nur eine davon gezogene Arbeits- oder Verkaufskopie."}
	if not disk.is_player_made_copy():
		return {"ok": false, "reason": "protected_source", "text":
			"GEKAUFTE QUELLDISK · BLEIBT BEI DIR. Erstelle mit X-COPY eine eigene Kopie; nur diese wird übergeben."}
	var gate: Dictionary = CopyTradeManager.sale_status(disk, "dealer")
	if not bool(gate.get("ok", false)):
		return gate
	return {"ok": true, "reason": "", "text": Loc.t("sys.dealer_manager.komplette_satz_ist_lauffaehig_verkaufsbereit", "Der komplette Satz ist lauffaehig und verkaufsbereit.")}


func _sale_parts(disk: Disk) -> Array:
	var parts := DiskManager.disk_set_parts(disk)
	return parts if not parts.is_empty() else ([disk] if disk != null else [])


func _average_condition(parts: Array) -> float:
	if parts.is_empty():
		return 0.0
	var total := 0.0
	for part: Disk in parts:
		total += float(part.condition)
	return total / float(parts.size())


## Bezahlung pro vollständigem Satz: Grundwert und zusätzliche Disketten plus
## das schwächste Etikett, mittlerer Zustand und Händlervertrauen.
func evaluate_pay(disk: Disk) -> int:
	return int(pay_breakdown(disk).get("total", 0))


func pay_breakdown(disk: Disk) -> Dictionary:
	if disk == null:
		return {"base": 0, "label": 0, "condition": 0, "trust": 0, "total": 0,
			"disk_count": 0, "condition_percent": 0}
	var parts := _sale_parts(disk)
	if parts.is_empty():
		return {"base": 0, "label": 0, "condition": 0, "trust": 0, "total": 0,
			"disk_count": 0, "condition_percent": 0}
	var weakest_label := 4
	for part: Disk in parts:
		weakest_label = mini(weakest_label, clampi(part.label_quality, 0, 4))
	var condition_percent := roundi(_average_condition(parts))
	var base := BASE_PAY + maxi(0, parts.size() - 1) * 5
	var label_bonus := weakest_label * 3
	var condition_bonus := clampi(roundi(float(condition_percent) / 20.0), 0, 5)
	var trust_bonus := mini(8, floori(float(trust) / 6.0))
	var total := maxi(4, base + label_bonus + condition_bonus + trust_bonus)
	return {"base": base, "label": label_bonus, "condition": condition_bonus,
		"trust": trust_bonus, "total": total,
		"disk_count": parts.size(), "condition_percent": condition_percent,
		"preview_min": total if disk.checked else total - condition_bonus,
		"preview_max": total if disk.checked else total - condition_bonus + 5}


func _bulk_bonus_rate(quantity: int) -> int:
	if quantity >= 8: return 15
	if quantity >= 5: return 10
	if quantity >= 3: return 6
	if quantity >= 2: return 3
	return 0


## Aktuelles Angebot fuer alle sofort verkaufsfaehigen Saetze. Der Bonus gilt
## auf die Menge der Saetze, nicht auf die Zahl der Disketten eines Titels.
func bulk_quote() -> Dictionary:
	var entries: Array = []
	var subtotal := 0
	var disk_count := 0
	for candidate: Disk in deliverable_disks():
		var pay := evaluate_pay(candidate)
		var parts := _sale_parts(candidate)
		entries.append({"disk": candidate, "pay": pay, "parts": parts})
		subtotal += pay
		disk_count += parts.size()
	var rate := _bulk_bonus_rate(entries.size())
	var bonus := roundi(float(subtotal) * float(rate) / 100.0)
	return {"entries": entries, "quantity": entries.size(), "disk_count": disk_count,
		"subtotal": subtotal, "bonus_rate": rate, "bonus": bonus, "total": subtotal + bonus}


## Eine Kopie an den Händler liefern. {ok, text, pay}.
func deliver(disk: Disk) -> Dictionary:
	if disk == null or disk not in DiskManager.disks:
		return {"ok": false, "reason": "not_owned", "text": Loc.t("sys.dealer_manager.diese_diskette_liegt_nicht_mehr_in", "Diese Diskette liegt nicht mehr in deiner Box.")}
	var valid := _is_valid_copy(disk)
	if not bool(valid.get("ok", false)):
		return valid
	return _complete_sales([{"disk": disk, "pay": evaluate_pay(disk), "parts": _sale_parts(disk)}], false)


func deliver_all() -> Dictionary:
	var quote := bulk_quote()
	var entries: Array = quote.get("entries", [])
	if entries.is_empty():
		return {"ok": false, "reason": "empty", "text": Loc.t("sys.dealer_manager.in_deiner_box_liegt_gerade_kein", "In deiner Box liegt gerade kein verkaufsfaehiger Kopiensatz.")}
	return _complete_sales(entries, true)


func _complete_sales(requested: Array, bulk: bool) -> Dictionary:
	# Vor der Mutation jedes Angebot erneut pruefen. So kann ein alter UI-Callback
	# weder doppelt auszahlen noch einen inzwischen unvollstaendigen Satz verkaufen.
	var sales: Array = []
	var removals: Array = []
	var subtotal := 0
	var physical_disks := 0
	var low_read := false
	var weak_label := false
	for entry: Dictionary in requested:
		var representative := entry.get("disk") as Disk
		if representative == null or representative not in DiskManager.disks:
			continue
		var gate := _is_valid_copy(representative)
		if not bool(gate.get("ok", false)):
			continue
		var parts := _sale_parts(representative)
		if parts.is_empty() or parts.any(func(part: Disk) -> bool: return part in removals):
			continue
		var pay := evaluate_pay(representative)
		sales.append({"disk": representative, "parts": parts, "pay": pay})
		removals.append_array(parts)
		subtotal += pay
		physical_disks += parts.size()
		low_read = low_read or parts.any(func(part: Disk) -> bool: return part.condition < 70)
		weak_label = weak_label or parts.any(func(part: Disk) -> bool: return part.label_quality < 2)
	if sales.is_empty():
		return {"ok": false, "reason": "stale", "text": Loc.t("sys.dealer_manager.ausgewaehlten_kopien_sind_nicht_mehr_vollstaendig", "Die ausgewaehlten Kopien sind nicht mehr vollstaendig in deiner Box.")}
	var rate := _bulk_bonus_rate(sales.size()) if bulk else 0
	var bonus := roundi(float(subtotal) * float(rate) / 100.0)
	var total := subtotal + bonus
	var deals_before := deals
	var scene := get_node_or_null("/root/SceneReleaseManager")
	for sale: Dictionary in sales:
		var representative := sale.get("disk") as Disk
		var pay := int(sale.get("pay", 0))
		var parts: Array = sale.get("parts", [])
		if scene != null and scene.has_method("note_sale"):
			scene.call("note_sale", representative, "dealer", pay)
		AchievementManager.note("sold_copy")
		QuestManager.note_action("sell_copy")
		QuestManager.note_action("dealer_delivery")
		if not parts.is_empty() \
				and parts.all(func(part: Disk) -> bool: return part.label_quality >= 4):
			AchievementManager.note("sold_color")
			QuestManager.note_action("sell_color_copy")
	DiskManager.remove_disks(removals)
	PlayerStats.add_money(total)
	PlayerStats.change_stat("ruf", sales.size())
	trust = mini(100, trust + TRUST_PER_DEAL * sales.size())
	deals += sales.size()
	if has_node("/root/NPCManager"):
		NPCManager.change_trust("npc_haendler", 2 * sales.size())
	if trust >= 12:
		known = true
	AudioManager.play("coins")
	RaidManager.track_sale(total)

	var msg := ""
	if bulk:
		msg = "»Ich nehme alles, was sauber laeuft.« %d Kopiensaetze (%d Disketten): %d DM" % [
			sales.size(), physical_disks, subtotal]
		if bonus > 0:
			msg += " + %d DM Mengenbonus (%d %%)" % [bonus, rate]
		msg += " = %d DM." % total
	else:
		msg = "»Sauber. Laeuft, Etikett passt.« Der Haendler zaehlt dir %d DM fuer den kompletten Satz hin." % total
	# Etiketten-Tipp (einmal, frueh): saubere Labels = mehr Geld.
	if deals_before < 2 and deals >= 2 and weak_label \
			and not bool(GameManager.flags.get("dealer_label_tip", false)):
		GameManager.flags["dealer_label_tip"] = true
		msg += "\n\n»Tipp unter uns: Mit ordentlichem ETIKETT zahl ich spuerbar mehr. Besorg dir einen Drucker und mach saubere Labels.«"
	# FDD-Enthuellung: sein Testgeraet macht die Dejustage als echten Zustand sichtbar.
	if not fdd_hinted and (low_read or deals >= FDD_REVEAL_AFTER):
		fdd_hinted = true
		GameManager.flags["fdd_needs_service"] = true
		PlayerStats.set_drive_alignment(minf(PlayerStats.drive_alignment(), 0.58))
		msg += "\n\n»Moment.« Sein Testgeraet zeigt Spurfehler. »DF0 ist dejustiert. Lass das bei Gruber richten.«"
	dealer_changed.emit()
	return {"ok": true, "text": msg, "pay": total, "subtotal": subtotal,
		"bonus": bonus, "bonus_rate": rate, "quantity": sales.size(), "disk_count": physical_disks}


# ---------------------------------------------------------------- Persistenz

func to_dict() -> Dictionary:
	return {"trust": trust, "deals": deals, "wanted": wanted, "wanted_day": wanted_day,
		"fdd_hinted": fdd_hinted, "known": known,
		"stock_day": stock_day, "stock": stock.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	trust = int(d.get("trust", 0))
	deals = int(d.get("deals", 0))
	wanted = _canonical_software_id(str(d.get("wanted", "")))
	wanted_day = int(d.get("wanted_day", -1))
	fdd_hinted = bool(d.get("fdd_hinted", false))
	known = bool(d.get("known", false))
	stock_day = int(d.get("stock_day", -1))
	stock = (d.get("stock", []) as Array).duplicate(true)
	dealer_changed.emit()


func reset() -> void:
	trust = 0
	deals = 0
	wanted = ""
	wanted_day = -1
	fdd_hinted = false
	known = false
	stock_day = -1
	stock = []
