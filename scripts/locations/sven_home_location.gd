extends LocationBase
## Svens Bude (LOCATION_FRIEND_ROOM_SVEN) — umgebauter Dachboden von Schulfreund
## Sven im Wohngebiet. Freundes-Hideout MIT WERKBANK: hier lernst du bei Sven
## Hardware — zerlegen, löten, aufrüsten, reparieren. Das ist als richtiges System
## geplant (Werkbank-Simulation + Wissens-Level statt Skilltree). Hier ist der Ort
## live verdrahtet; die Werkbank-Interaktionen sind evokative Haken auf das kommende
## RepairManager/UpgradeManager/HardwareManager-System — es wird NICHTS erfunden.
##
## Sven ist nicht immer da (NPC-Zeitplan). Der Raum ist trotzdem begehbar
## (WorksEmpty). Ist Sven da, baut ihr Freundschaft auf und er bringt dir was bei.
## Hotspots grob über dem 1672x941-Artwork — bei Bedarf mit dem Hotspot-Editor feinjustieren.


func background_base() -> String:
	return "LOCATION_FRIEND_ROOM_SVEN"


func _build() -> void:
	if not has_background():
		add_hotspot(Rect2(30, 40, 130, 100), Loc.t("place.sven_home_location.werkbank_hardware_bei_sven", "Werkbank — Hardware bei Sven"), _workbench)
		add_hotspot(Rect2(200, 40, 90, 90), Loc.t("place.sven_home_location.mod_sammlung_reinhoren", "MOD-Sammlung — reinhören"), _mods)
		add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.sven_home_location.tur_orte", "Tür (Orte)"), UIManager.open_map)
		return
	cover_mode = true
	virtual_size = Vector2(1672, 941)
	if not _sven_home():
		add_away_notice("Sven ist nicht da — komm später wieder.\n(Werkbank & Sammlung kannst du trotzdem ansehen.)")
	if bool(GameManager.flags.get("monitor_needs_repair", false)) \
			and not bool(GameManager.flags.get("monitor_repaired_by_friend", false)):
		add_depth_prop("res://assets/backgrounds/story_props/BROKEN_CRT_REPAIR_BENCH_V01.png",
			Rect2(765, 260, 370, 215), "BrokenCrtRepairBench")
	# Positionen auf das Artwork abgestimmt (1672x941). Reihenfolge: große Flächen
	# zuerst, wichtige/kleine später (letzte gewinnt Überlappung).
	add_hotspot(Rect2(1230, 560, 442, 381), Loc.t("place.sven_home_location.sofa_abhangen", "Sofa — abhängen"), _sofa)
	add_hotspot(Rect2(150, 80, 205, 690), Loc.t("place.sven_home_location.disketten_regal_tausch_stapel", "Disketten-Regal — Tausch-Stapel"), _diskbox)
	add_hotspot(Rect2(180, 775, 300, 165), Loc.t("place.sven_home_location.kisten_kram_verstecktes", "Kisten — Kram & Verstecktes"), _closet)
	add_hotspot(Rect2(385, 300, 320, 250), Loc.t("place.sven_home_location.computertisch_svens_amiga", "Computertisch — Svens Amiga"), _desk)
	add_hotspot(Rect2(690, 95, 285, 175), Loc.t("place.sven_home_location.mod_sammlung_reinhoren", "MOD-Sammlung — reinhören"), _mods)
	add_hotspot(Rect2(1180, 80, 450, 250), Loc.t("place.sven_home_location.dachfenster_blick_uber_siedlung", "Dachfenster — Blick über die Siedlung"), _window)
	add_hotspot(Rect2(1085, 345, 205, 150), Loc.t("place.sven_home_location.fernseher", "Fernseher"), _tv)
	add_hotspot(Rect2(1300, 350, 150, 250), Loc.t("place.sven_home_location.hifi_turm_anlage", "HiFi-Turm — Anlage"), _hifi)
	add_hotspot(Rect2(1300, 615, 360, 205), Loc.t("place.sven_home_location.magazin_kassetten_regal", "Magazin-/Kassetten-Regal"), _magazines)
	add_hotspot(Rect2(735, 560, 270, 175), Loc.t("place.sven_home_location.teile_schublade_chips_ram_kabel", "Teile-Schublade — Chips, RAM, Kabel"), _parts)
	add_hotspot(Rect2(905, 715, 425, 170), Loc.t("place.sven_home_location.kopfhorer_tisch_reinhoren", "Kopfhörer-Tisch — reinhören"), _hifi)
	# Werkbank (Herzstück) + Werkzeugwand + Ausgang zuletzt → gewinnen den Treffertest.
	add_hotspot(Rect2(700, 330, 440, 250), Loc.t("place.sven_home_location.werkbank_hardware_mit_sven", "Werkbank — Hardware mit Sven"), _workbench)
	add_hotspot(Rect2(975, 335, 300, 120), Loc.t("place.sven_home_location.werkzeugwand", "Werkzeugwand"), _tools)
	add_hotspot(Rect2(0, 120, 150, 720), Loc.t("place.sven_home_location.tur_raus_orte", "Tür — raus (Orte)"), UIManager.open_map)


