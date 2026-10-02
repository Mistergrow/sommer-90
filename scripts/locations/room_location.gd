extends LocationBase
## Das Jugendzimmer — Hauptschauplatz. Master-Raum ROOM_MASTER_1992 in
## Frontansicht (Tageslicht; Wetter/Tageszeit kommen als Overlays,
## s. docs/VFX_BIBLE.md). Prozeduraler Platzhalter als Fallback.


var _starter_carton_hotspot: Button = null


func background_base() -> String:
	return "LOCATION_ROOM_MASTER"


## Layer-System hat Vorrang (Art-Bible): Liegt ein ROOM_BASE-Layer unter
## assets/backgrounds/layers/, baut der RoomCompositor das Zimmer modular
## zusammen (Basis + Hardware + Overlays). Sonst: Einzelbild (room_<jahr>.png)
## oder prozeduraler Platzhalter.
func _try_load_background() -> void:
	if RoomCompositor.base_available(TimeManager.year):
		var comp := RoomCompositor.new()
		add_child(comp)
		# Der Raum hat keinen flachen _bg_rect, sondern echte RGBA-Hardwarelagen.
		# Trotzdem exponiert er denselben Offset-Vertrag an LocationBase, damit
		# Hotspots exakt mit der neuen RoomDepth-Projektion mitwandern.
		_stage_25d = comp
		_has_background = true
		return
	super()


func _build() -> void:
	if has_background():
		# Hotspots auf dem Master-Raum (Master-Koordinaten 1920x1080, Cover-
		# Projektion wie der Compositor). Quelle: data/room_anchors.json →
		# "hotspots" — im Deko-Modus sichtbar und editierbar (Taste T).
		cover_mode = true
		virtual_size = Vector2(1920.0, 1080.0)
		var cover_anchor_data: Array = RoomCompositor.config().get(
			"gameplay_cover_anchor", [0.5, 0.5])
		if cover_anchor_data.size() >= 2:
			cover_anchor = Vector2(
				float(cover_anchor_data[0]), float(cover_anchor_data[1]))
		var actions := {
			"computer": _on_computer, "window": _on_window,
			"magazine": _on_magazine, "sleep": _on_sleep,
			"map": UIManager.open_map, "stereo": _on_stereo,
			"monitor_power": _on_monitor_power, "amiga_power": _on_amiga_power,
			"monitor_primary": _on_monitor_primary,
			"monitor_tune": UIManager.open_monitor_tune,
			"strip_power": _on_strip_power,
			"telefon": _on_telefon, "kalender": UIManager.open_calendar,
			"trophywall": _on_trophywall, "joystick_repair": UIManager.open_joystick_repair,
			"muell": _on_muell, "demo": _on_demo,
			"jobs": UIManager.open_jobs, "chores": _on_chores,
			"starter_carton": _on_starter_carton,
			"collection": UIManager.open_collection_cabinet,
		}
		for hotspot_name in RoomCompositor.config().get("hotspots", {}):
			var entry: Dictionary = RoomCompositor.config()["hotspots"][hotspot_name]
			if not _room_hotspot_active(entry):
				continue
			var callback: Callable = actions.get(str(entry.get("action", "")), Callable())
			if not callback.is_valid():
				continue
			var label := _hotspot_label(hotspot_name, str(entry.get("label", hotspot_name)))
			var corners: Array = entry.get("corners", [])
			var r: Array = entry.get("rect", [])
			var added := false
			# Bildschirm und physische CRT-Bedienelemente folgen ihrem jeweiligen
			# Modellprofil. So sitzt der Einschalter beim 1084S, 1901, 1942 und
			# 17-Zoll-Multisync wirklich auf dem sichtbaren Gehaeuse.
			var monitor_region := str(entry.get("from_monitor_control", ""))
			if not monitor_region.is_empty():
				var mr := RoomCompositor.monitor_control_master_rect(
					monitor_region, float(entry.get("pad", 0.0)))
				if mr.size.x > 0.0:
					add_hotspot(mr, label, callback)
					added = true
			# "from_layer": Klickfeld folgt automatisch dem Prop-Layer (Anchor im
			# Deko-Editor), statt an einem festen — leicht driftenden — Rect zu kleben.
			var from_layer := str(entry.get("from_layer", ""))
			if not added and from_layer != "":
				var lr := RoomCompositor.layer_master_rect(from_layer, float(entry.get("pad", 14.0)))
				if lr.size.x > 0.0:
					add_hotspot(lr, label, callback)
					added = true
			if not added and corners.size() == 4:
				add_hotspot_quad(corners, label, callback)
				added = true
			elif not added and r.size() == 4:
				add_hotspot(Rect2(r[0], r[1], r[2], r[3]), label, callback)
				added = true
			if added:
				var hotspot_button := (_hotspot_defs.back() as Dictionary).get("button") as Button
				if hotspot_name == "desk_magazine":
					hotspot_button.name = "HotspotDeskMagazine"
				elif str(entry.get("action", "")) == "starter_carton":
					_starter_carton_hotspot = hotspot_button
					_starter_carton_hotspot.name = "HotspotStarterCarton"
		return
	# Platzhalter-Zeichnung (virtuelle Koordinaten 415x194, s. LocationBase)
	add_hotspot(Rect2(60, 52, 145, 65), Loc.t("place.room_location.computer_an_den_rechner_setzen_werkbank", "Computer — an den Rechner setzen (WERKBANK 1.3)"), _on_computer)
	add_hotspot(Rect2(330, 118, 84, 72), Loc.t("place.room_location.bett_schlafen_bis_zum_nachsten_morgen", "Bett — schlafen bis zum nächsten Morgen"), _on_sleep)
	add_hotspot(Rect2(8, 55, 40, 100), Loc.t("place.room_location.tur_rausgehen_orte", "Tür — rausgehen (Orte)"), UIManager.open_map)
	add_hotspot(Rect2(295, 88, 100, 24), Loc.t("place.room_location.regal_zeitschrift_lesen", "Regal — Zeitschrift lesen"), _on_magazine)
	add_hotspot(Rect2(248, 16, 84, 66), Loc.t("place.room_location.fenster_dem_regen_zusehen", "Fenster — dem Regen zusehen"), _on_window)
	add_hotspot(Rect2(172, 85, 24, 27), Loc.t("place.room_location.joystick_offnen_loten_prufen", "Joystick — öffnen, löten & prüfen"), UIManager.open_joystick_repair)
	add_hotspot(Rect2(210, 105, 36, 22), Loc.t("place.room_location.notizbuch_jobs_bezahlte_hausarbeit", "Notizbuch — Jobs & bezahlte Hausarbeit"), UIManager.open_jobs)


