extends RetroWindow
## Die Anlage — spielt deine gesammelten MOD-Tracks (nativ, ProTracker).
## Nur was du besitzt, steht in der Liste; neue Mods findest du unterwegs.

var _list: ItemList
var _now: Label
var _rows: Array = []  # track_ids parallel zur Liste


func _init() -> void:
	title = Loc.t("ui.music_window.anlage_mod_player", "ANLAGE — MOD-PLAYER")
	win_size = Vector2(560, 400)


func _ready() -> void:
	super._ready()
	MusicManager.music_changed.connect(_refresh)

	_now = Bezel.lcd_label("", Palette.LCD_GREEN, 12)
	content.add_child(_now)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(_i: int) -> void: _play_selected())
	content.add_child(_list)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	buttons.add_child(make_button(Loc.t("ui.music_window.abspielen", "▶ Abspielen"), _play_selected))
	buttons.add_child(make_button(Loc.t("ui.music_window.stopp", "■ Stopp"), MusicManager.stop))
	buttons.add_child(make_button(Loc.t("ui.music_window.nachster", "⏭ Nächster"), MusicManager.play_next))
	buttons.add_child(make_button(Loc.t("ui.music_window.mixtape", "● Mixtape"), UIManager.open_mixtape))
	content.add_child(buttons)
	content.add_child(make_button(Loc.t("ui.mods.button", "MOD-Ordner & Soundtrack"),
		func() -> void:
			UIManager.toggle_window("win_user_mods", func() -> Control:
				return load("res://scripts/ui/mod_library_window.gd").new())))

	var hint := Label.new()
	hint.text = Loc.t("ui.music_window.neue_mods_gibt_s_beim_computerclub", "Neue Mods gibt's beim Computerclub, im BBS oder beim Tausch — auf Diskette mitnehmen.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	content.add_child(hint)

	_refresh()


func _refresh() -> void:
	var sel := _list.get_selected_items()
	var keep := sel[0] if not sel.is_empty() else -1
	_list.clear()
	_rows.clear()
	for t in MusicManager.owned_tracks():
		var mark := "♪ " if t.get("id", "") == MusicManager.current else "   "
		var resolved := MusicManager.playback_track(str(t.get("id", "")))
		var caption := "%s%s" % [mark, t.get("title", "?")]
		if bool(resolved.get("fallback", false)):
			caption += " → " + str(resolved.get("title", "?"))
		_list.add_item(caption)
		_list.set_item_tooltip(_list.item_count - 1, "%s — %s" % [
			resolved.get("title", "?"), resolved.get("author", "")])
		_rows.append(t.get("id", ""))
	if _rows.is_empty():
		_list.add_item(Loc.t("ui.music_window.noch_keine_mod_diskette_in_deiner", "— Noch keine MOD-Diskette in deiner Sammlung —"))
		_list.set_item_disabled(0, true)
	if keep >= 0 and keep < _list.item_count:
		_list.select(keep)
	if MusicManager.is_playing():
		var t := MusicManager.playback_track(MusicManager.current)
		_now.text = Loc.t("ui.music_window.s_s", "▶ %s — %s") % [t.get("title", "?"), t.get("author", "?")]
	else:
		_now.text = Loc.t("ui.music_window.keine_mod_diskette", "— Keine MOD-Diskette —") \
			if _rows.is_empty() else Loc.t("ui.music_window.stereo_off", "— Anlage aus —")


func _play_selected() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty() or sel[0] >= _rows.size():
		UIManager.toast(Loc.t("ui.music_window.erst_einen_track_wahlen", "Erst einen Track wählen."))
		return
	MusicManager.play(_rows[sel[0]])
