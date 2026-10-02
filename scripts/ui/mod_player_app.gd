extends WbApp
## MOD-PLAYER — Modul-Player im Stil der Amiga-Tracker/Player (Homage, nicht-
## kommerziell). Spielt die gesammelten `.mod`-Module über die native Wiedergabe
## (MusicManager): Modulinfo, animierte 4/6/8-Kanal-VU, Pos/Pattern-Zähler, Transport
## (Play/Stop/Prev/Next/Eject), Lautstärke, scrollbare Modulliste.

const VISIBLE := 10
const ROW_H := 15.0
const LIST_Y := 214.0

var _sel := 0
var _scroll := 0
var _scope_t := 0.0
var _pos := 0
var _patt := 0
var _postime := 0.0


func _init() -> void:
	app_title = "PRO-TRACKER  v2.3   ·   MOD-PLAYER"
	app_bg = Color8(18, 22, 40)
	app_bar = Color8(40, 74, 96)
	app_accent = Color8(110, 170, 230)


func _build_app() -> void:
	MusicManager.music_changed.connect(_on_music_changed)
	# aktuelle Auswahl = laufendes Modul
	var owned := _owned()
	if MusicManager.current != "":
		_sel = maxi(0, owned.find(MusicManager.current))
	_rebuild()


func _on_music_changed() -> void:
	_rebuild()


func _owned() -> Array:
	return MusicManager.owned_tracks().map(func(t: Dictionary) -> String: return str(t.get("id", "")))


func _rebuild() -> void:
	clear_widgets()
	# Transport
	add_button("|◀", Rect2(20, 176, 40, 22), _prev, app_accent)
	add_button("▶ PLAY", Rect2(64, 176, 74, 22), _play, Color8(120, 230, 130))
	add_button("■ STOP", Rect2(142, 176, 74, 22), _stop_it, Color8(230, 120, 110))
	add_button("▶|", Rect2(220, 176, 40, 22), _next, app_accent)
	add_button("⏏", Rect2(264, 176, 40, 22), _eject, Color.WHITE)
	add_button("VOL −", Rect2(430, 176, 60, 22), _vol_down, Color.WHITE)
	add_button("VOL +", Rect2(494, 176, 60, 22), _vol_up, Color.WHITE)
	# Liste (nur Klickflächen, Zeilen zeichnet die App)
	var owned := _owned()
	_scroll = clampi(_scroll, 0, maxi(0, owned.size() - VISIBLE))
	for i in mini(VISIBLE, owned.size() - _scroll):
		var idx := _scroll + i
		add_button("", Rect2(20, LIST_Y + i * ROW_H, 600, ROW_H), _pick.bind(idx), Color.WHITE, false)
	if owned.size() > VISIBLE:
		add_button("▲", Rect2(600, LIST_Y, 20, 20), _scroll_up, app_accent)
		add_button("▼", Rect2(600, LIST_Y + (VISIBLE - 1) * ROW_H, 20, 20), _scroll_down, app_accent)
	_layout()


# ----------------------------------------------------------------- Aktionen

func _pick(idx: int) -> void:
	_sel = idx
	var owned := _owned()
	if idx >= 0 and idx < owned.size():
		MusicManager.play(owned[idx])
		_reset_counters()


func _play() -> void:
	var owned := _owned()
	if owned.is_empty():
		return
	_sel = clampi(_sel, 0, owned.size() - 1)
	MusicManager.play(owned[_sel])
	_reset_counters()


func _stop_it() -> void:
	MusicManager.stop()


func _prev() -> void:
	var owned := _owned()
	if owned.is_empty(): return
	_sel = (_sel - 1 + owned.size()) % owned.size()
	MusicManager.play(owned[_sel]); _reset_counters()


func _next() -> void:
	var owned := _owned()
	if owned.is_empty(): return
	_sel = (_sel + 1) % owned.size()
	MusicManager.play(owned[_sel]); _reset_counters()


func _eject() -> void:
	MusicManager.stop()


func _vol_up() -> void:
	SettingsManager.set_value("music", clampf(float(SettingsManager.value("music")) + 0.1, 0.0, 1.0))


func _vol_down() -> void:
	SettingsManager.set_value("music", clampf(float(SettingsManager.value("music")) - 0.1, 0.0, 1.0))


func _scroll_up() -> void: _scroll = maxi(0, _scroll - 1); _rebuild()
func _scroll_down() -> void: _scroll = _scroll + 1; _rebuild()


func _reset_counters() -> void:
	_pos = 0; _patt = 0; _postime = 0.0


func _app_process(delta: float) -> void:
	_scope_t += delta
	# Echte Abspielposition vom nativen Player (für POS/PATT + Pattern-Hex).
	if MusicManager.is_playing():
		var v: Dictionary = MusicManager.native_player().playback_view(1)
		if bool(v.get("ok", false)):
			_pos = int(v.get("row", 0))
			_patt = int(v.get("order", 0))


# ----------------------------------------------------------------- Zeichnen

