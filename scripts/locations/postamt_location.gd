extends LocationBase
## Postamt (LOCATION_POST_MASTER) — kleine Deutsche-Bundespost-Filiale, Innenstadt.
## Kernfunktion: Bestellungen/Pakete abholen (Alternative zum Ladenabholen über
## OrderManager), plus Briefmarken, Formulare, Schwarzes Brett, Briefkasten.
## Öffnungszeiten (Mo–Sa) stehen in town.json; Sonntag zu.
##
## Hotspots im Bildraster (virtual_size 1920×1080): Schalter, Paketabholung,
## Postversand-Abholung, Paketversand, Briefmarken, Formulare, Schwarzes Brett,
## Briefkasten, Ausgangstür. Läuft auch ohne Asset (Platzhalter-Hotspots).


func background_base() -> String:
	return "LOCATION_POST_MASTER"


func _build() -> void:
	if not has_background():
		add_hotspot(Rect2(30, 40, 120, 100), Loc.t("place.postamt_location.schalter_pakete_abholen", "Schalter — Pakete abholen"), _pickup)
		add_hotspot(Rect2(200, 40, 90, 90), Loc.t("place.postamt_location.schwarzes_brett", "Schwarzes Brett"), _board)
		add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.postamt_location.tur_raus_orte", "Tür — raus (Orte)"), UIManager.open_map)
		if OrderManager.has_news():
			UIManager.toast.call_deferred(Loc.t("place.postamt_location.am_schalter_liegt_sendung_fur_dich", "Am Schalter liegt eine Sendung für dich bereit."))
		return
	cover_mode = true
	virtual_size = Vector2(1920, 1080)
	# Große Flächen zuerst, kleine (am Tresen) zuletzt — so gewinnen die kleinen den Treffertest.
	add_hotspot(Rect2(0, 40, 170, 900), Loc.t("place.postamt_location.tur_raus_zu_den_orten", "Tür — raus (zu den Orten)"), UIManager.open_map)
	add_hotspot(Rect2(150, 440, 205, 330), Loc.t("place.postamt_location.gelber_briefkasten_briefe_disketten_einwerfen", "Gelber Briefkasten — Briefe & Disketten einwerfen"), _mailbox)
	add_hotspot(Rect2(395, 165, 175, 410), Loc.t("place.postamt_location.prospektstander_schwarzes_brett_anzeigen_geruchte", "Prospektständer / Schwarzes Brett — Anzeigen & Gerüchte"), _board)
	add_hotspot(Rect2(405, 515, 300, 275), Loc.t("place.postamt_location.stehpult_formulare_ausfullen_kuli_an_kette", "Stehpult — Formulare ausfüllen (Kuli an der Kette)"), _forms)
	add_hotspot(Rect2(1555, 230, 365, 580), Loc.t("place.postamt_location.paketregal_deine_abholpakete", "Paketregal — deine Abholpakete"), _pickup)
	add_hotspot(Rect2(1175, 625, 380, 215), Loc.t("place.postamt_location.sendungstisch_post_versandabholung", "Sendungstisch — Post-/Versandabholung"), _pickup)
	add_hotspot(Rect2(640, 330, 740, 250), Loc.t("place.postamt_location.schalter_frau_am_schalter_ansprechen", "Schalter — Frau am Schalter ansprechen"), _counter)
	add_hotspot(Rect2(660, 400, 230, 160), Loc.t("place.postamt_location.briefmarken_kaufen", "Briefmarken kaufen"), _stamps)
	add_hotspot(Rect2(905, 400, 210, 160), Loc.t("place.postamt_location.rechnungen_bezahlen_telefon", "Rechnungen bezahlen (Telefon)"), _pay_bill)
	add_hotspot(Rect2(910, 470, 190, 120), Loc.t("place.postamt_location.paketwaage_paket_aufgeben", "Paketwaage — Paket aufgeben"), _shipping)
	if OrderManager.has_news():
		UIManager.toast.call_deferred(Loc.t("place.postamt_location.postbeamtin_nickt_zum_regal_paket_liegt", "Die Postbeamtin nickt zum Regal: »Ein Paket liegt für Sie bereit.«"))


# ------------------------------------------------------------- Aktionen

