extends Node
## OrderManager — der Bestellkatalog hinter Herrn Grubers Theke.
##
## Seltene oder teure Hardware gibt es 1992 nicht einfach über den Ladentisch.
## Herr Gruber bestellt sie beim Großhändler: »Kann ich besorgen. Dauert
## ungefähr zwei Wochen.« Nach ein paar Spieltagen trifft die Ware ein, er
## ruft an — und beim nächsten Besuch liegt das Paket abholbereit im Laden.
##
## Das entschleunigt bewusst: Anticipation statt Sofortkauf-Menü, passend zum
## nostalgischen Rhythmus des Spiels. Bezahlt wird bei der Bestellung; abgeholt
## wird später (die Kauf-Aktion selbst führt ShopManager.apply_action aus).

signal orders_changed

const ShopEra := preload("res://scripts/data/computer_shop_era.gd")

var pending: Array = []   # [{id, name, price, ordered_day, arrives_day}]
var arrived: Array = []   # [{id, name}] — liegt abholbereit im Laden
var fulfilled: Array[String] = [] # dauerhafte Quittung bereits abgeholter Bestellware


func _ready() -> void:
	TimeManager.day_changed.connect(_on_day_changed)


## Frisches Spiel: keine offenen/abholbereiten Bestellungen aus dem alten
## Durchlauf mitschleppen (Autoloads leben über den Spielstart hinaus).
func reset() -> void:
	pending = []
	arrived = []
	fulfilled = []
	orders_changed.emit()


# --------------------------------------------------------------- Katalog

## Bestellbarer Katalog im aktuellen Jahr (Living-Timeline-Filter).
func catalog() -> Array:
	return ShopManager.catalog()


func is_pending(id: String) -> bool:
	for o in pending:
		if o.get("id", "") == id:
			return true
	return false


func is_arrived(id: String) -> bool:
	return _is_arrived(id)


func days_left(id: String) -> int:
	for o in pending:
		if o.get("id", "") == id:
			return maxi(0, int(o.get("arrives_day", 0)) - TimeManager.day_counter)
	return -1


## Etwas liegt abholbereit? (für Sidebar-/Dialog-Hinweise)
func has_news() -> bool:
	return not arrived.is_empty()


## Einheitliche Sicht auf bezahlte Spielbestellungen. Die physische
## Sammlervitrine darf eine OVP erst nach der Abholung zeigen; UIs können mit
## dieser Liste trotzdem klar benennen, welche Box unterwegs bzw. abholbereit
## ist. Der SoftwareBible-Fallback repariert dabei alte Saves ohne
## `software`-Kennzeichen.
func software_orders() -> Array:
	var result: Array = []
	for raw_order: Dictionary in pending:
		if not _is_software_entry(raw_order):
			continue
		var order := raw_order.duplicate(true)
		order["status"] = "pending"
		order["days_left"] = maxi(0,
			int(order.get("arrives_day", TimeManager.day_counter)) - TimeManager.day_counter)
		result.append(order)
	for raw_order: Dictionary in arrived:
		if not _is_software_entry(raw_order):
			continue
		var order := raw_order.duplicate(true)
		order["status"] = "ready"
		order["days_left"] = 0
		result.append(order)
	return result


func _is_software_entry(order: Dictionary) -> bool:
	if bool(order.get("software", false)):
		return true
	var id := str(order.get("id", ""))
	return id != "" and not SoftwareBible.entry(id).is_empty() \
		and ShopManager.get_item(id).is_empty()


func _owns_hardware(item: Dictionary) -> bool:
	if item.get("action", "") != "add_hardware":
		return false
	return PlayerStats.has_hardware(item.get("payload", {}).get("hardware", ""))


## Ein ausdrücklich verkauftes Gerät darf eine alte Abholquittung beim nächsten
## Laden nicht wieder materialisieren und kann später erneut bestellt werden.
func note_hardware_sold(hardware_id: String) -> void:
	var changed := false
	for index in range(fulfilled.size() - 1, -1, -1):
		var item := ShopManager.get_item(fulfilled[index])
		if str((item.get("payload", {}) as Dictionary).get("hardware", "")) == hardware_id:
			fulfilled.remove_at(index)
			changed = true
	if changed:
		orders_changed.emit()


# --------------------------------------------------------------- Bestellen

