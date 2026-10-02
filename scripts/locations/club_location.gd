extends LocationBase
## Der Computerclub — Treffpunkt der Szene. Hier wächst über die Jahre die
## MOD-Bibliothek: stöbern, vorhören, auf Diskette kopieren und daheim auf der
## Anlage hören. Nutzt LOCATION_COMPUTER_CLUB_MASTER_V01; ist das Bild nicht
## vorhanden, wird die Platzhalter-Zeichnung unten gerendert.


func background_base() -> String:
	return "LOCATION_COMPUTER_CLUB_MASTER"


func ambient_banter_profile() -> String:
	return "computer_club"


func present_npc_pressed(npc_id: String) -> void:
	if npc_id == "npc_stefan" and _offer_first_job():
		return
	super.present_npc_pressed(npc_id)


func _build() -> void:
	if has_background():
		cover_mode = true
		virtual_size = Vector2(1672, 941)
		# Fronttisch mit Disketten & Heften = MOD-Bibliothek
		add_hotspot(Rect2(280, 470, 670, 430), Loc.t("place.club_location.diskettentisch_mods_stobern_auf_diskette_kopieren", "Diskettentisch — MODs stöbern & auf Diskette kopieren"), UIManager.open_music_club)
		add_hotspot(Rect2(900, 300, 470, 240), Loc.t("place.club_location.mitglieder_neuigkeiten_horen", "Mitglieder — Neuigkeiten hören"), _talk)
		add_hotspot(Rect2(30, 130, 340, 230), Loc.t("place.club_location.schwarzes_brett_aushange", "Schwarzes Brett — Aushänge"), _board)
		add_hotspot(Rect2(1460, 330, 210, 260), Loc.t("place.club_location.kaffee_ecke", "Kaffee-Ecke"), _coffee)
		# Tauschabend: Kopien mit gutem Etikett finden hier Abnehmer.
		add_hotspot(Rect2(950, 560, 400, 280), Loc.t("place.club_location.tauschtisch_kopien_verkaufen", "Tauschtisch — Kopien verkaufen"), UIManager.open_copy_sale)
		add_hotspot(Rect2(1330, 210, 100, 220), Loc.t("place.club_location.tur_raus_orte", "Tür — raus (Orte)"), UIManager.open_map)
		return
	# Platzhalter-Hotspots (virtueller Raum 415x194)
	add_hotspot(Rect2(40, 90, 130, 80), Loc.t("place.club_location.diskettenkiste_mods_stobern_kopieren", "Diskettenkiste — Mods stöbern & kopieren"), UIManager.open_music_club)
	add_hotspot(Rect2(210, 60, 90, 70), Loc.t("place.club_location.mitglieder_neuigkeiten", "Mitglieder — Neuigkeiten"), _talk)
	add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.club_location.tur_raus_orte", "Tür — raus (Orte)"), UIManager.open_map)


