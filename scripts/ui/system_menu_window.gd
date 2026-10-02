extends RetroWindow
## OPTIONEN/Systemmenü: Speichern, Laden, CRT-Shader, neues Spiel, Beenden.

const DevelopmentGate := preload("res://scripts/core/development_gate.gd")

var _new_game_armed := false
var _new_game_button: Button


func _init() -> void:
	title = Loc.t("ui.system_menu_window.title", "OPTIONEN")
	# Menüzeilen brauchen bei der aktuellen Theme-Höhe mehr Platz als das
	# alte 322-px-Fenster. Sonst ragte »Beenden« bei 720p sichtbar aus dem Rahmen.
	win_size = Vector2(280, 360)
	chrome_accent = Palette.PINK


func _ready() -> void:
	super._ready()
	content.add_child(make_button(Loc.t("ui.system_menu_window.weiterspielen", "Weiterspielen"), queue_free))
	content.add_child(make_button(Loc.t("ui.system_menu_window.hilfe_f1", "Hilfe (F1)"), func() -> void: UIManager.open_help()))
	content.add_child(make_button(Loc.t("ui.system_menu_window.speichern_f5", "Speichern (F5)"), func() -> void: SaveManager.save_game()))
	content.add_child(make_button(Loc.t("ui.system_menu_window.laden_f9", "Laden (F9)"), func() -> void:
		SaveManager.load_game_with_screen()))
	content.add_child(make_button(Loc.t("ui.system_menu_window.optionen", "Optionen"), func() -> void: UIManager.open_options()))
	content.add_child(make_button(Loc.t("ui.system_menu_window.erfolge_d_d", "🏆 Erfolge (%d/%d)") % [AchievementManager.unlocked_count(), AchievementManager.total()],
		func() -> void: UIManager.open_achievements()))
	content.add_child(make_button(Loc.t("ui.system_menu_window.erinnerungen_d", "📷 Erinnerungen (%d)") % PhotoManager.count(),
		func() -> void: UIManager.open_photos()))
	if DevelopmentGate.enabled():
		content.add_child(make_button(Loc.t("ui.system_menu_window.playtest_bericht", "Playtest-Bericht"), func() -> void:
			UIManager.open_playtest_report()))
	_new_game_button = make_button(Loc.t("ui.system_menu_window.neues_spiel", "Neues Spiel"), _on_new_game)
	content.add_child(_new_game_button)
	content.add_child(make_button(Loc.t("ui.system_menu_window.speichern_hauptmenu", "Speichern & Hauptmenü"), func() -> void:
		if SaveManager.save_game():
			GameManager.return_to_title()))
	content.add_child(make_button(Loc.t("ui.system_menu_window.beenden", "Beenden"), func() -> void:
		if DevelopmentGate.enabled():
			PlaytestTelemetry.write_live_checkpoint()
		SaveManager.save_on_exit()
		get_tree().quit()))
	_fit_frame_to_content()


## Falls Theme/Schrift später höhere Buttons erzeugen, wächst der Rahmen mit dem
## echten Inhalt. Die feste Grundhöhe hält das Fenster trotzdem 720p-tauglich.
func _fit_frame_to_content() -> void:
	var required_height := 36.0 + content.get_combined_minimum_size().y
	win_size.y = maxf(win_size.y, required_height)
	size = win_size
	custom_minimum_size = win_size


## Zweistufige Bestätigung: der aktuelle Stand ginge sonst verloren.
func _on_new_game() -> void:
	if not _new_game_armed:
		_new_game_armed = true
		_new_game_button.text = Loc.t("ui.system_menu_window.wirklich_ungespeichert_weg", "Wirklich? (ungespeichert = weg)")
		return
	var slot := await SaveManager.choose_new_game_slot()
	if slot < 1:
		return
	queue_free()
	SaveManager.start_new_game_with_screen(slot)
