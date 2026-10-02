extends LocationBase
## Pommes-Palast: begehbare 1990er-Imbiss-Zeitkapsel. Das Sortiment teilt den
## HistoryShopCatalog mit dem Kiosk, besitzt aber seine eigene Kaufentscheidung
## „hier essen / mitnehmen“ und eine historische Sprachkontext-Karte.

const AnalogClock25D := preload("res://scripts/gfx/location_analog_clock_25d.gd")


func background_base() -> String:
	return "LOCATION_IMBISS_MASTER"


func uses_generic_npcs() -> bool:
	return false


func _build() -> void:
	AudioManager.play("shop_bell")
	if not has_background():
		add_hotspot(Rect2(30, 40, 180, 100), Loc.t("place.imbiss_location.theke_bestellen", "Theke — bestellen"), _open_menu)
		add_hotspot(Rect2(235, 40, 100, 100), Loc.t("place.imbiss_location.speisekarte", "Speisekarte"), _menu_history)
		add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.imbiss_location.raus_zu_den_orten", "Raus (zu den Orten)"), UIManager.open_map)
		return
	cover_mode = true
	virtual_size = Vector2(1672, 941)
	add_hotspot(Rect2(355, 420, 1090, 355), Loc.t("place.imbiss_location.theke_bestellen_hier_essen_oder_mitnehmen", "Theke — bestellen: hier essen oder mitnehmen"), _open_menu)
	add_hotspot(Rect2(610, 80, 820, 210), Loc.t("place.imbiss_location.speisekarte_d_preise_erinnerungen", "Speisekarte %d — Preise und Erinnerungen") % TimeManager.year, _menu_history)
	add_hotspot(Rect2(355, 290, 610, 220), Loc.t("place.imbiss_location.fritteuse_kueche_frisch_gemacht", "Fritteuse und Kueche — frisch gemacht"), _kitchen)
	add_hotspot(Rect2(975, 300, 480, 230), Loc.t("place.imbiss_location.warmhalteauslage_pommes_papierschalen", "Warmhalteauslage — Pommes und Papierschalen"), _display)
	add_hotspot(Rect2(1380, 340, 180, 240), Loc.t("place.imbiss_location.zigeuner_saucen_angebot_direkt_bestellen", "Paprikasaucen-Angebot — direkt bestellen"), _sauce_offer)
	add_hotspot(Rect2(0, 735, 420, 206), Loc.t("place.imbiss_location.stehtisch_links", "Stehtisch links"), _table)
	add_hotspot(Rect2(1310, 735, 362, 206), Loc.t("place.imbiss_location.stehtisch_rechts", "Stehtisch rechts"), _table)
	add_hotspot(Rect2(690, 810, 310, 131), Loc.t("place.imbiss_location.ausgang_zu_den_orten", "Ausgang (zu den Orten)"), UIManager.open_map)
	# Reales Produktasset, nicht in den Hintergrund eingebrannt: bleibt separat
	# skalierbar und folgt derselben 2,5D-Projektion wie Hotspots/Nahkante.
	add_depth_prop("res://assets/backgrounds/layers/IMBISS_ZIGEUNERSAUCE_1990_V01.png",
		Rect2(1450, 362, 64, 176), "HistoricalPaprikaSauce")
	# Der V02-Master besitzt bewusst nur Zifferblatt/Pivot. Die echten Zeiger
	# kommen aus TimeManager und haengen als Wandebene in derselben 2,5D-Stage.
	var clock := AnalogClock25D.new()
	clock.name = "ImbissWallClock"
	var clock_parent: Control = _stage_25d if _stage_25d != null else self
	clock_parent.add_child(clock)
	# Sichtbarer Cover-Crop-Anker (nicht Rohbild-Pixel): exakt der schwarze
	# Pivot des Zifferblatts in der HUD-Mitte bei allen 16:9-Aufloesungen.
	clock.setup(self, _stage_25d, Vector2(465, 110), 38.0)


func _open_menu() -> void:
	UIManager.toggle_window("win_history_imbiss", func() -> Control:
		var window := HistoryShopWindow.new()
		window.shop_id = "imbiss"
		return window)


func _menu_history() -> void:
	UIManager.open_info("POMMES-PALAST · SPEISEKARTE %d" % TimeManager.year,
		"Papierschale, Zweizackgabel, Currypulver und Pfandglas: Hier wird nicht nur Energie aufgefuellt. "
		+ "Jede Bestellung ist als kleines Alltagsobjekt der Dekade gebaut.\n\n"
		+ "An der Theke entscheidest du bei jedem Gericht: HIER ESSEN oder MITNEHMEN.")


func _sauce_offer() -> void:
	UIManager.toggle_window("win_history_imbiss", func() -> Control:
		var window := HistoryShopWindow.new()
		window.shop_id = "imbiss"
		window.initial_item_id = "pommes_paprikasauce"
		return window)


func _kitchen() -> void:
	UIManager.toast(Loc.t("place.imbiss_location.fritteuse_edelstahl_klacken_papierschalen_kein_display", "Fritteuse, Edelstahl und das Klacken der Papierschalen — kein Display, kein Lieferdienst, keine App."))


func _display() -> void:
	UIManager.toast(Loc.t("place.imbiss_location.frische_pommes_in_warmhalteauslage_bestellt_wird", "Frische Pommes in der Warmhalteauslage. Bestellt wird an der Theke."))


func _table() -> void:
	UIManager.toast(Loc.t("place.imbiss_location.hoher_resopal_stehtisch_hier_essen_bedeutet", "Ein hoher Resopal-Stehtisch. Hier essen bedeutet: keine Verpackung im Inventar, kein Muell im Zimmer."))