func _content(font: Font) -> void:
	var playing := MusicManager.is_playing()
	var owned := _owned()
	var show_id := ""
	if playing:
		show_id = MusicManager.current
	elif not owned.is_empty() and _sel < owned.size():
		show_id = owned[_sel]
	var info: Dictionary = MusicManager.playback_track(show_id) if show_id != "" else {}

	# Modulinfo-Panel
	rect(14, 24, VW - 28, 66, Color8(10, 14, 30))
	rect_line(14, 24, VW - 28, 66, app_accent)
	var title: String = str(info.get("title", "— kein Modul —"))
	text(font, "»%s«" % title, 24, 44, 15, Color8(240, 210, 90))
	text(font, "von %s" % str(info.get("author", "?")), 24, 60, 11, Color8(150, 200, 240))
	var vol_pct := roundi(float(SettingsManager.value("music")) * 100.0)
	var view: Dictionary = MusicManager.native_player().playback_view(5) if playing else {"ok": false}
	var spd := int(view.get("speed", 6))
	var bpm := int(view.get("bpm", 125))
	var orders := int(view.get("orders", 1))
	text(font, "POS %02d/%02d   PATT %02d   ROW %02d/64   SPD %02d/%d   VOL %02d" %
		[_patt, orders, int(view.get("pattern", 0)), _pos, spd, bpm, roundi(vol_pct / 100.0 * 64)],
		24, 78, 10, Color8(120, 210, 130))
	text(font, "▶ PLAYING" if playing else "■ STOPPED", VW - 110, 44, 12,
		Color8(120, 230, 130) if playing else Color8(200, 120, 110))

	# Pattern-Anzeige: 4/6/8 Kanaele als laufende MOD-Hex-Zeilen ("C-3 04 A08"),
	# aktuelle Zeile mittig hervorgehoben — wie damals auf dem Amiga. Über jeder
	# Spalte ein kleiner Kanal-VU-Balken aus der echten Stimmen-Lautstärke.
	rect(14, 96, VW - 28, 74, Color8(6, 8, 18))
	rect_line(14, 96, VW - 28, 74, Color8(60, 70, 90))
	var channels := clampi(int(view.get("channels", 4)), 4, 8)
	var col_w := (VW - 28.0 - 34.0) / float(channels)
	for ch in channels:
		var bx := 48.0 + ch * col_w
		var lvl: float = MusicManager.native_player().channel_level(ch) if playing else 0.0
		text(font, "CH%d" % (ch + 1), bx + 2, 106, 8, Color8(120, 150, 190))
		rect(bx + 28, 100, (col_w - 40.0) * lvl, 5, Color8(90, 220, 110))
		rect_line(bx + 28, 100, col_w - 40.0, 5, Color8(50, 62, 84))
	if bool(view.get("ok", false)):
		var rows: Array = view.get("rows", [])
		for i in rows.size():
			var rr: Dictionary = rows[i]
			var yy := 118.0 + i * 10.0
			var is_cur := i == floori(float(rows.size()) / 2.0)
			if is_cur:
				rect(16, yy - 8, VW - 32, 10, Color8(28, 48, 80))
			var rnum := int(rr.get("row", -1))
			if rnum >= 0:
				text(font, "%02d" % rnum, 20, yy, 8,
					Color8(240, 210, 90) if is_cur else Color8(90, 110, 140))
			var cells: Array = rr.get("cells", [])
			for ch2 in mini(channels, cells.size()):
				var cell := str(cells[ch2])
				var ccol: Color = Color8(200, 220, 240) if is_cur else Color8(110, 140, 175)
				if cell.begins_with("---"):
					ccol = Color8(70, 88, 115) if not is_cur else Color8(130, 150, 175)
				text(font, cell, 48.0 + ch2 * col_w, yy, 8, ccol)
	else:
		text(font, "— kein Modul geladen —", 24, 138, 9, Color8(90, 110, 140))

	# Modulliste
	rect(14, LIST_Y - 8, VW - 28, VISIBLE * ROW_H + 12, Color8(10, 14, 28))
	rect_line(14, LIST_Y - 8, VW - 28, VISIBLE * ROW_H + 12, Color8(60, 74, 100))
	text(font, "MODULE  (%d)" % owned.size(), 20, LIST_Y - 12, 9, app_accent)
	for w in _widgets:
		if w.get("auto_draw", true):
			continue
		var r: Rect2 = w["rect"]
		var i := int((r.position.y - LIST_Y) / ROW_H)
		var idx := _scroll + i
		if idx >= owned.size():
			continue
		var id: String = owned[idx]
		var t: Dictionary = MusicManager.track(id)
		var is_cur := id == MusicManager.current
		if is_cur:
			rect(r.position.x, r.position.y, r.size.x, ROW_H - 1, Color8(30, 60, 90))
		elif widget_hovered(w):
			rect(r.position.x, r.position.y, r.size.x, ROW_H - 1, Color8(24, 34, 52))
		var mark := "▶ " if is_cur else "  "
		var col: Color = Color8(240, 210, 90) if is_cur else Color8(200, 214, 230)
		text(font, "%s%s — %s" % [mark, str(t.get("title", id)), str(t.get("author", ""))],
			r.position.x + 6, r.position.y + 11, 10, col)

	text(font, "Neue Module gibt's im Computerclub / per Mystery-Karton. Esc = zurück.",
		20, VH - 8, 9, Color8(120, 140, 170))
