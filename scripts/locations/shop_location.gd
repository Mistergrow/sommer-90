extends LocationBase
## Herrn Grubers Computerladen (LOCATION_COMPUTER_SHOP_MASTER_V01).
## Volles Artwork als Hintergrund; die Hotspots liegen im Bildraster
## (1672x941) über Regalen, Auslage, Tresen, Bestellkatalog und Tür.

const ShopEra := preload("res://scripts/data/computer_shop_era.gd")


## Eigenes NPC-Handling → generische Ansprech-Leiste aus.
func uses_generic_npcs() -> bool:
	return false


func background_base() -> String:
	return "LOCATION_COMPUTER_SHOP_MASTER"


func _build() -> void:
	AudioManager.play("shop_bell")   # Türglocke
	if has_background():
		cover_mode = true
		virtual_size = Vector2(1672, 941)
		_build_hotspots()
		if bool(GameManager.flags.get("fdd_needs_service", false)) \
				and not bool(GameManager.flags.get("fdd_serviced", false)):
			add_depth_prop("res://assets/backgrounds/story_props/FDD_ALIGNMENT_BENCH_V01.png",
				Rect2(805, 270, 330, 190), "FddAlignmentBench")
	else:
		_build_placeholder_hotspots()

	# Das finale Ladenmotiv besitzt absichtlich keinen eingebrannten Menschen:
	# Der jeweilige Inhaber ist ein echter, anklickbarer Laufzeit-Aktor. So
	# stimmen Anwesenheit, Dialog und Quest-Hotspot sichtbar miteinander ueberein.
	# Nach dem abgeschlossenen Abschiedsauftrag uebernimmt Jan Gruber; sein Onkel
	# ist dann wirklich im Ruhestand und nur noch gelegentlich am Flohmarkt.
	if has_background():
		# Der Inhaber steht hinter der langen Ruecktheke. Die Maske endet bewusst
		# einige Pixel oberhalb der Holzblende: So bleibt die helle Tischplatte als
		# klare Vordergrundkante sichtbar und die Figur kann nie vor der Theke
		# schweben. Position/Groesse bleiben im ShopPreview (F8) justierbar.
		add_npc_actor(ShopEra.owner_id(), Rect2(650, 205, 170, 270), _on_owner, 0.585)
	elif not has_background():
		var portrait := TextureRect.new()
		portrait.texture = NPCManager.portrait(ShopEra.owner_id())
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.custom_minimum_size = Vector2(64, 64)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(portrait)
		portrait.set_anchors_preset(Control.PRESET_CENTER)
		portrait.position += Vector2(-10, -40)

	# Rocky ist bei der Gesellenpruefung kein unsichtbares Job-Kriterium mehr,
	# sondern steht als eigener anklickbarer Pruefer am Serviceplatz. Eine aktive
	# Pruefung erzwingt seine Anwesenheit ueber NPCManager.forced_location().
	if "npc_rocky" in NPCManager.present_now("computer_shop"):
		add_npc_actor("npc_rocky",
			Rect2(955, 215, 165, 260) if has_background()
			else Rect2(265, 52, 52, 84), _on_rocky,
			0.585 if has_background() else 1.0)

	# Wartet eine Bestellung auf Abholung? Dezenter Hinweis beim Betreten.
	if OrderManager.has_news():
		UIManager.toast(Loc.t("place.shop_location.s_nickt_zur_theke_deine_bestellung", "%s nickt zur Theke: »Deine Bestellung liegt bereit.«") % \
			ShopEra.owner_name())


