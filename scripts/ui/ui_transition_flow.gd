extends RefCounted
## Vollbild-Jahres-/Tageswechsel und die datengetriebene Morgenkarte.


static func open_year(owner: Node, screen_script: Script, from_year: int, to_year: int,
		review: Dictionary) -> Control:
	var layer: Control = owner.get("window_layer")
	if layer == null:
		return null
	var existing := layer.get_node_or_null("win_year_transition")
	if existing != null:
		return existing as Control
	var screen: Control = screen_script.new()
	screen.name = "win_year_transition"
	screen.set_meta("no_center", true)
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.call("configure", from_year, to_year, review)
	layer.add_child(screen)
	return screen


static func open_sleep(owner: Node, screen_script: Script, from_date: Dictionary) -> Control:
	var layer: Control = owner.get("window_layer")
	if layer == null:
		return null
	var existing := layer.get_node_or_null("win_sleep_transition")
	if existing != null:
		return existing as Control
	var progress: Dictionary = TimeManager.campaign_progress()
	var elapsed_days := maxi(1, TimeManager.day_counter - int(from_date.get("day_counter", TimeManager.day_counter - 1)))
	var duty: String = TimeManager.morning_duty()
	var holiday: String = TimeManager.holiday_name()
	var year_finale := TimeManager.is_year_end_pending()
	var notices: Array[String] = []
	var notice_specs: Array[Dictionary] = []
	if year_finale:
		# Der Sprung vom letzten kuratierten Ferientag auf Silvester ist eine
		# bewusste Saisonmontage, kein gewoehnlicher Schlaf. Wetter und
		# "Morgenplan" wuerden hier einen Kalenderfehler suggerieren.
		var summer_year := int(from_date.get("year", TimeManager.year))
		notices.append("SOMMERKAPITEL '%02d ABGESCHLOSSEN" % (summer_year % 100))
		notices.append("HERBST UND WINTER · ALS MONTAGE VERGANGEN")
		notice_specs.append({"kind": "summer_chapter", "year": summer_year})
		notice_specs.append({"kind": "season_montage"})
		if not holiday.is_empty():
			notices.append(holiday.to_upper())
			notice_specs.append({"kind": "holiday", "holiday": _holiday_id(holiday)})
	else:
		notices = ["WETTER · %s" % WeatherManager.label().to_upper(),
			"MORGENPLAN · %s" % (duty.to_upper() if not duty.is_empty() else "FREI")]
		notice_specs = [
			{"kind": "weather", "weather": WeatherManager.state()},
			{"kind": "duty", "duty": _duty_id(duty)},
		]
		if not holiday.is_empty():
			notices.append(holiday.to_upper())
			notice_specs.append({"kind": "holiday", "holiday": _holiday_id(holiday)})
		if elapsed_days > 1:
			notices.append("LIEFERUNGEN · TERMINE · COOLDOWNS AKTUALISIERT")
			notice_specs.append({"kind": "deliveries"})
		notices.append_array(morning_reminders())
		notice_specs.append_array(morning_reminder_specs())
	var summary := {
		"from_date": from_date.duplicate(true),
		"to_date_label": _localized_date(TimeManager.day, TimeManager.month, TimeManager.year),
		"to_day": TimeManager.day,
		"to_month": TimeManager.month,
		"from_year": int(from_date.get("year", TimeManager.year)),
		"to_year": TimeManager.year,
		"weekday": TimeManager.localized_weekday_name(),
		"weekday_index": TimeManager.weekday(),
		"elapsed_days": elapsed_days,
		"notices": notices,
		"notice_specs": notice_specs,
		"campaign_day": int(progress.get("day", 0)),
		"campaign_total": int(progress.get("total_days", 0)),
		"year_finale": year_finale,
		"feature": morning_feature(),
	}
	var screen: Control = screen_script.new()
	screen.name = "win_sleep_transition"
	screen.set_meta("no_center", true)
	screen.z_index = 500
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.call("configure", summary)
	layer.add_child(screen)
	# Nach dem Einhaengen sofort die Parent-Rect uebernehmen; vorbereitete
	# Eventfenster duerfen den modal sichtbaren Tageswechsel nicht ueberholen.
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return screen


static func _localized_date(day: int, month: int, year: int) -> String:
	var month_name := TimeManager.localized_month_name(month)
	var locale := TranslationServer.get_locale().split("_")[0].to_lower()
	if locale == "en":
		return "%s %d, %d" % [month_name, day, year]
	return "%d. %s %d" % [day, month_name, year]