## Eine Bestellung aufgeben. Bezahlt sofort; Lieferung nach order_days Tagen.
## Rückgabe {ok, text} für die UI.
func place_order(id: String) -> Dictionary:
	var item := ShopManager.get_item(id)
	if item.is_empty() or not item.get("order_only", false):
		return {"ok": false, "text": Loc.t("sys.order_manager.steht_nicht_im_bestellkatalog", "Das steht nicht im Bestellkatalog.")}
	if not ShopManager.is_item_available(item):
		return {"ok": false, "text": Loc.t("sys.order_manager.fuhrt_herr_gruber_dieses_jahr_nicht", "Das führt Herr Gruber dieses Jahr nicht.")}
	var requirement := ShopManager.item_requirement_status(item)
	if not bool(requirement.get("ok", false)):
		return {"ok": false, "text": Loc.t("sys.order_manager.herr_gruber_schuttelt_den_kopf_s", "Herr Gruber schüttelt den Kopf: %s.") % str(requirement.get("reason", "Voraussetzung fehlt"))}
	if is_pending(id):
		return {"ok": false, "text": Loc.t("sys.order_manager.schon_bestellt_kommt_in_d_tagen", "Schon bestellt — kommt in %d Tagen.") % days_left(id)}
	if _is_arrived(id):
		return {"ok": false, "text": Loc.t("sys.order_manager.liegt_doch_schon_abholbereit_im_laden", "Liegt doch schon abholbereit im Laden!")}
	if _owns_hardware(item):
		return {"ok": false, "text": Loc.t("sys.order_manager.hast_du_langst_herr_gruber_hebt", "Hast du längst. Herr Gruber hebt die Augenbraue.")}
	var price := ShopManager.price_of(item)
	if not PlayerStats.spend_money(price):
		return {"ok": false, "text": Loc.t("sys.order_manager.zu_teuer_dir_fehlen_s", "Zu teuer. Dir fehlen %s.") % Currency.format(price - PlayerStats.geld)}
	var days := maxi(1, int(item.get("order_days", 14)))
	pending.append({
		"id": id,
		"name": item.get("name", "?"),
		"price": price,
		"ordered_day": TimeManager.day_counter,
		"arrives_day": TimeManager.day_counter + days,
	})
	orders_changed.emit()
	return {"ok": true, "text": Loc.t("sys.order_manager.bestellt_kann_ich_besorgen_dauert_ungefahr", "Bestellt! »Kann ich besorgen — dauert ungefähr %d Tage.«") % days}


## Ein SPIEL auf Nachfrage bestellen (steht nicht im Regal). Bezahlt sofort zum
## Regalpreis; Herr Gruber besorgt es beim Großhändler (etwas schneller als Hardware).
func place_game_order(software_id: String) -> Dictionary:
	var entry := SoftwareBible.entry(software_id)
	if entry.is_empty() or not ShopManager.is_game_catalogued(software_id):
		return {"ok": false, "text": Loc.t("sys.order_manager.spiel_nicht_im_ovp_katalog",
			"Dieser Titel ist noch nicht im OVP-Katalog des Ladens verfügbar.")}
	if ShopManager.game_stock().has(software_id):
		return {"ok": false, "text": Loc.t("sys.order_manager.spiel_steht_im_regal",
			"Die OVP steht heute im Regal und kann sofort gekauft werden.")}
	if is_pending(software_id) or _is_arrived(software_id):
		return {"ok": false, "text": Loc.t("sys.order_manager.ist_schon_bestellt", "Das ist schon bestellt.")}
	var price := ShopManager.game_price(software_id)
	if not PlayerStats.spend_money(price):
		return {"ok": false, "text": Loc.t("sys.order_manager.zu_teuer_dir_fehlen_s", "Zu teuer. Dir fehlen %s.") % Currency.format(price - PlayerStats.geld)}
	var nm := str(entry.get("display_name", "Spiel"))
	var days := randi_range(5, 12)
	pending.append({
		"id": software_id,
		"name": nm,
		"price": price,
		"software": true,
		"ordered_day": TimeManager.day_counter,
		"arrives_day": TimeManager.day_counter + days,
	})
	orders_changed.emit()
	return {
		"ok": true,
		"text": Loc.t("sys.order_manager.ovp_verbindlich_bestellt",
			"Verbindlich bestellt und bezahlt: »%s«. Lieferung in etwa %d Tagen. "
			+ "Nach dem Anruf im Laden abholen — danach steht die OVP in deiner Vitrine.") % [nm, days],
		"days": days,
		"status": "pending",
	}


# --------------------------------------------------------------- Lieferung

func _is_arrived(id: String) -> bool:
	for a in arrived:
		if a.get("id", "") == id:
			return true
	return false


## Tageswechsel: fällige Bestellungen treffen ein. Herr Gruber »ruft an«
## (Meldung im INFOS-Ticker) — auch wenn der Spieler gerade nicht im Laden ist.
func _on_day_changed() -> void:
	var still: Array = []
	var newly: Array = []
	for o in pending:
		if TimeManager.day_counter >= int(o.get("arrives_day", 0)):
			newly.append(o)
		else:
			still.append(o)
	if newly.is_empty():
		return
	pending = still
	for o in newly:
		arrived.append({"id": o.get("id", ""), "name": o.get("name", "?"),
			"software": _is_software_entry(o)})
		UIManager.toast(Loc.t("sys.order_manager.shop_owner_called_order_ready",
			"%s hat angerufen: »%s ist da — kannst es abholen.«") % [
				ShopEra.owner_name(), o.get("name", "?")])
	orders_changed.emit()