## Hotspots über dem finalen Artwork (Bildkoordinaten 1672x941). Größere
## Flächen zuerst, spezifische (Tresen, Katalog, Tür) zuletzt — so gewinnen
## die kleinen Ziele den Treffertest in Überlappungszonen.
func _build_hotspots() -> void:
	add_hotspot(Rect2(0, 30, 415, 875), Loc.t("place.shop_location.regale_links_leerdisketten_zubehor_gebrauchtes", "Regale links — Leerdisketten, Zubehör & Gebrauchtes"),
		UIManager.open_shop.bind("stock"))
	add_hotspot(Rect2(1180, 25, 492, 885), Loc.t("place.shop_location.regale_rechts_zeitschriften_spiele_boxen", "Regale rechts — Zeitschriften, Spiele & Boxen"),
		UIManager.open_shop.bind("stock"))
	add_hotspot(Rect2(520, 445, 650, 496), Loc.t("place.shop_location.auslage_aufrust_ecke_hardware_ausbau", "Auslage — Aufrüst-Ecke (Hardware-Ausbau)"),
		UIManager.open_upgrade_tree)
	add_hotspot(Rect2(300, 45, 175, 315), Loc.t("place.shop_location.schaufenster_zur_strasse", "Schaufenster zur Straße"), _on_window)
	var repair_tip := Loc.t(
		"place.shop_location.reparaturannahme_nimmt_geraete_an",
		"Reparaturannahme — %s nimmt Geräte an") % ShopEra.owner_name()
	if QuestManager.is_active("q_gruber_abschied"):
		repair_tip = Loc.t(
			"place.shop_location.kundenrechner_uebergabefall_diagnostizieren",
			"Kundenrechner · Übergabefall — mit Jan diagnostizieren") \
			if QuestManager.stage("q_gruber_abschied") == 0 \
			else Loc.t(
				"place.shop_location.uebergabeprotokoll_zu_jan",
				"Übergabeprotokoll fertig — zu Jan bringen")
	elif QuestManager.is_active("q_gesellenpruefung") \
			and QuestManager.stage("q_gesellenpruefung") == 1:
		repair_tip = Loc.t(
			"place.shop_location.esd_pruefplatz_pruefung_starten",
			"ESD-Prüfplatz — praktische Gesellenprüfung starten")
	add_hotspot(Rect2(858, 205, 195, 130), repair_tip, _on_repair)
	add_hotspot(Rect2(635, 205, 205, 190), Loc.t("place.shop_location.s_am_tresen_ansprechen", "%s hinter dem Tresen — ansprechen") % \
		ShopEra.owner_name(), _on_owner)
	add_hotspot(Rect2(880, 375, 150, 95), Loc.t("place.shop_location.bestellkatalog_sonderbestellungen_abholung", "Bestellkatalog — Sonderbestellungen & Abholung"),
		UIManager.open_shop.bind("catalog"))
	add_hotspot(Rect2(745, 185, 108, 205), Loc.t("place.shop_location.tur_raus_zu_den_orten", "Tür — raus (zu den Orten)"), UIManager.open_map)


## Fallback-Hotspots für die Platzhalter-Zeichnung (virtual 415x194).
func _build_placeholder_hotspots() -> void:
	add_hotspot(Rect2(170, 60, 60, 70), Loc.t("place.shop_location.s_ansprechen", "%s — ansprechen") % ShopEra.owner_name(), _on_owner)
	add_hotspot(Rect2(20, 30, 120, 90), Loc.t("place.shop_location.regale_sortiment_ansehen", "Regale — Sortiment ansehen"), UIManager.open_shop.bind("stock"))
	add_hotspot(Rect2(160, 118, 90, 30), Loc.t("place.shop_location.bestellkatalog_sonderbestellungen", "Bestellkatalog — Sonderbestellungen"), UIManager.open_shop.bind("catalog"))
	add_hotspot(Rect2(370, 60, 40, 110), Loc.t("place.shop_location.tur_rausgehen_orte", "Tür — rausgehen (Orte)"), UIManager.open_map)


func _on_owner() -> void:
	# Der Abschluss der Ladenuebergabe gehoert Jan. Auch in einem aelteren Save,
	# in dem Grubers Ruhestandsflag noch nicht gesetzt wurde, darf der sichtbare
	# Tresen den Spieler deshalb nicht wieder zu seinem Onkel schicken.
	if QuestManager.is_active("q_gruber_abschied") \
			and QuestManager.stage("q_gruber_abschied") == 1:
		_on_successor()
		return
	if ShopEra.gruber_retired():
		_on_successor()
	else:
		_on_gruber()