## Kernfunktion: bereitliegende Bestellungen/Pakete abholen (OrderManager) — das
## Postamt ist die Alternative zum Abholen im Computerladen.
func _pickup() -> void:
	AudioManager.play("box_item")
	if not OrderManager.has_news():
		UIManager.toast(Loc.t("place.postamt_location.kein_paket_bereit_vielleicht_ist_noch", "Kein Paket bereit. Vielleicht ist noch etwas unterwegs — Geduld."))
		return
	var picked: Array = []
	for entry in OrderManager.arrived.duplicate():
		var r: Dictionary = OrderManager.pickup(str(entry.get("id", "")))
		if r.get("ok", false):
			picked.append(str(r.get("text", "")))
	if picked.is_empty():
		UIManager.toast(Loc.t("place.postamt_location.am_schalter_klemmt_s_komm_gleich", "Am Schalter klemmt's — komm gleich nochmal."))
	else:
		UIManager.open_info("POSTAMT — ABHOLUNG", "Frisch abgestempelt und ausgehändigt:\n\n" + "\n".join(picked))
		MemoryManager.record("postamt", "am Postamt %d Sendung(en) abgeholt" % picked.size())


func _counter() -> void:
	var lines := ["»Guten Morgen! Was kann ich für Sie tun?«", ""]
	if OrderManager.has_news():
		lines.append("»Sie haben Post — schauen Sie mal ins Regal.«")
	elif not OrderManager.pending.is_empty():
		lines.append("»Ihre Bestellung ist noch unterwegs. Kommt bald.«")
	else:
		lines.append("»Momentan liegt nichts für Sie bereit. Briefmarken vielleicht?«")
	UIManager.open_info("POSTBEAMTIN", "\n".join(lines))


func _board() -> void:
	UIManager.toggle_window("win_bulletin", func() -> Control:
		var w := BulletinBoardWindow.new()
		w.board_id = "postamt"
		return w)


func _stamps() -> void:
	if PlayerStats.geld < 1:
		UIManager.toast(Loc.t("place.postamt_location.nichtmal_fur_ne_briefmarke_reicht_s", "Nichtmal für 'ne Briefmarke reicht's grad. Später."))
		return
	UIManager.toast(Loc.t("place.postamt_location.bogen_sondermarken_hinter_glas_fur_heute", "Ein Bogen Sondermarken hinter Glas. Für heute brauchst du keine — anschauen kostet nichts."))


func _forms() -> void:
	UIManager.toast(Loc.t("place.postamt_location.nachnahme_paketkarte_postanweisung_formulare_an_kette", "Nachnahme, Paketkarte, Postanweisung … die Formulare an der Kette. (Bald nutzbar.)"))


func _shipping() -> void:
	UIManager.toast(Loc.t("place.postamt_location.waage_portotabelle_braunes_packpapier_ohne_adressiertes", "Waage, Portotabelle, braunes Packpapier. Ohne adressiertes Paket gibt es hier nichts aufzugeben."))


func _mailbox() -> void:
	UIManager.toast(Loc.t("place.postamt_location.gelbe_briefkasten_wird_nachmittags_geleert_dein", "Der gelbe Briefkasten wird nachmittags geleert. Dein Rucksack enthält gerade keine frankierte Sendung."))


## Telefonrechnung am Schalter bezahlen (bar) — sonst sperrt Papa die Leitung.
func _pay_bill() -> void:
	if PhoneManager.bill_due <= 0:
		UIManager.open_info("RECHNUNGEN", "Keine offene Telefonrechnung.\n\nAufgelaufene Gebühren diesen Monat: %d DM (Rechnung kommt am Monatsersten)." % PhoneManager.bill_open)
		return
	if PhoneManager.pay_bill():
		AudioManager.relay()
		UIManager.toast(Loc.t("place.postamt_location.telefonrechnung_bezahlt_papa_ist_besanftigt_leitung", "Telefonrechnung bezahlt. Papa ist besänftigt — die Leitung ist frei."))
	else:
		UIManager.toast(Loc.t("place.postamt_location.nicht_genug_bargeld_fur_rechnung_d", "Nicht genug Bargeld für die Rechnung (%d DM). Hebe was ab oder verkauf Kopien.") % PhoneManager.bill_due)
