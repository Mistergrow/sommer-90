extends Node
## FleaMarketManager — der lebendige Flohmarkt (nur samstags).
##
## KEIN Reset: Was du nicht kaufst, ist nächste Woche vielleicht verkauft,
## billiger geworden oder der Händler ist gar nicht mehr da. Händler kündigen
## kommende Ware an ("Nächste Woche räum ich den Keller meines Bruders aus").
## Dazu Mystery-Kartons: versiegelt, Preis dran, Inhalt prozedural — Papierkram
## oder ein Schatz. Der Zustand des Marktes wird gespeichert und entwickelt sich
## Woche für Woche weiter.

signal flea_changed

const InsertCatalog := preload("res://scripts/data/software_insert_catalog.gd")
const StefanGames := preload("res://scripts/games/stefan_game_catalog.gd")
const MAX_OFFERS := 6
const MAX_BOXES := 3
const USED_DISKBOX_PRICE := 35 # Gruber: 25 DM; Flohmarkt ist der teure Notkauf
## Flohmarktverkaeufer mit STABILER ID.
##
## Frueher war das eine blosse Liste deutscher Anzeigenamen, aus der das
## Feilsch-Minispiel per Teilstringsuche Geschlecht, Alter UND die
## Portraet-Identitaet ableitete ("oma" -> weiblich, 68; stable_id aus dem
## kleingeschriebenen Namen). Eine Uebersetzung haette damit demselben
## Verkaeufer ein anderes Gesicht gegeben — lautlos, ohne Fehlermeldung.
## Identitaet und Merkmale gehoeren deshalb an die ID, nicht an den Text.
const SELLERS := [
	{"id": "krause", "name": "Krause"},
	{"id": "diedrich", "name": "Frau Diedrich", "gender": "f", "age": 52},
	{"id": "ingenieur", "name": "der Ingenieur a. D.", "gender": "m", "age": 62},
	{"id": "schueler", "name": "ein Schüler", "gender": "m", "age": 16},
	{"id": "sowa", "name": "Herr Sowa", "gender": "m", "age": 44},
	{"id": "reinhardt", "name": "Oma Reinhardt", "gender": "f", "age": 68},
]


## Zufaelliger Verkaeufer als Angebotsfelder. "seller" bleibt der Anzeigename
## (Altspielstaende lesen ihn weiter), "seller_id" traegt die stabile Identitaet.
static func _random_seller(rng: RandomNumberGenerator) -> Dictionary:
	var entry: Dictionary = SELLERS[rng.randi_range(0, SELLERS.size() - 1)]
	return {"seller": str(entry["name"]), "seller_id": str(entry["id"])}


## Merkmale eines Verkaeufers ueber seine ID — sprachunabhaengig.
## Bewusst NICHT statisch: der FleaMarketManager ist ein Autoload und wird als
## Instanz angesprochen (FleaMarketManager.seller_traits(...)). Eine statische
## Funktion wuerde dort STATIC_CALLED_ON_INSTANCE ausloesen.
func seller_traits(seller_id: String) -> Dictionary:
	for entry: Dictionary in SELLERS:
		if str(entry["id"]) == seller_id:
			return entry.duplicate(true)
	return {}
const BOX_KINDS := {
	"disketten": {"label": "Disketten", "price": 5},
	"computerkram": {"label": "Computerkram", "price": 10},
	"alles": {"label": "Alles zusammen", "price": 20},
}
# Erwerbsformen echter Katalogspiele auf dem Trödel — nicht alles ist ein Karton!
# Karton (OVP) = teuer/komplett · lose Original-Disk (gedrucktes Label) · Handbuch.
const SW_FORMS := {
	"box":    {"label": "Karton (OVP)", "icon": "📦", "prov": "original_box", "min": 24, "max": 58},
	"disk":   {"label": "Original-Disk", "icon": "💾", "prov": "original", "min": 10, "max": 26},
	"disk_set": {"label": "Original-Diskettensatz", "icon": "💾", "prov": "original", "min": 12, "max": 30},
	"manual": {"label": "Handbuch", "icon": "📖", "prov": "", "min": 4, "max": 12},
}

var offers: Array = []       # {id, template_id|software_id, [form], price, seller, haggled}
var boxes: Array = []         # {id, kind, label, price}
var tip: Dictionary = {}      # {text, special}
var last_changes: Array = []  # Notizen "seit letzter Woche"
var _week := 0
var _last_gen_day := -1
var _next_id := 1


# ---------------------------------------------------------------- Marktlauf

## Beim Betreten des Flohmarkts aufrufen: an einem neuen Markttag (Samstag)
## entwickelt sich der Markt weiter.
func ensure_current() -> void:
	if TimeManager.weekday() != 5:
		return
	if TimeManager.day_counter == _last_gen_day:
		return
	_evolve()
	_last_gen_day = TimeManager.day_counter
	flea_changed.emit()


