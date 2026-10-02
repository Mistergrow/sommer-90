extends Control
## Einstiegspunkt: baut das Bezel-Layout (Mockup: Top-Bar, Sidebar,
## Bottom-Bar, Zimmeransicht in der Mitte), Titelscreen, Software-Cursor
## und die optionale CRT-Shader-Ebene. Registriert die UI bei den Managern.

const TOP_BAR_HEIGHT := 76.0
const SIDE_BAR_WIDTH := 104.0
const BOTTOM_BAR_HEIGHT := 94.0
const PixelConfettiRainScript := preload("res://scripts/ui/pixel_confetti_rain.gd")
const CrtProfiles := preload("res://scripts/gfx/crt_profile_store.gd")
const SoftwareVisualWarmupScript := preload("res://scripts/gfx/software_visual_warmup.gd")
const DevelopmentGate := preload("res://scripts/core/development_gate.gd")

var _crt_rect: ColorRect
var _event_confetti: Control
var _crt_profile_id := ""


func _ready() -> void:
	randomize()
	theme = RetroTheme.build()
	get_node("/root/CursorManager").call("show_cursor")
	# Bei normalem Projektstart hat der StartupLoader diesen Warmup bereits vor
	# dem Hauptmenü ausgeführt und als Kind mitgebracht. Direkt geladene Main-
	# Tests/Editor-Szenen behalten den bisherigen verteilten Fallback.
	if not has_node("SoftwareVisualWarmup"):
		add_child(SoftwareVisualWarmupScript.new())

	# --- Grundfläche ---
	var background := ColorRect.new()
	background.color = Palette.UI_BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# --- Zimmeransicht (Mitte) ---
	var location_host := Control.new()
	location_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	location_host.offset_left = SIDE_BAR_WIDTH
	location_host.offset_top = TOP_BAR_HEIGHT
	location_host.offset_bottom = -BOTTOM_BAR_HEIGHT
	location_host.clip_contents = true
	add_child(location_host)
	GameManager.register_location_host(location_host)

	# Bezel-Rahmen um die Zimmeransicht (Mockup: Ansicht sitzt im Gehäuse)
	var view_frame := Panel.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0, 0, 0, 0)
	frame_style.border_color = Color(0.015, 0.015, 0.018)
	frame_style.set_border_width_all(2)
	view_frame.add_theme_stylebox_override("panel", frame_style)
	view_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	view_frame.offset_left = SIDE_BAR_WIDTH
	view_frame.offset_top = TOP_BAR_HEIGHT
	view_frame.offset_bottom = -BOTTOM_BAR_HEIGHT
	view_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view_frame)

	# --- HUD-Leisten ---
	var top_bar := TopBar.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = TOP_BAR_HEIGHT
	add_child(top_bar)
	top_bar.add_child(HudScanlines.new())

	var side_bar := SideBar.new()
	side_bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	side_bar.offset_top = TOP_BAR_HEIGHT + 24.0
	side_bar.offset_right = SIDE_BAR_WIDTH
	side_bar.offset_bottom = -BOTTOM_BAR_HEIGHT
	add_child(side_bar)

	var bottom_bar := BottomBar.new()
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_top = -BOTTOM_BAR_HEIGHT
	add_child(bottom_bar)
	bottom_bar.add_child(HudScanlines.new())

	# Ereignisregen liegt ueber dem HUD, aber unter Fenstern/Cursor. Positive
	# Kalender- und Fundereignisse bekommen so einen kurzen 16-Bit-Moment, ohne
	# dass negative Ereignisse wie ein Stromausfall versehentlich gefeiert werden.
	var confetti_layer := CanvasLayer.new()
	confetti_layer.layer = 48
	add_child(confetti_layer)
	_event_confetti = PixelConfettiRainScript.new()
	confetti_layer.add_child(_event_confetti)
	EventManager.event_triggered.connect(_on_event_confetti)

	# --- Titelscreen (verschwindet bei game_started) ---
	# MUSS VOR der Fensterebene ins Baum: Godot pickt Maus-Input nach Baum-
	# Reihenfolge (letztes Kind zuerst), NICHT nach z_index. Läge der Titelscreen
	# hinter der Fensterebene, würde sein bildschirmfüllender Wurzel-Control
	# (MOUSE_FILTER_STOP) alle Klicks abfangen und das darüber GEZEICHNETE
	# Optionen-Fenster wäre nicht bedienbar („gefangen im Hauptmenü").
	add_child(TitleScreen.new())

	# --- Fensterebene (Diskbox, Shop, Dialoge, Events, Optionen ...) ---
	# Letztes Kind → bekommt Maus-Input zuerst. IGNORE lässt Klicks dort durch,
	# wo kein Fenster liegt (Titelscreen-Buttons bleiben klickbar).
	var window_layer := Control.new()
	window_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Ein einziger, projektweiter Safe-Area-Vertrag fuer alle frei schwebenden
	# Fenster. UiWindowSupport wertet die Insets bei jeder aktuellen
	# Viewportgroesse neu aus; damit landen Dialoge weder unter der Topbar noch
	# hinter Sidebar/Notizboard. Die Werte liegen als Metadaten am Host, damit
	# Fensterklassen keine Kopie der Main-Layoutkonstanten pflegen muessen.
	window_layer.set_meta("safe_area_insets", Vector4(
		SIDE_BAR_WIDTH + 8.0, TOP_BAR_HEIGHT + 8.0,
		8.0, BOTTOM_BAR_HEIGHT + 8.0))
	window_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Über Raum UND Vollbild-Apps zeichnen: Werkbank-Apps/X-COPY reichen bis z70.
	# Eine Gleichlage (früher z50) machte sichtbare Overlay-Buttons abhängig von
	# Baum-/GUI-Reihenfolge. z80 bleibt bewusst unter dem Software-Cursor/Juice
	# (Canvas-Layer 85) und unter echten Übergangsscreens (z500).
	window_layer.z_index = 80
	add_child(window_layer)
	UIManager.register_window_layer(window_layer)

	# Sichttest: Optionen-Fenster im Hauptmenü öffnen (DSS_OPTIONS=1)
	if OS.get_environment("DSS_OPTIONS") == "1":
		(func() -> void:
			await get_tree().create_timer(0.6).timeout
			UIManager.open_options()).call_deferred()
	# Für visuelle Tests/Diagnose: Spiel direkt starten (DSS_AUTOSTART=1),
	# optional gleich mit aktivem Deko-Modus (DSS_DECO=1)
	if OS.get_environment("DSS_AUTOSTART") == "1":
		GameManager.new_game.call_deferred()
		if OS.get_environment("DSS_DECO") == "1":
			(func() -> void:
				var comp := _find_compositor()
				if comp != null:
					comp.set_edit_mode(true)).call_deferred()
		# Sichttest Power/Boot: DSS_POWER=mon|amiga|both|boot setzt nach kurzem
		# Vorlauf die Einschaltzustände (Monitor/Amiga/Kickstart/gebootet).
		if OS.get_environment("DSS_POWER") != "":
			(func() -> void:
				await get_tree().create_timer(0.6).timeout
				var mode := OS.get_environment("DSS_POWER")
				UIManager.set_strip_power(true)
				if mode in ["mon", "both", "boot"]:
					UIManager.set_monitor_power(true)
				if mode in ["amiga", "both", "boot"]:
					UIManager.set_amiga_power(true)
				if mode == "boot":
					UIManager.system_disk_inserted = true
					UIManager.monitor_changed.emit()).call_deferred()
		# Kultur-Sichttest: Cracktro-/Kopierschutz-Flow direkt öffnen
		if OS.get_environment("DSS_CULTURE") == "1":
			(func() -> void:
				UIManager.set_strip_power(true)
				UIManager.set_monitor_power(true)
				UIManager.set_amiga_power(true)
				UIManager._set_computer_ui(true)
				var disk: Disk = DiskManager.create_disk("game_space_lemming", "Sichttest")
				DiskManager.add_disk(disk)
				UIManager.play_disk_flow(disk)).call_deferred()
		# Sicht-Test-Hooks: kurz warten (Intro läuft ab), Fenster schließen,
		# dann Ort direkt setzen und optional Shop/Bestellkatalog öffnen.
		#   DSS_GOTO=computer_shop|friend_cellar   DSS_SHOP=stock|catalog
		#   DSS_ORDERS=1 seedet eine bereitliegende + eine unterwegs-Bestellung.
		var goto_id := OS.get_environment("DSS_GOTO")
		var shop_mode := OS.get_environment("DSS_SHOP")
		var seed_orders := OS.get_environment("DSS_ORDERS") == "1"
		var rumor_view := OS.get_environment("DSS_RUMOR")
		if goto_id != "" or shop_mode != "" or seed_orders or rumor_view != "" or OS.get_environment("DSS_MUSIC") == "1" or OS.get_environment("DSS_CLUB") == "1" or OS.get_environment("DSS_FLEA") == "1" or OS.get_environment("DSS_MAP") == "1" or OS.get_environment("DSS_WERKBANK") != "" or OS.get_environment("DSS_XCOPY") != "" or OS.get_environment("DSS_APP") != "":
			(func() -> void:
				await get_tree().create_timer(1.5).timeout
				UIManager.close_all_windows()
				if rumor_view != "":
					for _i in 4:  # ein paar Tage ausbreiten lassen
						TimeManager.day_counter += 1
						TimeManager.day_changed.emit()
				var slot_env := OS.get_environment("DSS_SLOT")
				if slot_env != "":
					TimeManager.slot = int(slot_env)
				if goto_id != "":
					GameManager._enter_location(goto_id)
				if seed_orders:
					OrderManager.arrived.append({"id": "order_hand_scanner", "name": "Handscanner (Grauwert)"})
					OrderManager.pending.append({"id": "order_laser_printer", "name": "Laserdrucker",
						"price": 1290, "ordered_day": 0, "arrives_day": 9})
					OrderManager.orders_changed.emit()
				if shop_mode != "":
					UIManager.open_shop(shop_mode)
				if rumor_view != "":
					UIManager.open_rumors("board" if rumor_view == "board" else "group", rumor_view)
				# Anlage/MOD-Player-Sichttest (DSS_MUSIC=1 spielt gleich den ersten Track)
				if OS.get_environment("DSS_MUSIC") == "1":
					MusicManager.play("space_debris")
					UIManager.open_music()
				# Computerclub-Bibliothek-Sichttest (DSS_CLUB=1, Jahr 1996 = volle Liste)
				if OS.get_environment("DSS_CLUB") == "1":
					TimeManager.year = 1996
					UIManager.open_music_club()
				# Flohmarkt-Sichttest (Samstag setzen, Markt erzeugen, Fenster auf)
				if OS.get_environment("DSS_FLEA") == "1":
					TimeManager.year = 1992
					TimeManager.month = 7
					TimeManager.day = 11
					TimeManager.day_counter = 50
					GameManager._enter_location("flea_market")
					UIManager.open_flea()
				if OS.get_environment("DSS_MAP") == "1":
					TimeManager.year = 1992
					TimeManager.month = 7
					TimeManager.day = 14
					TimeManager.slot = 2  # Nachmittag (5-Fenster-Tag)
					UIManager.open_map()
				if OS.get_environment("DSS_WERKBANK") != "":
					UIManager.set_strip_power(true)
					UIManager.set_monitor_power(true)
					UIManager.set_amiga_power(true)
					if OS.get_environment("DSS_WERKBANK") == "full":
						PlayerStats.add_hardware("modem")
						PlayerStats.add_hardware("laser_printer")
						TimeManager.year = 1994
						for prog in ["xcopy", "viruschecker", "file_manager_opus_homage", "lha_unpacker", "protracker", "dpaint", "texteditor", "download_manager", "snoop_monitor"]:
							PlayerStats.add_program(prog)
					UIManager.open_werkbank()
				if OS.get_environment("DSS_XCOPY") != "":
					var xv := OS.get_environment("DSS_XCOPY")
					UIManager.set_strip_power(true)
					UIManager.set_monitor_power(true)
					UIManager.set_amiga_power(true)
					UIManager.open_werkbank()
					if xv == "pro" or xv == "copypro":
						UIManager.open_xcopy_pro()
					else:
						UIManager.open_disk_copy()
					if xv.begins_with("copy"):
						var xc: Node = GameManager.location_host.get_node_or_null("XCopy")
						if xc != null:
							xc.demo_start()
				if OS.get_environment("DSS_APP") != "":
					TimeManager.year = 1994
					UIManager.open_werkbank()
					var av := OS.get_environment("DSS_APP")
					if av == "mod":
						UIManager.open_mod_player()
					elif av == "virus":
						UIManager.open_virus_checker()
					elif av == "sysinfo":
						UIManager.open_sysinfo()
					elif av == "text":
						UIManager.open_text_editor()
					elif av == "opus":
						UIManager.open_program("file_manager_opus_homage")
					else:
						UIManager.open_paint()).call_deferred()

	# Der „AUFSTEHEN"-Knopf ist Teil des UI (SideBar) und erscheint dort, wenn man
	# am Computer sitzt — kein schwebendes Overlay mehr.

	# --- Juice-Ebene: Toast-Sprechblasen + Meilenstein-Banner (über HUD/Fenstern) ---
	var juice_layer := CanvasLayer.new()
	juice_layer.layer = 85
	add_child(juice_layer)
	juice_layer.add_child(JuiceLayer.new())

	# --- CRT-Shader-Ebene: optional global ueber Spiel/HUD/Fenstern oder lokal
	# waehrend der Spieler am eingeschalteten Computer sitzt. ---
	var crt_layer := CanvasLayer.new()
	crt_layer.layer = 100
	add_child(crt_layer)
	_crt_rect = ColorRect.new()
	_crt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var crt_material := ShaderMaterial.new()
	crt_material.shader = load("res://shaders/crt.gdshader")
	_crt_rect.material = crt_material
	_crt_rect.visible = UIManager.crt_enabled or bool(SettingsManager.value("crt_global_filter"))
	crt_layer.add_child(_crt_rect)
	UIManager.crt_toggled.connect(func(_enabled: bool) -> void:
		_refresh_crt_visibility())
	SettingsManager.settings_changed.connect(_refresh_crt_visibility)
	GameManager.location_changed.connect(func(_id: String) -> void:
		_crt_profile_id = ""
		_refresh_crt_profile())
	_refresh_crt_visibility()
	_refresh_crt_profile()