# ------------------------------------------------------------- Interaktionen

## Raum-Hotspots folgen denselben Flag-Gates wie sichtbare Prop-Layer. Damit
## bleibt nach einem Save/Load kein unsichtbarer Klickrahmen an einer Stelle,
## deren Karton oder Gerät längst aus der Szene entfernt wurde.
func _room_hotspot_active(entry: Dictionary) -> bool:
	var required_item := str(entry.get("requires_inventory", ""))
	if not required_item.is_empty():
		var minimum := maxi(1, int(entry.get("requires_inventory_count", 1)))
		if InventoryManager.count(required_item) < minimum:
			return false
	var required_flag := str(entry.get("requires_flag", ""))
	if not required_flag.is_empty() and not bool(GameManager.flags.get(required_flag, false)):
		return false
	var excluded_flag := str(entry.get("unless_flag", ""))
	if not excluded_flag.is_empty() and bool(GameManager.flags.get(excluded_flag, false)):
		return false
	for flag_value: Variant in entry.get("unless_any_flags", []):
		if bool(GameManager.flags.get(str(flag_value), false)):
			return false
	return true


## Klick auf den Schreibtisch/Amiga: hängt vom Einschalt-/Boot-Zustand ab.
## Erst Monitor an, dann Amiga am Netzteil an → Kickstart „Diskette einlegen";
## einlegen bootet und setzt an die WERKBANK 1.3.
## Vor dem Aufbau steht noch kein Rechner auf dem Tisch → zum Karton lenken statt
## verwirrender Strom-Hinweise auf leere Stellen.
func _setup_pending() -> bool:
	if bool(GameManager.flags.get("monitor_placed", false)):
		return false
	UIManager.toast(Loc.t("place.room_location.hier_steht_noch_kein_rechner_offne", "Hier steht noch kein Rechner. Öffne den Karton vom Vater auf dem Boden und bau Amiga, Monitor und Netzteil auf."))
	return true