func _evolve() -> void:
	_week += 1
	last_changes = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xF1EA ^ (TimeManager.day_counter * 2654435761)

	# Angekündigte Ware trifft ein
	if not tip.is_empty():
		_fulfill_tip(rng)

	# Bestehende Stände entwickeln sich (verkauft / billiger / weg)
	var kept: Array = []
	for o in offers:
		var r := rng.randf()
		if r < 0.28:
			last_changes.append("»%s« ist verkauft." % _oname(o))
			continue
		elif r < 0.42:
			last_changes.append("Ein Händler ist heute nicht da — »%s« ist weg." % _oname(o))
			continue
		elif r < 0.62:
			o["price"] = maxi(1, int(float(o["price"]) * 0.7))
			o["haggled"] = false
			last_changes.append("»%s« ist billiger: %d DM." % [_oname(o), o["price"]])
		kept.append(o)
	offers = kept

	# Unberührte Kartons: manche greift sich ein anderer
	boxes = boxes.filter(func(_b: Dictionary) -> bool: return rng.randf() < 0.5)

	# Frische Ware: Spiele stammen aus der Software-Bibel; disks.json liefert nur
	# PD/Tools/Magazine und Story-Sonderstücke, nie mehr zufällige Fantasiespiele.
	for _i in rng.randi_range(2, 3):
		if offers.size() < MAX_OFFERS:
			if rng.randf() < 0.6:
				_add_software_offer(rng)
			else:
				_add_offer(rng)
	# Mindestens eine weitere echte Originaldisk-Chance aus der Bibel.
	if offers.size() < MAX_OFFERS and rng.randf() < 0.65:
		_add_software_offer(rng)
	# Regenschirmprinzip: Wer fast keinen Platz hat, kann am Markt mit etwas
	# Glueck sofort eine gebrauchte Box kaufen — aber teurer als bei Gruber.
	if DiskManager.free_slots() <= 2 and offers.size() < MAX_OFFERS \
			and not offers.any(func(o: Dictionary) -> bool: return str(o.get("item_kind", "")) == "diskbox"):
		_add_storage_box_offer(rng)
	for _i in rng.randi_range(1, 2):
		if boxes.size() < MAX_BOXES:
			_add_box(rng)
	_ensure_quest_offer(rng)


## Echtes Bibel-Spiel als Trödel-Fund: zufällige Form (Karton/lose Disk/Handbuch),
## nur Titel mit vollständigem Artwork und nur, wenn schon erschienen.
func _add_software_offer(rng: RandomNumberGenerator, rare_only := false) -> void:
	var games: Array = SoftwareBible.illustrated_games()
	var year := TimeManager.year
	games = games.filter(func(id: String) -> bool:
		var info := SoftwareBible.entry(id)
		return int(info.get("release_year", 3000)) <= year \
			and (not rare_only or str(info.get("rarity", "common")) in ["rare", "legendary"]))
	if games.is_empty() and rare_only:
		games = SoftwareBible.illustrated_games().filter(func(id: String) -> bool:
			return int(SoftwareBible.entry(id).get("release_year", 3000)) <= year)
	if games.is_empty():
		return
	var sid: String = games[rng.randi_range(0, games.size() - 1)]
	# Auf dem Trödel werden Spiele als lose ORIGINAL-Diskettensätze verkauft.
	# Standard-Master sind rot; AAA-Originale bleiben im Sammlungscode lila.
	# Box/Handbuch-Formen bleiben nur zum Laden alter Markt-Spielstände lesbar.
	var form := "disk_set"
	var f: Dictionary = SW_FORMS[form]
	var disk_count := SoftwareBible.disk_count(sid)
	var disk_number := 1
	var used_condition := rng.randi_range(55, 91)
	var price := rng.randi_range(int(f["min"]), int(f["max"])) + (disk_count - 1) * 6
	price = mini(price, maxi(18, roundi(float(ShopManager.game_price(sid)) * 0.72)))
	offers.append({"id": _new_id(), "software_id": sid, "form": form,
		"disk_number": disk_number, "disk_count": disk_count,
		"price": price, "condition": used_condition, "package_condition": "used",
		"haggled": false}.merged(_random_seller(rng)))

	# Tipp auf nächste Woche
	if tip.is_empty() and rng.randf() < 0.55:
		tip = _make_tip(rng)


func _add_offer(rng: RandomNumberGenerator) -> void:
	var pool := DiskManager.template_ids_in_pool("flea").filter(func(id: Variant) -> bool:
		return str((DiskManager.templates.get(str(id), {}) as Dictionary).get("content_type", "")) != "spiel")
	if pool.is_empty():
		return
	var tid: String = pool[rng.randi_range(0, pool.size() - 1)]
	offers.append({"id": _new_id(), "template_id": tid, "price": _base_price(tid, rng),
		"haggled": false}.merged(_random_seller(rng)))


