extends RetroWindow
## BBS-Terminal — die Online-Welt der Kulturschicht (docs/KULTUR_LAYER.md).
## ANSI/Amiga-Terminal mit echter Einwahl-, Bereichs- und Carrier-Hierarchie.
## Ablauf:
##   Board-Liste (Jahr-gefiltert) -> Einwahl-Sequenz (ATDT…CONNECT) ->
##   verbunden: News, Dateien (Download -> Diskette), Nachrichten, Anzeigen.
## Kein Asset — reine Terminal-Zeichnung.

const GREEN := Color(0.55, 1.0, 0.6)
const DIM := Color(0.4, 0.75, 0.45)
const AMBER := Color(1.0, 0.82, 0.35)
const MESSAGES_PER_PAGE := 6
const ARTISTS_PER_PAGE := 6
const ARTIST_TRACKS_PER_PAGE := 8
const ECHOES_PER_PAGE := 5

var _screen: RichTextLabel
var _buttons: VBoxContainer
var _status_left: Label
var _status_right: Label
var _storage_status: Label
var _assistant_input: LineEdit
var _dialing := false
var _dial_lines: Array = []
var _dial_target := ""
var _dial_index := 0
var _dial_time := 0.0
var _session_seconds := 0.0
var _status_accumulator := 0.0
var _was_connected := false


func _init() -> void:
	title = Loc.t("ui.bbs_window.modem_terminal", "MODEM-TERMINAL")
	win_size = Vector2(940, 590)
	chrome_accent = Palette.LCD_GREEN


func _ready() -> void:
	super._ready()
	BBSManager.connection_changed.connect(_refresh)

	var status_top := PanelContainer.new()
	status_top.custom_minimum_size = Vector2(0, 42)
	status_top.add_theme_stylebox_override("panel", _terminal_style(Color(0.08, 0.22, 0.14), 6))
	content.add_child(status_top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	status_top.add_child(top_row)
	var brand := Bezel.lcd_label(Loc.t("ui.bbs_window.ami_comm_professional", "AMI-COMM PROFESSIONAL"), AMBER, 15)
	brand.custom_minimum_size = Vector2(210, 0)
	top_row.add_child(brand)
	_status_left = Bezel.lcd_label(Loc.t("ui.bbs_window.offline_ready", "OFFLINE · READY"), GREEN, 12)
	_status_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_status_left)
	_status_right = Bezel.lcd_label(Loc.t("ui.bbs_window.8n1_ansi_vt100", "8N1 · ANSI · VT100"), DIM, 11)
	_status_right.custom_minimum_size = Vector2(260, 0)
	_status_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_row.add_child(_status_right)

	var term_box := StyleBoxFlat.new()
	term_box.bg_color = Color(0.02, 0.05, 0.03)
	term_box.border_color = Color(0.15, 0.35, 0.2)
	term_box.set_border_width_all(2)
	term_box.set_content_margin_all(10)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", term_box)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	_screen = RichTextLabel.new()
	_screen.name = "TerminalScreen"
	_screen.bbcode_enabled = true
	_screen.scroll_following = true
	_screen.selection_enabled = true
	_screen.context_menu_enabled = false
	_screen.custom_minimum_size = Vector2(650, 0)
	_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen.add_theme_font_size_override("normal_font_size", 14)
	_screen.add_theme_font_size_override("bold_font_size", 14)
	_screen.add_theme_color_override("default_color", GREEN)
	_screen.add_theme_color_override("font_shadow_color", Color(0.1, 0.45, 0.18, 0.38))
	_screen.add_theme_constant_override("shadow_offset_x", 1)
	_screen.add_theme_constant_override("shadow_offset_y", 1)
	row.add_child(_screen)

	_buttons = VBoxContainer.new()
	_buttons.name = "CommandRail"
	_buttons.add_theme_constant_override("separation", 6)
	_buttons.custom_minimum_size = Vector2(220, 0)
	row.add_child(_buttons)

	var footer := PanelContainer.new()
	footer.custom_minimum_size = Vector2(0, 30)
	footer.add_theme_stylebox_override("panel", _terminal_style(Color(0.05, 0.16, 0.11), 5))
	content.add_child(footer)
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 12)
	footer.add_child(footer_row)
	var leds := Bezel.lcd_label(Loc.t("ui.bbs_window.aa_cd_oh_rd_sd_tr", "AA  CD  OH  RD  SD  TR"), Color(0.25, 0.72, 0.43), 10)
	leds.custom_minimum_size = Vector2(190, 0)
	footer_row.add_child(leds)
	var hint := Bezel.dim_label(Loc.t("ui.bbs_window.maus_return_auswaehlen_esc_fenster_schliessen", "MAUS/RETURN: AUSWAEHLEN · ESC: FENSTER SCHLIESSEN"), 11)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(hint)
	var storage := Bezel.lcd_label(Loc.t("ui.bbs_window.leerdisks_0", "LEERDISKS 0"), AMBER, 10)
	storage.name = "StorageStatus"
	storage.custom_minimum_size = Vector2(110, 0)
	storage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer_row.add_child(storage)
	_storage_status = storage

	_refresh()


func _process(delta: float) -> void:
	if _dialing:
		_dial_step(delta)
	if BBSManager.connected():
		_session_seconds += delta
	_status_accumulator += delta
	if _status_accumulator >= 0.25:
		_status_accumulator = 0.0
		_update_status()


# ------------------------------------------------------------- Ansichten

func _refresh() -> void:
	if _dialing:
		return
	if BBSManager.connected() and not _was_connected:
		_session_seconds = 0.0
	_was_connected = BBSManager.connected()
	_update_status()
	if BBSManager.connected():
		_show_board()
	else:
		_show_board_list()


func _clear_buttons() -> void:
	for c in _buttons.get_children():
		# Sofort aus dem Layout/Input-Baum nehmen. queue_free() allein laesst die
		# alte Bereichsschaltflaeche bis zum Frame-Ende ueber dem neuen Button
		# liegen; schnelle echte Mausklicks landeten dadurch wieder im Altbereich.
		_buttons.remove_child(c)
		c.queue_free()


func _add_button(text: String, cb: Callable, disabled := false) -> Button:
	var b := make_button(text, cb)
	b.custom_minimum_size = Vector2(210, 36)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = disabled
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = text
	_buttons.add_child(b)
	return b


func _terminal_style(border: Color, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.035, 0.022, 0.98)
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(margin)
	return style