func _on_event_confetti(event: Dictionary) -> void:
	if _event_confetti != null:
		_event_confetti.call("celebrate", event)


func _process(_delta: float) -> void:
	# Ein Appwechsel kann innerhalb desselben Computer-Sitzens stattfinden. Der
	# billige Kontextvergleich sorgt dafuer, dass X-Copy/Demo/Spiel ihr eigenes im
	# CRT-Editor gespeichertes Profil sofort bekommen.
	if _crt_rect != null and _crt_rect.visible:
		_refresh_crt_profile()


func _refresh_crt_visibility() -> void:
	if _crt_rect == null:
		return
	_crt_rect.visible = UIManager.crt_enabled or bool(SettingsManager.value("crt_global_filter"))
	if _crt_rect.visible:
		_crt_profile_id = ""
		_refresh_crt_profile()


func _refresh_crt_profile() -> void:
	if _crt_rect == null:
		return
	var id := _current_crt_profile()
	# Der Shader ist ein Post-Process: räumliche Kruemmung verschiebt das sichtbare
	# Bild, nicht aber Godots Control-Hitboxen oder den nativen Cursor. Deshalb
	# laufen ALLE bedienbaren Ansichten mit deckungsgleicher Geometrie. Der echte
	# Monitor-Modus behaelt das vollstaendige CRT-Signalbild (Scanlines, Maske,
	# Bloom, Farbsäume, Rollband usw.); nur die Klicks verschiebende Geometrie ist
	# neutral. Volle Kruemmung bleibt im nicht interaktiven CRT-Editor sichtbar.
	var geometry_mode := "interactive_monitor" if UIManager.crt_enabled else "global_flat"
	var cache_id := "%s|%s" % [id, geometry_mode]
	if cache_id == _crt_profile_id:
		return
	_crt_profile_id = cache_id
	var crt_mat := _crt_rect.material as ShaderMaterial
	if crt_mat == null:
		return
	crt_mat.set_shader_parameter("reduced_motion", bool(SettingsManager.value("reduced_motion")))
	var params := CrtProfiles.interactive_params_for(id)
	for spec: Dictionary in CrtProfiles.PARAMETERS:
		var key := str(spec["id"])
		crt_mat.set_shader_parameter(key, float(params.get(key, 0.0)))