func _add_storage_box_offer(rng: RandomNumberGenerator) -> void:
	# EIN Zug, nicht zwei: zwei Aufrufe wuerden zwei verschiedene Verkaeufer
	# ziehen und Name und ID desselben Angebots auseinanderlaufen lassen.
	offers.append({"id": _new_id(), "item_kind": "diskbox",
		"price": USED_DISKBOX_PRICE,
		"haggled": false, "condition": rng.randi_range(62, 88)}
		.merged(_random_seller(rng)))


func _add_box(rng: RandomNumberGenerator, kind := "") -> void:
	if kind == "":
		kind = BOX_KINDS.keys()[rng.randi_range(0, BOX_KINDS.size() - 1)]
	var def: Dictionary = BOX_KINDS[kind]
	boxes.append({"id": _new_id(), "kind": kind, "label": def["label"], "price": def["price"]})


func _base_price(template_id: String, rng: RandomNumberGenerator) -> int:
	match DiskManager.templates.get(template_id, {}).get("rarity", "common"):
		"rare": return rng.randi_range(9, 15)
		"uncommon": return rng.randi_range(5, 10)
		_: return rng.randi_range(3, 6)


## Quest-relevante Trödel-Funde garantieren, damit Aufträge nicht am Zufall des
## Markts hängen: Stefans Spielewünsche und unbeschriftete Disketten (Alex).
func _ensure_quest_offer(rng: RandomNumberGenerator) -> void:
	# 1991-1999: exakt der aktuell offene Stefan-Wunsch wird garantiert als
	# physische Originaldiskette angeboten. Die zentrale Katalogabfrage ersetzt
	# 27 fehleranfaellige Sonderzweige und laesst alte Marktstaende unangetastet.
	for request: Dictionary in StefanGames.acquisition_requests():
		var template_id := str(request.get("disk_template_id", ""))
		if template_id.is_empty() or DiskManager.has_template(template_id) or _has_offer(template_id):
			continue
		offers.append({"id": _new_id(), "template_id": template_id,
			"price": _base_price(template_id, rng), "seller": "Krause", "seller_id": "krause", "haggled": false,
			"note": "Stefan hat genau nach diesem Titel gefragt."})
	# Stefans Weltraumspiel — liegt erst aus, wenn der kuratierte Questslot offen
	# ist. Der Telefon-Flag allein darf Woche 1 nicht vorwegnehmen.
	if QuestManager.is_active("q_stefan_space") \
			and QuestManager.stage("q_stefan_space") == 0 \
			and not DiskManager.has_template("game_space_lemming") \
			and not _has_offer("game_space_lemming"):
		offers.append({"id": _new_id(), "template_id": "game_space_lemming",
			"price": _base_price("game_space_lemming", rng), "seller": "Krause", "seller_id": "krause", "haggled": false})
	# Zweiter Auftrag von Stefan: Turbo Kart erscheint erst, wenn der Spieler
	# zugesagt hat und Ferienwoche 3 den Auftrag wirklich freigeschaltet hat.
	# So ist Krauses Ankündigung verlässlich, ohne das normale Marktangebot zu
	# ersetzen oder den Fund bereits vor dem Telefonat vorwegzunehmen.
	if QuestManager.is_active("q_stefan_turbo") \
			and QuestManager.stage("q_stefan_turbo") == 0 \
			and not DiskManager.has_template("game_turbo_kart") \
			and not _has_offer("game_turbo_kart"):
		offers.append({"id": _new_id(), "template_id": "game_turbo_kart",
			"price": _base_price("game_turbo_kart", rng), "seller": "Krause", "seller_id": "krause", "haggled": false})
	# Dritter, optionaler Spielefund: das seltene Original von CODE RED samt
	# Handbuch-Abfrage. Er erscheint erst nach Stefans ausdruecklichem Auftrag.
	if QuestManager.is_active("q_stefan_code_red") \
			and QuestManager.stage("q_stefan_code_red") == 0 \
			and not DiskManager.has_template("game_code_red") \
			and not _has_offer("game_code_red"):
		offers.append({"id": _new_id(), "template_id": "game_code_red",
			"price": _base_price("game_code_red", rng), "seller": "Krause", "seller_id": "krause", "haggled": false})
	# Alex' Wühlkisten-Jagd — unbeschriftete Disketten sind billige Kramkisten-Ware.
	if QuestManager.is_active("q_alex_find") \
			and (QuestManager.stage("q_alex_find") == 0 \
				or not DiskManager.has_template("mystery_unlabeled")) \
			and not _has_offer("mystery_unlabeled"):
		offers.append({"id": _new_id(), "template_id": "mystery_unlabeled",
			"price": rng.randi_range(2, 4), "seller": "Krause", "seller_id": "krause", "haggled": false,
			"note": "Unbeschriftet — könnte alles drauf sein."})