## Abholung im Laden. Führt die eigentliche Kauf-Aktion aus (Ware ist bezahlt).
func pickup(id: String) -> Dictionary:
	var entry := {}
	for a in arrived:
		if a.get("id", "") == id:
			entry = a
			break
	if entry.is_empty():
		return {"ok": false, "text": Loc.t("sys.order_manager.dafur_liegt_nichts_bereit", "Dafür liegt nichts bereit.")}
	# Sonderbestelltes Spiel: als OVP-Diskette ausliefern (schon bezahlt).
	if _is_software_entry(entry):
		var r := ShopManager.deliver_game(id)
		if not r.get("ok", false):
			return r                                   # z.B. Box voll → bleibt liegen
		arrived.erase(entry)
		orders_changed.emit()
		return {"ok": true, "text": "Abgeholt: %s" % r.get("text", "")}
	var item := ShopManager.get_item(id)
	if item.is_empty():
		return {"ok": false, "text": Loc.t("sys.order_manager.artikel_ist_aus_dem_katalog_verschwunden", "Der Artikel ist aus dem Katalog verschwunden.")}
	# Der dauerhafte Abholbeleg wird bei Hardware bewusst VOR add_hardware()
	# geschrieben. add_hardware() emittiert stats_changed und kann dadurch einen
	# Autosave auslösen. Ein Save genau in diesem Signal-Fenster enthält nun
	# bereits den Beleg und heilt beim Laden selbst dann, wenn die restlichen
	# Zeilen dieser Abholung nicht mehr ausgeführt wurden.
	var hardware_id := ""
	if str(item.get("action", "")) == "add_hardware":
		hardware_id = str((item.get("payload", {}) as Dictionary).get("hardware", ""))
		if hardware_id.is_empty():
			return {"ok": false, "text": Loc.t("sys.order_manager.abholung_nicht_verbucht_paket_bleibt_fur", "Abholung nicht verbucht — das Paket bleibt für dich zurückgelegt.")}
		if not id in fulfilled:
			fulfilled.append(id)
	var text := ShopManager.apply_action(item)
	if text == "":
		# Kein gültiger Effekt: kein Eigentumsbeleg. Das bezahlte Paket bleibt
		# weiterhin in `arrived`, sodass nichts verloren geht.
		fulfilled.erase(id)
		return {"ok": false, "text": Loc.t("sys.order_manager.herr_gruber_findet_paket_nicht_wieder", "Herr Gruber findet das Paket nicht wieder …")}
	# Eine Bestellung wird erst aus dem Lager entfernt, wenn der versprochene
	# Hardwareeffekt wirklich in PlayerStats angekommen ist. Damit kann ein
	# Daten-/ID-Fehler nie wieder eine bezahlte A501 spurlos verschlucken.
	if not hardware_id.is_empty():
		if not PlayerStats.has_hardware(hardware_id):
			return {"ok": false, "text": Loc.t("sys.order_manager.abholung_nicht_verbucht_paket_bleibt_fur", "Abholung nicht verbucht — das Paket bleibt für dich zurückgelegt.")}
	arrived.erase(entry)
	if not id in fulfilled:
		fulfilled.append(id)
	ShopManager.shop_changed.emit()
	orders_changed.emit()
	return {"ok": true, "text": "Abgeholt: %s" % text}


# --------------------------------------------------------------- Speichern

func to_dict() -> Dictionary:
	return {"pending": pending.duplicate(true), "arrived": arrived.duplicate(true),
		"fulfilled": fulfilled.duplicate()}


func from_dict(d: Dictionary) -> void:
	pending = d.get("pending", []).duplicate(true)
	arrived = d.get("arrived", []).duplicate(true)
	fulfilled = []
	for raw_id: Variant in d.get("fulfilled", []):
		var id := str(raw_id)
		if id == "" or id in fulfilled:
			continue
		fulfilled.append(id)
		# Quittung ist staerker als ein beschaedigter/alter Hardware-Rohwert:
		# bereits abgeholte Ware wird beim Laden selbstheilend wieder eingesetzt.
		var item := ShopManager.get_item(id)
		if str(item.get("action", "")) == "add_hardware":
			var hardware_id := str((item.get("payload", {}) as Dictionary).get("hardware", ""))
			if hardware_id != "" and not PlayerStats.has_hardware(hardware_id):
				PlayerStats.add_hardware(hardware_id)
	# Reparatur eines "torn save" aus älteren Builds: Der Hardwareeffekt war
	# bereits gespeichert, aber das Paket stand wegen der damaligen
	# Signal-/Speicherreihenfolge noch unter `arrived`. Besitz + bereitliegende
	# Einzelbestellung ist ein eindeutiger Beweis für eine abgeschlossene
	# Abholung; wir erzeugen den fehlenden Beleg und entfernen nur diesen
	# doppelten Lagereintrag.
	for index in range(arrived.size() - 1, -1, -1):
		var entry: Dictionary = arrived[index]
		if bool(entry.get("software", false)):
			continue
		var item := ShopManager.get_item(str(entry.get("id", "")))
		if str(item.get("action", "")) != "add_hardware":
			continue
		var hardware_id := str((item.get("payload", {}) as Dictionary).get("hardware", ""))
		if hardware_id.is_empty() or not PlayerStats.has_hardware(hardware_id):
			continue
		var order_id := str(entry.get("id", ""))
		if not order_id in fulfilled:
			fulfilled.append(order_id)
		arrived.remove_at(index)
	orders_changed.emit()
