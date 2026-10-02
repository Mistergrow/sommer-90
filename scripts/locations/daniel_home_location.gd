extends LocationBase
## Daniels Zimmer (LOCATION_FRIEND_ROOM_DANIEL) — Programmier-Zimmer von Schulfreund
## Daniel im Wohngebiet. Ruhig, geordnet, akademisch: Bücherregale voller Ordner &
## Doku, Endlosdrucker, Telefon/Modem fürs BBS, sauber beschriftete & sortierte
## Disketten. Das komplette Gegenteil von Alex' Chaos.
##
## Daniel ist der SOFTWARE-MENTOR (Gegenstück zu Sven/Hardware): hier lernt der
## Spieler wirklich programmieren — BASIC, Assembler, BBS, Netzwerke — NICHT über
## XP, sondern über echte Projekte ("Schreib ein Diskettenmenü", "Hilf beim
## BBS-Skript"). `programming_knowledge` wächst in einer tagesbegrenzten
## Mentorstrecke (parallel zu Svens `hardware_knowledge`).
## Alex mal da/mal weg (Zeitplan), Raum bleibt begehbar. Hotspots aufs 1672x941-Artwork.

const DanielLessons := preload("res://scripts/data/daniel_lesson_catalog.gd")


func background_base() -> String:
	return "LOCATION_FRIEND_ROOM_DANIEL"


func _build() -> void:
	if not has_background():
		add_hotspot(Rect2(30, 40, 130, 100), Loc.t("place.daniel_home_location.computertisch_mit_daniel_programmieren", "Computertisch — mit Daniel programmieren"), _desk)
		add_hotspot(Rect2(200, 40, 90, 90), Loc.t("place.daniel_home_location.bucherregal_doku", "Bücherregal — Doku"), _books)
		add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.daniel_home_location.tur_orte", "Tür (Orte)"), UIManager.open_map)
		return
	cover_mode = true
	virtual_size = Vector2(1672, 941)
	if not _daniel_home():
		add_away_notice(Loc.t("place.daniel_home_location.away_notice_line1",
			"Daniel ist nicht da — komm später wieder.") + "\n" +
			Loc.t("place.daniel_home_location.away_notice_line2",
				"Bücher und Listings kannst du trotzdem ansehen."))
	# Positionen aufs Artwork abgestimmt (große Flächen zuerst, wichtige/kleine später).
	add_hotspot(Rect2(1270, 560, 402, 381), Loc.t("place.daniel_home_location.bett", "Bett"), _bed)
	add_hotspot(Rect2(1040, 10, 300, 340), Loc.t("place.daniel_home_location.fenster_blick_in_siedlung", "Fenster — Blick in die Siedlung"), _window)
	add_hotspot(Rect2(700, 10, 340, 510), Loc.t("place.daniel_home_location.regal_ordner_dokumentation", "Regal — Ordner & Dokumentation"), _books)
	add_hotspot(Rect2(1470, 0, 202, 560), Loc.t("place.daniel_home_location.regal_programmier_bucher", "Regal — Programmier-Bücher"), _prog_books)
	add_hotspot(Rect2(150, 470, 380, 471), Loc.t("place.daniel_home_location.disketten_archiv_sauber_beschriftet", "Disketten-Archiv — sauber beschriftet"), _disk_archive)
	add_hotspot(Rect2(890, 330, 340, 205), Loc.t("place.daniel_home_location.arbeitstisch_listings_gerate", "Arbeitstisch — Listings & Geräte"), _prog_desk)
	add_hotspot(Rect2(905, 335, 165, 130), Loc.t("place.daniel_home_location.drucker_endlospapier", "Drucker — Endlospapier"), _printer)
	add_hotspot(Rect2(1085, 360, 120, 105), Loc.t("place.daniel_home_location.telefon", "Telefon"), _phone)
	add_hotspot(Rect2(1085, 465, 130, 70), Loc.t("place.daniel_home_location.modem_ins_bbs", "Modem — ins BBS"), _modem)
	add_hotspot(Rect2(185, 165, 190, 130), Loc.t("place.daniel_home_location.pinnwand_notizen_flussdiagramme", "Pinnwand — Notizen & Flussdiagramme"), _whiteboard)
	add_hotspot(Rect2(1340, 690, 300, 251), Loc.t("place.daniel_home_location.notizbuch_quellcode", "Notizbuch — Quellcode"), _notebook)
	# Computertisch (Herzstück: programmieren mit Daniel) + Ausgang zuletzt.
	add_hotspot(Rect2(200, 260, 420, 340), Loc.t("place.daniel_home_location.computertisch_mit_daniel_programmieren", "Computertisch — mit Daniel programmieren"), _desk)
	add_hotspot(Rect2(0, 110, 140, 720), Loc.t("place.daniel_home_location.tur_raus_orte", "Tür — raus (Orte)"), UIManager.open_map)


