extends RetroWindow
## Discoverable local soundtrack overrides, including errors and real credits.

var _status: Label
var _details: TextEdit


func _init() -> void:
	title = Loc.t("ui.mods.title", "EIGENE MOD-MUSIK")
	win_size = Vector2(700, 480)
	chrome_accent = Palette.LCD_CYAN


func _ready() -> void:
	super._ready()
	var hint := Label.new()
	hint.text = Loc.t("ui.mods.hint", "Eigene .mod-Dateien hier ablegen. Passende Titel ersetzen den Soundtrack; weitere Dateien erscheinen in deiner Anlage.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)
	var path := LineEdit.new()
	path.text = MusicManager.mod_folder()
	path.editable = false
	path.tooltip_text = path.text
	content.add_child(path)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	_details = TextEdit.new()
	_details.editable = false
	_details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.add_theme_font_size_override("font_size", 13)
	content.add_child(_details)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.add_child(make_button(Loc.t("ui.mods.open", "Ordner öffnen"), _open_folder))
	buttons.add_child(make_button(Loc.t("ui.mods.rescan", "Neu einlesen"), _rescan))
	buttons.add_child(make_button(Loc.t("ui.common.back", "Zurück"), queue_free))
	content.add_child(buttons)
	_refresh()


func _open_folder() -> void:
	if OS.shell_open(MusicManager.mod_folder()) != OK:
		UIManager.toast(Loc.t("ui.mods.open_failed", "Ordner konnte nicht geöffnet werden. Du kannst den Pfad im Fenster kopieren."))


func _rescan() -> void:
	MusicManager.rescan_mods()
	_refresh()


func _refresh() -> void:
	var report := MusicManager.mod_library_status()
	_status.text = Loc.t("ui.mods.status", "%d Dateien · %d Zuordnungen · %d eigene Titel · %d Hinweise") % [
		report.scanned, report.matched, report.personal, report.issues.size()]
	var lines: Array[String] = []
	lines.append(Loc.t("ui.mods.guide", "4/6/8 Kanäle · maximal 8 MiB je Datei. Zuordnung per ID, Dateiname oder eindeutigem MOD-Titel. Bei fehlenden oder ungültigen Dateien spielt der Original-Soundtrack. Details und overrides.json-Beispiel stehen in README.txt im Ordner."))
	for issue: String in report.issues:
		lines.append("• " + issue)
	lines.append("")
	lines.append(Loc.t("ui.mods.assignments", "SAMMELTITEL → WIEDERGABE (ID für overrides.json)"))
	for slot: Dictionary in MusicManager.tracks:
		var id := str(slot.get("id", ""))
		var resolved := MusicManager.playback_track(id)
		var marker := "MOD" if bool(resolved.get("user_mod", false)) else "OST"
		lines.append("[%s] %s → %s  (%s)" % [marker, slot.get("title", id), resolved.get("title", "?"), id])
	_details.text = "\n".join(lines)
