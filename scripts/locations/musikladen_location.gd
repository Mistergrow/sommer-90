extends LocationBase
## Musikladen — Vorne (LOCATION_MUSIC_SHOP_FRONT_MASTER). Innenstadt, Mo–Sa.
## Vinyl, Kassetten, Leerkassetten, Walkman/HiFi, Hörstation, Magazine — und die
## Tür ins Hinterzimmer (Computer Music). Später: Keller mit Raritäten (Gerüchte!).
## Die Regale sind als abgeschlossene, atmosphärische Interaktionen umgesetzt;
## die Hörstation öffnet zusätzlich die spielbare Musiksammlung.
##
## Hotspot-Positionen grob gesetzt — bei Bedarf mit dem Hotspot-Editor feinjustieren.


func background_base() -> String:
	return "LOCATION_MUSIC_SHOP_FRONT_MASTER"


func _build() -> void:
	AudioManager.play("shop_bell")   # Türglocke
	if not has_background():
		add_hotspot(Rect2(30, 40, 120, 100), Loc.t("place.musikladen_location.stobern", "Stöbern"), _listen)
		add_hotspot(Rect2(200, 40, 90, 90), Loc.t("place.musikladen_location.hinterzimmer_computer_music", "Hinterzimmer — Computer Music"), _backroom)
		add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.musikladen_location.tur_orte", "Tür (Orte)"), UIManager.open_map)
		return
	cover_mode = true
	virtual_size = Vector2(1920, 1080)
	add_hotspot(Rect2(60, 60, 230, 150), Loc.t("place.musikladen_location.schwarzes_brett_anzeigen_geruchte", "Schwarzes Brett — Anzeigen & Gerüchte"), _board)
	add_hotspot(Rect2(40, 250, 360, 560), Loc.t("place.musikladen_location.vinyl_regal_lps_singles", "Vinyl-Regal — LPs & Singles"), _vinyl)
	add_hotspot(Rect2(410, 290, 300, 490), Loc.t("place.musikladen_location.kassetten_regal_musikkassetten", "Kassetten-Regal — Musikkassetten"), _cassette)
	add_hotspot(Rect2(720, 330, 220, 340), Loc.t("place.musikladen_location.leerkassetten_zum_aufnehmen", "Leerkassetten — zum Aufnehmen"), _blank)
	add_hotspot(Rect2(1160, 290, 290, 320), Loc.t("place.musikladen_location.tragbare_player_walkman", "Tragbare Player / Walkman"), _walkman)
	add_hotspot(Rect2(1160, 640, 300, 240), Loc.t("place.musikladen_location.musikmagazine_hefte_durchblattern", "Musikmagazine — Hefte durchblättern"), _magazines)
	add_hotspot(Rect2(1480, 240, 400, 430), Loc.t("place.musikladen_location.hifi_wand_anlagen_boxen", "HiFi-Wand — Anlagen & Boxen"), _hifi)
	add_hotspot(Rect2(760, 620, 340, 260), Loc.t("place.musikladen_location.horstation_reinhoren", "Hörstation — reinhören"), _listen)
	add_hotspot(Rect2(980, 380, 180, 200), Loc.t("place.musikladen_location.kasse_verkaufer_ansprechen", "Kasse — Verkäufer ansprechen"), _register)
	# Tür ins Hinterzimmer + Ausgang zuletzt → gewinnen den Treffertest.
	add_hotspot(Rect2(1560, 700, 340, 380), Loc.t("place.musikladen_location.tur_zum_hinterzimmer_computer_music", "Tür zum Hinterzimmer → Computer Music"), _backroom)
	add_hotspot(Rect2(800, 905, 320, 175), Loc.t("place.musikladen_location.ausgang_zu_den_orten", "Ausgang (zu den Orten)"), UIManager.open_map)


func _vinyl() -> void:
	UIManager.toast(Loc.t("place.musikladen_location.kisten_voller_lps_von_schlager_bis", "Kisten voller LPs — von Schlager bis Import. Der Verkäufer deutet auf die Preisschilder: Heute reicht dein Budget kaum für die Raritäten."))


func _cassette() -> void:
	UIManager.toast(Loc.t("place.musikladen_location.musikkassetten_sauber_alphabetisch_horkassetten_bleiben_hinter", "Musikkassetten, sauber alphabetisch. Die Hörkassetten bleiben hinter dem Tresen; durchblättern ist erlaubt."))


func _blank() -> void:
	UIManager.toast(Loc.t("place.musikladen_location.leerkassetten_c60_c90_verkaufer_empfiehlt_c90", "Leerkassetten C60 und C90. Der Verkäufer empfiehlt C90 für lange Radiosendungen, legt heute aber keine zurück."))


func _walkman() -> void:
	UIManager.toast(Loc.t("place.musikladen_location.walkman_tragbare_player_in_vitrine_dein", "Drei tragbare Kassettenspieler liegen in der Vitrine. Der Verkäufer lässt dich Gewicht, Tasten und Kopfhörer vergleichen."))


func _hifi() -> void:
	UIManager.toast(Loc.t("place.musikladen_location.verstarker_boxen_plattenspieler_grosse_anlage_furs", "Verstärker, Boxen und Plattenspieler stehen im A/B-Vergleich bereit. Ein Paar klingt großartig — und kostet fast dein ganzes Erspartes."))


func _magazines() -> void:
	UIManager.toast(Loc.t("place.musikladen_location.musikhefte_mit_charts_tests_anzeigen_magazine", "Musikhefte mit Charts, Gerätetests und Kleinanzeigen. Die Eselsohren markieren offenbar die spannenden Seiten."))


func _listen() -> void:
	UIManager.open_music()


func _board() -> void:
	UIManager.toggle_window("win_bulletin", func() -> Control:
		var w := BulletinBoardWindow.new()
		w.board_id = "musikladen"
		return w)


func _register() -> void:
	var t: int = int(GameManager.flags.get("music_owner_trust", 0))
	GameManager.flags["music_owner_trust"] = mini(100, t + 3)   # etwas Vertrauen schon vorne
	var lines := ["»Was suchst du? Vinyl, Kassette — oder was für'n Computer?«", ""]
	var tip := MODBible.friend_recommendation()
	if tip != "":
		lines.append("»Wenn's um Computer-Musik geht: %s Frag hinten nach.«" % tip)
	else:
		lines.append("»Hinten haben wir die Computer-Music-Ecke. Schau mal rein.«")
	UIManager.open_info("PLATTENDEALER", "\n".join(lines))


func _backroom() -> void:
	GameManager.goto_location("musikladen_computer_music", false)