func _on_computer() -> void:
	if _setup_pending():
		return
	# Lief beim Aufstehen etwas live auf der Röhre weiter? Dann nahtlos dort weitermachen.
	if UIManager.resume_live_app():
		return
	match UIManager.boot_state():
		"off":
			if not UIManager.strip_power:
				UIManager.toast(Loc.t("place.room_location.alles_stromlos_erst_den_roten_schalter", "Alles stromlos. Erst den roten Schalter am Mehrfachverteiler unterm Tisch einschalten."))
			else:
				UIManager.toast(Loc.t("place.room_location.monitor_ist_aus_schalte_ihn_erst", "Der Monitor ist aus — schalte ihn erst am Gerät ein."))
		"nosignal":
			UIManager.toast(Loc.t("place.room_location.kein_signal_schalte_den_amiga_am", "Kein Signal. Schalte den Amiga am Netzteil-Brick ein."))
		"kickstart":
			if UIManager.has_hdd():
				if PlayerStats.hdd_bootable():
					# Bereits vollständig eingerichtete Platte: Standardboot.
					UIManager.boot_from_hdd()
				else:
					UIManager.toast(Loc.t("place.room_location.hdd_not_bootable_insert_system",
						"HDD erkannt, nicht bootfähig — Install-/Workbench-Disk einlegen."))
					UIManager.open_boot_selector()
			else:
				# Aktiver Amiga ohne passende Festplatte: Kickstart fragt nach
				# der Boot-Diskette (A500-Hand bzw. A600-2.x-Animation).
				# Alle Disketten der Sammlung anzeigen → eine zum Booten wählen.
				UIManager.open_boot_selector()
		"booted":
			UIManager.open_werkbank()


## Die grosse sichtbare Roehre ist die normale Rechnerinteraktion. Kalibrieren
## ist eine bewusste Servicehandlung an den Reglern und darf nicht bei jedem
## Klick auf das Monitorbild erneut den Spielfluss unterbrechen.
func _on_monitor_primary() -> void:
	_on_computer()


## Der Karton vom Vater — gestaffeltes Auspacken. Jede Stufe blendet über ein Flag
## das nächste Gerät auf dem (anfangs leeren) Schreibtisch ein und baut den Raum neu:
## öffnen → Amiga+Netzteil aufstellen → Monitor+Maus aufstellen → einschalten & booten.
func _on_starter_carton() -> void:
	var f: Dictionary = GameManager.flags
	# Stufe 1 — Karton öffnen.
	if not bool(f.get("starter_carton_opened", false)):
		f["starter_carton_opened"] = true
		AudioManager.play("box_tape")
		_rebuild_room()
		UIManager.open_info(Loc.t("place.room_location.father_box_title", "DER KARTON VOM VATER"),
			Loc.t("place.room_location.father_box_body", "Klebeband ab, Laschen auf: ein Amiga 500, ein 1084S-Monitor, das schwere Netzteil und eine Maus. Alles gebraucht, aber vollständig.\n\nZieh zuerst den Amiga heraus und stell ihn auf den Schreibtisch."))
		return
	# Stufe 2 — Amiga + Netzteil aufstellen.
	if not bool(f.get("amiga_placed", false)):
		f["amiga_placed"] = true
		AudioManager.play("box_tape")
		_rebuild_room()
		UIManager.toast(Loc.t("place.room_location.amiga_steht_tastatur_schwere_netzteil_brick", "Der Amiga steht — Tastatur und das schwere Netzteil-Brick dran. Jetzt Monitor und Maus aus dem Karton."))
		return
	# Stufe 3 — Monitor + Maus aufstellen. Danach ist der Karton leer.
	if not bool(f.get("monitor_placed", false)):
		f["monitor_placed"] = true
		AudioManager.play("box_tape")
		_retire_starter_carton_hotspot()
		_rebuild_room()
		UIManager.open_info(Loc.t("place.room_location.setup_complete_title", "AUFGEBAUT"),
			Loc.t("place.room_location.setup_complete_body", "Amiga, Monitor, Maus, Netzteil — alles steht, der Karton ist leer.\n\nJetzt der Strom: erst der rote Schalter am Mehrfachverteiler unterm Tisch, dann Monitor und Amiga-Netzteil. Dann fragt der Kickstart nach der Startdiskette."))
		return
	# Fertig aufgebaut.
	if not bool(f.get("booted_amiga", false)):
		UIManager.toast(Loc.t("place.room_location.karton_ist_leer_schalt_den_verteiler", "Der Karton ist leer. Schalt den Verteiler unterm Tisch an, dann Monitor und Netzteil — dann bootet die Werkbank."))
	else:
		UIManager.toast(Loc.t("place.room_location.leere_karton_vom_vater_den_heb", "Der leere Karton vom Vater. Den heb ich mir auf."))


