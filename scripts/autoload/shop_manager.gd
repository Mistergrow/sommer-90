extends Node
## ShopManager — Computerladen-Sortiment aus data/shop.json.
## Das Angebot ist Timeline-gefiltert (year_available/year_obsolete) und
## der Preis folgt dem Jahres-Preisfaktor: Hardware wird über die Jahre
## billiger, verschwindet aber auch wieder aus den Regalen.

signal shop_changed

var items: Array = []  # alle Shop-Items (ungefiltert)
var drift_issues: Array[String] = []


func _ready() -> void:
	_load_data()


func _load_data() -> void:
	var file := FileAccess.open("res://data/shop.json", FileAccess.READ)
	if file == null:
		push_error("shop.json fehlt!")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("shop.json ist kein gueltiges JSON-Objekt!")
		return
	var data: Dictionary = parsed
	items = data.get("items", [])
	drift_issues = []
	_check_hardware_db_drift()


## Drift-Guard (Muster town.json): Shop-Artikel mit db_name referenzieren die
## HardwareBible als Katalog-Wahrheit — Eintrag muss existieren, und verkauft
## wird nichts VOR seiner Markteinführung. Fiktive Homage-Geräte (MX-90 …)
## tragen bewusst KEIN db_name.
func _check_hardware_db_drift() -> void:
	if not HardwareBible.loaded:
		HardwareBible.reload()   # Autoload-Reihenfolge absichern
	for item: Dictionary in items:
		var db_name := str(item.get("db_name", ""))
		if db_name.is_empty():
			continue
		if not HardwareBible.has_device(db_name):
			drift_issues.append("'%s' verweist auf fehlenden Katalog-Eintrag '%s'."
				% [item.get("name", "?"), db_name])
			continue
		var shop_from := int(item.get("year_available", 1990))
		var shop_to := int(item.get("year_obsolete", 1999))
		var bible_from := HardwareBible.year_from(db_name)
		var bible_to := HardwareBible.year_to(db_name)
		if shop_from < bible_from:
			drift_issues.append("'%s' ab %d im Laden, Katalog-Markteinführung erst %d."
				% [item.get("name", "?"), shop_from, bible_from])
		if bible_to > 0 and shop_to > bible_to:
			drift_issues.append("'%s' bis %d im Laden, Katalog-Marktzeit endet %d."
				% [item.get("name", "?"), shop_to, bible_to])
	for issue: String in drift_issues:
		push_warning("Shop-Drift: " + issue)


## Effektive Marktzeit eines Artikels. Autorensortiment und HardwareBible werden
## geschnitten: Gruber darf ein Modell enger kuratieren, aber niemals vor oder
## nach der belegten Marktzeit fuehren. Artikel ohne db_name bleiben rein
## timeline-getrieben.
func market_years(item: Dictionary) -> Vector2i:
	var year_from := int(item.get("year_available", 1990))
	var year_to := int(item.get("year_obsolete", 1999))
	var db_name := str(item.get("db_name", ""))
	if db_name != "" and HardwareBible.has_device(db_name):
		year_from = maxi(year_from, HardwareBible.year_from(db_name))
		var bible_to := HardwareBible.year_to(db_name)
		if bible_to > 0:
			year_to = mini(year_to, bible_to)
	return Vector2i(year_from, year_to)


## Zentraler Era-Guard fuer Regal, Katalog UND direkte Kauf-APIs.
func is_item_available(item: Dictionary, year: int = -1) -> bool:
	if item.is_empty():
		return false
	var at_year := TimeManager.year if year < 0 else year
	var market := market_years(item)
	if at_year < market.x or at_year > market.y:
		return false
	# Saisonfelder brauchen Datumskontext und gelten deshalb nur fuer das echte
	# aktuelle Jahr. Hardware ist derzeit nicht saisonal, der Vertrag bleibt aber
	# mit TimelineManager konsistent.
	return TimelineManager.is_available(item) if at_year == TimeManager.year else true


