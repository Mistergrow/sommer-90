extends LocationBase
## Mikes Zimmer (LOCATION_FRIEND_ROOM_MIKE) — Schlafzimmer von Schulfreund Mike im
## Wohngebiet. Mike ist KEIN Bastler, sondern GAMER: überall Spieleschachteln,
## Joysticks, ein Fernseher mit laufendem Spiel, Beanbag, laute Stereoanlage,
## Cola & Süßkram. Hier: Spielen, tauschen, Multiplayer, Highscore-/Turnier-Kram,
## Gaming-Magazine, Spiele-Geheimnisse. Gegenstück zu Svens Bastelbude.
##
## Ort ist live; Gaming-Interaktionen sind Haken aufs kommende GameLibrary/
## TournamentManager-System — nichts erfunden. Mike ist nicht immer da (Zeitplan),
## der Raum bleibt begehbar (WorksEmpty). Hotspots aufs 1672x941-Artwork abgestimmt.


func background_base() -> String:
	return "LOCATION_FRIEND_ROOM_MIKE"


func _build() -> void:
	if not has_background():
		add_hotspot(Rect2(30, 40, 130, 100), Loc.t("place.mike_home_location.spiele_regal_tauschen", "Spiele-Regal — tauschen"), _games)
		add_hotspot(Rect2(200, 40, 90, 90), Loc.t("place.mike_home_location.fernseher_spiel_lauft", "Fernseher — Spiel läuft"), _tv)
		add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.mike_home_location.tur_orte", "Tür (Orte)"), UIManager.open_map)
		return
	cover_mode = true
	virtual_size = Vector2(1672, 941)
	if not _mike_home():
		add_away_notice("Mike ist nicht da — komm später wieder.\n(Spiele & Anlage kannst du trotzdem ansehen.)")
	# Positionen aufs Artwork abgestimmt (große Flächen zuerst, wichtige/kleine später).
	add_hotspot(Rect2(1204, 540, 468, 401), Loc.t("place.mike_home_location.bett", "Bett"), _bed)
	add_hotspot(Rect2(700, 20, 360, 380), Loc.t("place.mike_home_location.fenster_blick_in_siedlung", "Fenster — Blick in die Siedlung"), _window)
	add_hotspot(Rect2(150, 40, 230, 230), Loc.t("place.mike_home_location.regal_spiele_videos", "Regal — Spiele & Videos"), _console)
	add_hotspot(Rect2(300, 470, 270, 340), Loc.t("place.mike_home_location.spiele_regal_tausch_stapel", "Spiele-Regal — Tausch-Stapel"), _games)
	add_hotspot(Rect2(250, 785, 320, 156), Loc.t("place.mike_home_location.disketten_am_boden_kram", "Disketten am Boden — Kram"), _closet)
	add_hotspot(Rect2(360, 270, 380, 300), Loc.t("place.mike_home_location.computertisch_mikes_amiga", "Computertisch — Mikes Amiga"), _desk)
	add_hotspot(Rect2(735, 330, 140, 190), Loc.t("place.mike_home_location.gaming_magazine_cheats_tests", "Gaming-Magazine — Cheats & Tests"), _magazines)
	add_hotspot(Rect2(1030, 285, 235, 390), Loc.t("place.mike_home_location.fernseher_ecke_spiel_lauft", "Fernseher-Ecke — Spiel läuft"), _tv)
	add_hotspot(Rect2(860, 525, 285, 185), Loc.t("place.mike_home_location.sitzsack_abhangen", "Sitzsack — abhängen"), _beanbag)
	add_hotspot(Rect2(1300, 265, 245, 330), Loc.t("place.mike_home_location.stereoanlage_laut", "Stereoanlage — laut!"), _stereo)
	add_hotspot(Rect2(1000, 745, 330, 196), Loc.t("place.mike_home_location.tisch_cola_susskram_kassetten", "Tisch — Cola, Süßkram, Kassetten"), _snacks)
	# Joystick + Ausgang zuletzt → gewinnen den Treffertest.
	add_hotspot(Rect2(615, 355, 130, 95), Loc.t("place.mike_home_location.joysticks_wettkampf", "Joysticks — Wettkampf!"), _joysticks)
	add_hotspot(Rect2(0, 100, 150, 740), Loc.t("place.mike_home_location.tur_raus_orte", "Tür — raus (Orte)"), UIManager.open_map)


