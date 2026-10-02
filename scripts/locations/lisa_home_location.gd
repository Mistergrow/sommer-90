extends LocationBase
## Lisas Zimmer (LOCATION_FRIEND_ROOM_LISA) — Kreativ-Studio von Schulfreundin Lisa
## im Wohngebiet. Bunt, gemütlich, musikalisch: Amiga mit Deluxe Paint, großer
## Zeichentisch, Pixel-Art an allen Wänden, MIDI-Keyboard, Stereo-Ecke, Farben &
## Pinsel. Lisa ist die KREATIVE / CONTENT-CREATORIN des Freundeskreises.
##
## Rollen im Freundeskreis: Sven=Hardware · Mike=Spiele · Alex=Sammeln ·
## Daniel=Software · Lisa=Präsentation & Design. ⭐ Große Idee: Lisa macht nicht
## DICH künstlerischer, sondern deine PROJEKTE schöner — Cover, Disk-Labels, Poster,
## Logos, Menüs werden mit steigender Freundschaft hochwertiger (`design_quality`).
## Hier als klarer „kommt"-Haken angelegt; nichts erfunden. Raum bleibt begehbar.
## Hotspots aufs 1672x941-Artwork abgestimmt.


func background_base() -> String:
	return "LOCATION_FRIEND_ROOM_LISA"


func _build() -> void:
	if not has_background():
		add_hotspot(Rect2(30, 40, 130, 100), Loc.t("place.lisa_home_location.amiga_deluxe_paint", "Amiga — Deluxe Paint"), _amiga)
		add_hotspot(Rect2(200, 40, 90, 90), Loc.t("place.lisa_home_location.zeichentisch", "Zeichentisch"), _drawing)
		add_hotspot(Rect2(360, 60, 45, 110), Loc.t("place.lisa_home_location.tur_orte", "Tür (Orte)"), UIManager.open_map)
		return
	cover_mode = true
	virtual_size = Vector2(1672, 941)
	if not _lisa_home():
		add_away_notice("Lisa ist nicht da — komm später wieder.\n(Ihre Kunst kannst du trotzdem ansehen.)")
	# Positionen aufs Artwork abgestimmt (große Flächen zuerst, wichtige/kleine später).
	add_hotspot(Rect2(1150, 480, 420, 320), Loc.t("place.lisa_home_location.bett", "Bett"), _bed)
	add_hotspot(Rect2(800, 10, 240, 330), Loc.t("place.lisa_home_location.fenster_blick_in_siedlung", "Fenster — Blick in die Siedlung"), _window)
	add_hotspot(Rect2(460, 0, 290, 520), Loc.t("place.lisa_home_location.regal_skizzenbucher_kunstbucher", "Regal — Skizzenbücher & Kunstbücher"), _sketch_shelf)
	add_hotspot(Rect2(1440, 0, 232, 340), Loc.t("place.lisa_home_location.pixel_art_wand_lisas_werke", "Pixel-Art-Wand — Lisas Werke"), _pixel_wall)
	add_hotspot(Rect2(1180, 255, 260, 210), Loc.t("place.lisa_home_location.stereo_ecke_anlage_kopfhorer", "Stereo-Ecke — Anlage & Kopfhörer"), _stereo)
	add_hotspot(Rect2(660, 300, 380, 250), Loc.t("place.lisa_home_location.zeichentisch_skizzen_storyboards", "Zeichentisch — Skizzen & Storyboards"), _drawing)
	add_hotspot(Rect2(700, 470, 210, 185), Loc.t("place.lisa_home_location.schubladen_schrank_mappen_vorlagen", "Schubladen-Schrank — Mappen & Vorlagen"), _art_cabinet)
	add_hotspot(Rect2(1037, 430, 165, 185), Loc.t("place.lisa_home_location.kassetten_platten_regal", "Kassetten- & Platten-Regal"), _cassette)
	add_hotspot(Rect2(1180, 360, 170, 80), Loc.t("place.lisa_home_location.midi_keyboard_tracker_musik", "MIDI-Keyboard — Tracker-Musik"), _midi)
	add_hotspot(Rect2(70, 90, 190, 200), Loc.t("place.lisa_home_location.inspirations_wand", "Inspirations-Wand"), _inspiration)
	add_hotspot(Rect2(60, 690, 320, 251), Loc.t("place.lisa_home_location.kisten_disketten_magazine", "Kisten — Disketten & Magazine"), _magazines)
	add_hotspot(Rect2(985, 690, 615, 251), Loc.t("place.lisa_home_location.farben_pinsel_malzeug", "Farben & Pinsel — Malzeug"), _paint)
	# Amiga (Herzstück: mit Lisa gestalten) + Ausgang zuletzt → gewinnen den Treffertest.
	add_hotspot(Rect2(90, 280, 430, 350), Loc.t("place.lisa_home_location.amiga_deluxe_paint_mit_lisa_gestalten", "Amiga — Deluxe Paint (mit Lisa gestalten)"), _amiga)
	add_hotspot(Rect2(0, 110, 130, 720), Loc.t("place.lisa_home_location.tur_raus_orte", "Tür — raus (Orte)"), UIManager.open_map)