## Beim letzten Auspackschritt sofort aus Eingabe und Layout entfernen. Nur
## queue_free() wäre einen Frame lang noch hover-/klickbar und erzeugte genau den
## störenden Rahmen, obwohl der Compositor den Karton bereits ausgeblendet hat.
func _retire_starter_carton_hotspot() -> void:
	if not is_instance_valid(_starter_carton_hotspot):
		return
	_starter_carton_hotspot.disabled = true
	_starter_carton_hotspot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_starter_carton_hotspot.visible = false
	for index in range(_hotspot_defs.size() - 1, -1, -1):
		if (_hotspot_defs[index] as Dictionary).get("button") == _starter_carton_hotspot:
			_hotspot_defs.remove_at(index)
			break
	_starter_carton_hotspot.queue_free()
	_starter_carton_hotspot = null


## RoomCompositor neu zusammensetzen, damit neu freigeschaltete Layer erscheinen.
func _rebuild_room() -> void:
	for child in get_children():
		if child is RoomCompositor:
			child.rebuild()


## Monitor am Gerät ein-/ausschalten (Einschalt-Effekt läuft im Overlay).
func _on_monitor_power() -> void:
	if _setup_pending():
		return
	if not UIManager.monitor_power and not UIManager.strip_power:
		UIManager.toast(Loc.t("place.room_location.netzschalter_klickt_aber_rohre_bleibt_dunkel", "Der Netzschalter klickt, aber die Röhre bleibt dunkel — der Mehrfachverteiler unterm Tisch ist aus."))
		return
	UIManager.toggle_monitor_power()
	var state_text := Loc.t("place.room_location.switched_on", "eingeschaltet") if UIManager.monitor_power \
		else Loc.t("place.room_location.switched_off", "ausgeschaltet")
	UIManager.toast(Loc.t("place.room_location.monitor_s", "Monitor %s.") % state_text)


## Amiga am Netzteil-Brick ein-/ausschalten (der A500 hat keinen eigenen Schalter,
## geschaltet wird am externen Netzteil — es steckt im Mehrfachverteiler).
func _on_amiga_power() -> void:
	if _setup_pending():
		return
	if not UIManager.amiga_power and not UIManager.strip_power:
		UIManager.toast(Loc.t("place.room_location.netzteil_hangt_am_mehrfachverteiler_ist_aus", "Das Netzteil hängt am Mehrfachverteiler — und der ist aus. Erst die Leiste einschalten."))
		return
	UIManager.toggle_amiga_power()
	AudioManager.relay()   # trockener mechanischer Klick des Netzteil-Kippschalters
	if not UIManager.amiga_power:
		UIManager.toast(Loc.t("place.room_location.amiga_am_netzteil_ausgeschaltet", "Amiga am Netzteil ausgeschaltet."))
	elif UIManager.monitor_power:
		UIManager.toast(Loc.t("place.room_location.amiga_lauft_kickstart_ladt_diskette_einlegen", "Amiga läuft — Kickstart lädt. Diskette einlegen."))
	else:
		UIManager.toast(Loc.t("place.room_location.amiga_eingeschaltet_monitor_ist_noch_aus", "Amiga eingeschaltet. (Der Monitor ist noch aus.)"))