# ------------------------------------------------------------- Anwesenheit
func _sven_home() -> bool:
	var env := OS.get_environment("DSS_AWAY")
	if env == "1":
		return false
	if env == "0":
		return true
	return NPCManager.is_here_now("npc_sven", "sven_home")


# ------------------------------------------------------------- Aktionen
## Herzstück: die Werkbank. Mit Sven lernst du echtes Hardware-Handwerk (kommt als
## Simulation + Wissens-Level). Ohne ihn siehst du dich nur um.
func _workbench() -> void:
	if not _sven_home():
		UIManager.toast(Loc.t("place.sven_home_location.svens_werkbank_lotstation_schraubendreher_teile_kisten", "Svens Werkbank: Lötstation, Schraubendreher, Teile-Kisten. Ohne Sven fasst du hier besser nichts an."))
		return
	if bool(GameManager.flags.get("monitor_needs_repair", false)) \
			and not bool(GameManager.flags.get("monitor_repaired_by_friend", false)):
		GameManager.flags["monitor_repaired_by_friend"] = true
		GameManager.flags.erase("monitor_needs_repair")
		PlayerStats.change_stat("wissen", 3)
		NPCManager.change_trust("npc_sven", 3)
		MemoryManager.record_once("monitor_repaired_with_friend")
		UIManager.open_info("SVEN · CRT-REPARATUR", "Sven misst erst die Versorgung, entlädt die Röhre fachgerecht und findet eine kalte Lötstelle in der Vertikalablenkung. Du lötest nach seiner Anleitung nach. Das Bild steht wieder stabil.\n\n+3 Wissen · +3 Vertrauen")
		remove_depth_prop("BrokenCrtRepairBench")
		return
	# Testbild-Kalibrierung anlernen (der Spieler hat's am eigenen Monitor versucht).
	if bool(GameManager.flags.get("wants_monitor_calibration", false)) \
			and not bool(GameManager.flags.get("learned_monitor_calibration", false)):
		GameManager.flags["learned_monitor_calibration"] = true
		GameManager.flags.erase("wants_monitor_calibration")
		PlayerStats.change_stat("wissen", 2)
		NPCManager.change_trust("npc_sven", 2)
		MemoryManager.record_once("learned_monitor_calibration_sven")
		UIManager.open_info("SVEN · TESTBILD EINSTELLEN", "»Dein Bild sitzt schief und ist zu dunkel? Guck.« Sven ruft das Testbild auf und dreht ruhig an H-Lage, V-Lage, Helligkeit, Fokus und Konvergenz, bis das Gitter sauber und mittig steht. »Nicht schwer — nur Geduld.«\n\nJetzt kannst du deinen eigenen Monitor zu Hause kalibrieren (Klick auf den Monitor).\n\n+2 Wissen · +2 Vertrauen")
		return
	var kn: int = int(GameManager.flags.get("hardware_knowledge", 0))
	GameManager.flags["hardware_knowledge"] = kn + 1   # echtes Wissen wächst durchs Zusehen/Mitmachen
	NPCManager.change_trust("npc_sven", 1)
	MemoryManager.record_once("first_soldering_lesson")   # Meilenstein: erste Lötstunde
	var lesson := "»Erst Draht und Öse erwärmen, dann wenig Zinn — nie nur die Spitze verzinnen.«" if kn == 0 \
		else ("»Farbe allein reicht nicht: markier jeden Kanal zusätzlich mit einem Symbol.«" if kn < 3 \
		else "»Heute üben wir Diagnose: matt ist kalt, ein dicker Blob kann zwei Kanäle brücken.«")
	UIManager.open_info("SVEN — WERKBANK",
		"»Setz dich, ich zeig dir was.« %s\n\nDie erste Lötstunde ist geschafft. Zu Hause kannst du jetzt den "
		% lesson + "Vierkanal-Joystick öffnen, Leitungen zuordnen, Lötstellen nacharbeiten und am Prüfstand testen. Weitere Hardware-Umbauten folgen später.")