func _has_offer(template_id: String) -> bool:
	for o in offers:
		if o.get("template_id", "") == template_id:
			return true
	return false


# ---------------------------------------------------------------- Tipps

func _make_tip(rng: RandomNumberGenerator) -> Dictionary:
	var options := [
		{"text": Loc.t("sys.flea_manager.krause_zwinkert_nachste_woche_raum_ich", "Krause zwinkert: »Nächste Woche räum ich den Keller meines Bruders aus. Komm früh vorbei.«"), "special": "box_alles"},
		{"text": Loc.t("sys.flea_manager.am_samstag_bring_ich_kiste_originale", "»Am Samstag bring ich eine Kiste Originale mit«, sagt der Händler."), "special": "offer_rare"},
		{"text": Loc.t("sys.flea_manager.ich_hab_noch_alte_amiga_hefte", "»Ich hab noch alte Amiga-Hefte im Schuppen — nächste Woche liegen die hier«, verspricht Frau Diedrich."), "special": "box_computerkram"},
		{"text": Loc.t("sys.flea_manager.sammler_flustert_nachsten_samstag_kommt_was", "Ein Sammler flüstert: »Nächsten Samstag kommt was Besonderes rein.«"), "special": "box_alles"},
	]
	return options[rng.randi_range(0, options.size() - 1)]


func _fulfill_tip(rng: RandomNumberGenerator) -> void:
	match tip.get("special", ""):
		"box_alles":
			_add_box(rng, "alles")
			last_changes.append("Wie versprochen liegt heute ein großer Karton bereit.")
		"box_computerkram":
			_add_box(rng, "computerkram")
			last_changes.append("Die angekündigten alten Hefte sind da (Karton).")
		"offer_rare":
			_add_software_offer(rng, true)
			last_changes.append("Die versprochenen Originale liegen aus.")
	tip = {}


# ---------------------------------------------------------------- Kauf / Feilschen

func offer_by_id(id: int) -> Dictionary:
	for o in offers:
		if o["id"] == id:
			return o
	return {}


func haggle(id: int) -> Dictionary:
	var o := offer_by_id(id)
	if o.is_empty() or o["haggled"]:
		return {"ok": false, "text": ""}
	o["haggled"] = true
	var chance := clampf(0.35 + float(PlayerStats.ruf) * 0.01, 0.0, 0.75)
	if randf() < chance:
		o["price"] = maxi(1, roundi(float(o["price"]) * 0.6))
		PlayerStats.change_stat("ruf", 1)
		flea_changed.emit()
		return {"ok": true, "text": Loc.t("sys.flea_manager.na_gut_aber_nur_weil_du", "»Na gut. Aber nur, weil du's bist.« Neuer Preis: %d DM.") % o["price"]}
	flea_changed.emit()
	return {"ok": false, "text": Loc.t("sys.flea_manager.preis_ist_heiss_er_bleibt_so", "»Der Preis ist heiß. Und er bleibt so.«")}


## Atomare Naht des Karten-Minispiels. Das konkrete Angebot kann pro Markttag
## genau einen verhandelten Run annehmen; Preisgrenzen werden hier nochmals
## unabhaengig von der UI validiert, damit kein Reopen/Reroll Geld erzeugt.
func apply_negotiation(id: int, run_id: String, negotiated_price: int,
		details: Dictionary = {}) -> Dictionary:
	var o := offer_by_id(id)
	if o.is_empty():
		return {"ok": false, "text": Loc.t("sys.flea_manager.angebot_ist_nicht_mehr_da", "Das Angebot ist nicht mehr da.")}
	if bool(o.get("haggled", false)) or o.has("negotiation"):
		return {"ok": false, "text": "Ueber diese Ware wurde heute bereits verhandelt."}
	var old_price := int(o.get("price", 1))
	var floor_price := maxi(1, ceili(old_price * 0.58))
	if run_id.is_empty() or negotiated_price < floor_price or negotiated_price > old_price:
		return {"ok": false, "text": Loc.t("sys.flea_manager.gegenangebot_liegt_ausserhalb_des_fairen_korridors", "Das Gegenangebot liegt ausserhalb des fairen Korridors.")}
	o["price"] = negotiated_price
	o["haggled"] = true
	o["negotiation"] = {"run_id": run_id, "day": TimeManager.day_counter,
		"original_price": old_price, "price": negotiated_price,
		"details": details.duplicate(true)}
	flea_changed.emit()
	return {"ok": true, "text": "Handschlag bei %d DM." % negotiated_price,
		"price": negotiated_price}