func _update_status() -> void:
	if _status_left == null:
		return
	if BBSManager.connected():
		var board: Dictionary = BBSManager.current_board
		_status_left.text = Loc.t("ui.bbs_window.connect_d_s_node_1", "CONNECT %d · %s · NODE 1") % [
			BBSManager.connection_baud(board), str(board.get("name", "MAILBOX")).to_upper()]
		_status_right.text = Loc.t("ui.bbs_window.02d_02d_online_rechnung_d_dm", "%02d:%02d ONLINE · RECHNUNG %d DM") % [
			floori(_session_seconds / 60.0), floori(_session_seconds) % 60, PhoneManager.bill_due]
	else:
		_status_left.text = Loc.t("ui.bbs_window.offline_modem_d_baud_ready", "OFFLINE · MODEM %d BAUD · READY") % BBSManager.player_baud()
		_status_right.text = Loc.t("ui.bbs_window.8n1_ansi_vt100_rechnung_d_dm", "8N1 · ANSI · VT100 · RECHNUNG %d DM") % PhoneManager.bill_due
	if is_instance_valid(_storage_status):
		_storage_status.text = Loc.t("ui.bbs_window.leerdisks_d", "LEERDISKS %d") % DiskManager.blank_disks().size()


func _show_board_list() -> void:
	_clear_buttons()
	var boards := BBSManager.boards_for_year()
	var mission_board_id := BBSManager.farewell_board_id() \
		if BBSManager.farewell_mission_active() else ""
	if not mission_board_id.is_empty():
		boards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_target := str(a.get("id", "")) == mission_board_id
			var b_target := str(b.get("id", "")) == mission_board_id
			if a_target != b_target:
				return a_target
			return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0)
	var lines := [
		"[color=#8fd]AMI-COMM PROFESSIONAL v2.4[/color]",
		"[color=#363]========================================================[/color]", ""]
	if not BBSManager.available():
		lines.append(Loc.t("ui.bbs_window.no_modem", "[color=#f88]KEIN MODEM ANGESCHLOSSEN.[/color]"))
		lines.append("")
		lines.append(Loc.t("ui.bbs_window.modem_shop_hint_1", "Ein passendes Modem gibt es im"))
		lines.append(Loc.t("ui.bbs_window.modem_shop_hint_2", "Computerladen oder Bestellkatalog."))
		lines.append(Loc.t("ui.bbs_window.online_world_hint", "Danach öffnet sich die Online-Welt:"))
		lines.append(Loc.t("ui.bbs_window.online_world_list", "BBS, Shareware, Kleinanzeigen …"))
		_screen.text = "\n".join(lines)
		return
	if boards.is_empty():
		lines.append(Loc.t("ui.bbs_window.no_board_this_year", "Keine Mailbox erreichbar in diesem Jahr."))
		_screen.text = "\n".join(lines)
		return
	lines.append(Loc.t("ui.bbs_window.choose_board", "WÄHLE EINE MAILBOX · TELEFONBUCH %d") % TimeManager.year)
	if not mission_board_id.is_empty():
		lines.append("[color=#fd6]%s[/color]" % (
			Loc.t("ui.bbs_window.mission_download", "AUFTRAG: Nachtschicht Board → DATEIEN → PFLICHTDATEI 1/1")
			if BBSManager.farewell_archive_pending()
			else Loc.t("ui.bbs_window.mission_upload", "AUFTRAG: Nachtschicht Board → EIGENE RELEASES → ABSCHIEDSGRUSS")))
	lines.append("")
	for b in boards:
		var is_target := str(b.get("id", "")) == mission_board_id
		var board_label := (Loc.t("ui.bbs_window.mission_prefix", "[AUFTRAG] ") if is_target else "") + str(b.get("name", "?"))
		lines.append("[color=#fd6]%s[/color]" % board_label if is_target \
			else "[color=#8fd]%s[/color]" % board_label)
		lines.append(Loc.t("ui.bbs_window.board_line", "  %s · %d Baud · SysOp: %s") % [
			b.get("number", "?"), int(b.get("baud", 2400)), b.get("sysop", "?")])
		lines.append("  [color=#6b6]%s[/color]" % b.get("tagline", ""))
		lines.append("")
		_add_button(board_label, _begin_dial.bind(b.get("id", "")))
	_screen.text = "\n".join(lines)


func _show_board() -> void:
	_clear_buttons()
	var b := BBSManager.current_board
	var lines := [
		"[color=#8fd]%s[/color]" % str(b.get("name", "?")).to_upper(),
		"[color=#363]========================================================[/color]",
		"[color=#6b6]CONNECT %d · SYSOP %s · ANSI EMULATION[/color]" % [
			BBSManager.connection_baud(b), b.get("sysop", "?")],
		"",
	]
	for n in BBSManager.news():
		lines.append("[color=#fd6]» %s[/color]" % n)
	lines.append("")
	# Oneliner-WALL — die Shout-Zeile jeder guten Box.
	lines.append("[color=#8fd]■ WALL ■[/color]")
	for w in BBSScene.wall_for(str(b.get("id", ""))):
		lines.append("[color=#6b6]· %s[/color]" % w)
	lines.append("")
	# Wer ist gerade online (NPC-Pseudonyme + Szene-Gruppen).
	var users: Array = BBSScene.users_for(str(b.get("id", "")))
	lines.append("[color=#8fd]■ ONLINE (%d) ■[/color]  [color=#6b6]%s[/color]" % [
		users.size(), ", ".join(users)])
	lines.append("")
	lines.append(Loc.t("ui.bbs_window.choose_area", "Wähle einen Bereich rechts."))
	_screen.text = "\n".join(lines)
	var scene_posts: Array = BBSScene.posts_for(str(b.get("id", "")))
	var archive_live_posts: Array = BBSScene.archive_live_posts_for(str(b.get("id", "")))
	var file_label := Loc.t("ui.bbs_window.files_count", "Dateien (%d)") % BBSManager.files().size()
	if BBSManager.farewell_archive_pending() \
			and str(b.get("id", "")) == BBSManager.farewell_board_id():
		file_label = Loc.t("ui.bbs_window.files_mission_count", "Dateien (%d) · AUFTRAG") % BBSManager.files().size()
	var files_button := _add_button(file_label, _show_files)
	files_button.name = "FilesButton"
	files_button.tooltip_text = Loc.t(
		"ui.bbs_window.dateibereich_oeffnen_downloads_auf_leerdiskette",
		"Dateibereich öffnen · Downloads landen auf einer Leerdiskette")
	_add_button(Loc.t("ui.bbs_window.messages_count", "Nachrichten (%d)") % (
		BBSManager.messages().size() + scene_posts.size() + archive_live_posts.size()),
		_show_messages)
	var archive_button := _add_button(
		Loc.t("ui.bbs_window.artist_archive_count", "Kuenstlerarchiv (%d)") %
			BBSScene.playable_artist_catalog().size(), _show_archive_index)
	archive_button.tooltip_text = Loc.t(
		"ui.bbs_window.artist_archive_tooltip",
		"Alle spielbaren MODs · Credits, Quellenstatus und belegte Rueckblicke")
	if BBSManager.scene_upload_area():
		_add_button(Loc.t("ui.bbs_window.own_releases_count", "Eigene Releases (%d)") % BBSManager.scene_uploads().size(), _show_scene_uploads)
	_add_button(Loc.t("ui.bbs_window.scene_status", "Szene-Status"), _show_scene_status)
	_add_button(Loc.t("ui.bbs_window.classifieds_count", "Kleinanzeigen (%d)") % BBSManager.classifieds().size(), _show_classifieds)
	var assistant_button := _add_button(BBSManager.assistant_name(), _show_assistant)
	assistant_button.name = "AssistantButton"
	_add_button(Loc.t("ui.bbs_window.hang_up", "» Auflegen «"), _hang_up)


