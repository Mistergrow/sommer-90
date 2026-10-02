extends LocationBase
## Alex' Zimmer (LOCATION_FRIEND_ROOM_ALEX) — Sammlerzimmer von Schulfreund Alex im
## Wohngebiet. Alex ist der ENTDECKER/SAMMLER: Regale voller (halb sortierter)
## Hardware, Glasvitrine mit den guten Stücken, überall Mystery-Kartons vom
## Flohmarkt, Kameras/Radios, Kisten unbeschrifteter Disketten. Zweck: Sammlungen
## inspizieren, Hardware identifizieren, Mystery-Boxen auspacken, Schätze finden.
##
## ⭐ Herzstück ist das Mystery-Box-System (wöchentlich neue Kartons via
## FleaMarketManager, zusammen auspacken/identifizieren/testen). Hier als klarer
## „kommt"-Haken angelegt — nichts erfunden. Alex mal da/mal weg (Zeitplan),
## Raum bleibt begehbar (WorksEmpty). Hotspots aufs 1672x941-Artwork abgestimmt.


func background_base() -> String:
	return "LOCATION_FRIEND_ROOM_ALEX"


func _build() -> void:
	if not has_background():
		add_hotspot(Rect2(30, 40, 130, 100), Loc.t("place.alex_home_location.mystery_kartons_auspacken", "Mystery-Kartons — auspacken"), _mystery)
		add_hotspot(Rect2(200, 40, 90, 90), Loc.t("place.alex_home_location.vitrine_guten_stucke", "Vitrine — die guten Stücke"), _cabinet)
		add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.alex_home_location.tur_orte", "Tür (Orte)"), UIManager.open_map)
		return
	cover_mode = true
	virtual_size = Vector2(1672, 941)
	if not _alex_home():
		add_away_notice("Alex ist nicht da — komm später wieder.\n(Die Sammlung kannst du trotzdem ansehen.)")
	# Positionen aufs Artwork abgestimmt (große Flächen zuerst, wichtige/kleine später).
	add_hotspot(Rect2(1210, 600, 462, 341), Loc.t("place.alex_home_location.bett", "Bett"), _bed)
	add_hotspot(Rect2(1340, 10, 332, 320), Loc.t("place.alex_home_location.fenster_blick_in_siedlung", "Fenster — Blick in die Siedlung"), _window)
	add_hotspot(Rect2(150, 10, 440, 250), Loc.t("place.alex_home_location.hardware_regal_alte_rechner", "Hardware-Regal — alte Rechner"), _hardware)
	add_hotspot(Rect2(600, 15, 400, 555), Loc.t("place.alex_home_location.sammel_regal_halb_sortiert", "Sammel-Regal — halb sortiert"), _collection)
	add_hotspot(Rect2(150, 270, 430, 330), Loc.t("place.alex_home_location.computertisch_alex_amiga", "Computertisch — Alex' Amiga"), _desk)
	add_hotspot(Rect2(1010, 80, 195, 410), Loc.t("place.alex_home_location.glasvitrine_guten_stucke", "Glasvitrine — die guten Stücke"), _cabinet)
	add_hotspot(Rect2(1475, 330, 197, 390), Loc.t("place.alex_home_location.regal_magazine_kataloge", "Regal — Magazine & Kataloge"), _magazines)
	add_hotspot(Rect2(1250, 285, 210, 95), Loc.t("place.alex_home_location.fensterbank_kameras_radios", "Fensterbank — Kameras & Radios"), _camera)
	add_hotspot(Rect2(150, 610, 320, 331), Loc.t("place.alex_home_location.disketten_archiv_unbeschriftet", "Disketten-Archiv — unbeschriftet"), _floppy)
	add_hotspot(Rect2(470, 610, 180, 200), Loc.t("place.alex_home_location.schublade_kleinteile", "Schublade — Kleinteile"), _drawer)
	add_hotspot(Rect2(1205, 360, 150, 240), Loc.t("place.alex_home_location.stapel_kram_verstecktes", "Stapel — Kram & Verstecktes"), _closet)
	# Mystery-Kartons (Herzstück) + Ausgang zuletzt → gewinnen den Treffertest.
	add_hotspot(Rect2(630, 560, 560, 381), Loc.t("place.alex_home_location.mystery_kartons_mit_alex_auspacken", "Mystery-Kartons — mit Alex auspacken"), _mystery)
	add_hotspot(Rect2(0, 120, 150, 720), Loc.t("place.alex_home_location.tur_raus_orte", "Tür — raus (Orte)"), UIManager.open_map)