## Mehrfachverteiler unterm Tisch: der rote Kippschalter ist die Wurzel der
## Stromkette — Lampe, Amiga-Netzteil und Monitor stecken in seinen vier Dosen.
func _on_strip_power() -> void:
	var devices_were_on := UIManager.monitor_power or UIManager.amiga_power
	UIManager.toggle_strip_power()
	AudioManager.relay()
	if UIManager.strip_power:
		UIManager.toast(Loc.t("place.room_location.verteiler_eingeschaltet_leiste_hat_strom_monitor", "Verteiler eingeschaltet — die Leiste hat Strom. Monitor und Netzteil haben eigene Schalter."))
	else:
		UIManager.toast(Loc.t("place.room_location.verteiler_ausgeschaltet", "Verteiler ausgeschaltet.") + (
			Loc.t("place.room_location.devices_switch_off_too", " Monitor und Amiga gehen mit aus.") if devices_were_on else ""))


func _on_sleep() -> void:
	var from_date := {
		"year": TimeManager.year,
		"month": TimeManager.month,
		"day": TimeManager.day,
		"date_label": TimeManager.date_string(),
		"slot_name": TimeManager.slot_name(),
		"clock": TimeManager.clock_string(),
		"day_counter": TimeManager.day_counter,
	}
	if not TimeManager.sleep():
		UIManager.toast(Loc.t("place.room_location.jahr_ist_bereits_zu_ende_schliesse", "Das Jahr ist bereits zu Ende. Schließe zuerst den Jahresrückblick ab."))
		return
	UIManager.open_sleep_transition(from_date)
	# Schlafen = Autosave: Alle Tageswechsel-Reaktionen sind hier bereits
	# gelaufen. Deferred, damit Uebergangsbildschirm und Signalketten stehen.
	SaveManager.save_game.call_deferred()


## Zeitschrift lesen: die Ausgaben durchblättern (Titel/Berichte/Rückseite).
## Konzentriertes Lesen bringt einmal am Tag Wissen (kostet Energie).
func _on_magazine() -> void:
	if InventoryManager.count("magazine") <= 0:
		UIManager.toast(Loc.t("place.room_location.keine_zeitschriften_da_kiosk_hat_sicher", "Keine Zeitschriften da. Der Kiosk hat sicher Nachschub (Events!)."))
		return
	# Das Heft ist ein echtes Tischobjekt: Der passende Layer-Hotspot folgt dem
	# im Raumeditor verschiebbaren Magazin. Das Papiergeräusch bestätigt das
	# Aufheben noch vor dem Öffnen der Heftansicht.
	AudioManager.play("paper", 0.03, -2.0)
	UIManager.open_magazines()
	# Einmal pro Tag lohnt sich gründliches Lesen (Wissensbonus).
	if GameManager.flags.get("mag_read_day", -1) != TimeManager.day_counter \
			and PlayerStats.use_energy(15):
		GameManager.flags["mag_read_day"] = TimeManager.day_counter
		PlayerStats.change_stat("wissen", 3)
		UIManager.toast(_magazine_line(randi() % 3))


## Stereoanlage öffnet den MOD-Player (deine gesammelten Tracks).
func _on_stereo() -> void:
	UIManager.open_music()


## Telefon an der Wand: jemanden anrufen (eigener Anschluss, Leitung teilt
## sich mit dem Modem).
func _on_telefon() -> void:
	UIManager.open_phone(false)


## Poster-/Trophäenwand öffnen (wächst mit Erfolgen + Erinnerungen).
func _on_trophywall() -> void:
	UIManager.open_trophy_wall()


## Muell-/Ordnungs-Hotspot: startet das vollwertige Aufraeumspiel. Der bisherige
## Sofortpfad bleibt RoomManager.take_out_trash() fuer Hausarbeits-/Systemeffekte,
## kann den spielbaren Zimmerhotspot aber nicht mehr umgehen.
func _on_muell() -> void:
	UIManager.open_room_tidy()