func _show_files() -> void:
	_clear_buttons()
	var lines := [Loc.t("ui.bbs_window.file_area", "[color=#8fd]■ DATEI-BEREICH ■[/color]"), ""]
	var farewell_files_view := BBSManager.farewell_archive_pending() \
		and str(BBSManager.current_board.get("id", "")) == BBSManager.farewell_board_id()
	if farewell_files_view:
		lines.append(Loc.t("ui.bbs_window.exactly_one_mission_file", "[color=#fd6]■ AUFTRAG · GENAU EINE PFLICHTDATEI ■[/color]"))
		lines.append(Loc.t("ui.bbs_window.archive_one_of_one", "[color=#fff]1/1  NACHTSCHICHT-KOMPLETTARCHIV[/color]"))
		lines.append(Loc.t("ui.bbs_window.only_this_file_counts", "[color=#6b6]Nur diese Datei zählt. PROGRAMM-DOWNLOADS: OPTIONAL.[/color]"))
		lines.append("")
	for f in BBSManager.files():
		var mission_file := bool(f.get("mission_critical", false))
		lines.append((Loc.t("ui.bbs_window.mission_file_row", "[color=#fd6][AUFTRAG] [PFLICHT 1/1] %s[/color]") if mission_file \
			else "[color=#8fd]%s[/color]") % f.get("content_title", "?"))
		lines.append(Loc.t("ui.bbs_window.file_size_row", "  %s · %d KB") % [f.get("content_type", "?"), int(f.get("size_kb", 0))])
		if f.get("note", "") != "":
			lines.append("  [color=#6b6]%s[/color]" % f["note"])
		lines.append("")
		var download_button := _add_button((Loc.t("ui.bbs_window.mission_file_prefix", "[AUFTRAG] [PFLICHT 1/1] ") if mission_file else "↓ ") \
			+ _short(f.get("content_title", "?")), _download.bind(f))
		if mission_file:
			download_button.name = "FarewellArchiveDownload"
			download_button.tooltip_text = Loc.t(
				"ui.bbs_window.nachtschicht_komplettarchiv_lokal_sichern",
				"NACHTSCHICHT-KOMPLETTARCHIV lokal sichern")
	# Programm-Archiv: Software aus der Bibliothek (Modem = Zugang). Nicht alles
	# ist sofort verfügbar — Voraussetzungen (Jahr/RAM/Hardware/Ruf) werden gezeigt.
	var progs := ProgramLibrary.available_from("bbs_download")
	if not progs.is_empty():
		lines.append(Loc.t("ui.bbs_window.optional_program_archive", "[color=#6b6]■ PROGRAMM-ARCHIV · OPTIONAL ■[/color]") if farewell_files_view \
			else Loc.t("ui.bbs_window.program_archive", "[color=#fd6]■ PROGRAMM-ARCHIV ■[/color]"))
		if farewell_files_view:
			lines.append(Loc.t("ui.bbs_window.programs_not_required", "[color=#6b6]Keines dieser Programme wird für den Auftrag benötigt.[/color]"))
		lines.append("")
		for p in progs:
			var req: Dictionary = ProgramLibrary.requirement_status(p)
			var col := "8fd" if req["ok"] else "b66"
			lines.append("[color=#%s]%s[/color]" % [col, p.get("display_name", "?")])
			lines.append("  [color=#6b6]%s[/color]" % p.get("description", ""))
			if not req["ok"]:
				lines.append("  [color=#f88][LOCK] %s[/color]" % req["reason"])
			lines.append("")
			_add_button((Loc.t("ui.bbs_window.optional_program", "V [OPTIONAL] %s") if req["ok"] else Loc.t("ui.bbs_window.locked_optional_program", "[LOCK] [OPTIONAL] %s")) \
				% _short(p.get("display_name", "?")),
				_install_program.bind(p), not req["ok"])
	lines.append(Loc.t("ui.bbs_window.data_to_disk", "[color=#6b6]Daten → Diskette (Leerdiskette nötig).[/color]"))
	lines.append(Loc.t("ui.bbs_window.programs_to_workbench", "[color=#6b6]Programme → direkt installiert (Werkbank).[/color]"))
	_screen.text = "\n".join(lines)
	_add_button(Loc.t("ui.bbs_window.back", "« Zurück"), _show_board)


func _install_program(program: Dictionary) -> void:
	var result := BBSManager.download_program(program)
	UIManager.toast(result["text"])
	if result["ok"]:
		_show_files()


func _show_messages(page := 0) -> void:
	_clear_buttons()
	var posts := _message_posts()
	var page_count := maxi(1, ceili(float(posts.size()) / float(MESSAGES_PER_PAGE)))
	page = clampi(page, 0, page_count - 1)
	var lines := [
		Loc.t("ui.bbs_window.messages_header", "[color=#8fd]■ NACHRICHTEN ■[/color]"),
		Loc.t("ui.bbs_window.messages_legend",
			"[color=#6b6]LIVE = Spielwelt · REK = quellennahe Rekonstruktion, kein Originalpost[/color]"),
		Loc.t("ui.bbs_window.message_page", "[color=#363]SEITE %d/%d · %d THREADS[/color]") %
			[page + 1, page_count, posts.size()], ""]
	var first := page * MESSAGES_PER_PAGE
	var last := mini(first + MESSAGES_PER_PAGE, posts.size())
	for index in range(first, last):
		var post := posts[index] as Dictionary
		var kind := _message_kind_label(post)
		var time := str(post.get("timestamp", "--:--"))
		lines.append("[color=#363]%02d · %s · %s[/color]  [color=#fd6]%s[/color]" % [
			index + 1, time, kind, str(post.get("from", "?"))])
		lines.append("[color=#8fd]%s[/color]" % str(post.get("subject", "")))
		lines.append(Loc.t("ui.bbs_window.open_thread_hint", "  RETURN/KLICK · THREAD OEFFNEN"))
		lines.append("")
		_add_button("%02d · %s" % [index + 1, _short(str(post.get("subject", "?")))],
			_open_message.bind(index, page))
	_screen.text = "\n".join(lines)
	if page > 0:
		_add_button(Loc.t("ui.bbs_window.previous_page", "‹ Vorige Seite"),
			_show_messages.bind(page - 1))
	if page + 1 < page_count:
		_add_button(Loc.t("ui.bbs_window.next_page", "Naechste Seite ›"),
			_show_messages.bind(page + 1))
	_add_button(Loc.t("ui.bbs_window.artist_archive", "Kuenstlerarchiv"), _show_archive_index)
	_add_button(Loc.t("ui.bbs_window.back", "« Zurück"), _show_board)


