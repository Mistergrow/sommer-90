extends LocationBase
## Stefans Zimmer (LOCATION_FRIEND_ROOM_MASTER_V01) — Jugendzimmer mit Amiga,
## Regal voller Originale, Postern und Diskettenboxen. Hier laufen Stefans
## Spielewünsche (fiktive Tauschkultur unter Freunden).
##
## Das Zimmer dient laut Asset-DB als Vorlage für spätere Freunde. Umgesetzt
## ist bereits das VisitSystem-Prinzip: Der Freund ist nicht immer daheim —
## manchmal muss man später wiederkommen. Die Quest wird davon nie blockiert.

const StefanGames := preload("res://scripts/games/stefan_game_catalog.gd")
const StefanMoments := preload("res://scripts/data/stefan_moment_catalog.gd")


## Eigenes NPC-Handling → generische Ansprech-Leiste aus.
func uses_generic_npcs() -> bool:
	return false


func background_base() -> String:
	return "LOCATION_FRIEND_ROOM_MASTER"


func _build() -> void:
	var stefan_home := _stefan_home()
	if has_background():
		cover_mode = true
		virtual_size = Vector2(1672, 941)
		if not stefan_home:
			_add_away_overlay()
		_build_hotspots()
	else:
		_build_placeholder_hotspots()
	# friend_location besitzt eigene Questdialoge und schaltet deshalb die
	# generische NPC-Leiste ab. Stefan muss hier trotzdem wie alle anderen
	# Freunde sichtbar im Raum stehen; die alte unsichtbare Groß-Hitbox bleibt
	# nur als komfortable zweite Klickfläche erhalten.
	if stefan_home:
		var actor_rect := _default_room_actor_rect() if has_background() \
			else Rect2(170, 48, 70, 105)
		add_npc_actor("npc_stefan", actor_rect, _on_stefan)


## Hotspots über dem Artwork (Bildkoordinaten 1672x941).
func _build_hotspots() -> void:
	add_hotspot(Rect2(30, 40, 380, 500), Loc.t("place.friend_location.poster_weltraum_schnelle_autos", "Poster — Weltraum & schnelle Autos"), _on_poster)
	add_hotspot(Rect2(430, 20, 370, 410), Loc.t("place.friend_location.fenster_blick_in_siedlung", "Fenster — Blick in die Siedlung"), _on_window)
	add_hotspot(Rect2(975, 30, 220, 750), Loc.t("place.friend_location.regal_stefans_sammlung_ansehen", "Regal — Stefans Sammlung ansehen"), _on_shelf)
	add_hotspot(Rect2(1200, 30, 472, 880), Loc.t("place.friend_location.schrank_besser_nicht_schnuffeln", "Schrank — besser nicht schnüffeln"), _on_closet)
	add_hotspot(Rect2(120, 560, 440, 381), Loc.t("place.friend_location.bett_zeitschriftenstapel_darunter", "Bett — Zeitschriftenstapel darunter"), _on_bed)
	add_hotspot(Rect2(465, 460, 545, 320), Loc.t("place.friend_location.schreibtisch_stefans_anlage_bestaunen", "Schreibtisch — Stefans Anlage bestaunen"), _on_desk)
	add_hotspot(Rect2(640, 520, 280, 330), Loc.t("place.friend_location.stefan_quatschen_oder_arbeitskopie_abgeben", "Stefan — quatschen oder eine Arbeitskopie abgeben"), _on_stefan)
	add_hotspot(Rect2(0, 450, 180, 491), Loc.t("place.friend_location.tur_rausgehen_orte", "Tür — rausgehen (Orte)"), UIManager.open_map)


## Kühle Abdunkelung übers ganze Zimmer, wenn Stefan nicht da ist — man sieht
## sofort beim Reinkommen, dass niemand daheim ist. Liegt über dem Artwork,
## aber unter den Hotspots (die bleiben klickbar).
func _add_away_overlay() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.09, 0.64)  # Nachtblau, kein totes Schwarz
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)


## Fallback für die Platzhalter-Zeichnung (virtual 415x194).
func _build_placeholder_hotspots() -> void:
	add_hotspot(Rect2(170, 55, 70, 90), Loc.t("place.friend_location.stefan_quatschen_oder_arbeitskopie_abgeben", "Stefan — quatschen oder eine Arbeitskopie abgeben"), _on_stefan)
	add_hotspot(Rect2(370, 50, 40, 120), Loc.t("place.friend_location.treppe_rausgehen_orte", "Treppe — rausgehen (Orte)"), UIManager.open_map)


## Ist Stefan gerade zu Hause? Deterministisch pro Tag (kein nerviges
## Neuwürfeln bei jedem Klick). Wenn ein aktiver Spieleauftrag die Übergabe
## verlangt, ist er IMMER da — die Story hängt nie am Zufall.
func _stefan_home() -> bool:
	# Sichttest-Override: DSS_AWAY=1 erzwingt Abwesenheit, =0 erzwingt Anwesenheit.
	var away_env := OS.get_environment("DSS_AWAY")
	if away_env == "1":
		return false
	if away_env == "0":
		return true
	return NPCManager.is_here_now("npc_stefan", "friend_cellar")


func _space_quest_ready() -> bool:
	# Der globale Story-Flag wird schon im Telefonat gesetzt, die Quest selbst
	# oeffnet aber erst in Ferienwoche 2. Nur der QuestManager darf deshalb
	# entscheiden, ob Stefan den Kopier-/Uebergabe-Dialog anbietet. Das rettet
	# zugleich alte Saves, bei denen eine verfruehte Abgabe den Flag bereits auf
	# "done" setzte, waehrend die Quest noch in Stufe 2 festhing.
	if not QuestManager.is_active("q_stefan_space"):
		return false
	var current_stage := QuestManager.stage("q_stefan_space")
	return current_stage in [1, 2] and DiskManager.has_template("game_space_lemming")


