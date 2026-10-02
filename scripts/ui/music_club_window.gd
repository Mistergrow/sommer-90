extends RetroWindow
## Computerclub — MOD-Bibliothek. Was es im aktuellen Jahr schon gibt und du
## noch nicht hast: vorhören und auf Diskette kopieren (→ daheim auf der Anlage).
## Die Bibliothek wächst mit den Jahren (Living Timeline).

var _list: ItemList
var _info: Label
var _rows: Array = []


func _init() -> void:
	title = Loc.t("ui.music_club_window.computerclub_mod_bibliothek", "COMPUTERCLUB — MOD-BIBLIOTHEK")
	win_size = Vector2(460, 360)


func _ready() -> void:
	super._ready()
	MusicManager.music_changed.connect(_refresh)

	_info = Bezel.lcd_label("", Palette.LCD_GREEN, 12)
	content.add_child(_info)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(_i: int) -> void: _copy())
	content.add_child(_list)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	buttons.add_child(make_button(Loc.t("ui.music_club_window.vorhoren", "▶ Vorhören"), _preview))
	buttons.add_child(make_button(Loc.t("ui.music_club_window.auf_diskette", "⬇ Auf Diskette"), _copy))
	buttons.add_child(make_button(Loc.t("ui.music_club_window.stopp", "■ Stopp"), MusicManager.stop))
	content.add_child(buttons)

	var hint := Label.new()
	hint.text = Loc.t("ui.music_club_window.neue_mods_tauchen_mit_den_jahren", "Neue Mods tauchen mit den Jahren auf. Kopiertes läuft daheim auf der Anlage.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	content.add_child(hint)

	_refresh()


func _refresh() -> void:
	var sel := _list.get_selected_items()
	var keep := sel[0] if not sel.is_empty() else -1
	_list.clear()
	_rows.clear()
	var lib := MusicManager.club_library()
	for t in lib:
		var star := "★ " if t.get("highlight", false) else "   "
		_list.add_item("%s%s — %s  (%d)" % [star, t.get("title", "?"), t.get("author", "?"), int(t.get("year", 0))])
		_rows.append(t.get("id", ""))
	if keep >= 0 and keep < _list.item_count:
		_list.select(keep)
	_info.text = Loc.t("ui.music_club_window.verfugbar_d_deine_sammlung_d_tracks", "Verfügbar %d · deine Sammlung %d Tracks") % [lib.size(), MusicManager.owned.size()]


func _selected_id() -> String:
	var sel := _list.get_selected_items()
	if sel.is_empty() or sel[0] >= _rows.size():
		return ""
	return _rows[sel[0]]


func _preview() -> void:
	var id := _selected_id()
	if id == "":
		UIManager.toast(Loc.t("ui.music_club_window.erst_einen_mod_wahlen", "Erst einen Mod wählen."))
		return
	MusicManager.preview(id)


func _copy() -> void:
	var id := _selected_id()
	if id == "":
		UIManager.toast(Loc.t("ui.music_club_window.erst_einen_mod_wahlen", "Erst einen Mod wählen."))
		return
	if MusicManager.collect(id):
		UIManager.toast(Loc.t("ui.music_club_window.auf_diskette_kopiert_s_lauft_jetzt", "Auf Diskette kopiert: %s — läuft jetzt daheim auf der Anlage.") % MusicManager.track(id).get("title", "?"))
	_refresh()