func _message_posts() -> Array:
	var board_id := str(BBSManager.current_board.get("id", ""))
	var posts: Array = []
	# Neue Reaktionen auf eigene Releases gehoeren auf die erste Seite. Vor der
	# Pagination lagen sie hinter Grundbestand und Archiv-Rekonstruktionen; das
	# Terminal meldete zwar neue Antworten, zeigte sie aber erst mehrere Seiten
	# spaeter. Der Rest bleibt stabil und deterministisch sortiert.
	posts.append_array(SceneReleaseManager.dynamic_posts(board_id))
	posts.append_array(BBSManager.messages())
	posts.append_array(BBSScene.archive_live_posts_for(board_id))
	posts.append_array(BBSScene.posts_for(board_id))
	var read_count := SceneReleaseManager.mark_feedback_read(board_id)
	if read_count > 0:
		QuestManager.note_action("bbs_read_reaction", read_count)
	return posts


func _open_message(index: int, page: int) -> void:
	var posts := _message_posts()
	if index < 0 or index >= posts.size():
		_show_messages(page)
		return
	_show_message_detail(posts[index], index, posts.size(), page)


func _show_message_detail(
		post: Dictionary, index: int, total: int, return_page: int) -> void:
	_clear_buttons()
	var kind := _message_kind_label(post)
	var lines := [
		Loc.t("ui.bbs_window.thread_header", "[color=#8fd]■ THREAD %02d/%02d ■[/color]") %
			[index + 1, total],
		"[color=#363]%s · %s[/color]" % [kind, str(post.get("timestamp", "--:--"))],
		Loc.t("ui.bbs_window.message_from", "[color=#fd6]Von: %s[/color]") %
			str(post.get("from", "?")),
		"[color=#8fd]%s[/color]" % str(post.get("subject", "")),
		"[color=#363]────────────────────────────────────────────────[/color]",
		str(post.get("body", "")), ""]
	if str(post.get("kind", "")) == "reconstructed":
		lines.append(Loc.t(
			"ui.bbs_window.reconstruction_disclaimer",
			"[color=#fd6]REDAKTION: Quellennahe Fiktion mit erfundenem Handle; kein historischer Originalpost.[/color]"))
		_append_source_summary(lines, post.get("source_ids", []),
			Loc.t("ui.bbs_window.source_patterns", "QUELLENMUSTER"))
	_screen.text = "\n".join(lines)
	if index > 0:
		_add_button(Loc.t("ui.bbs_window.previous_thread", "‹ Voriger Thread"),
			_open_message.bind(index - 1,
				floori(float(index - 1) / float(MESSAGES_PER_PAGE))))
	if index + 1 < total:
		_add_button(Loc.t("ui.bbs_window.next_thread", "Naechster Thread ›"),
			_open_message.bind(index + 1,
				floori(float(index + 1) / float(MESSAGES_PER_PAGE))))
	_add_button(Loc.t("ui.bbs_window.thread_list", "« Thread-Liste"),
		_show_messages.bind(return_page))
	_add_button(Loc.t("ui.bbs_window.back_to_board", "« Hauptbrett"), _show_board)


func _message_kind_label(post: Dictionary) -> String:
	if str(post.get("kind", "")) == "reconstructed":
		return Loc.t("ui.bbs_window.kind_reconstructed", "REK")
	return Loc.t("ui.bbs_window.kind_live", "LIVE")


func _show_archive_index() -> void:
	_clear_buttons()
	var lines := [
		Loc.t("ui.bbs_window.artist_archive_header", "[color=#8fd]■ MOD-KUENSTLERARCHIV ■[/color]"),
		Loc.t("ui.bbs_window.archive_intro_1",
			"[color=#fd6]DOKUMENTARISCHE RUECKSCHAU · NICHT DAS LIVE-BRETT[/color]"),
		Loc.t("ui.bbs_window.artist_archive_complete",
			"Jede vorhandene MOD-Datei erscheint im Register; kein Track verschwindet wegen einer offenen Zuordnung."),
		Loc.t("ui.bbs_window.artist_archive_truth",
			"Persoenliche Aussagen gibt es ausschliesslich als belegte, spaetere Rueckschau."), "",
		Loc.t("ui.bbs_window.artist_archive_stats",
			"[color=#6b6]%d MODS · %d CREDITS · %d MIT BELEGTER RUECKSCHAU[/color]") % [
			BBSScene.artist_catalog_track_count(),
			BBSScene.playable_artist_catalog().size(),
			BBSScene.artist_catalog_sourced_count()],
		Loc.t("ui.bbs_window.artist_archive_unresolved",
			"[color=#fd6]%d MODS MIT UNGEKLAERTEM ODER LEEREM CREDIT[/color]") %
			BBSScene.artist_catalog_unresolved_track_count(), "",
		Loc.t("ui.bbs_window.artist_archive_layers", "DREI GETRENNTE EBENEN"),
		Loc.t("ui.bbs_window.artist_archive_layer_1", "1  IM SPIEL HOERBAR · physische MOD-Datei vorhanden"),
		Loc.t("ui.bbs_window.artist_archive_layer_2", "2  CREDIT-STATUS · geprueft oder offen"),
		Loc.t("ui.bbs_window.artist_archive_layer_3", "3  RUECKSCHAU · nur mit verlinkter Originalquelle")]
	_screen.text = "\n".join(lines)
	_add_button(Loc.t("ui.bbs_window.all_mod_artists", "Alle MOD-Kuenstler"),
		_show_artist_catalog)
	_add_button(Loc.t("ui.bbs_window.sourced_retrospectives_count", "Belegte Archivtexte (%d)") %
		BBSScene.archive_echoes().size(), _show_archive_echo_index)
	_add_button(Loc.t("ui.bbs_window.catalog_method", "Katalog & Methodik"),
		_show_catalog_methodology)
	_add_button(Loc.t("ui.bbs_window.back_to_board", "« Hauptbrett"), _show_board)