## Kompatibilitätsadapter für ältere Raumdaten/Saves. Hausarbeit besitzt kein
## separates unsichtbares Fenster mehr, sondern öffnet die gemeinsame Jobzentrale.
func _on_chores() -> void:
	UIManager.open_jobs()


## Szene-Studio: eigene Demo/Cracktro coden & releasen (Demoscene).
func _on_demo() -> void:
	# Vor 1991 ist die Projektwerkbank bewusst noch nicht Teil des eigenen
	# Systems. Aktive Kreativaufträge reparieren beim Laden Programm und
	# Arbeitsdisk; die erneute Abfrage hier fängt zusätzlich einen gerade erst
	# freigewordenen Diskettenplatz ab.
	if not ProgramLibrary.is_installed("scene_studio"):
		QuestManager.reconcile_required_resources(true)
	if not ProgramLibrary.is_installed("scene_studio"):
		UIManager.toast(Loc.t("place.room_location.noch_kein_szene_studio_installiert_tobias", "Noch kein Szene-Studio installiert. Tobias bringt die schwarze Club-Arbeitsdisk mit dem ersten gemeinsamen Projekt."))
		return
	UIManager.open_demo_maker()


## Fenster: Atmosphäre pur, einmal pro Slot ein Hauch Energie.
func _on_window() -> void:
	var slot_key := TimeManager.day_counter * 10 + TimeManager.slot
	if GameManager.flags.get("gazed_slot", -1) != slot_key:
		GameManager.flags["gazed_slot"] = slot_key
		PlayerStats.change_stat("energie", 2)
	UIManager.toast(_gaze_line(randi() % 4))


func _magazine_line(index: int) -> String:
	match index:
		0: return Loc.t("place.room_location.magazine_reviews", "Testberichte, Listings, Leserbriefe. +3 Wissen.")
		1: return Loc.t("place.room_location.magazine_tracker", "Ein Workshop über Tracker-Musik! +3 Wissen.")
	return Loc.t("place.room_location.magazine_hardware", "Die Hardware-Rubrik träumt von Festplatten. +3 Wissen.")


func _gaze_line(index: int) -> String:
	match index:
		0: return Loc.t("place.room_location.gaze_traffic", "Draußen rauscht der Verkehr. Drinnen wartet der Computer.")
		1: return Loc.t("place.room_location.gaze_trees", "Die Bäume vorm Plattenbau bewegen sich im Wind.")
		2: return Loc.t("place.room_location.gaze_same_computer", "Irgendwo in der Stadt sitzt gerade jemand vor dem gleichen Computer.")
	return Loc.t("place.room_location.gaze_keyboard", "Ein Blick nach draußen, dann wieder an die Tastatur.")