## Vorprüfung für den finalen Handschlag. Sie benutzt eine Kopie des Angebots,
## damit Preis, Geld und Diskettenplätze geprüft werden, ohne bereits Weltzustand
## zu verändern. Das Preisgespräch darf also nie in einem bezahlten Nichts enden.
func negotiated_purchase_gate(id: int, negotiated_price: int) -> Dictionary:
	var offer := offer_by_id(id)
	if offer.is_empty():
		return {"ok": false, "text": Loc.t("sys.flea_manager.angebot_ist_nicht_mehr_da", "Das Angebot ist nicht mehr da.")}
	if bool(offer.get("haggled", false)) or offer.has("negotiation"):
		return {"ok": false, "text": Loc.t("sys.flea_manager.uber_diese_ware_wurde_heute_bereits", "Über diese Ware wurde heute bereits verhandelt.")}
	var old_price := int(offer.get("price", 1))
	var floor_price := maxi(1, ceili(old_price * 0.58))
	if negotiated_price < floor_price or negotiated_price > old_price:
		return {"ok": false, "text": Loc.t("sys.flea_manager.gegenangebot_liegt_ausserhalb_des_fairen_korridors_1752", "Das Gegenangebot liegt außerhalb des fairen Korridors.")}
	var preview: Dictionary = offer.duplicate(true)
	preview["price"] = negotiated_price
	var gate := purchase_gate(preview)
	if not bool(gate.get("ok", false)):
		return gate
	if PlayerStats.geld + 0.005 < float(negotiated_price):
		return {"ok": false, "reason": "money",
			"text": Loc.t("sys.flea_manager.fur_den_handschlag_fehlen_dir_d", "Für den Handschlag fehlen dir %d DM.") % ceili(float(negotiated_price) - PlayerStats.geld)}
	return {"ok": true, "price": negotiated_price, "text": Loc.t("sys.flea_manager.preis_ubergabe_sind_bereit", "Preis und Übergabe sind bereit.")}


## Ein einziger verbindlicher Commit: Preis festhalten UND Ware bezahlen. Schlägt
## die eigentliche Übergabe unerwartet fehl, wird der Verhandlungszustand sauber
## zurückgerollt; der Spieler verliert weder Geld noch seinen einzigen Versuch.
func settle_negotiation(id: int, run_id: String, negotiated_price: int,
		details: Dictionary = {}) -> Dictionary:
	var gate := negotiated_purchase_gate(id, negotiated_price)
	if not bool(gate.get("ok", false)):
		return gate
	var offer := offer_by_id(id)
	var old_price := int(offer.get("price", 1))
	var applied := apply_negotiation(id, run_id, negotiated_price, details)
	if not bool(applied.get("ok", false)):
		return applied
	var bought := buy_offer(id)
	if bool(bought.get("ok", false)):
		bought["price"] = negotiated_price
		bought["negotiated"] = true
		return bought
	# Der Kaufcode ist ebenfalls atomar; deshalb genügt hier die Wiederherstellung
	# des Preisgesprächs. Das Angebot befindet sich bei einem Fehler noch im Array.
	offer = offer_by_id(id)
	if not offer.is_empty():
		offer["price"] = old_price
		offer["haggled"] = false
		offer.erase("negotiation")
		flea_changed.emit()
	return bought


func buy_offer(id: int) -> Dictionary:
	var o := offer_by_id(id)
	if o.is_empty():
		return {"ok": false, "text": Loc.t("sys.flea_manager.ist_schon_weg", "Das ist schon weg.")}
	var gate := purchase_gate(o)
	if not bool(gate.get("ok", false)):
		return gate
	if str(o.get("item_kind", "")) == "diskbox":
		if not PlayerStats.spend_money(int(o["price"])):
			return {"ok": false, "text": Loc.t("sys.flea_manager.zu_wenig_geld_fur_gebrauchte_diskettenbox", "Zu wenig Geld für die gebrauchte Diskettenbox.")}
		RoomManager.add_object("diskbox")
		offers.erase(o)
		flea_changed.emit()
		return {"ok": true, "text": Loc.t("sys.flea_manager.gebrauchte_12er_diskettenbox_gekauft_jetzt_sind", "Gebrauchte 12er-Diskettenbox gekauft — jetzt sind wieder %d Plätze frei. Bei Gruber wäre sie billiger gewesen.") % DiskManager.free_slots()}
	# Echte Katalog-Ware (Bibel) — Form entscheidet: Handbuch braucht keinen Diskplatz.
	if o.has("software_id"):
		return _buy_software_offer(o)
	# Erst die Diskette erzeugen/prüfen, DANN bezahlen — sonst Absturz (Null) und
	# Geldverlust, falls das Template unbekannt ist.
	var disk := DiskManager.create_disk(o["template_id"], "Flohmarkt-Fund, %s" % TimeManager.date_string())
	if disk == null:
		return {"ok": false, "text": Loc.t("sys.flea_manager.krause_kramt_findet_diskette_aber_nicht", "Krause kramt, findet die Diskette aber nicht mehr.")}
	if not PlayerStats.spend_money(int(o["price"])):
		return {"ok": false, "text": Loc.t("sys.flea_manager.zu_wenig_geld_krause_nimmt_keine", "Zu wenig Geld. Krause nimmt keine Naturalien.")}
	disk.owner_history.append(o["seller"])
	disk.checked = false
	DiskManager.add_disk(disk)
	offers.erase(o)
	flea_changed.emit()
	var text := "Gekauft: %s. Ob sie läuft? Zu Hause prüfen!" % disk.display_name()
	var copy_tutorial: bool = str(o.get("template_id", "")) == "game_space_lemming" \
		and QuestManager.is_active("q_stefan_space")
	if copy_tutorial:
		text += "  ROTE MASTERDISK: Behalten! Zieh Stefan zuerst mit X-COPY eine blaue Kopie."
	# Memory Layer: Flohmarkt-Funde tauchen Jahre später wieder auf.
	MemoryManager.record("flohmarkt", "auf dem Flohmarkt %s von %s gekauft" % [disk.display_name(), o["seller"]])
	QuestManager.note_action("flea_purchase")
	QuestManager.evaluate()
	return {"ok": true, "text": text, "tutorial": "space_copy" if copy_tutorial else ""}