func _show_artist_catalog(page := 0) -> void:
	_clear_buttons()
	var catalog := BBSScene.playable_artist_catalog()
	var page_count := maxi(1, ceili(float(catalog.size()) / float(ARTISTS_PER_PAGE)))
	page = clampi(page, 0, page_count - 1)
	var lines := [
		Loc.t("ui.bbs_window.artist_register_header", "[color=#8fd]■ ALLE MOD-KUENSTLER ■[/color]"),
		Loc.t("ui.bbs_window.artist_register_page",
			"[color=#363]SEITE %d/%d · %d CREDITS · %d MODS[/color]") % [
			page + 1, page_count, catalog.size(), BBSScene.artist_catalog_track_count()],
		Loc.t("ui.bbs_window.artist_register_legend",
			"[color=#6b6]BELEGT = Originalquelle · KATALOG = keine erfundene Aussage · OFFEN = Credit ungeklärt[/color]"), ""]
	var first := page * ARTISTS_PER_PAGE
	var last := mini(first + ARTISTS_PER_PAGE, catalog.size())
	for index in range(first, last):
		var artist := catalog[index] as Dictionary
		var status := Loc.t("ui.bbs_window.artist_status_sourced", "BELEGT") \
			if bool(artist.get("sourced", false)) else (
				Loc.t("ui.bbs_window.artist_status_open", "OFFEN") \
				if bool(artist.get("unresolved", false)) \
				else Loc.t("ui.bbs_window.artist_status_catalog", "KATALOG"))
		var color := "6b6" if bool(artist.get("sourced", false)) else (
			"fd6" if bool(artist.get("unresolved", false)) else "8fd")
		lines.append("[color=#363]%03d · %s · %s[/color]  [color=#%s]%s[/color]" % [
			index + 1, _artist_year_span(artist), status, color,
			str(artist.get("name", "?"))])
		lines.append(Loc.t("ui.bbs_window.artist_track_count", "  %d spielbare MOD-Datei(en) · %d Credit(s) offen") % [
			int(artist.get("track_count", 0)), int(artist.get("review_count", 0))])
		_add_button("%03d · %s" % [index + 1, _short(str(artist.get("name", "?")))],
			_show_artist_detail.bind(index, page, 0))
	_screen.text = "\n".join(lines)
	if page > 0:
		_add_button(Loc.t("ui.bbs_window.previous_page", "‹ Vorige Seite"),
			_show_artist_catalog.bind(page - 1))
	if page + 1 < page_count:
		_add_button(Loc.t("ui.bbs_window.next_page", "Naechste Seite ›"),
			_show_artist_catalog.bind(page + 1))
	_add_button(Loc.t("ui.bbs_window.archive_overview", "« Archiv-Uebersicht"),
		_show_archive_index)
	_add_button(Loc.t("ui.bbs_window.back_to_board", "« Hauptbrett"), _show_board)


func _show_artist_detail(
		artist_index: int, catalog_page: int, track_page := 0) -> void:
	var catalog := BBSScene.playable_artist_catalog()
	if artist_index < 0 or artist_index >= catalog.size():
		_show_artist_catalog(catalog_page)
		return
	_clear_buttons()
	var artist := catalog[artist_index] as Dictionary
	var tracks := artist.get("tracks", []) as Array
	var page_count := maxi(1, ceili(float(tracks.size()) / float(ARTIST_TRACKS_PER_PAGE)))
	track_page = clampi(track_page, 0, page_count - 1)
	var aliases := artist.get("aliases", []) as Array
	var lines := [
		Loc.t("ui.bbs_window.artist_card_header", "[color=#8fd]■ KUENSTLERKARTE %03d/%03d ■[/color]") %
			[artist_index + 1, catalog.size()],
		"[color=#fd6]%s[/color]" % str(artist.get("name", "?")),
		Loc.t("ui.bbs_window.artist_card_range", "%s · %d spielbare MOD-Datei(en)") % [
			_artist_year_span(artist), int(artist.get("track_count", 0))],
		Loc.t("ui.bbs_window.artist_card_aliases", "Roh-Credits: %s") % ", ".join(aliases), ""]
	if bool(artist.get("sourced", false)):
		lines.append(Loc.t("ui.bbs_window.artist_card_sourced",
			"[color=#6b6]BELEGTE RUECKSCHAU VERFUEGBAR · Quelle und Jahr werden am Text gezeigt.[/color]"))
	else:
		lines.append(Loc.t("ui.bbs_window.artist_card_unsourced",
			"[color=#fd6]KEINE KUENSTLERAUSSAGE · Diese Karte zeigt nur den lokalen MOD-Katalog.[/color]"))
	lines.append(Loc.t("ui.bbs_window.artist_track_page",
		"[color=#363]TRACKS · SEITE %d/%d · GRUEN = CREDIT GEPRUEFT[/color]") % [
			track_page + 1, page_count])
	lines.append("")
	var first := track_page * ARTIST_TRACKS_PER_PAGE
	var last := mini(first + ARTIST_TRACKS_PER_PAGE, tracks.size())
	for index in range(first, last):
		var track := tracks[index] as Dictionary
		var status := Loc.t("ui.bbs_window.credit_checked", "CREDIT GEPRUEFT") \
			if bool(track.get("verified", false)) \
			else Loc.t("ui.bbs_window.credit_open", "CREDIT PRUEFEN")
		var color := "6b6" if bool(track.get("verified", false)) else "fd6"
		lines.append("[color=#%s]%03d · %d · %s[/color]" % [
			color, index + 1, int(track.get("year", 0)), str(track.get("title", "?"))])
		lines.append("  [color=#363][MOD OK] %s[/color]" % status)
	_screen.text = "\n".join(lines)
	for echo_index in artist.get("echo_indexes", []):
		var echoes := BBSScene.archive_echoes()
		if int(echo_index) >= 0 and int(echo_index) < echoes.size():
			var echo := echoes[int(echo_index)] as Dictionary
			_add_button(Loc.t("ui.bbs_window.open_sourced_retrospective", "Belegte Rueckschau: %s") %
				_short(str(echo.get("subject", "?"))),
				_show_archive_echo.bind(int(echo_index)))
	if track_page > 0:
		_add_button(Loc.t("ui.bbs_window.previous_tracks", "‹ Vorige Tracks"),
			_show_artist_detail.bind(artist_index, catalog_page, track_page - 1))
	if track_page + 1 < page_count:
		_add_button(Loc.t("ui.bbs_window.next_tracks", "Naechste Tracks ›"),
			_show_artist_detail.bind(artist_index, catalog_page, track_page + 1))
	_add_button(Loc.t("ui.bbs_window.artist_register_back", "« Kuenstlerregister"),
		_show_artist_catalog.bind(catalog_page))
	_add_button(Loc.t("ui.bbs_window.archive_overview", "« Archiv-Uebersicht"),
		_show_archive_index)


func _artist_year_span(artist: Dictionary) -> String:
	var first := int(artist.get("first_year", 0))
	var last := int(artist.get("last_year", 0))
	if first <= 0:
		return Loc.t("ui.bbs_window.year_unknown", "Jahr offen")
	if first == last:
		return str(first)
	return "%d-%d" % [first, last]