# ------------------------------------------------------------- Anwesenheit
func _daniel_home() -> bool:
	var env := OS.get_environment("DSS_AWAY")
	if env == "1":
		return false
	if env == "0":
		return true
	return NPCManager.is_here_now("npc_daniel", "daniel_home")


# ------------------------------------------------------------- Aktionen
## Herzstück: mit Daniel programmieren lernen — über echte Projekte, nicht XP.
func _desk() -> void:
	if not _daniel_home():
		UIManager.toast(Loc.t("place.daniel_home_location.daniels_amiga_mit_blinkendem_cursor_daneben", "Daniels Amiga mit blinkendem Cursor — daneben ordentlich gestapelte Listings. Ohne Daniel bleibt er dunkel."))
		return
	if int(GameManager.flags.get("daniel_lesson_day", -1)) == TimeManager.day_counter:
		UIManager.open_info(Loc.t("place.daniel_home_location.daily_project_title",
			"DANIEL · TAGESPROJEKT"), Loc.t("place.daniel_home_location.daily_project_done",
			"Für heute ist das Projekt durch. Daniel zeigt auf den kommentierten Ausdruck: »Erst verstehen, dann morgen erweitern.«"))
		return
	if PlayerStats.energie < 8:
		UIManager.toast(Loc.t("place.daniel_home_location.zu_mude_fur_fehlersuche_listings_daniel", "Zu müde für Fehlersuche und Listings. Daniel: »Morgen mit klarem Kopf.«"))
		return
	var annual_lesson := DanielLessons.active_lesson()
	if not annual_lesson.is_empty():
		_run_annual_lesson(annual_lesson)
		return
	var kn: int = int(GameManager.flags.get("programming_knowledge", 0))
	var projects: Array[Dictionary] = [
		{"brief_key": "place.daniel_home_location.project.disk_menu.brief",
			"brief": "Ein Diskettenmenü in Sommer BASIC schreiben und jede Eingabe abfangen.",
			"program": "my_listing_tool", "unlock_key": "place.daniel_home_location.project.disk_menu.unlock",
			"unlock": "MEIN LISTING-TOOL"},
		{"brief_key": "place.daniel_home_location.project.sorting.brief",
			"brief": "Dateinamen sortieren, Schleifen kürzen und den Speicherverbrauch messen.",
			"program": "amos_homage", "unlock_key": "place.daniel_home_location.project.sorting.unlock",
			"unlock": "SOMMER BASIC"},
		{"brief_key": "place.daniel_home_location.project.asm.brief",
			"brief": "Eine kleine 68000-Routine lesen, kommentieren und fehlerfrei assemblieren.",
			"program": "devpac_homage", "unlock_key": "place.daniel_home_location.project.asm.unlock",
			"unlock": "ASSEMBLER-WERKSTATT"},
		{"brief_key": "place.daniel_home_location.project.bbs.brief",
			"brief": "Ein BBS-Login-Skript mit sauberem Timeout und Abbruchpfad bauen.",
			"program": "terminal", "unlock_key": "place.daniel_home_location.project.bbs.unlock",
			"unlock": "NACHT-COMM"},
	]
	var lesson_index := mini(kn, projects.size() - 1)
	var project: Dictionary = projects[lesson_index]
	GameManager.flags["programming_knowledge"] = kn + 1
	GameManager.flags["daniel_lesson_day"] = TimeManager.day_counter
	PlayerStats.change_stat("energie", -8)
	PlayerStats.change_stat("wissen", 2 if kn < projects.size() else 1)
	NPCManager.change_trust("npc_daniel", 1)
	var unlocked := PlayerStats.add_program(str(project.get("program", "")))
	var unlock_name := Loc.t(str(project.get("unlock_key", "")), str(project.get("unlock", "")))
	var unlock_text := "\n\n" + Loc.t("place.daniel_home_location.new_program", "NEUES PROGRAMM: %s") % unlock_name if unlocked else ""
	var brief := Loc.t(str(project.get("brief_key", "")), str(project.get("brief", "")))
	UIManager.open_info(Loc.t("place.daniel_home_location.programming_title", "DANIEL — PROGRAMMIEREN"),
		Loc.t("place.daniel_home_location.programming_intro", "»Setz dich. Heute bauen wir etwas, das wirklich läuft.«")
		+ "\n\n" + brief + "\n\n"
		+ Loc.t("place.daniel_home_location.programming_review", "Daniel lässt dich den Fehler selbst finden, prüft dann jede Zeile mit dir und heftet den Ausdruck ab.")
		+ unlock_text + "\n\n" + Loc.t("place.daniel_home_location.programming_reward", "+%d Wissen · −8 Energie · nächstes Projekt morgen") % (2 if kn < projects.size() else 1))