## Kauf echter Katalog-Ware (Bibel) je nach Form.
func _buy_software_offer(o: Dictionary) -> Dictionary:
	var sid := str(o["software_id"])
	var form := str(o.get("form", "disk"))
	var e: Dictionary = SoftwareBible.entry(sid)
	var nm := str(e.get("display_name", e.get("historical_name", "Spiel")))
	if form == "manual":
		if not PlayerStats.spend_money(int(o["price"])):
			return {"ok": false, "text": Loc.t("sys.flea_manager.zu_wenig_geld_fur_handbuch", "Zu wenig Geld für das Handbuch.")}
		GameManager.flags["manual_%s" % sid] = true
		InsertCatalog.grant_kind(sid, "manual")
		PlayerStats.change_stat("ruf", 1)
		MemoryManager.record("flohmarkt", "Original-Handbuch zu %s ergattert" % nm)
		offers.erase(o)
		flea_changed.emit()
		QuestManager.note_action("flea_purchase")
		return {"ok": true, "text": Loc.t("sys.flea_manager.original_handbuch_zu_s_ohne_disk", "Ein original Handbuch zu %s — ohne Disk, aber Sammlergold!") % nm}
	# Diskettensatz/Karton → kompletter Satz; alter lose-Disk-Save → angebotener Teil.
	# Erst erzeugen/prüfen, DANN Geld abbuchen — sonst zahlt man bei einem
	# unbekannten Titel und bekäme nichts.
	var disk_count := SoftwareBible.disk_count(sid)
	var required_slots := disk_count if form in ["box", "disk_set"] else 1
	if not DiskManager.can_store_disks(required_slots):
		return {"ok": false, "text": Loc.t("sys.flea_manager.dafur_brauchst_du_d_freie_diskettenplatze", "Dafür brauchst du %d freie Diskettenplätze; frei sind %d.") % [required_slots, DiskManager.free_slots()]}
	var prov: String = str(SW_FORMS[form]["prov"])
	var game_disks: Array = []
	if form in ["box", "disk_set"]:
		game_disks = DiskManager.create_software_set(sid, prov, "Flohmarkt-Fund, %s" % TimeManager.date_string())
	else:
		var disk_number := clampi(int(o.get("disk_number", 1)), 1, disk_count)
		var loose_disk := DiskManager.create_from_software(sid, prov,
			"Flohmarkt-Fund, %s" % TimeManager.date_string(), disk_number)
		if loose_disk != null:
			game_disks.append(loose_disk)
	if game_disks.is_empty():
		return {"ok": false, "text": Loc.t("sys.flea_manager.titel_ist_bibel_unbekannt", "Der Titel ist der Bibel unbekannt.")}
	if not PlayerStats.spend_money(int(o["price"])):
		return {"ok": false, "text": Loc.t("sys.flea_manager.zu_wenig_geld_krause_nimmt_keine", "Zu wenig Geld. Krause nimmt keine Naturalien.")}
	for disk: Disk in game_disks:
		disk.owner_history.append(o["seller"])
		disk.package_condition = "used" if form == "box" else ""
		disk.color = "red"
		disk.enforce_master_color()
		disk.condition = int(o.get("condition", disk.condition))
	if not DiskManager.add_disks(game_disks):
		PlayerStats.add_money(int(o["price"]))
		return {"ok": false, "text": Loc.t("sys.flea_manager.diskettensatz_passt_nicht_mehr_in_box", "Der Diskettensatz passt nicht mehr in die Box. Kauf storniert.")}
	offers.erase(o)
	flea_changed.emit()
	MemoryManager.record("flohmarkt", "%s (%s) auf dem Flohmarkt gekauft" % [nm, SW_FORMS[form]["label"]])
	QuestManager.note_action("flea_purchase")
	var collection_color := "lila AAA-Originaldiskette(n)" if game_disks[0].color == "purple" else "rote Masterdiskette(n)"
	var extra := ("  GEBRAUCHTER Originalsatz: %d %s, alle mit gedrucktem Label, Zustand %d%%." % [disk_count, collection_color, int(o.get("condition", 70))] if form == "disk_set" else
		("  GEBRAUCHTE Komplett-OVP mit %d Diskette(n), Zustand %d%%." % [disk_count, int(o.get("condition", 70))] if form == "box" else
		"  Lose Original-Disk %d/%d mit gedrucktem Label." % [game_disks[0].disk_number, disk_count]))
	return {"ok": true, "text": Loc.t("sys.flea_manager.gekauft_s_s_zu_hause_prufen", "Gekauft: %s.%s Zu Hause prüfen!") % [nm, extra]}