func _show_archive_echo_index(page := 0) -> void:
	_clear_buttons()
	var echoes := BBSScene.archive_echoes()
	var page_count := maxi(1, ceili(float(echoes.size()) / float(ECHOES_PER_PAGE)))
	page = clampi(page, 0, page_count - 1)
	var lines := [
		Loc.t("ui.bbs_window.archive_header", "[color=#8fd]■ ARCHIV-ECHOS ■[/color]"),
		Loc.t("ui.bbs_window.archive_intro_2",
			"Reale Namen erscheinen hier nur als redaktionell paraphrasierte, spaetere Interviews."),
		Loc.t("ui.bbs_window.archive_intro_3",
			"Jeder Eintrag nennt Quelle und Interviewjahr; erfundene Antworten gibt es nicht."),
		Loc.t("ui.bbs_window.archive_echo_page", "[color=#363]SEITE %d/%d · %d EINTRAEGE[/color]") %
			[page + 1, page_count, echoes.size()], ""]
	var first := page * ECHOES_PER_PAGE
	var last := mini(first + ECHOES_PER_PAGE, echoes.size())
	for index in range(first, last):
		var echo := echoes[index] as Dictionary
		var entry_label := Loc.t("ui.bbs_window.original_artist", "ORIGINAL-KUENSTLER") \
			if str(echo.get("entry_type", "archive")) == "artist" \
			else Loc.t("ui.bbs_window.archive_entry", "ARCHIV")
		lines.append("[color=#363]%02d · %s · %d[/color]  [color=#fd6]%s[/color]" % [
			index + 1, entry_label, int(echo.get("source_year", 0)),
			str(echo.get("author", "?"))])
		lines.append("[color=#8fd]%s[/color]" % str(echo.get("subject", "")))
		_add_button("%02d · %s" % [index + 1, _short(str(echo.get("author", "?")))],
			_show_archive_echo.bind(index))
	_screen.text = "\n".join(lines)
	if page > 0:
		_add_button(Loc.t("ui.bbs_window.previous_page", "‹ Vorige Seite"),
			_show_archive_echo_index.bind(page - 1))
	if page + 1 < page_count:
		_add_button(Loc.t("ui.bbs_window.next_page", "Naechste Seite ›"),
			_show_archive_echo_index.bind(page + 1))
	_add_button(Loc.t("ui.bbs_window.archive_overview", "« Archiv-Uebersicht"),
		_show_archive_index)


func _show_archive_echo(index: int) -> void:
	var echoes := BBSScene.archive_echoes()
	if index < 0 or index >= echoes.size():
		_show_archive_echo_index()
		return
	_clear_buttons()
	var echo := echoes[index] as Dictionary
	var entry_label := Loc.t(
		"ui.bbs_window.original_artist_sourced", "ORIGINAL-KUENSTLER · BELEGTE RUECKSCHAU") \
		if str(echo.get("entry_type", "archive")) == "artist" \
		else Loc.t("ui.bbs_window.archive_editorial", "ARCHIV · REDAKTIONELLE RUECKSCHAU")
	var lines := [
		Loc.t("ui.bbs_window.archive_echo_header",
			"[color=#8fd]■ ARCHIV-ECHO %02d/%02d ■[/color]") % [index + 1, echoes.size()],
		Loc.t("ui.bbs_window.archive_not_live",
			"[color=#fd6]SPAETERE RUECKSCHAU · KEIN LIVE-POST AUS DEM SPIELJAHR[/color]"),
		"[color=#6b6]%s[/color]" % entry_label,
		"[color=#363]%d · %s[/color]" % [
			int(echo.get("source_year", 0)), str(echo.get("author", "?"))],
		"[color=#8fd]%s[/color]" % str(echo.get("subject", "")),
		"[color=#363]────────────────────────────────────────────────[/color]",
		str(echo.get("body", "")), ""]
	_append_source_summary(lines, echo.get("source_ids", []),
		Loc.t("ui.bbs_window.archive_sources", "BELEGE"))
	_screen.text = "\n".join(lines)
	for source in BBSScene.archive_sources_for(echo.get("source_ids", [])):
		_add_button(Loc.t("ui.bbs_window.source_button", "Quelle: %s") %
			_short(str(source.get("archive", "Archiv"))),
			_show_archive_source.bind(source, index))
	if index > 0:
		_add_button(Loc.t("ui.bbs_window.previous_echo", "‹ Voriges Echo"),
			_show_archive_echo.bind(index - 1))
	if index + 1 < echoes.size():
		_add_button(Loc.t("ui.bbs_window.next_echo", "Naechstes Echo ›"),
			_show_archive_echo.bind(index + 1))
	_add_button(Loc.t("ui.bbs_window.archive_list", "« Archiv-Liste"),
		_show_archive_echo_index.bind(floori(float(index) / float(ECHOES_PER_PAGE))))
	_add_button(Loc.t("ui.bbs_window.back_to_board", "« Hauptbrett"), _show_board)


func _show_archive_source(source: Dictionary, return_index: int) -> void:
	_clear_buttons()
	var lines := [
		Loc.t("ui.bbs_window.source_header", "[color=#8fd]■ QUELLENNACHWEIS ■[/color]"),
		"[color=#fd6]%s[/color]" % str(source.get("title", "?")),
		"%s · %d" % [str(source.get("archive", "?")), int(source.get("year", 0))], "",
		str(source.get("note", "")), "",
		Loc.t("ui.bbs_window.source_url", "[color=#363]URL[/color]  %s") %
			str(source.get("url", "")), "",
		Loc.t("ui.bbs_window.source_editorial_note",
			"[color=#6b6]Im Spiel werden nur kurze redaktionelle Paraphrasen verwendet.[/color]")]
	_screen.text = "\n".join(lines)
	var url := str(source.get("url", ""))
	var source_button := _add_button(
		Loc.t("ui.bbs_window.open_source_browser", "Quelle im Browser oeffnen"),
		_open_archive_url.bind(url), not url.begins_with("https://"))
	source_button.tooltip_text = url
	_add_button(Loc.t("ui.bbs_window.back_to_echo", "« Zurueck zum Echo"),
		_show_archive_echo.bind(return_index))
	_add_button(Loc.t("ui.bbs_window.archive_list", "« Archiv-Liste"),
		_show_archive_echo_index.bind(floori(float(return_index) / float(ECHOES_PER_PAGE))))


func _show_catalog_methodology() -> void:
	_clear_buttons()
	var sources := BBSScene.artist_catalog_sources()
	var lines := [
		Loc.t("ui.bbs_window.catalog_method_header", "[color=#8fd]■ KATALOG & METHODIK ■[/color]"),
		Loc.t("ui.bbs_window.catalog_method_1",
			"Der Spielkatalog zaehlt nur vorhandene MOD-Dateien. Sichere Schreibvarianten werden zusammengefuehrt; zweifelhafte Namen bleiben getrennt."),
		Loc.t("ui.bbs_window.catalog_method_2",
			"AMP und ExoticA dienen als Nachschlagewerke, ersetzen aber keine noch offene Einzelpruefung."), "",
		Loc.t("ui.bbs_window.catalog_sources", "[color=#363]KATALOGQUELLEN[/color]")]
	for source in sources:
		lines.append("[color=#6b6]· %s · %s[/color]" % [
			str(source.get("archive", "?")), str(source.get("title", "?"))])
		_add_button(Loc.t("ui.bbs_window.source_button", "Quelle: %s") %
			_short(str(source.get("archive", "Archiv"))),
			_show_catalog_source.bind(source))
	_screen.text = "\n".join(lines)
	_add_button(Loc.t("ui.bbs_window.archive_overview", "« Archiv-Uebersicht"),
		_show_archive_index)