func _run_annual_lesson(lesson: Dictionary) -> void:
	var knowledge := int(GameManager.flags.get("programming_knowledge", 0))
	GameManager.flags["programming_knowledge"] = knowledge + 1
	GameManager.flags["daniel_lesson_day"] = TimeManager.day_counter
	PlayerStats.change_stat("energie", -8)
	PlayerStats.change_stat("wissen", 2)
	NPCManager.change_trust("npc_daniel", 1)
	var program_id := str(lesson.get("program", ""))
	var unlocked := not program_id.is_empty() and PlayerStats.add_program(program_id)
	QuestManager.note_action(str(lesson.get("action", "")))
	var unlock_text := "\n\n" + Loc.t("place.daniel_home_location.new_program", "NEUES PROGRAMM: %s") % str(lesson.get("unlock", program_id.to_upper())) \
		if unlocked else ""
	UIManager.open_info(Loc.t("place.daniel_home_location.annual_title", "DANIEL %d · PROJEKT %d/3") % [
		int(lesson.get("year", TimeManager.year)), int(lesson.get("stage", 0)) + 1],
		Loc.t("place.daniel_home_location.annual_intro", "»Heute reicht kein Abschreiben. Wir bauen einen Test, der den Fehler beweist.«") + "\n\n"
		+ str(lesson.get("title", Loc.t("place.daniel_home_location.annual_default_title", "Programmierprojekt"))) + "\n\n"
		+ str(lesson.get("brief", ""))
		+ "\n\n" + Loc.t("place.daniel_home_location.annual_review", "Du setzt den ersten Entwurf um, Daniel provoziert drei Fehlerfälle und ihr heftet erst die bestandene Fassung ab.")
		+ unlock_text + "\n\n" + Loc.t("place.daniel_home_location.annual_reward", "+2 Wissen · −8 Energie · nächster Projekttag morgen"))


func _prog_desk() -> void:
	UIManager.toast(Loc.t("place.daniel_home_location.arbeitstisch_mit_endlospapier_listings_sauber_gelocht", "Arbeitstisch mit Endlospapier-Listings, sauber gelocht und abgeheftet. Hier entstehen Daniels Tools."))


func _books() -> void:
	UIManager.toast(Loc.t("place.daniel_home_location.regalmeter_voller_ordner_doku_handbucher_ausgedruckter", "Regalmeter voller Ordner: Doku, Handbücher, ausgedruckter Quellcode — alles beschriftet und sortiert."))