func _on_successor() -> void:
	if QuestManager.is_active("q_gruber_abschied") \
			and QuestManager.stage("q_gruber_abschied") == 1:
		DialogueManager.start_dialogue("jan_gruber_greet", "npc_jan_gruber", "n_handover")
		return
	var start_node := "n1" if bool(GameManager.flags.get("shop_successor_met", false)) \
		else "n_intro"
	DialogueManager.start_dialogue("jan_gruber_greet", "npc_jan_gruber", start_node)


func _on_gruber() -> void:
	# Herr Grubers eigene sichtbare Figur darf im letzten aktiven Auftrag noch
	# genau eine persoenliche Verweisung geben. gruber_weg ist bereits eine
	# Startbedingung dieser Quest; wuerden wir zuerst nur den Ruhestand pruefen,
	# leitete auch sein eigener Actor faelschlich direkt zu Jan um.
	if QuestManager.is_active("q_gruber_abschied") \
			and QuestManager.stage("q_gruber_abschied") == 1:
		DialogueManager.start_dialogue("gruber_greet", "npc_gruber", "n_farewell")
		return
	# Save-kompatible Absicherung: Wurde der Abschied waehrend dieses Besuchs
	# abgeschlossen, antwortet nicht erneut der bereits pensionierte Inhaber.
	if ShopEra.gruber_retired():
		_on_successor()
		return
	# Der bereits angenommene letzte Kundenfall ist Grubers aktuelle Priorität.
	# Freiwillige Kabel-/ESD-Jobs derselben Werkstatt dürfen ihn nicht verdecken.
	if _open_gruber_farewell_diagnosis_if_due():
		return
	# Die aktive Gesellenpruefung gewinnt vor Laden-Smalltalk. Damit fuehren
	# sowohl der Inhaber als auch Rocky und der sichtbare Serviceplatz zum selben
	# autoritativen Hardware-Minispiel.
	if _open_gesellenpruefung_if_due():
		return
	# 1993 fuehrt direkt von Grubers sichtbarem Tresen in die Arbeitsprobe.
	# Ohne diesen Pfad war die Quest zwar aktiv, ihr einziges Minispiel aber nur
	# ueber den unspezifischen JOBS-Knopf zu erraten.
	if _open_ausbildung_probe_if_due():
		return
	# Die storykritische Praktikumsschicht gewinnt vor allgemeinem Smalltalk.
	# Der sichtbare Gruber ist damit zugleich der Einstieg, statt dass der Spieler
	# den separaten JOBS-Knopf erraten muss.
	if QuestManager.is_active("q_praktikum") and QuestManager.stage("q_praktikum") == 1:
		var practice := JobManager.job_by_id("job_praktikum_shift")
		if JobManager.offered_here(practice, "computer_shop"):
			var gate := JobManager.can_do(practice)
			if bool(gate.get("ok", false)):
				UIManager.open_cable_untangle("job_praktikum_shift")
			else:
				UIManager.toast(Loc.t("place.shop_location.gruber_schaut_auf_den_dienstplan_s", "Gruber schaut auf den Dienstplan: »%s«") % str(gate.get("reason", "Heute nicht.")))
		else:
			UIManager.open_info("GRUBERS PRAKTIKUMSPLAN",
				"Deine betreute Schicht ist eingetragen.\n\n%s\n\nKomm mittags oder nachmittags wieder und sprich Gruber direkt hinter der Kasse an." % \
				JobManager.appointment_text(practice))
		return
	# Werkstattwissen wird ausschliesslich im Dialog und nach sichtbarer Erlaubnis
	# vergeben. Ein vorheriger Klick auf den eigenen Monitor ist nur Interesse,
	# niemals eine heimliche oder automatische Lehrstunde.
	# Ein aktiver Auftrag gewinnt vor allgemeinen Ladenfragen. Das repariert auch
	# bestehende Spielstaende, die bereits auf Stufe 2/2 warten: Der Spieler landet
	# beim Klick auf Gruber sofort in der passenden Erklaerung.
	var start_node := "n_diskcare_limits" if QuestManager.is_active("q_tut_diskcare") \
		and QuestManager.stage("q_tut_diskcare") == 1 else ""
	DialogueManager.start_dialogue("gruber_greet", "npc_gruber", start_node)