# ------------------------------------------------------------- Anwesenheit
func _mike_home() -> bool:
	var env := OS.get_environment("DSS_AWAY")
	if env == "1":
		return false
	if env == "0":
		return true
	return NPCManager.is_here_now("npc_mike", "mike_home")


# ------------------------------------------------------------- Aktionen
func _desk() -> void:
	if _mike_home():
		NPCManager.change_trust("npc_mike", 1)
		UIManager.open_info("MIKE — AMIGA",
			"»Setz dich, zock ne Runde!« Mikes Amiga läuft ständig — Spiele tauschen, "
			+ "zu zweit am Joystick, Highscores jagen. Heute zeigt Mike dir erst einmal seine besten Läufe.")
	else:
		UIManager.toast(Loc.t("place.mike_home_location.mikes_amiga_mit_farbmonitor_daneben_stapel", "Mikes Amiga mit Farbmonitor — daneben ein Stapel Spiele-Disks zum Tauschen."))


func _tv() -> void:
	UIManager.toast(Loc.t("place.mike_home_location.auf_dem_fernseher_lauft_shoot_em", "Auf dem Fernseher läuft ein Shoot'em Up im Loop — Mike übt für den Highscore. (Demos/Turniere kommen.)"))


func _console() -> void:
	UIManager.toast(Loc.t("place.mike_home_location.regal_voller_spieleschachteln_videos_konsole_kommt", "Regal voller Spieleschachteln und Videos. Eine Konsole kommt erst später dazu."))


func _games() -> void:
	UIManager.toast(Loc.t("place.mike_home_location.stapelweise_spiele_zum_tauschen_mike_uberfliegt", "Stapelweise Spiele zum Tauschen. Mike überfliegt deine Box: »Heute ist nichts dabei — bring nächstes Mal was Seltenes mit.«"))


func _magazines() -> void:
	UIManager.toast(Loc.t("place.mike_home_location.gaming_hefte_mit_losungen_cheats_highscore", "Gaming-Hefte mit Lösungen, Cheats und Highscore-Listen — Mike kennt jeden Trick."))


func _joysticks() -> void:
	if _mike_home():
		NPCManager.change_trust("npc_mike", 1)
		UIManager.toast(Loc.t("place.mike_home_location.haufen_joysticks_wettkampf_wer_zuerst_abkratzt", "Ein Haufen Joysticks. »Wettkampf? Wer zuerst abkratzt, zahlt die Cola!« (Turniere kommen.)"))
	else:
		UIManager.toast(Loc.t("place.mike_home_location.haufen_joysticks_manche_schon_durchgespielt_competitive", "Ein Haufen Joysticks — manche schon durchgespielt. Competitive-Ecke."))


func _beanbag() -> void:
	if _mike_home():
		NPCManager.change_trust("npc_mike", 1)
		UIManager.toast(Loc.t("place.mike_home_location.ihr_lummelt_im_sitzsack_quatscht_uber", "Ihr lümmelt im Sitzsack, quatscht über Spiele, Cheats und wer was gehört hat."))
	else:
		UIManager.toast(Loc.t("place.mike_home_location.fetter_sitzsack_chips_krumel_inklusive_mikes", "Ein fetter Sitzsack, Chips-Krümel inklusive. Mikes Lieblingsplatz."))


func _stereo() -> void:
	UIManager.open_music()


func _snacks() -> void:
	UIManager.toast(Loc.t("place.mike_home_location.cola_chips_brausepulver_walkman_mit_kassetten", "Cola, Chips, Brausepulver — und ein Walkman mit Kassetten. Gaming-Proviant."))


func _bed() -> void:
	UIManager.toast(Loc.t("place.mike_home_location.ungemachtes_bett_mit_buntem_bettzeug_darunter", "Ungemachtes Bett mit buntem Bettzeug. Darunter garantiert noch mehr Spiele-Disks."))


func _closet() -> void:
	UIManager.toast(Loc.t("place.mike_home_location.disketten_quellen_aus_den_kisten_mike", "Disketten quellen aus den Kisten. Mike hält den Deckel fest: »Da krame ich selbst durch — irgendwann.«"))


func _window() -> void:
	var w := "Draußen scheint die Sonne." if WeatherManager.state() == "clear" else "Draußen ist's grau."
	UIManager.toast(Loc.t("place.mike_home_location.fenster_mit_karo_gardinen_s", "Fenster mit Karo-Gardinen. %s") % w)