func _prog_books() -> void:
	var level := int(GameManager.flags.get("programming_knowledge", 0))
	var subjects := [
		Loc.t("place.daniel_home_location.rack.subject.0", "BASIC und Programmstruktur"),
		Loc.t("place.daniel_home_location.rack.subject.1", "Sortierung und Speicher"),
		Loc.t("place.daniel_home_location.rack.subject.2", "68000-Assembler"),
		Loc.t("place.daniel_home_location.rack.subject.3", "Modem- und BBS-Skripte"),
	]
	var active := DanielLessons.active_lesson()
	var annual := ""
	if not active.is_empty():
		annual = "\n\n" + Loc.t("place.daniel_home_location.annual_lab", "Aktuelles Jahreslabor: %s (Projekt %d/3)") % [
			str(active.get("title", "")), int(active.get("stage", 0)) + 1]
	UIManager.open_info(Loc.t("place.daniel_home_location.rack_title", "DANIELS PROGRAMMIERREGAL"),
		Loc.t("place.daniel_home_location.rack_body", "Ordner mit kommentierten Listings, Fehlerprotokollen und eigenen Beispielen.") + "\n\n"
		+ Loc.t("place.daniel_home_location.rack_progress_done", "Dein Stand: %d Lektion(en) abgeschlossen.") % level + "\n"
		+ Loc.t("place.daniel_home_location.rack_progress_next", "Nächstes Thema: %s") % subjects[mini(level, subjects.size() - 1)]
		+ annual)


func _disk_archive() -> void:
	UIManager.toast(Loc.t("place.daniel_home_location.disketten_penibel_beschriftet_alphabetisch_sortiert_komplette", "Disketten, penibel beschriftet und alphabetisch sortiert — das komplette Gegenteil von Alex' Kisten."))


func _printer() -> void:
	UIManager.toast(Loc.t("place.daniel_home_location.nadeldrucker_mit_endlospapier_damit_druck_ich", "Nadeldrucker mit Endlospapier. »Damit druck ich Listings — und du bald deine eigenen Etiketten.«"))


func _phone() -> void:
	UIManager.toast(Loc.t("place.daniel_home_location.telefon_daniels_leitung_nach_draussen_furs", "Das Telefon — Daniels Leitung nach draußen. Fürs Modem und für Absprachen mit der Szene."))


func _modem() -> void:
	if int(GameManager.flags.get("programming_knowledge", 0)) < 3:
		UIManager.toast(Loc.t("place.daniel_home_location.daniel_erst_eingaben_fehlerpfade_sauber_beherrschen", "Daniel: »Erst Eingaben und Fehlerpfade sauber beherrschen. Dann gehen wir ans BBS.«"))
		return
	var unlocked := PlayerStats.add_program("terminal")
	GameManager.flags["daniel_bbs_briefing"] = true
	UIManager.open_info(Loc.t("place.daniel_home_location.bbs_title", "DANIEL · BBS-VERBINDUNG"),
		Loc.t("place.daniel_home_location.bbs_body", "Daniel erklärt Wählton, Handshake, Login und den sauberen Verbindungsabbruch. ")
		+ (Loc.t("place.daniel_home_location.bbs_installed", "NACHT-COMM wurde installiert.") if unlocked else Loc.t("place.daniel_home_location.bbs_existing", "NACHT-COMM ist bereits auf deiner Sommerbench.")))


func _whiteboard() -> void:
	UIManager.toast(Loc.t("place.daniel_home_location.pinnwand_voller_notizen_flussdiagramme_adressen_daniel", "Pinnwand voller Notizen, Flussdiagramme und Adressen. Daniel denkt in Strukturen."))


func _notebook() -> void:
	UIManager.toast(Loc.t("place.daniel_home_location.notizbuch_voller_handgeschriebenem_quellcode_ideen_daniels", "Ein Notizbuch voller handgeschriebenem Quellcode und Ideen. Daniels Kladde."))


func _bed() -> void:
	UIManager.toast(Loc.t("place.daniel_home_location.ordentlich_gemachtes_bett_daneben_stapel_fachbucher", "Ordentlich gemachtes Bett. Daneben ein Stapel Fachbücher — Gute-Nacht-Lektüre."))


func _window() -> void:
	var w := Loc.t("place.daniel_home_location.weather_clear", "Draußen scheint die Sonne.") if WeatherManager.state() == "clear" else Loc.t("place.daniel_home_location.weather_grey", "Draußen ist's grau.")
	UIManager.toast(Loc.t("place.daniel_home_location.fenster_mit_blick_uber_siedlung_s", "Fenster mit Blick über die Siedlung. %s") % w)