func _current_crt_profile() -> String:
	var location_id := GameManager.current_location_id
	return location_id if CrtProfiles.has_level(location_id) else "default"


func _find_compositor() -> RoomCompositor:
	if GameManager.location_host == null:
		return null
	for location in GameManager.location_host.get_children():
		for child in location.get_children():
			if child is RoomCompositor:
				return child
	return null



## Globale Shortcuts: N Notizblock, F1 Hilfe, F5 Speichern, F8 Deko-Modus (nur
## Entwicklung), F9 Laden, F10 CRT, F11 Vollbild, ESC Menü.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_N:
			if GameManager.state == GameManager.State.PLAYING:
				UIManager.open_tasks()
		KEY_F1:
			UIManager.open_help()
		KEY_F5:
			if GameManager.state == GameManager.State.PLAYING:
				SaveManager.save_game()
		KEY_F9:
			# Schnell-Laden nur im laufenden Spiel (lädt den aktiven Slot neu).
			# Am Titel führt „Spiel fortsetzen" mit expliziter Slot-Wahl zum Ziel;
			# der Vorgabe-Slot wäre dort sonst falsch geraten.
			if GameManager.state == GameManager.State.PLAYING:
				SaveManager.load_game_with_screen()
		KEY_F10:
			UIManager.toast(Loc.t("misc.main.crt_gesamtfilter_s_umschalten_unter_optionen", "CRT-Gesamtfilter: %s · umschalten unter OPTIONEN.") %
				("AN" if bool(SettingsManager.value("crt_global_filter")) else "AUS"))
		KEY_F11:
			SettingsManager.set_value("fullscreen", not bool(SettingsManager.value("fullscreen")))
		KEY_F8:
			# Deko-Modus ist ein Autorenwerkzeug: Im Export ist res:// schreibgeschuetzt,
			# verschobene Moebel gingen verloren und Klickflaechen liefen auseinander.
			if not DevelopmentGate.enabled():
				return
			var comp := _find_compositor()
			if comp == null:
				UIManager.toast(Loc.t("misc.main.deko_modus_geht_nur_im_zimmer", "Deko-Modus geht nur im Zimmer. Orte einrichten: Editor-Szene in scenes/ oeffnen (F6)."))
			else:
				comp.set_edit_mode(not comp.edit_mode)
				UIManager.toast(Loc.t("misc.main.deko_modus_an_ziehen_verschieben_mausrad", "Deko-Modus AN: ziehen = verschieben, Mausrad = Größe, F8 = speichern.")
					if comp.edit_mode else "Deko-Modus AUS — Layout gespeichert (data/room_anchors.json).")
		KEY_ESCAPE:
			if GameManager.state == GameManager.State.PLAYING:
				UIManager.open_system_menu()