# ------------------------------------------------------------- Anwesenheit
func _alex_home() -> bool:
	var env := OS.get_environment("DSS_AWAY")
	if env == "1":
		return false
	if env == "0":
		return true
	return NPCManager.is_here_now("npc_alex", "alex_home")


# ------------------------------------------------------------- Aktionen
## Herzstück: die Mystery-Kartons. Mit Alex zusammen auspacken/identifizieren/testen.
func _mystery() -> void:
	if not _alex_home():
		UIManager.toast(Loc.t("place.alex_home_location.stapel_ungeoffneter_flohmarkt_kartons_ohne_alex", "Stapel ungeöffneter Flohmarkt-Kartons. Ohne Alex wühlst du da besser nicht drin. (Mystery-Boxen kommen.)"))
		return
	NPCManager.change_trust("npc_alex", 1)
	UIManager.open_info("ALEX — MYSTERY-KARTONS",
		"»Neue Kiste vom Flohmarkt! Weiß selbst nicht, was drin ist — machen wir zusammen auf?«\n\n"
		+ "Auspacken · Hardware identifizieren · säubern · testen · behalten oder tauschen. "
		+ "Jede Woche schleppt Alex neue Kartons vom Flohmarkt an; nicht jeder Fund ist sein Geld wert.")


func _desk() -> void:
	UIManager.toast(Loc.t("place.alex_home_location.alex_amiga_halb_unter_fundstucken_begraben", "Alex' Amiga, halb unter Fundstücken begraben — hier katalogisiert er seine Schätze."))


func _collection() -> void:
	UIManager.toast(Loc.t("place.alex_home_location.meterweise_regal_voller_hardware_alles_nur", "Meterweise Regal voller Hardware, alles nur halb sortiert. »Irgendwo ist hier ein Schatz.«"))


func _hardware() -> void:
	UIManager.toast(Loc.t("place.alex_home_location.alte_rechner_erweiterungskarten_unbekannte_kastchen_alex", "Alte Rechner, Erweiterungskarten, unbekannte Kästchen — Alex rät bei der Hälfte selbst und nennt den Rest vorsichtshalber selten."))


func _cabinet() -> void:
	UIManager.toast(Loc.t("place.alex_home_location.hinter_glas_guten_stucke_seltene_hardware", "Hinter Glas: die guten Stücke. Seltene Hardware, Prototypen, ein paar echte Raritäten."))


func _floppy() -> void:
	UIManager.toast(Loc.t("place.alex_home_location.kisten_voller_unbeschrifteter_disketten_keiner_weiss", "Kisten voller unbeschrifteter Disketten. »Keiner weiß, was drauf ist — genau das ist das Spannende.«"))


func _magazines() -> void:
	UIManager.toast(Loc.t("place.alex_home_location.alte_computer_magazine_versandkataloge_alex_nachschlagewerk", "Alte Computer-Magazine und Versandkataloge — Alex' Nachschlagewerk zum Bestimmen von Kram."))


func _camera() -> void:
	UIManager.toast(Loc.t("place.alex_home_location.kameras_transistorradios_fernglas_alex_sammelt_nicht", "Kameras, Transistorradios, ein Fernglas — Alex sammelt nicht nur Computer. Alles mit Technik zählt."))


func _drawer() -> void:
	UIManager.toast(Loc.t("place.alex_home_location.schublade_voller_kleinteile_chips_stecker_namenlose", "Schublade voller Kleinteile: Chips, Stecker, namenlose Platinen. Sortiersystem: keins."))


func _closet() -> void:
	UIManager.toast(Loc.t("place.alex_home_location.stapel_hinter_dem_noch_mehr_stapel", "Ein Stapel, hinter dem noch mehr Stapel steht. Alex blockt den Weg: »Nicht anfassen, sonst kippt alles.«"))


func _bed() -> void:
	UIManager.toast(Loc.t("place.alex_home_location.bett_dient_halb_als_ablage_sogar", "Das Bett dient halb als Ablage — sogar hier stapeln sich Fundstücke."))


func _window() -> void:
	var w := "Draußen scheint die Sonne." if WeatherManager.state() == "clear" else "Draußen ist's grau."
	UIManager.toast(Loc.t("place.alex_home_location.fenster_mit_blick_uber_siedlung_s", "Fenster mit Blick über die Siedlung. %s") % w)