## Aktuelles Regal-Sortiment (Living-Timeline-Filter, ohne Bestellware).
func current_stock() -> Array:
	var result: Array = []
	for item: Dictionary in items:
		if not item.get("order_only", false) and is_item_available(item):
			result.append(_localized_item(item))
	return result


## Bestellkatalog: seltene/teure Ware, die es nur auf Bestellung gibt
## (OrderManager wickelt Lieferzeit + Abholung ab).
func catalog() -> Array:
	var result: Array = []
	for item: Dictionary in items:
		if item.get("order_only", false) and is_item_available(item):
			result.append(_localized_item(item))
	return result


## Tagespreis eines Items inkl. Jahres-Preisfaktor.
func price_of(item: Dictionary) -> int:
	var factor := 1.0 if bool(item.get("fixed_price", false)) else TimelineManager.price_factor()
	return maxi(1, roundi(float(item.get("price", 1)) * factor))


## Eine gemeinsame, UI-sichere Preiszusage fuer Regal, Bestellkatalog und
## Hardwarebaum. So kann keine Oberflaeche den JSON-Basispreis anzeigen,
## waehrend die Kauf-API den zeitabhaengigen Marktpreis abbucht.
func price_quote(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {"base_price": 0.0, "factor": 1.0, "price": 0.0,
			"affordable": true, "shortfall": 0.0}
	var base_price := float(item.get("price", 0.0))
	var factor := 1.0 if bool(item.get("fixed_price", false)) else TimelineManager.price_factor()
	var price := float(price_of(item))
	var shortfall := Currency.snap(maxf(0.0, price - PlayerStats.geld))
	return {
		"base_price": base_price,
		"factor": factor,
		"price": price,
		"affordable": shortfall <= 0.005,
		"shortfall": shortfall,
	}


## Technische Voraussetzungen gelten fuer ALLE Kaufwege (Regal, Katalog und
## direkte API), nicht nur fuer die Karten im Aufruestbaum.
func item_requirement_status(item: Dictionary) -> Dictionary:
	var raw: Variant = item.get("requires_hardware", [])
	var required: Array = raw if raw is Array else ([str(raw)] if not str(raw).is_empty() else [])
	for hardware_id: Variant in required:
		var id := str(hardware_id)
		if not PlayerStats.has_hardware(id):
			return {"ok": false, "reason": "braucht zuerst %s" % _hardware_display_name(id),
				"hardware": id}
	return {"ok": true, "reason": ""}


func _hardware_display_name(hardware_id: String) -> String:
	for candidate: Dictionary in items:
		if str((candidate.get("payload", {}) as Dictionary).get("hardware", "")) == hardware_id:
			return str(_localized_item(candidate).get("name", hardware_id))
	return hardware_id.replace("_", " ")


# --------------------------------------------------------------- Spiele-Regal
const GAME_SHELF := 14   # so viele Boxspiele stehen gleichzeitig im Regal

## Spiele, die AKTUELL im Laden stehen: KURATIERTE, wöchentlich wechselnde Auswahl
## aus dem verfügbaren Jahrgang (nicht mehr der ganze Katalog). Neuere bevorzugt,
## pro Woche stabil (Seed = Jahr + Kalenderwoche seit Spielstart). Neu importierte
## Titel erscheinen automatisch im richtigen Jahr und rotieren mit.
func game_stock() -> Array:
	var stock_seed := TimeManager.year * 53 + floori(TimeManager.day_counter / 7.0)
	return SoftwareBible.shop_stock(TimeManager.year, stock_seed, GAME_SHELF)


## Alle bis heute erschienenen, vollständig bebilderten OVPs. Das ist der
## durchsuchbare Händlerkatalog; `game_stock()` bleibt das kleine physische
## Regal. Dadurch sind Altveröffentlichungen weiterhin bestellbar, ohne dass
## Hunderte Boxen gleichzeitig im Laden stehen müssen.
func game_catalog() -> Array:
	return SoftwareBible.catalog_titles(TimeManager.year)


## Neuerscheinung dieses Jahr? (für die „NEU"-Markierung im Regal)
func is_new_release(software_id: String) -> bool:
	return int(SoftwareBible.entry(software_id).get("release_year", 0)) == TimeManager.year


## Preis + Preisstufe eines OVP-Boxspiels, altersabhängig:
##   NEU (Erscheinungsjahr): 89 DM Vollpreis · 1–2 Jahre: fällt ~20 DM/Jahr ·
##   ab 3 Jahren: BUDGET/Neuauflage (Sonderposten, ~29 DM abwärts bis 15).
func game_offer(software_id: String) -> Dictionary:
	var e := SoftwareBible.entry(software_id)
	var ry := int(e.get("release_year", TimeManager.year))
	var age := maxi(0, TimeManager.year - ry)
	if age <= 0:
		return {"price": 89, "tier": "neu"}
	if age >= 3:
		return {"price": clampi(29 - (age - 3) * 3, 15, 29), "tier": "budget"}
	return {"price": clampi(89 - age * 20, 45, 89), "tier": ""}


func game_price(software_id: String) -> int:
	return int(game_offer(software_id)["price"])


## "neu" | "budget" | "" — für die Regal-Markierung.
func price_tier(software_id: String) -> String:
	return str(game_offer(software_id)["tier"])


## Boxspiel im Laden kaufen → fabrikneue OVP-Diskette (funktioniert, geprüft).
func buy_game(software_id: String) -> Dictionary:
	# Die UI kann noch eine Auswahl des vorigen Wochenregals halten. Autoritaet
	# bleibt der Manager: Zukunftstitel und reine Bestellware sind kein Sofortkauf.
	if not is_game_catalogued(software_id):
		return {"ok": false, "text": Loc.t("sys.order_manager.spiel_nicht_im_ovp_katalog",
			"Dieser Titel ist noch nicht im OVP-Katalog des Ladens verfügbar.")}
	if not game_stock().has(software_id):
		return {"ok": false, "text": Loc.t("sys.shop_manager.ist_bestellware_bitte_uber_grubers_bestellkatalog",
			"Das ist Bestellware. Bitte über Grubers Bestellkatalog ordern.")}
	var disk_count := SoftwareBible.disk_count(software_id)
	# Erst die Diskette erzeugen/prüfen, DANN bezahlen — sonst zahlt man bei
	# einem der Bibel unbekannten Titel und bekäme nichts.
	var game_disks := DiskManager.create_software_set(software_id, "original_box",
		"Neu gekauft im Computerladen, %s" % TimeManager.date_string())
	if game_disks.is_empty():
		return {"ok": false, "text": Loc.t("sys.shop_manager.artikel_nicht_gefunden", "Artikel nicht gefunden.")}
	var price := game_price(software_id)
	if not PlayerStats.spend_money(price):
		return {"ok": false, "text": Loc.t("sys.shop_manager.zu_teuer_dir_fehlen_s", "Zu teuer. Dir fehlen %s.") % Currency.format(price - PlayerStats.geld)}
	for disk: Disk in game_disks:
		disk.checked = true                       # Neuware läuft
		disk.condition = 100
		disk.package_condition = "sealed"
	if not DiskManager.add_disks(game_disks):
		PlayerStats.add_money(price)
		return {"ok": false, "text": Loc.t("sys.shop_manager.vollstandige_ovp_konnte_nicht_in_sammlung", "Die vollständige OVP konnte nicht in die Sammlung übernommen werden. Kauf storniert.")}
	shop_changed.emit()
	var nm := str(SoftwareBible.entry(software_id).get("display_name", "Spiel"))
	return {"ok": true, "text": Loc.t("sys.shop_manager.s_gekauft_fabrikneu_versiegelt_d_diskette", "»%s« gekauft — fabrikneu und versiegelt, %d Diskette(n), Box und Handbuch. Herr Gruber nickt anerkennend.") % [nm, disk_count], "disk_count": disk_count}


## Spiele aus dem vollständigen, bis heute erschienenen OVP-Katalog, die gerade
## NICHT im Regal stehen — die kann der Laden beim Großhändler, aus Restlagern
## oder über den Archivverbund bestellen (OrderManager).
func orderable_games() -> Array:
	var shelf: Dictionary = {}
	for id: String in game_stock():
		shelf[id] = true
	var out: Array = []
	for id: String in game_catalog():
		if not shelf.has(id):
			out.append(id)
	return out


func is_game_catalogued(software_id: String) -> bool:
	return game_catalog().has(software_id)


## Auslieferung einer Sonderbestellung (bereits bei der Bestellung bezahlt) →
## fabrikneue OVP-Diskette in die Box. Wird von OrderManager.pickup aufgerufen.
func deliver_game(software_id: String) -> Dictionary:
	var disk_count := SoftwareBible.disk_count(software_id)
	var game_disks := DiskManager.create_software_set(software_id, "original_box",
		"Sonderbestellung bei Herrn Gruber, %s" % TimeManager.date_string())
	if game_disks.is_empty():
		return {"ok": false, "text": Loc.t("sys.shop_manager.artikel_nicht_gefunden", "Artikel nicht gefunden.")}
	for disk: Disk in game_disks:
		disk.checked = true
		disk.condition = 100
		disk.package_condition = "sealed"
	if not DiskManager.add_disks(game_disks):
		return {"ok": false, "text": Loc.t("sys.shop_manager.vollstandige_ovp_konnte_nicht_in_sammlung_b427", "Die vollständige OVP konnte nicht in die Sammlung übernommen werden.")}
	shop_changed.emit()
	var nm := str(SoftwareBible.entry(software_id).get("display_name", "Spiel"))
	return {"ok": true, "text": Loc.t("sys.shop_manager.s_deine_bestellung_original_verpackt_mit", "»%s« — deine Bestellung, original verpackt mit %d Diskette(n)!") % [nm, disk_count], "disk_count": disk_count}


func get_item(id: String) -> Dictionary:
	for item in items:
		if item.get("id", "") == id:
			return _localized_item(item)
	return {}


## Daten und Saves behalten ihre stabilen Artikel-IDs. Nur die Kopie, die eine
## Oberflaeche erhaelt, wird in die aktive Sprache uebersetzt; ein Sprachwechsel
## kann deshalb niemals Preis-, Besitz- oder Bestelllogik veraendern.
func _localized_item(source: Dictionary) -> Dictionary:
	var item := source.duplicate(true)
	var item_id := str(source.get("id", ""))
	if item_id.is_empty():
		return item
	for field: String in ["name", "desc", "description"]:
		var fallback := str(source.get(field, ""))
		if not fallback.is_empty():
			item[field] = Loc.t("wares.%s.%s" % [item_id, field], fallback)
	return item


## Katalogeintrag zu einem Besitzflag. Geräteverkauf und Inventar lesen damit
## denselben Namen/Listenpreis wie Bestellung und Abholung.
func item_for_hardware(hardware_id: String) -> Dictionary:
	for item: Dictionary in items:
		if str(item.get("action", "")) != "add_hardware":
			continue
		if str((item.get("payload", {}) as Dictionary).get("hardware", "")) == hardware_id:
			return _localized_item(item)
	return {}


## Garantierter Gebrauchtwert: mindestens die Hälfte des höchsten regulären
## Ladenpreises, zu dem das Gerät bis heute angeboten worden sein konnte.
## Dadurch verlieren frühe Käufe mit höherem Zeitfaktor nicht rückwirkend Geld.
func hardware_resale_value(hardware_id: String) -> int:
	var item := item_for_hardware(hardware_id)
	if item.is_empty():
		return 0
	var base := float(item.get("price", 0))
	var highest_price := base
	var years := market_years(item)
	var last_year := mini(TimeManager.year, years.y)
	if last_year >= years.x:
		for year in range(years.x, last_year + 1):
			var factor := float(TimelineManager.year_data(year).get("price_factor", 1.0))
			highest_price = maxf(highest_price, float(roundi(base * factor)))
	return ceili(highest_price * 0.5)


## Kauf abwickeln. Prüft Geld und (bei Disketten) Boxplatz VOR der Buchung.
## Rückgabe: {ok: bool, text: String} für die UI.
func buy(id: String) -> Dictionary:
	var item := get_item(id)
	if item.is_empty():
		return {"ok": false, "text": Loc.t("sys.shop_manager.artikel_nicht_gefunden", "Artikel nicht gefunden.")}
	if not is_item_available(item):
		return {"ok": false, "text": Loc.t("sys.shop_manager.dieses_modell_fuhrt_herr_gruber_in", "Dieses Modell führt Herr Gruber in diesem Jahr nicht.")}
	if bool(item.get("order_only", false)):
		return {"ok": false, "text": Loc.t("sys.shop_manager.ist_bestellware_bitte_uber_grubers_bestellkatalog", "Das ist Bestellware. Bitte über Grubers Bestellkatalog ordern.")}
	var requirement := item_requirement_status(item)
	if not bool(requirement.get("ok", false)):
		return {"ok": false, "text": Loc.t("sys.shop_manager.noch_nicht_moglich_s", "Noch nicht möglich: %s.") % str(requirement.get("reason", "Voraussetzung fehlt"))}
	var price := price_of(item)
	var action: String = item.get("action", "")
	var payload: Dictionary = item.get("payload", {})

	# Boxplatz vor dem Bezahlen prüfen — kein Geld für nichts!
	if action == "add_blank_disk" and DiskManager.free_slots() <= 0:
		return {"ok": false, "text": Loc.t("sys.shop_manager.deine_diskettenbox_ist_voll_erst_platz", "Deine Diskettenbox ist voll. Erst Platz schaffen (oder eine Box kaufen).")}
	if action == "add_hardware" and PlayerStats.has_hardware(payload.get("hardware", "")):
		return {"ok": false, "text": Loc.t("sys.shop_manager.hast_du_schon_herr_gruber_schaut", "Hast du schon! Herr Gruber schaut irritiert.")}
	if not PlayerStats.spend_money(price):
		return {"ok": false, "text": Loc.t("sys.shop_manager.zu_teuer_dir_fehlen_s", "Zu teuer. Dir fehlen %s.") % Currency.format(price - PlayerStats.geld)}

	var text := apply_action(item)
	if text == "":
		PlayerStats.add_money(price)   # unbekannte Aktion → Geld zurück, nicht einbehalten
		return {"ok": false, "text": "Unbekannte Kauf-Aktion: %s" % action}
	shop_changed.emit()
	return {"ok": true, "text": text}


## Kauf-Aktion eines Artikels ausführen (ohne Bezahlung/Prüfung) und die
## Bestätigungszeile liefern. Von buy() UND OrderManager.pickup() genutzt,
## damit bestellte Ware bei Abholung genauso landet wie ein Direktkauf.
## Rückgabe "" = unbekannte Aktion.
func apply_action(item: Dictionary) -> String:
	var payload: Dictionary = item.get("payload", {})
	match item.get("action", ""):
		"add_blank_disk":
			var disk := DiskManager.create_disk(payload.get("template", "disk_blank_dd"),
				"Neu gekauft im Computerladen, %s" % TimeManager.date_string())
			DiskManager.add_disk(disk)
			return "Eine fabrikneue Leerdiskette! Es gibt Schöneres? Falsch."
		"add_item":
			InventoryManager.add_item(payload.get("item", ""), int(payload.get("amount", 1)))
			AudioManager.play("cash_register")
			return "%s gekauft." % item.get("name", "")
		"add_room_object":
			RoomManager.add_object(payload.get("object", ""))
			return "%s gekauft — steht ab sofort im Zimmer!" % item.get("name", "")
		"add_hardware":
			var hardware_id := str(payload.get("hardware", ""))
			PlayerStats.add_hardware(hardware_id)
			DiskManager.ensure_bundled_system_media(hardware_id)
			return "%s angeschlossen. Das Zimmer sieht gleich professioneller aus!" % item.get("name", "")
	return ""