## Eine einzige atomare Kaufregel fuer Listenbutton, Doppelklick, Feilschen und
## direkten Manager-Aufruf. So kann kein UI-Weg eine volle Diskettenbox umgehen.
func purchase_gate(offer: Dictionary) -> Dictionary:
	if offer.is_empty():
		return {"ok": false, "text": Loc.t("sys.flea_manager.angebot_ist_nicht_mehr_da", "Das Angebot ist nicht mehr da.")}
	if str(offer.get("item_kind", "")) == "diskbox":
		return {"ok": true, "required_slots": 0}
	var required_slots := 1
	if offer.has("software_id"):
		var form := str(offer.get("form", "disk"))
		required_slots = 0 if form == "manual" else (SoftwareBible.disk_count(str(offer["software_id"])) if form in ["box", "disk_set"] else 1)
	if not DiskManager.can_store_disks(required_slots):
		return {"ok": false, "required_slots": required_slots,
			"text": Loc.t("sys.flea_manager.kein_platz_dieses_angebot_braucht_d", "Kein Platz: Dieses Angebot braucht %d freie Diskettenplätze, frei sind %d. Kauf erst eine Box oder geh zu Gruber.") % [required_slots, DiskManager.free_slots()]}
	return {"ok": true, "required_slots": required_slots}


# ---------------------------------------------------------------- Mystery-Kartons

func box_by_id(id: int) -> Dictionary:
	for b in boxes:
		if b["id"] == id:
			return b
	return {}


## Karton kaufen und öffnen. Rückgabe {ok, lines:Array, jackpot:bool}.
func buy_box(id: int) -> Dictionary:
	var b := box_by_id(id)
	if b.is_empty():
		return {"ok": false, "lines": [], "jackpot": false, "text": Loc.t("sys.flea_manager.karton_ist_schon_weg", "Der Karton ist schon weg.")}
	if not PlayerStats.spend_money(int(b["price"])):
		return {"ok": false, "lines": [], "jackpot": false, "text": Loc.t("sys.flea_manager.zu_wenig_geld_fur_den_karton", "Zu wenig Geld für den Karton.")}
	boxes.erase(b)
	var result := _open_contents(b["kind"])
	flea_changed.emit()
	result["ok"] = true
	# Memory Layer: DIE klassische Erinnerung — die Kiste vom Flohmarkt.
	MemoryManager.record("flohmarkt", "auf dem Flohmarkt eine Kiste (%s) gekauft%s" % [
		str(b["kind"]), " — Jackpot!" if result.get("jackpot", false) else ""])
	QuestManager.note_action("flea_purchase")
	return result