func _on_rocky() -> void:
	if _open_gesellenpruefung_if_due():
		return
	# Nach dem praktischen Teil enthaelt rocky_default die bedingte fachliche
	# Abnahme. Der direkte Baum verhindert, dass ein Zufalls-Bark sie verdeckt.
	DialogueManager.start_dialogue("rocky_default", "npc_rocky")


func _on_window() -> void:
	UIManager.toast(Loc.t("place.shop_location.im_schaufenster_dreht_amiga_demo_passanten", "Im Schaufenster dreht ein Amiga eine Demo — Passanten bleiben stehen."))


func _on_repair() -> void:
	if _open_gruber_farewell_diagnosis_if_due():
		return
	if QuestManager.is_active("q_gruber_abschied") \
			and QuestManager.stage("q_gruber_abschied") == 1:
		_on_successor()
		return
	if _open_gesellenpruefung_if_due():
		return
	if bool(GameManager.flags.get("fdd_needs_service", false)) \
			and not bool(GameManager.flags.get("fdd_serviced", false)):
		GameManager.flags["fdd_serviced"] = true
		GameManager.flags.erase("fdd_needs_service")
		PlayerStats.set_drive_alignment(1.0)
		PlayerStats.change_stat("wissen", 2)
		MemoryManager.record_once("fdd_aligned_by_gruber")
		UIManager.open_info("WERKSTATT · DF0-JUSTAGE", "%s spannt die Referenzdisk ein, stellt Spur Null mit dem Oszilloskop ein und kontrolliert den Kopfanschlag. Die Spurtreue von DF0 liegt wieder bei 100 %%.\n\n+2 Wissen · DF0 vollständig justiert" % ShopEra.owner_name())
		remove_depth_prop("FddAlignmentBench")
		return
	if _open_ausbildung_probe_if_due():
		return
	var practice_job := JobManager.job_by_id("job_praktikum_shift")
	if QuestManager.is_active("q_praktikum") and QuestManager.stage("q_praktikum") == 1:
		if JobManager.offered_here(practice_job, "computer_shop") \
				and bool(JobManager.can_do(practice_job).get("ok", false)):
			UIManager.open_cable_untangle("job_praktikum_shift")
		else:
			UIManager.toast(Loc.t("place.shop_location.praktikum_s", "Praktikum: %s") % JobManager.appointment_text(practice_job))
		return
	var cable_job := JobManager.job_by_id("job_gruber_cables")
	var assembly_job := JobManager.job_by_id("job_gruber_assembly")
	var diagnosis_job := JobManager.job_by_id("job_gruber_diagnosis")
	if not cable_job.is_empty() and JobManager.offered_here(cable_job, "computer_shop"):
		var chk := JobManager.can_do(cable_job)
		if bool(chk.get("ok", false)):
			UIManager.open_cable_untangle("job_gruber_cables")
		elif not diagnosis_job.is_empty() and JobManager.offered_here(diagnosis_job, "computer_shop") \
				and bool(JobManager.can_do(diagnosis_job).get("ok", false)):
			UIManager.open_shop_diagnosis("job_gruber_diagnosis")
		elif not assembly_job.is_empty() and JobManager.offered_here(assembly_job, "computer_shop") \
				and bool(JobManager.can_do(assembly_job).get("ok", false)):
			UIManager.open_hardware_assembly("job_gruber_assembly")
		else: UIManager.toast(Loc.t("place.shop_location.gruber_deutet_auf_werkstatt_s", "Gruber deutet auf die Werkstatt: »%s«") % str(chk.get("reason", "Heute nicht mehr.")))
	elif not assembly_job.is_empty() and JobManager.offered_here(assembly_job, "computer_shop"):
		var assembly_check := JobManager.can_do(assembly_job)
		if bool(assembly_check.get("ok", false)): UIManager.open_hardware_assembly("job_gruber_assembly")
		else: UIManager.toast(Loc.t("place.shop_location.gruber_deutet_auf_esd_matte_s", "Gruber deutet auf die ESD-Matte: »%s«") % str(assembly_check.get("reason", "Heute nicht mehr.")))
	elif not diagnosis_job.is_empty() and JobManager.offered_here(diagnosis_job, "computer_shop"):
		var diagnosis_check := JobManager.can_do(diagnosis_job)
		if bool(diagnosis_check.get("ok", false)): UIManager.open_shop_diagnosis("job_gruber_diagnosis")
		else: UIManager.toast(Loc.t("place.shop_location.gruber_deutet_auf_den_kundenrechner_s", "Gruber deutet auf den Kundenrechner: »%s«") % str(diagnosis_check.get("reason", "Heute nicht mehr.")))
	elif OrderManager.has_news():
		UIManager.toast(Loc.t("place.shop_location.deine_bestellung_liegt_an_theke_reparaturen", "»Deine Bestellung liegt an der Theke — die Reparaturen laufen noch.«"))
	else:
		UIManager.toast(Loc.t("place.shop_location.reparaturannahme_s_sortiert_kabel_stecker_altgerate", "Reparaturannahme: %s sortiert Kabel, Stecker und Altgeräte hinter dem Tresen.") % \
			ShopEra.owner_name())