func _hotspot_label(hotspot_id: String, fallback: String) -> String:
	match hotspot_id:
		"schreibtisch": return Loc.t("place.room_location.hotspot_desk", "Schreibtisch — Computer & Diskettenbox")
		"fenster": return Loc.t("place.room_location.hotspot_window", "Fenster — nach draußen schauen")
		"desk_magazine": return Loc.t("place.room_location.hotspot_desk_magazine", "Zeitschrift — aufheben & lesen")
		"bett": return Loc.t("place.room_location.hotspot_bed", "Bett — schlafen bis zum nächsten Morgen")
		"rausgehen": return Loc.t("place.room_location.hotspot_leave", "Rausgehen (Orte)")
		"stereoanlage": return Loc.t("place.room_location.hotspot_stereo", "Stereoanlage — Musik hören")
		"monitor": return Loc.t("place.room_location.hotspot_monitor", "Monitorbild — Rechner benutzen")
		"monitor_switch": return Loc.t("place.room_location.hotspot_monitor_switch", "Monitor — ein-/ausschalten")
		"monitor_service": return Loc.t("place.room_location.hotspot_monitor_service", "Monitor-Regler — Testbild bewusst justieren")
		"netzteil": return Loc.t("place.room_location.hotspot_power_supply", "Netzteil-Brick — Amiga ein-/ausschalten")
		"verteiler": return Loc.t("place.room_location.hotspot_power_strip", "Mehrfachverteiler — Strom für die ganze Leiste")
		"telefon": return Loc.t("place.room_location.hotspot_phone", "Telefon — jemanden anrufen")
		"wandkalender": return Loc.t("place.room_location.hotspot_calendar", "Wandkalender — Termine ansehen")
		"trophywall": return Loc.t("place.room_location.hotspot_trophies", "Wand — Poster & Trophäen ansehen")
		"collection_reverse": return Loc.t("place.room_location.hotspot_collection", "Andere Zimmerseite — Sammlervitrine ansehen")
		"joystick_service": return Loc.t("place.room_location.hotspot_joystick", "Joystick — öffnen, löten & prüfen")
		"muell": return Loc.t("place.room_location.hotspot_trash", "Müll rausbringen — leere Dosen & Verpackungen")
		"demo": return Loc.t("place.room_location.hotspot_scene_studio", "Szene-Studio — Club-Intro, Demo oder Spiel bauen")
		"chores": return Loc.t("place.room_location.hotspot_jobs", "Notizbuch — Jobs & bezahlte Hausarbeit")
		"starter_carton": return Loc.t("place.room_location.hotspot_starter_box", "Kartons vom Vater — Amiga, Monitor und Netzteil auspacken")
	return fallback


# ------------------------------------------------------------- Platzhalter-Art

func _draw() -> void:
	if has_background():
		return
	var s := view_scale()
	draw_set_transform(view_offset(), 0.0, Vector2(s, s))

	# Wand & Boden (warme Abendstimmung)
	draw_rect(Rect2(0, 0, 415, 122), Palette.DARK_PURPLE.lightened(0.06))
	draw_rect(Rect2(0, 122, 415, 72), Palette.BROWN_DARK)
	draw_rect(Rect2(120, 150, 170, 40), Palette.TEAL_DARK)  # Teppich

	_draw_door()
	_draw_window()
	_draw_posters()
	_draw_shelf()
	_draw_desk_and_computer()
	_draw_bed()


func _draw_door() -> void:
	draw_rect(Rect2(8, 55, 40, 100), Palette.BROWN)
	draw_rect(Rect2(8, 55, 40, 100), Palette.BLACK, false, 1.0)
	draw_rect(Rect2(40, 100, 4, 4), Palette.SAND)  # Klinke


func _draw_window() -> void:
	# Nachthimmel + animierter Regen
	draw_rect(Rect2(248, 16, 84, 66), Palette.INDIGO)
	for i in 14:
		var x := 252.0 + fposmod(float(i) * 6.3 + anim_time * 14.0, 76.0)
		var y := 20.0 + fposmod(float(i) * 17.7 + anim_time * 60.0, 56.0)
		draw_line(Vector2(x, y), Vector2(x - 1.5, y + 5), Color(Palette.CYAN, 0.5), 1.0)
	draw_rect(Rect2(248, 16, 84, 66), Palette.BROWN_DARK, false, 3.0)
	draw_line(Vector2(290, 16), Vector2(290, 82), Palette.BROWN_DARK, 2.0)


func _draw_posters() -> void:
	# Demoscene-Poster (fiktiv) über dem Schreibtisch
	draw_rect(Rect2(80, 18, 34, 26), Palette.VIOLET)
	draw_rect(Rect2(84, 22, 26, 6), Palette.CYAN)
	draw_rect(Rect2(84, 32, 18, 3), Palette.PINK)
	draw_rect(Rect2(80, 18, 34, 26), Palette.BLACK, false, 1.0)
	draw_rect(Rect2(130, 22, 28, 22), Palette.RED_DARK)
	draw_rect(Rect2(134, 26, 20, 8), Palette.YELLOW)
	draw_rect(Rect2(130, 22, 28, 22), Palette.BLACK, false, 1.0)