func _turbo_quest_ready() -> bool:
	return QuestManager.is_active("q_stefan_turbo") \
		and QuestManager.stage("q_stefan_turbo") == 3 \
		and DiskManager.has_player_copy_of("turbo_kart_deluxe")


## Quest-Logik: Spiel dabei → Abschluss-Dialog (Tausch), sonst Smalltalk.
## Ist Stefan nicht da, kommt der Hinweis zum Wiederkommen.
func _on_stefan() -> void:
	if not _stefan_home():
		UIManager.toast(Loc.t("place.friend_location.niemand_da_stefan_ist_wohl_im", "Niemand da — Stefan ist wohl im Computerclub. Komm später wieder."))
		return
	if _space_quest_ready():
		DialogueManager.start_dialogue("stefan_quest_done", "npc_stefan")
	elif _turbo_quest_ready():
		DialogueManager.start_dialogue("stefan_turbo_quest_done", "npc_stefan")
	elif not StefanGames.active_delivery().is_empty():
		var result := StefanGames.deliver_active_copy()
		if bool(result.get("ok", false)):
			UIManager.open_info("STEFANS SPIELEABEND",
				str(result.get("text", "Stefan nimmt die Arbeitskopie."))
				+ "\n\n»Die probieren wir heute Abend zusammen. Danke — das war die Mühe wert!«"
				+ "\n\nNur deine Arbeitskopie wurde abgegeben. Das Original bleibt in deiner Sammlung.")
		else:
			UIManager.toast(str(result.get("text", "Die Arbeitskopie fehlt.")))
	elif not StefanMoments.active_moment().is_empty():
		if not StefanMoments.begin_active_dialogue():
			UIManager.toast(Loc.t("place.friend_location.stefans_gespraech_konnte_nicht_gestartet_werden", "Stefans Gespraech konnte nicht gestartet werden."))
	else:
		DialogueManager.start_dialogue("stefan_default", "npc_stefan")


func _on_shelf() -> void:
	UIManager.toast(Loc.t("place.friend_location.reihenweise_originale_mit_dicken_handbuchern_stefan", "Reihenweise Originale mit dicken Handbüchern. Stefan hütet sie wie Gold."))


func _on_desk() -> void:
	UIManager.toast(Loc.t("place.friend_location.amiga_mit_farbmonitor_drucker_joystick_telefon", "Amiga mit Farbmonitor, Drucker, Joystick — und ein Telefon fürs Modem."))


func _on_poster() -> void:
	UIManager.toast(Loc.t("place.friend_location.selbstgezogene_poster_aus_spielezeitschrift_mit_tesa", "Selbstgezogene Poster aus der Spielezeitschrift, mit Tesa an der Raufaser."))


func _on_window() -> void:
	UIManager.toast(Loc.t("place.friend_location.draussen_immergleiche_reihenhaussiedlung_drinnen_gluht_monitor", "Draußen die immergleiche Reihenhaussiedlung. Drinnen glüht der Monitor."))


func _on_bed() -> void:
	UIManager.toast(Loc.t("place.friend_location.unterm_bett_karton_voll_durchgeblatterter_zeitschriften", "Unterm Bett: ein Karton voll durchgeblätterter Zeitschriften."))


func _on_closet() -> void:
	UIManager.toast(Loc.t("place.friend_location.schrank_bleibt_zu_manche_sammlerstucke_zeigt", "Der Schrank bleibt zu. Manche Sammlerstücke zeigt Stefan nur, wenn er will."))


func _draw() -> void:
	if has_background():
		return
	var s := view_scale()
	draw_set_transform(view_offset(), 0.0, Vector2(s, s))

	# Zimmer: warme Wände, Teppichboden
	draw_rect(Rect2(0, 0, 415, 130), Palette.TEAL_DARK)
	draw_rect(Rect2(0, 130, 415, 64), Palette.GREY_DARK)

	# Bett
	draw_rect(Rect2(40, 110, 100, 40), Palette.BLUE_MID.darkened(0.2))
	draw_rect(Rect2(36, 100, 108, 14), Palette.BLUE_MID)
	draw_rect(Rect2(40, 110, 100, 40), Palette.BLACK, false, 1.0)

	# Monitor mit flackerndem Bild
	draw_rect(Rect2(260, 90, 54, 44), Palette.GREY_DARK)
	var flicker := 0.1 * sin(anim_time * 9.0)
	draw_rect(Rect2(265, 95, 44, 30), Palette.GREEN_DARK.lightened(0.2 + flicker))
	draw_rect(Rect2(272, 102, 8, 8), Palette.YELLOW)
	draw_rect(Rect2(260, 90, 54, 44), Palette.BLACK, false, 1.0)
	draw_rect(Rect2(258, 134, 58, 24), Palette.BROWN)

	# Diskettenstapel
	for i in 5:
		draw_rect(Rect2(150 + i * 3, 150 - i * 4, 14, 4),
			[Palette.BLUE_MID, Palette.RED_DARK, Palette.GREY, Palette.GREEN_DARK, Palette.SAND][i])

	# Tür
	for i in 5:
		draw_rect(Rect2(370, 160 - i * 22, 40, 10), Palette.GREY_MID)