## Storykritischer Einstieg fuer den gemeinsamen Uebergabefall. Der gemeinsame
## JobManager-Vertrag prueft weiterhin Ort, Termin, Energie und Voraussetzungen;
## nur ein fremder Werkstatt-Cooldown darf diesen neu angenommenen Fall nicht
## vier Tage unsichtbar machen.
func _open_gruber_farewell_diagnosis_if_due() -> bool:
	if not QuestManager.is_active("q_gruber_abschied") \
			or QuestManager.stage("q_gruber_abschied") != 0:
		return false
	var job := JobManager.job_by_id("job_gruber_diagnosis")
	if job.is_empty():
		UIManager.open_info("NEUSTART HINTER DEM TRESEN",
			"Der gemeinsame Übergabefall fehlt in den Werkstattunterlagen.")
		return true
	if JobManager.offered_here(job, "computer_shop"):
		var gate := JobManager.can_do(job)
		if bool(gate.get("ok", false)):
			UIManager.open_shop_diagnosis("job_gruber_diagnosis")
		else:
			UIManager.toast(Loc.t("place.shop_location.gruber_pruft_den_letzten_arbeitszettel_s", "Gruber prüft den letzten Arbeitszettel: »%s«") % \
				str(gate.get("reason", "Der Diagnoseplatz ist gerade nicht bereit.")))
	else:
		UIManager.open_info("NEUSTART HINTER DEM TRESEN",
			"Jan hat seinen ersten übernommenen Servicefall für dich reserviert.\n\n" + \
			"DEIN TERMIN: %s\n\nKomm mittags oder nachmittags wieder und sprich die beiden oder den Kundenrechner am Serviceplatz an." % \
			JobManager.appointment_text(job))
	return true


## Story-Einstieg der Gesellenpruefung. Alle sichtbaren Ladenwege benutzen
## dieselbe Jobdefinition und nennen bei falscher Uhrzeit den naechsten echten
## Termin. Im gueltigen Zeitfenster startet die ESD-Werkbank ohne JOBS-Umweg.
func _open_gesellenpruefung_if_due() -> bool:
	if not QuestManager.is_active("q_gesellenpruefung") \
			or QuestManager.stage("q_gesellenpruefung") != 1:
		return false
	var job := JobManager.job_by_id("job_gesellenpruefung")
	if job.is_empty():
		UIManager.open_info("GESELLENPRÜFUNG",
			"Rockys Prüfungsauftrag ist in den Werkstattunterlagen nicht auffindbar.")
		return true
	if JobManager.offered_here(job, "computer_shop"):
		var gate := JobManager.can_do(job)
		if bool(gate.get("ok", false)):
			UIManager.open_hardware_assembly("job_gesellenpruefung")
		else:
			UIManager.toast(Loc.t("place.shop_location.rocky_pruft_den_arbeitszettel_s", "Rocky prüft den Arbeitszettel: »%s«") % \
				str(gate.get("reason", "Die Prüfung kann gerade nicht beginnen.")))
	else:
		UIManager.open_info("PRAKTISCHE GESELLENPRÜFUNG",
			"Rocky hat den ESD-Prüfplatz für dich reserviert.\n\n" + \
			"DU BRAUCHST: mindestens 30 Energie\n" + \
			"DEIN TERMIN: %s\n\nSprich Rocky, Gruber oder den ESD-Prüfplatz an." % \
			JobManager.appointment_text(job))
	return true