func _draw_shelf() -> void:
	draw_rect(Rect2(295, 88, 100, 6), Palette.BROWN)
	# Zeitschriftenstapel
	if InventoryManager.count("magazine") > 0:
		for i in mini(4, InventoryManager.count("magazine")):
			draw_rect(Rect2(300 + i * 9, 78, 8, 10), [Palette.RED, Palette.CYAN, Palette.YELLOW, Palette.GREEN][i % 4])
	# Gekaufte Extra-Diskettenboxen wandern sichtbar ins Regal
	for i in RoomManager.count_object("diskbox"):
		var x := 348 + i * 18
		draw_rect(Rect2(x, 74, 16, 14), Color(Palette.GREY, 0.85))
		draw_rect(Rect2(x + 2, 76, 12, 2), Palette.BLUE_MID)
		draw_rect(Rect2(x, 74, 16, 14), Palette.BLACK, false, 1.0)


func _draw_desk_and_computer() -> void:
	# Schreibtisch
	draw_rect(Rect2(60, 108, 145, 8), Palette.LEATHER)
	draw_rect(Rect2(66, 116, 10, 40), Palette.BROWN)
	draw_rect(Rect2(190, 116, 10, 40), Palette.BROWN)

	# CRT-Monitor mit Flackern
	draw_rect(Rect2(84, 62, 52, 42), Palette.BEIGE.darkened(0.15))
	var flicker := 0.06 * sin(anim_time * 11.0) + 0.03 * sin(anim_time * 47.0)
	var screen_color := Palette.WB_BLUE.lightened(0.12 + flicker)
	draw_rect(Rect2(89, 66, 42, 30), screen_color)
	draw_rect(Rect2(92, 70, randi_range(18, 30), 2), Palette.WHITE_SOFT)  # "Textzeile"
	draw_rect(Rect2(92, 75, 24, 2), Color(Palette.WHITE_SOFT, 0.7))
	draw_rect(Rect2(84, 62, 52, 42), Palette.BLACK, false, 1.0)

	# Heimcomputer-Tastaturkeil (Amiga-inspiriert, ohne Logo)
	draw_rect(Rect2(76, 100, 76, 9), Palette.BEIGE)
	draw_rect(Rect2(80, 102, 62, 4), Palette.GREY_LIGHT)
	draw_rect(Rect2(76, 100, 76, 9), Palette.BLACK, false, 1.0)

	# Diskettenstapel + Joystick
	draw_rect(Rect2(160, 100, 12, 3), Palette.BLUE_MID)
	draw_rect(Rect2(161, 97, 12, 3), Palette.RED_DARK)
	draw_rect(Rect2(159, 94, 12, 3), Palette.GREY)
	draw_rect(Rect2(178, 96, 10, 12), Palette.DARK_PURPLE)
	draw_circle(Vector2(183, 94), 3.0, Palette.RED)

	# Externes Laufwerk (sichtbares Hardware-Upgrade!) mit Blink-LED
	if PlayerStats.has_hardware("external_drive"):
		draw_rect(Rect2(140, 88, 22, 10), Palette.BEIGE)
		draw_rect(Rect2(140, 88, 22, 10), Palette.BLACK, false, 1.0)
		var led := Palette.GREEN if fmod(anim_time, 1.0) < 0.5 else Palette.GREEN_DARK
		draw_rect(Rect2(158, 94, 2, 2), led)

	# Schreibtischlampe (warmer Lichtkegel)
	draw_line(Vector2(70, 108), Vector2(64, 84), Palette.GREY_DARK, 2.0)
	draw_circle(Vector2(66, 82), 4.0, Palette.GREY_DARK)
	draw_line(Vector2(66, 86), Vector2(84, 104), Color(Palette.SAND, 0.25), 8.0)


func _draw_bed() -> void:
	draw_rect(Rect2(330, 130, 84, 46), Palette.INDIGO.lightened(0.1))
	draw_rect(Rect2(330, 126, 20, 12), Palette.WHITE_SOFT)  # Kissen
	draw_rect(Rect2(330, 130, 84, 46), Palette.BLACK, false, 1.0)
	draw_rect(Rect2(330, 176, 84, 8), Palette.BROWN)