func _show_catalog_source(source: Dictionary) -> void:
	_clear_buttons()
	var lines := [
		Loc.t("ui.bbs_window.source_header", "[color=#8fd]■ QUELLENNACHWEIS ■[/color]"),
		"[color=#fd6]%s[/color]" % str(source.get("title", "?")),
		"%s · %d" % [str(source.get("archive", "?")), int(source.get("year", 0))], "",
		str(source.get("note", "")), "",
		Loc.t("ui.bbs_window.source_url", "[color=#363]URL[/color]  %s") %
			str(source.get("url", ""))]
	_screen.text = "\n".join(lines)
	var url := str(source.get("url", ""))
	var source_button := _add_button(
		Loc.t("ui.bbs_window.open_source_browser", "Quelle im Browser oeffnen"),
		_open_archive_url.bind(url), not url.begins_with("https://"))
	source_button.tooltip_text = url
	_add_button(Loc.t("ui.bbs_window.back_to_method", "« Zurueck zur Methodik"),
		_show_catalog_methodology)


func _append_source_summary(lines: Array, source_ids: Array, heading: String) -> void:
	var sources := BBSScene.archive_sources_for(source_ids)
	if sources.is_empty():
		return
	lines.append("[color=#363]%s[/color]" % heading)
	for source in sources:
		lines.append("[color=#6b6]· %s · %s · %d[/color]" % [
			str(source.get("archive", "?")), str(source.get("title", "?")),
			int(source.get("year", 0))])


func _open_archive_url(url: String) -> void:
	if not url.begins_with("https://"):
		return
	OS.shell_open(url)


func _show_scene_uploads() -> void:
	_clear_buttons()
	var lines := [
		Loc.t("ui.bbs_window.own_release_header", "[color=#8fd]■ EIGENE BYTEWERK-RELEASES ■[/color]"),
		Loc.t("ui.bbs_window.upload_mirrors", "[color=#6b6]Upload = Spiegelung. Deine Masterdisk bleibt in der Box.[/color]"),
		"",
	]
	var releases := BBSManager.scene_uploads()
	if releases.is_empty():
		lines.append(Loc.t("ui.bbs_window.no_new_release", "Kein neues Release für dieses Board."))
		lines.append("")
		lines.append(Loc.t("ui.bbs_window.verified_release_only", "Nur verifizierte Releases mit gesehenem Intro werden angeboten;"))
		lines.append(Loc.t("ui.bbs_window.no_duplicate_uploads", "bereits hochgeladene Serien erscheinen nicht doppelt."))
	else:
		for disk: Disk in releases:
			var data: Dictionary = disk.release_data
			var presenting := str(data.get("presenting", data.get("player_handle", "ANON")))
			lines.append("[color=#8fd]%s[/color]" % disk.display_name())
			lines.append("  %s · Q%d · %s" % [presenting,
				int(data.get("quality", disk.patch_score)),
				disk.release_serial if disk.release_serial != "" else Loc.t("ui.bbs_window.no_serial", "ohne Seriennummer")])
			lines.append("")
			_add_button("↑ %s" % _short(disk.display_name()), _upload_release.bind(disk))
	_screen.text = "\n".join(lines)
	_add_button(Loc.t("ui.bbs_window.scene_status", "Szene-Status"), _show_scene_status)
	_add_button(Loc.t("ui.bbs_window.back", "« Zurück"), _show_board)


func _upload_release(disk: Disk) -> void:
	var before_count := DiskManager.disks.size()
	var result := BBSManager.upload_scene_release(disk)
	# Safety-Net fuer die zentrale Designregel: Ein Upload darf das physische
	# Exemplar niemals verbrauchen. Der Manager arbeitet nur mit Serien-IDs.
	if bool(result.get("ok", false)) and DiskManager.disks.size() != before_count:
		push_error("BBS upload consumed a physical disk")
	UIManager.toast(str(result.get("text", "")))
	_show_scene_uploads()


func _show_scene_status() -> void:
	_clear_buttons()
	var lines := [Loc.t("ui.bbs_window.scene_status_header", "[color=#8fd]■ SZENE-STATUS ■[/color]"), ""]
	var handle := SceneReleaseManager.scene_handle
	if handle == "" or handle == "<null>":
		handle = Loc.t("ui.bbs_window.no_handle", "KEIN HANDLE")
	lines.append(Loc.t("ui.bbs_window.handle_row", "Handle: [color=#fd6]%s[/color]") % handle)
	lines.append(Loc.t("ui.bbs_window.recognition_row", "Anerkennung: [color=#8fd]%d[/color]") %
		SceneReleaseManager.scene_recognition)
	lines.append("")
	lines.append(Loc.t("ui.bbs_window.group_reputation", "[color=#8fd]■ GRUPPENRUF ■[/color]"))
	var statuses := SceneReleaseManager.all_group_status()
	for status: Dictionary in statuses:
		if not bool(status.get("active", true)):
			continue
		var next := int(status.get("next_threshold", -1))
		var suffix := Loc.t("ui.bbs_window.next_goal", " · nächstes Ziel %d") % next if next >= 0 \
			else Loc.t("ui.bbs_window.highest_tier", " · höchste Stufe")
		lines.append("[color=#fd6]%s[/color]  %d · %s%s" % [
			str(status.get("name", status.get("id", "?"))),
			int(status.get("reputation", 0)), str(status.get("tier_name", status.get("tier", Loc.t("ui.bbs_window.unknown", "unbekannt")))), suffix])
	if statuses.is_empty():
		lines.append(Loc.t("ui.bbs_window.no_group_reputation", "Noch keine Gruppe hat dich auf dem Radar."))

	var distribution := SceneReleaseManager.game_distribution_status()
	if not distribution.is_empty() and not str(distribution.get("mode", "")).is_empty():
		lines.append("")
		lines.append(Loc.t("ui.bbs_window.game_distribution", "[color=#8fd]■ EIGENES SPIEL · DISTRIBUTION ■[/color]"))
		lines.append("[color=#fd6]%s[/color]" % str(distribution.get("title",
			Loc.t("ui.bbs_window.own_game", "Eigenes Spiel"))))
		if str(distribution.get("mode", "")) == "paid":
			lines.append(Loc.t("ui.bbs_window.paid_distribution", "Kleinserie · bisher %d DM · noch %d Wochenabrechnung(en)") % [
				int(distribution.get("total_income", 0)),
				int(distribution.get("payments_left", 0))])
		else:
			lines.append(Loc.t("ui.bbs_window.free_distribution", "Freie Club-Distribution · Reichweite statt Verkaufserlös"))

	var offers := _cooperation_offers()
	lines.append("")
	lines.append(Loc.t("ui.bbs_window.cooperations", "[color=#8fd]■ KOOPERATIONEN ■[/color]"))
	if offers.is_empty():
		lines.append(Loc.t("ui.bbs_window.no_cooperation_offer", "Noch kein offenes Angebot. Releases und passende Styles bauen Ruf auf."))
	else:
		for offer in offers:
			var offer_id := str(offer.get("group_id", offer.get("id", "")))
			var offer_name := str(offer.get("group_name", offer.get("name", offer_id)))
			lines.append("[color=#fd6]%s[/color] · %s" % [offer_name,
				str(offer.get("text", Loc.t("ui.bbs_window.offers_cooperation", "bietet eine Zusammenarbeit an.")))])
			if offer_id != "":
				_add_button(Loc.t("ui.bbs_window.coop_button", "Koop: %s") % _short(offer_name), _accept_cooperation.bind(offer_id))
	_screen.text = "\n".join(lines)
	_add_button(Loc.t("ui.bbs_window.back", "« Zurück"), _show_board)


