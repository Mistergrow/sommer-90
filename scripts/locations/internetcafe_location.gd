extends LocationBase
## INTERNETCAFÉ (ab 1998) — als das Internet in die Stadt kommt, öffnet am Markt
## ein Café mit Rechnern zum Stundentarif. Wer (noch) kein eigenes Modem hat,
## geht hier online: E-Mail, das World Wide Web, Neuigkeiten aus aller Welt —
## gegen Kaffee und ein paar Mark die Stunde. Öffnet erst 1998 (town.json).

const HOUR_COST := 5   # DM pro Stunde online
const HOMEPAGE_EDITOR_PATH := "res://scripts/ui/homepage_editor_window.gd"

func background_base() -> String:
	return "LOCATION_INTERNETCAFE_MASTER"


func _build() -> void:
	if has_background():
		cover_mode = true
		virtual_size = Vector2(1672, 941)
		# Disjunkte Rechnerflaechen: Terminal 1 ist der Homepage-Arbeitsplatz,
		# die restliche Reihe dient dem normalen Online-Zugang. Ueberlappende
		# Buttons hatten zuvor Monitore 1-4 unerwartet zur Homepage umgeleitet.
		add_hotspot(Rect2(180, 260, 355, 520), Loc.t("place.internetcafe_location.terminals_2_5_online_gehen_d", "Terminals 2–5 — online gehen (%d DM/Std.)") % HOUR_COST, _go_online)
		add_hotspot(Rect2(815, 230, 500, 390), Loc.t("place.internetcafe_location.tresen_kaffee_2_dm", "Tresen — Kaffee (2 DM)"), _coffee)
		add_hotspot(Rect2(500, 165, 325, 210), Loc.t("place.internetcafe_location.aushang_kurse_infos", "Aushang — Kurse & Infos"), _board)
		add_hotspot(Rect2(0, 315, 180, 445), Loc.t("place.internetcafe_location.terminal_1_eigene_homepage_bauen_bearbeiten", "Terminal 1 — eigene Homepage bauen/bearbeiten"), _homepage)
		add_hotspot(Rect2(1430, 120, 242, 590), Loc.t("place.internetcafe_location.tur_raus_orte", "Tür — raus (Orte)"), UIManager.open_map)
		return
	add_hotspot(Rect2(40, 45, 160, 95), Loc.t("place.internetcafe_location.ans_terminal_online_gehen_d_dm", "Ans Terminal — online gehen (%d DM/Std.)") % HOUR_COST, _go_online)
	add_hotspot(Rect2(215, 45, 120, 95), Loc.t("place.internetcafe_location.tresen_kaffee_2_dm", "Tresen — Kaffee (2 DM)"), _coffee)
	add_hotspot(Rect2(40, 150, 175, 32), Loc.t("place.internetcafe_location.aushang_kurse_infos", "Aushang — Kurse & Infos"), _board)
	add_hotspot(Rect2(222, 148, 116, 36), Loc.t("place.internetcafe_location.eigene_homepage_bauen_bearbeiten", "Eigene Homepage bauen/bearbeiten"), _homepage)
	add_hotspot(Rect2(345, 55, 45, 110), Loc.t("place.internetcafe_location.tur_raus_orte", "Tür — raus (Orte)"), UIManager.open_map)


func _go_online() -> void:
	if PlayerStats.geld < HOUR_COST:
		UIManager.toast(Loc.t("place.internetcafe_location.kein_geld_fur_stunde_am_terminal", "Kein Geld für die Stunde am Terminal (%d DM).") % HOUR_COST)
		return
	if not PlayerStats.use_energy(8):
		UIManager.toast(Loc.t("place.internetcafe_location.zu_mude_um_jetzt_zu_surfen", "Zu müde, um jetzt zu surfen."))
		return
	PlayerStats.add_money(-HOUR_COST)
	PlayerStats.change_stat("wissen", 2)
	AudioManager.modem_dial()
	TimeManager.advance_slot()
	UIManager.open_info("INTERNETCAFÉ — ONLINE",
		"Das Modem kreischt, dann bist du drin. Seiten laden Zeile für Zeile, aber die Welt fühlt sich plötzlich klein an: Nachrichten aus Japan, eine Fanseite zu deinem Lieblingsspiel, ein Gästebuch voller Fremder.\n\nEine Stunde vergeht wie im Flug. (Wissen +2)")


## Eigene Homepage bauen/bearbeiten (GeoCities-Ära). Ab dem Internetcafé verfügbar.
func _homepage() -> void:
	UIManager.toggle_window("win_homepage", func() -> Control:
		var editor_script := load(HOMEPAGE_EDITOR_PATH) as Script
		return editor_script.new() as Control)


func _coffee() -> void:
	if PlayerStats.geld < 2:
		UIManager.toast(Loc.t("place.internetcafe_location.nicht_mal_fur_nen_kaffee_reicht", "Nicht mal für 'nen Kaffee reicht's gerade."))
		return
	PlayerStats.add_money(-2)
	PlayerStats.change_stat("energie", 8)
	UIManager.toast(Loc.t("place.internetcafe_location.starker_kaffee_wach_genug_fur_nachste", "Ein starker Kaffee — wach genug für die nächste Runde."))


func _board() -> void:
	UIManager.toggle_window("win_bulletin", func() -> Control:
		var w := BulletinBoardWindow.new()
		w.board_id = "internetcafe"
		return w)