func _talk() -> void:
	# 1990 bleibt der Spieler ausdrücklich Gast: ansehen, fragen, staunen — kein
	# eigenes Cracktro und keine Mitgliedschaft. Die spaeteren Club-Meilensteine
	# benutzen denselben realen Ort statt globaler Klick-Entscheidungen.
	if QuestManager.is_active("q_tut_bytewerk") and QuestManager.stage("q_tut_bytewerk") == 0:
		QuestManager.note_action("watch_club_demo")
		UIManager.open_info("HINTER DER CLUBTÜR",
			"Tobias startet eine Demo. Erst kommt ein kurzes Cracktro, dann laufen Code, Pixelgrafik und vier Musikkanäle zusammen. Du darfst Fragen stellen und Disketten ansehen — aber heute baust du nichts selbst.\n\nTobias: »Nächstes Jahr suchst du dir eine Rolle. Dann machen wir das gemeinsam.«")
		return
	if QuestManager.is_active("q_erste_demo"):
		if QuestManager.stage("q_erste_demo") == 3:
			QuestManager.note_action("present_club_intro")
			UIManager.open_info("DAS ERSTE CLUB-PROJEKT",
				"Euer Intro läuft auf dem Clubmonitor. Achim liest die Handle-Credits vor; die anderen erkennen deinen Beitrag und finden zwei echte Fehler, die ihr fürs nächste Release notiert. Das ist kein Solo-Tutorial mehr — es ist eure gemeinsame Arbeit.")
		else:
			UIManager.toast(Loc.t("place.club_location.tobias_setzt_dich_an_den_projekt", "Tobias setzt dich an den Projekt-Amiga: CLUB-INTRO wählen, Rolle und Beiträge verbinden, dann testen und auf Diskette freezen."))
			UIManager.open_demo_maker()
		return
	if QuestManager.is_active("q_club_member"):
		QuestManager.note_action("club_admission")
		UIManager.open_info("AUFNAHME",
			"Achim legt eure Intro-Disk auf den Tisch. »Du hast eine Rolle übernommen, Kritik ausgehalten und die anderen sauber genannt. Handschlag drauf: Ab heute gehörst du zum Club.«")
		return
	if _offer_first_job():
		return
	UIManager.open_rumors("group", "aeltere")


func _offer_first_job() -> bool:
	if not QuestManager.is_active("q_erster_job") or QuestManager.stage("q_erster_job") != 1:
		return false
	UIManager.toast(Loc.t("place.club_location.stefan_legt_dir_den_echten_auftrag", "Stefan legt dir den echten Auftrag hin. Unter JOBS kannst du ihn jetzt annehmen und direkt abliefern."))
	UIManager.open_jobs()
	return true


func _board() -> void:
	UIManager.toggle_window("win_bulletin", func() -> Control:
		var w := BulletinBoardWindow.new()
		w.board_id = "club"
		return w)


func _coffee() -> void:
	if PlayerStats.energie < 100:
		PlayerStats.change_stat("energie", 6)
		UIManager.toast(Loc.t("place.club_location.filterkaffee_aus_maschine_bitter_aber_wach", "Filterkaffee aus der Maschine. Bitter, aber wach macht er. (+Energie)"))
	else:
		UIManager.toast(Loc.t("place.club_location.kaffeemaschine_blubbert_jemand_hat_kekse_mitgebracht", "Die Kaffeemaschine blubbert. Jemand hat Kekse mitgebracht."))


func _draw() -> void:
	if has_background():
		return
	var s := view_scale()
	draw_set_transform(view_offset(), 0.0, Vector2(s, s))
	# Kellerraum: Neonlicht, Monitore, Diskettenkisten
	draw_rect(Rect2(0, 0, 415, 130), Palette.TEAL_DARK)
	draw_rect(Rect2(0, 130, 415, 64), Palette.GREY_DARK)
	draw_rect(Rect2(150, 6, 120, 8), Palette.WHITE_SOFT)  # Neonröhre
	# Tische mit flackernden Monitoren
	for i in 3:
		var x := 30 + i * 120
		draw_rect(Rect2(x, 70, 70, 40), Palette.BROWN)
		var flick := 0.12 * sin(anim_time * 8.0 + i)
		draw_rect(Rect2(x + 8, 44, 54, 30), Palette.GREY_DARK)
		draw_rect(Rect2(x + 12, 48, 46, 22), Palette.GREEN_DARK.lightened(0.2 + flick))
	# Diskettenkiste vorne links
	draw_rect(Rect2(40, 96, 120, 70), Palette.GREY_MID)
	for i in 8:
		draw_rect(Rect2(48 + i * 13, 100 + (i % 2) * 3, 10, 3),
			[Palette.BLUE_MID, Palette.RED_DARK, Palette.SAND, Palette.GREEN_DARK][i % 4])
	# Tür
	draw_rect(Rect2(365, 60, 40, 110), Palette.STEEL)
	draw_rect(Rect2(365, 60, 40, 110), Palette.BLACK, false, 1.0)