# ------------------------------------------------------------- Anwesenheit
func _lisa_home() -> bool:
	var env := OS.get_environment("DSS_AWAY")
	if env == "1":
		return false
	if env == "0":
		return true
	return NPCManager.is_here_now("npc_lisa", "lisa_home")


# ------------------------------------------------------------- Aktionen
## Herzstück: mit Lisa gestalten. Sie macht deine PROJEKTE schöner (Cover, Labels,
## Poster) — je enger die Freundschaft, desto hochwertiger (`design_quality`).
func _amiga() -> void:
	if not _lisa_home():
		UIManager.toast(Loc.t("place.lisa_home_location.lisas_amiga_mit_deluxe_paint_halbfertiges", "Lisas Amiga mit Deluxe Paint — ein halbfertiges Bild leuchtet am Monitor. Ohne Lisa fehlt dir ihr Auge."))
		return
	# Das beschriftete Herzstueck ist kein Infotext mehr, sondern der zweite echte
	# Zugang zum selben Creator-Programm. Die erste betreute Sitzung verbessert
	# Beziehung und Designwissen genau einmal; wiederholtes Oeffnen ist kein
	# endloser Vertrauens-/Qualitaets-Exploit.
	if not bool(GameManager.flags.get("lisa_paint_mentoring", false)):
		GameManager.flags["lisa_paint_mentoring"] = true
		GameManager.flags["design_quality"] = int(GameManager.flags.get("design_quality", 0)) + 1
		NPCManager.change_trust("npc_lisa", 1)
		UIManager.toast(Loc.t("place.lisa_home_location.lisa_setz_dich_erst_silhouette_kontrast", "Lisa: »Setz dich. Erst Silhouette und Kontrast, dann Details.«"))
	UIManager.open_paint()


func _drawing() -> void:
	UIManager.toast(Loc.t("place.lisa_home_location.grosser_zeichentisch_voller_skizzen_storyboards_hier", "Ein großer Zeichentisch voller Skizzen und Storyboards — hier entstehen Lisas Ideen auf Papier, bevor sie zu Pixeln werden."))


func _sketch_shelf() -> void:
	UIManager.toast(Loc.t("place.lisa_home_location.regal_voller_skizzenbucher_kunstbande_farbenlehre_anatomie", "Regal voller Skizzenbücher und Kunstbände — Farbenlehre, Anatomie, Design. Lisas Handbibliothek."))


func _pixel_wall() -> void:
	UIManager.toast(Loc.t("place.lisa_home_location.ganze_wand_voller_pixel_art_sonnenuntergange", "Eine ganze Wand voller Pixel-Art: Sonnenuntergänge, Skylines, Sprites. Lisas Portfolio zum Anschauen."))


func _stereo() -> void:
	UIManager.open_music()


func _midi() -> void:
	UIManager.toast(Loc.t("place.lisa_home_location.midi_keyboard_am_amiga_lisa_grafik", "Ein MIDI-Keyboard am Amiga. Lisa: »Grafik UND Musik — Rhythmus ist bei beidem die halbe Komposition.«"))


func _cassette() -> void:
	UIManager.toast(Loc.t("place.lisa_home_location.kassetten_platten_nach_stimmung_sortiert_musik", "Kassetten und Platten, nach Stimmung sortiert. Musik läuft hier immer beim Zeichnen."))


func _art_cabinet() -> void:
	UIManager.toast(Loc.t("place.lisa_home_location.schubladen_voller_mappen_fertige_cover_label", "Schubladen voller Mappen: fertige Cover, Label-Vorlagen, Logo-Entwürfe. Lisas Archiv."))


func _inspiration() -> void:
	UIManager.toast(Loc.t("place.lisa_home_location.inspirations_wand_ausgeschnittene_bilder_farbmuster_lieblings", "Inspirations-Wand: ausgeschnittene Bilder, Farbmuster, Lieblings-Screenshots. Von hier kommen ihre Ideen."))


func _paint() -> void:
	UIManager.toast(Loc.t("place.lisa_home_location.echte_farben_pinsel_marker_lisa_malt", "Echte Farben, Pinsel, Marker — Lisa malt auch analog. Manches Cover entsteht erst auf Papier."))


func _magazines() -> void:
	UIManager.toast(Loc.t("place.lisa_home_location.kisten_mit_kunst_musikmagazinen_plus_disketten", "Kisten mit Kunst- und Musikmagazinen plus Disketten voller Deluxe-Paint-Bilder."))


func _bed() -> void:
	UIManager.toast(Loc.t("place.lisa_home_location.buntes_gemustertes_bettzeug_auf_decke_liegt", "Buntes, gemustertes Bettzeug — auf der Decke liegt ein Skizzenblock. Selbst hier wird gezeichnet."))


func _window() -> void:
	var w := "Draußen scheint die Sonne." if WeatherManager.state() == "clear" else "Draußen ist's grau."
	UIManager.toast(Loc.t("place.lisa_home_location.fenster_mit_blick_uber_siedlung_s", "Fenster mit Blick über die Siedlung. %s") % w)