func _cooperation_offers() -> Array:
	var raw: Variant = SceneReleaseManager.cooperation_offers
	var out: Array = []
	if raw is Dictionary:
		raw = raw.values()
	if raw is not Array:
		return out
	for value in raw:
		if value is Dictionary and str(value.get("status", "offered")) in ["offered", "pending", "open"]:
			out.append(value)
	return out


func _accept_cooperation(id: String) -> void:
	var result := SceneReleaseManager.accept_cooperation(id)
	UIManager.toast(str(result.get("text", "")))
	_show_scene_status()


func _show_classifieds() -> void:
	_clear_buttons()
	var lines := [Loc.t("ui.bbs_window.classifieds_header", "[color=#8fd]■ KLEINANZEIGEN ■[/color]"), ""]
	for c in BBSManager.classifieds():
		lines.append("[color=#6b6]•[/color] %s" % c.get("text", ""))
		lines.append("")
	_screen.text = "\n".join(lines)
	_add_button(Loc.t("ui.bbs_window.back", "« Zurück"), _show_board)


func _show_assistant() -> void:
	_clear_buttons()
	var lines := [
		"[color=#8fd]%s[/color]" % BBSManager.assistant_name(),
		"[color=#363]========================================================[/color]",
		Loc.t("ui.bbs_window.local_knowledge_base", "[color=#6b6]Lokale Wissensbasis · kein Internetdienst · Verlauf gespeichert[/color]"),
		"",
	]
	var history: Array = BBSManager.assistant_history()
	if history.is_empty():
		lines.append(Loc.t("ui.bbs_window.assistant_welcome", "[color=#fd6]SYSOP>[/color] Frag kurz nach AUFTRAG, DOWNLOAD, UPLOAD, VIRUS, HDD oder KOSTEN."))
	else:
		for entry: Dictionary in history:
			var role := str(entry.get("role", "assistant"))
			var prefix := Loc.t("ui.bbs_window.you_prompt", "DU>") if role == "user" else "SYSOP>"
			var color := "8fd" if role == "user" else "fd6"
			lines.append("[color=#%s]%s[/color] %s" % [color, prefix, str(entry.get("text", ""))])
			lines.append("")
	_screen.text = "\n".join(lines)
	_buttons.add_child(Bezel.dim_label(Loc.t("ui.bbs_window.deine_frage", "DEINE FRAGE"), 10))
	_assistant_input = LineEdit.new()
	_assistant_input.name = "AssistantInput"
	_assistant_input.placeholder_text = Loc.t("ui.bbs_window.kurze_frage_eingeben", "Kurze Frage eingeben ...")
	_assistant_input.max_length = 120
	_assistant_input.custom_minimum_size = Vector2(210, 38)
	_assistant_input.text_submitted.connect(func(_value: String) -> void: _send_assistant())
	_buttons.add_child(_assistant_input)
	var send := _add_button(Loc.t("ui.bbs_window.send_return", "SENDEN / RETURN"), _send_assistant)
	send.name = "AssistantSend"
	_buttons.add_child(HSeparator.new())
	for quick in [Loc.t("ui.bbs_window.quick_mission", "AUFTRAG"), "DOWNLOAD", "VIRUS / X-COPY", "HDD / WORKBENCH", Loc.t("ui.bbs_window.quick_costs", "KOSTEN")]:
		_add_button(quick, _assistant_quick.bind(quick))
	_add_button(Loc.t("ui.bbs_window.back", "« Zurück"), _show_board)
	_assistant_input.grab_focus()


func _assistant_quick(text: String) -> void:
	if _assistant_input != null:
		_assistant_input.text = text
	_send_assistant()


func _send_assistant() -> void:
	if _assistant_input == null:
		return
	var result := BBSManager.assistant_send(_assistant_input.text)
	if not bool(result.get("ok", false)):
		UIManager.toast(str(result.get("text", "")))
		return
	_show_assistant()


# ------------------------------------------------------------- Aktionen

func _begin_dial(board_id: String) -> void:
	var board := BBSManager.board_by_id(board_id)
	_dialing = true
	_dial_target = board_id
	_clear_buttons()
	_dial_lines = [
		"ATZ",
		"OK",
		"AT&F E1 V1 X4",
		"OK",
		"ATDT%s" % str(board.get("number", "")).replace("-", ""),
		"",
		Loc.t("ui.bbs_window.dialing", "WÄHLE …"),
		"[color=#6b6]RINGBACK · HANDSHAKE · CARRIER[/color]",
		"[color=#6b6]NEGOTIATING V.32 / MNP5 ...[/color]",
	]
	_dial_index = 0
	_dial_time = 0.0
	_screen.text = ""
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.call("modem_dial")   # iconischer Einwahl-Handshake (synthetisiert)


func _dial_step(delta: float) -> void:
	_dial_time += delta
	if _dial_time < 0.55:
		return
	_dial_time = 0.0
	if _dial_index < _dial_lines.size():
		_screen.text += _dial_lines[_dial_index] + "\n"
		_dial_index += 1
		return
	# Sequenz fertig -> echte Einwahl
	_dialing = false
	var result := BBSManager.dial(_dial_target)
	if result["ok"]:
		_screen.text += "[color=#8fd]%s[/color]\n" % result["text"]
		UIManager.toast(result["text"])
		# _refresh kommt über connection_changed; hier nur Board-Ansicht sichern
	else:
		_screen.text += "[color=#f88]%s[/color]\n" % result["text"]
		UIManager.toast(result["text"])
		_add_button(Loc.t("ui.bbs_window.back", "« Zurück"), _show_board_list)


func _download(file_entry: Dictionary) -> void:
	UIManager.open_bbs_carrier(file_entry)


func _hang_up() -> void:
	BBSManager.hang_up()
	UIManager.toast(Loc.t("ui.bbs_window.no_carrier_aufgelegt", "NO CARRIER. Aufgelegt."))


func _short(text: String) -> String:
	return text if text.length() <= 16 else text.substr(0, 15) + "…"