func _desk() -> void:
	UIManager.toast(Loc.t("place.sven_home_location.svens_amiga_mit_offenem_deckel_er", "Svens Amiga mit offenem Deckel — er bastelt ständig dran rum. Monitor, Joystick, Modem."))


func _diskbox() -> void:
	UIManager.toast(Loc.t("place.sven_home_location.stapelweise_disketten_zum_tauschen_sven_winkt", "Stapelweise Disketten zum Tauschen. Sven winkt ab: »Erst prüfen und beschriften, dann reden wir über Tauschware.«"))


func _mods() -> void:
	UIManager.open_music()


func _magazines() -> void:
	UIManager.toast(Loc.t("place.sven_home_location.amiga_hefte_mit_angeknickten_ecken_sven", "Amiga-Hefte mit angeknickten Ecken — Sven markiert die Hardware-Tests mit Kuli."))


func _tools() -> void:
	UIManager.toast(Loc.t("place.sven_home_location.werkzeugschrank_schraubendreher_multimeter_spater_lotstation_svens", "Werkzeugschrank: Schraubendreher, Multimeter, später Lötstation. Svens Stolz."))


func _parts() -> void:
	UIManager.toast(Loc.t("place.sven_home_location.schublade_voller_chips_ram_riegel_kabel", "Schublade voller Chips, RAM-Riegel und Kabel. Sven kennt jedes Teil; du lässt die Sortierung lieber unangetastet."))


func _hifi() -> void:
	UIManager.toast(Loc.t("place.sven_home_location.hifi_ecke_mit_kopfhorern_hier_hort", "HiFi-Ecke mit Kopfhörern — hier hört ihr stundenlang MODs und diskutiert Tracks."))


func _sofa() -> void:
	if _sven_home():
		NPCManager.change_trust("npc_sven", 1)
		UIManager.toast(Loc.t("place.sven_home_location.ihr_lummelt_auf_dem_sofa_quatscht", "Ihr lümmelt auf dem Sofa, quatscht über Amiga, Fußball und wer die besten Disks hat."))
	else:
		UIManager.toast(Loc.t("place.sven_home_location.durchgesessenes_sofa_chipstuten_reste_gemutlich_aber", "Durchgesessenes Sofa, Chipstüten-Reste. Gemütlich — aber ohne Sven halb so lustig."))


func _tv() -> void:
	UIManager.toast(Loc.t("place.sven_home_location.alter_rohrenfernseher_meist_lauft_er_nebenbei", "Alter Röhrenfernseher, meist läuft er nebenbei. Manchmal hängt eine Konsole dran."))


func _closet() -> void:
	UIManager.toast(Loc.t("place.sven_home_location.vollgestopfter_schrank_sven_schiebt_tur_zu", "Vollgestopfter Schrank. Sven schiebt die Tür zu: »Das da hinten ist noch nicht für neugierige Hände.«"))


func _window() -> void:
	var w := "Draußen scheint die Sonne." if WeatherManager.state() == "clear" else "Draußen ist's grau."
	UIManager.toast(Loc.t("place.sven_home_location.dachfenster_mit_blick_uber_siedlung_s", "Dachfenster mit Blick über die Siedlung. %s") % w)