func _open_contents(kind: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()  # echte Überraschung
	var draws: int = {"disketten": 2, "computerkram": 3, "alles": 4}.get(kind, 2)
	var lines: Array = []
	var jackpot := false
	for _i in draws:
		var loot := _roll_loot(rng, kind)
		if loot["text"] != "":
			lines.append(loot["text"])
		if loot.get("jackpot", false):
			jackpot = true
	if lines.is_empty():
		lines.append("… nur alter Papierkram und Staub. Tja, Risiko.")
	return {"lines": lines, "jackpot": jackpot}


## Ein einzelner Fund. Gewichtung hängt von der Kartonsorte ab (alles = Chance
## auf Schätze, aber auch mehr Nieten).
func _roll_loot(rng: RandomNumberGenerator, kind: String) -> Dictionary:
	var r := rng.randf()
	var junk: float = 0.45 if kind == "disketten" else (0.4 if kind == "computerkram" else 0.35)
	if r < junk:
		var junks := ["ein Knäuel kaputter Kabel", "eine zerkratzte Diskette (unlesbar)",
			"eine alte Stromrechnung", "ein Handbuch ohne Software", "ein leeres Diskettencase"]
		return {"text": junks[rng.randi_range(0, junks.size() - 1)]}
	# MOD-Disk (die Anlage-Synergie!)
	var mod_chance: float = 0.10 if kind == "disketten" else (0.16 if kind == "computerkram" else 0.22)
	if r < junk + mod_chance:
		var lib: Array = MusicManager.club_library()
		if not lib.is_empty():
			var t: Dictionary = lib[rng.randi_range(0, lib.size() - 1)]
			MusicManager.collect(t["id"])
			return {"text": Loc.t("sys.flea_manager.unbeschriftete_mod_disk_s_s_lauft", "eine unbeschriftete MOD-Disk: »%s« (%s) — läuft auf der Anlage!") % [
				t.get("title", "?"), t.get("author", "?")], "jackpot": true}
	# Zeitschriften -> Wissen
	if r < junk + mod_chance + 0.18:
		var n := rng.randi_range(1, 3)
		PlayerStats.change_stat("wissen", n)
		return {"text": Loc.t("sys.flea_manager.stapel_computerzeitschriften_d_wissen", "ein Stapel Computerzeitschriften (+%d Wissen)") % n}
	# Zubehör -> Inventar
	if r < junk + mod_chance + 0.30:
		if rng.randf() < 0.5:
			InventoryManager.add_item("etiketten", 5)
			return {"text": Loc.t("sys.flea_manager.bogen_diskettenetiketten_5", "ein Bogen Diskettenetiketten (+5)")}
		InventoryManager.add_item("reinigungsdiskette", 1)
		return {"text": Loc.t("sys.flea_manager.laufwerk_reinigungsdiskette", "eine Laufwerk-Reinigungsdiskette")}
	# Diskette(n) aus dem Flohmarkt-Pool (evtl. ein Fund!)
	if DiskManager.free_slots() > 0:
		var pool := DiskManager.template_ids_in_pool("flea").filter(func(id: Variant) -> bool:
			return str((DiskManager.templates.get(str(id), {}) as Dictionary).get("content_type", "")) != "spiel")
		if not pool.is_empty():
			var tid: String = pool[rng.randi_range(0, pool.size() - 1)]
			var disk := DiskManager.create_disk(tid, "Aus einem Mystery-Karton, %s" % TimeManager.date_string())
			disk.checked = false
			DiskManager.add_disk(disk)
			var rare: bool = DiskManager.templates.get(tid, {}).get("rarity", "") == "rare"
			return {"text": Loc.t("sys.flea_manager.diskette_s_s", "eine Diskette: »%s«%s") % [disk.display_name(), "  — sieht selten aus!" if rare else ""],
				"jackpot": rare}
	return {"text": Loc.t("sys.flea_manager.noch_diskette_aber_deine_box_ist", "noch eine Diskette — aber deine Box ist voll.")}


# ---------------------------------------------------------------- Helfer

func _oname(offer: Dictionary) -> String:
	if str(offer.get("item_kind", "")) == "diskbox":
		return "▣ Diskettenbox (12 Plätze) · gebraucht"
	if offer.has("software_id"):
		var e: Dictionary = SoftwareBible.entry(str(offer["software_id"]))
		var nm := str(e.get("display_name", e.get("historical_name", "Spiel")))
		var f: Dictionary = SW_FORMS.get(str(offer.get("form", "disk")), {})
		var suffix := ""
		if str(offer.get("form", "disk")) == "disk" and int(offer.get("disk_count", 1)) > 1:
			suffix = " (Diskette %d/%d)" % [int(offer.get("disk_number", 1)), int(offer.get("disk_count", 1))]
		elif str(offer.get("form", "")) == "disk_set":
			suffix = " (%d Originaldisketten)" % int(offer.get("disk_count", 1))
		elif str(offer.get("form", "")) == "box" and int(offer.get("disk_count", 1)) > 1:
			suffix = " (%d Disketten)" % int(offer.get("disk_count", 1))
		return "%s %s: %s%s" % [f.get("icon", ""), f.get("label", "Ware"), nm, suffix]
	var tpl: Dictionary = DiskManager.templates.get(offer["template_id"], {})
	var label: String = tpl.get("label", "")
	return label if label != "" else "Unbeschriftete Diskette"


func offer_name(offer: Dictionary) -> String:
	return _oname(offer)


func _new_id() -> int:
	_next_id += 1
	return _next_id


func reset() -> void:
	offers = []
	boxes = []
	tip = {}
	last_changes = []
	_week = 0
	_last_gen_day = -1
	_next_id = 1
	flea_changed.emit()


func to_dict() -> Dictionary:
	return {"offers": offers.duplicate(true), "boxes": boxes.duplicate(true),
		"tip": tip.duplicate(true), "week": _week, "last_gen_day": _last_gen_day, "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	offers = d.get("offers", []).duplicate(true)
	boxes = d.get("boxes", []).duplicate(true)
	tip = d.get("tip", {}).duplicate(true)
	_week = int(d.get("week", 0))
	_last_gen_day = int(d.get("last_gen_day", -1))
	_next_id = int(d.get("next_id", 1))
	flea_changed.emit()