static func morning_feature() -> Dictionary:
	if PlayerIdentity.is_birthday_today():
		return {"kind": "birthday", "title_key": "ui.sleep_transition.feature.birthday_title",
			"title": "HEUTE IST DEIN GEBURTSTAG",
			"subtitle_key": "ui.sleep_transition.feature.birthday_subtitle",
			"subtitle": "ANRUFE · KUCHEN · EIN TAG, DER DIR GEHOERT"}
	var today := "%02d-%02d" % [TimeManager.month, TimeManager.day]
	for event: Dictionary in EventManager.events:
		if str(event.get("on_date", "")) == today and TimelineManager.is_available(event):
			return {"kind": "holiday", "title": str(event.get("title", "BESONDERER TAG")).to_upper(),
				"subtitle": str(event.get("memory", event.get("text", "HEUTE IST ETWAS BESONDERES"))).to_upper().left(72)}
	if bool(GameManager.flags.get("ccc_fest_today", false)):
		return {"kind": "club", "title_key": "ui.sleep_transition.feature.ccc_title",
			"title": "HEUTE IST CCC-FEST", "subtitle_key": "ui.sleep_transition.feature.ccc_subtitle",
			"subtitle": "DEMOS · MUSIK · WETTBEWERB · FREUNDE"}
	if TimeManager.weekday() == 5:
		return {"kind": "flea", "title_key": "ui.sleep_transition.feature.flea_title",
			"title": "HEUTE IST FLOHMARKT", "subtitle_key": "ui.sleep_transition.feature.flea_subtitle",
			"subtitle": "SAMSTAG · MORGENS BIS NACHMITTAGS · KRAUSES FUNDSTUECKE"}
	if TimeManager.weekday() == 4 and bool(GameManager.flags.get("club_member", false)):
		return {"kind": "club", "title_key": "ui.sleep_transition.feature.club_title",
			"title": "COMPUTERCLUB-ABEND", "subtitle_key": "ui.sleep_transition.feature.club_subtitle",
			"subtitle": "CCC-FREITAG · MODS · PD-DISKETTEN · SZENE-TREFFEN"}
	return {}


static func morning_reminder_specs() -> Array[Dictionary]:
	var reminders: Array[Dictionary] = []
	var weekday := TimeManager.weekday()
	if weekday == 4:
		var access: Dictionary = TownManager.story_access("computer_club")
		if bool(access.get("ok", false)) or bool(GameManager.flags.get("club_member", false)):
			reminders.append({"kind": "club_today"})
	if weekday == 5:
		reminders.append({"kind": "flea_today"})
	if not OrderManager.arrived.is_empty():
		var first_order: Dictionary = OrderManager.arrived[0]
		reminders.append({"kind": "order", "name": str(first_order.get("name", "BESTELLUNG")),
			"additional": maxi(0, OrderManager.arrived.size() - 1)})
	var phone_count := PhoneManager.unheard_count() + PhoneManager.pending_callbacks().size()
	if phone_count > 0:
		reminders.append({"kind": "phone", "count": phone_count})
	var active_quests: Array = QuestManager.active_quests()
	if not active_quests.is_empty():
		reminders.append({"kind": "quest", "count": active_quests.size(),
			"quest_id": str((active_quests[0] as Dictionary).get("id", ""))})
	elif TaskManager.open_count() > 0:
		reminders.append({"kind": "tasks", "count": TaskManager.open_count()})
	return reminders.slice(0, 3)


static func _duty_id(duty: String) -> String:
	match duty:
		"Schule": return "school"
		"Betrieb & Berufsschule": return "vocational"
		"Arbeit": return "work"
	return "free"


static func _holiday_id(holiday: String) -> String:
	match holiday:
		"Weihnachtsferien": return "christmas"
		"Osterferien": return "easter"
		"Pfingstferien": return "whitsun"
		"Sommerferien": return "summer"
		"Herbstferien": return "autumn"
	return ""


static func morning_reminders() -> Array[String]:
	var reminders: Array[String] = []
	var weekday := TimeManager.weekday()
	if weekday == 4:
		var access: Dictionary = TownManager.story_access("computer_club")
		if bool(access.get("ok", false)) or bool(GameManager.flags.get("club_member", false)):
			reminders.append("HEUTE MÖGLICH · COMPUTERCLUB AM ABEND")
	if weekday == 5:
		reminders.append("HEUTE MÖGLICH · FLOHMARKT AM VORMITTAG")
	if not OrderManager.arrived.is_empty():
		var first_order: Dictionary = OrderManager.arrived[0]
		reminders.append("ABHOLBEREIT BEI GRUBER · %s%s" % [
			str(first_order.get("name", "BESTELLUNG")).to_upper(),
			" · +%d WEITERE" % (OrderManager.arrived.size() - 1) if OrderManager.arrived.size() > 1 else ""])
	var phone_count := PhoneManager.unheard_count() + PhoneManager.pending_callbacks().size()
	if phone_count > 0:
		reminders.append("TELEFON · %d NEUE NACHRICHT%s / RÜCKRUF%s" % [phone_count,
			"EN" if phone_count != 1 else "", "E" if phone_count != 1 else ""])
	var active_quests: Array = QuestManager.active_quests()
	if not active_quests.is_empty():
		var title := QuestManager.localized_title(str((active_quests[0] as Dictionary).get("id", ""))).to_upper()
		reminders.append(Loc.t("ui.transition.active_quests", "AUFTRÄGE · %d OFFEN · %s") \
			% [active_quests.size(), title])
	elif TaskManager.open_count() > 0:
		reminders.append("NOTIZBOARD · %d OFFENE AUFGABE%s" % [TaskManager.open_count(),
			"N" if TaskManager.open_count() != 1 else ""])
	return reminders.slice(0, 3)