## Gemeinsamer Story-Einstieg fuer Gruber-Aktor und Reparaturannahme. Die Quest
## gewinnt vor zufaelligen Werkstattjobs und nennt bei falscher Uhrzeit den
## naechsten echten Termin aus derselben Jobdefinition.
func _open_ausbildung_probe_if_due() -> bool:
	if not QuestManager.is_active("q_ausbildung") or QuestManager.stage("q_ausbildung") != 1:
		return false
	var job := JobManager.job_by_id("job_ausbildung_probe")
	if job.is_empty():
		UIManager.open_info("AUSBILDUNGSPLATZ",
			"Grubers Arbeitsprobe ist in den Werkstattunterlagen nicht auffindbar.")
		return true
	if JobManager.offered_here(job, "computer_shop"):
		var gate := JobManager.can_do(job)
		if bool(gate.get("ok", false)):
			UIManager.open_shop_diagnosis("job_ausbildung_probe")
		else:
			UIManager.toast(Loc.t("place.shop_location.gruber_schaut_auf_den_arbeitszettel_s", "Gruber schaut auf den Arbeitszettel: »%s«") % \
				str(gate.get("reason", "Heute nicht.")))
	else:
		UIManager.open_info("GRUBERS ARBEITSPROBE",
			"Gruber legt einen unbekannten Kundenrechner auf den Serviceplatz.\n\n" + \
			"DEIN TERMIN: %s\n\nKomm zu diesem Zeitfenster in den Laden und sprich Gruber hinter der Kasse an." % \
			JobManager.appointment_text(job))
	return true


func _draw() -> void:
	if has_background():
		return
	var s := view_scale()
	draw_set_transform(view_offset(), 0.0, Vector2(s, s))

	# Laden: helle Wände, Linoleumboden, Neonlicht-Stimmung
	draw_rect(Rect2(0, 0, 415, 120), Palette.TEAL)
	draw_rect(Rect2(0, 120, 415, 74), Palette.GREY_MID)
	draw_rect(Rect2(150, 8, 130, 12), Palette.WHITE_SOFT)  # Neonröhre

	# Regale: echte Box-Art des Jahres-Sortiments (Software-Bibel), Rest Platzhalter
	var games: Array = ShopManager.game_stock()
	var gi := 0
	for row in 3:
		var y := 34 + row * 28
		draw_rect(Rect2(20, y + 18, 120, 4), Palette.BROWN)   # Regalbrett
		for i in 5:
			var rect := Rect2(24 + i * 23, y, 18, 18)
			var placed := false
			if gi < games.size():
				var tex: Texture2D = SoftwareBible.art_texture(games[gi], "box_front")
				if tex != null:
					draw_texture_rect(tex, rect, false)
					placed = true
					gi += 1
			if not placed:
				var box_colors := [Palette.RED_DARK, Palette.BLUE_MID, Palette.SAND, Palette.GREEN_DARK, Palette.VIOLET]
				draw_rect(rect, box_colors[(i + row) % 5])
			draw_rect(rect, Palette.BLACK, false, 1.0)

	# Tresen mit Kasse
	draw_rect(Rect2(160, 118, 90, 30), Palette.BROWN)
	draw_rect(Rect2(160, 114, 90, 6), Palette.LEATHER)
	draw_rect(Rect2(218, 100, 18, 14), Palette.GREY_DARK)  # Kasse

	# Tür
	draw_rect(Rect2(370, 60, 40, 110), Palette.STEEL)
	draw_rect(Rect2(374, 66, 32, 60), Palette.CYAN.darkened(0.3))  # Glas
	draw_rect(Rect2(370, 60, 40, 110), Palette.BLACK, false, 1.0)

	# Schild
	draw_rect(Rect2(160, 30, 100, 16), Palette.WB_BLUE)
	draw_rect(Rect2(160, 30, 100, 16), Palette.WHITE, false, 1.0)
