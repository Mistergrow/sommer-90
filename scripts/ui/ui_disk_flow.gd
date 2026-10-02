extends RefCounted
## „Diskette starten"-Flow: aus UIManager ausgelagert (Zeilen-Budget). Statische
## Funktionen nach Projekt-Splitmuster; `ui` ist der UIManager-Host. Inszeniert
## das Kopierschutz-Erlebnis der Ära (docs/KULTUR_LAYER.md) und startet
## registrierte Vollspiele. BEWUSST ohne class_name (Pfad-preload, s. UiLiveMonitor).

const CracktroWindow := preload("res://scripts/ui/cracktro_window.gd")
const ProtectionWindow := preload("res://scripts/ui/protection_window.gd")
const ProtectionFullscreenScreenScript := preload("res://scripts/ui/protection_fullscreen_screen.gd")
const PlayableGameRegistry := preload("res://scripts/games/playable_game_registry.gd")
const DiskAccessPolicy := preload("res://scripts/ui/disk_access_policy.gd")


## Hat diese Diskette ein tatsaechlich implementiertes Vollspiel? Die bestehende
## software_id ist absichtlich der einzige Schluessel: Sie ueberlebt Kopien und
## Save-Roundtrips bereits, ohne das Disk-Format um ein game_id-Feld zu erweitern.
static func _is_registered_disk_game(disk: Disk) -> bool:
	return disk != null and PlayableGameRegistry.is_registered(disk.software_id)


## Uebergibt die Disk nur, wenn das konkrete Spiel eine solche Property anbietet.
## Dadurch bleibt die Registry auch mit kleinen Diagnose-/Testspielen nutzbar.
static func _assign_disk_if_supported(game: Control, disk: Disk) -> void:
	for property: Dictionary in game.get_property_list():
		if str(property.get("name", "")) == "disk":
			game.set("disk", disk)
			return


## Startet ein registriertes selbstbootendes Vollspiel auf dem Rechner. Diese
## Funktion fuehrt selbst keinen Schutzcheck durch und wird deshalb ausschliesslich
## aus den erfolgreichen Zweigen von play() aufgerufen.
static func _launch_registered_disk_game(ui, disk: Disk) -> bool:
	if not _is_registered_disk_game(disk):
		return false
	var host: Control = GameManager.location_host
	if host == null:
		return false
	var game: Control = PlayableGameRegistry.instantiate(disk.software_id)
	if game == null:
		return false
	var node_name: String = PlayableGameRegistry.node_name_for(disk.software_id)
	if node_name == "":
		game.free()
		return false

	# Diskbox, Werkbank und ein eventuell bereits laufendes Vollprogramm muessen
	# verschwinden, bevor das selbstbootende Spiel den Monitor uebernimmt.
	ui._close_all_fullscreen()
	var old_game := host.get_node_or_null(NodePath(node_name))
	if old_game != null:
		old_game.free()
	_assign_disk_if_supported(game, disk)
	game.name = node_name
	# Ein Vollspiel ersetzt die eingelegte Systemdiskette. Nach dem Auswerfen
	# wartet der Rechner deshalb wieder am Kickstart-Schirm statt eine alte
	# Werkbank-Sitzung aus dem Nichts fortzusetzen.
	ui.system_disk_inserted = false
	ui.wb_booted = false
	host.add_child(game)
	# Selbstbootende Spiele belegen den gesamten Monitor-Host. Das explizite
	# Layout direkt nach dem Einhaengen verhindert auch einen einzelnen Frame mit
	# alter/kleiner Control-Groesse beim Kopierschutz-Handoff.
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Zocken nutzt den Joystick ab (Wackelkontakte) — so bleibt die Löt-Werkstatt
	# ein wiederkehrendes Ritual statt einer einmaligen Erstreparatur.
	PlayerStats.damage_joystick(0.04)
	if bool(SettingsManager.value("crt_auto_monitor")):
		ui.set_crt(true)
	ui._set_computer_ui(true)
	ui.monitor_changed.emit()
	return true


## Erfolgreicher Disk-Pfad: implementiertes Spiel uebernimmt den Monitor, alle
## anderen Titel behalten exakt die bisherige erzählerische Toast-Rueckmeldung.
static func _continue_disk_after_success(ui, disk: Disk, fallback_text: String) -> void:
	# Mehrdisketten-Spiele: erst das Amiga-Disketten-Wechsel-Ritual (Disk 2..N),
	# dann übernimmt das Spiel. Der vollständige Satz ist hier bereits garantiert
	# (DiskManager.play_disk lehnt unvollständige Sätze vorher ab).
	var required := 1
	if disk != null and disk.software_id != "":
		required = maxi(SoftwareBible.disk_count(disk.software_id), disk.disk_count)
	if required > 1:
		ui.close_window("win_diskswap")
		ui.toggle_window("win_diskswap", func() -> Control:
			var w: Control = load("res://scripts/ui/disk_swap_window.gd").new()
			w.set("total", required)
			w.set("software_title", disk.display_name())
			w.set("on_complete", func() -> void:
				if not _launch_registered_disk_game(ui, disk):
					ui.toast(fallback_text))
			return w)
		return
	if not _launch_registered_disk_game(ui, disk):
		ui.toast(fallback_text)


## Selbstbootende Vollspiele beginnen bereits MIT dem Kopierschutz auf dem
## Monitor. Ein normales Desktop-Popup liess besonders CODE RED wie ein Fenster
## im Zimmer statt wie ein gestartetes Amiga-Spiel wirken.
static func _open_fullscreen_protection(ui, disk: Disk, result: Dictionary) -> bool:
	if not _is_registered_disk_game(disk):
		return false
	var host: Control = GameManager.location_host
	if host == null:
		return false
	var was_seated := bool(ui.at_computer)
	ui.close_all_windows()
	var old := host.get_node_or_null("app_game_copy_protection")
	if old != null:
		old.free()
	var screen: Control = ProtectionFullscreenScreenScript.new()
	screen.name = "app_game_copy_protection"
	screen.game_title = result["title"]
	screen.software_id = disk.software_id
	screen.protection = result["protection"]
	screen.has_beilagen = result["has_beilagen"]
	screen.missing_beilagen = result.get("missing_beilagen", [])
	screen.was_at_computer = was_seated
	screen.on_result = func(ok: bool) -> void:
		if ok:
			_continue_disk_after_success(ui, disk, str(result["text"]))
		else:
			ui.toast(Loc.t("ui.ui_disk_flow.abfrage_gescheitert_nur_demomodus_lauft", "Abfrage gescheitert — nur der Demomodus läuft."))
	host.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui._set_computer_ui(true)
	ui.monitor_changed.emit()
	return true


## „Diskette starten" — Cracktro bei Szene-Kopien, Abfrage-Ritual bei Originalen,
## authentische Absage bei nackten Kopien.
static func play(ui, disk: Disk) -> void:
	if disk == null:
		ui.toast(Loc.t("ui.ui_disk_flow.keine_diskette_ausgewaehlt", "Keine Diskette ausgewaehlt."))
		return
	if not DiskAccessPolicy.require_computer(ui, "Diskette starten"):
		return
	# Programm-Disketten (z.B. X-COPY) starten direkt die zugehörige App.
	if disk.program_id != "":
		if ui.open_program_from_media(disk.program_id):
			ui.toast(Loc.t("ui.ui_disk_flow.s_gestartet",
				"»%s« von Diskette gestartet.") % disk.display_name())
		return
	var result: Dictionary = DiskManager.play_disk(disk)
	if not result["ok"]:
		ui.toast(result["text"])
		return
	match result["flow"]:
		"cracktro":
			ui.close_window("win_cracktro")
			ui.toggle_window("win_cracktro", func() -> Control:
				var w: Control = CracktroWindow.new()
				w.game_title = result["title"]
				w.release_data = disk.release_data.duplicate(true)
				# Nur der explizite [ Spiel starten ]-Klick ruft diesen Callback.
				# Das Fenster-X bzw. Esc lässt cracktro_seen unverändert.
				w.on_continue = func() -> void:
					var manager: Node = ui.get_node_or_null("/root/SceneReleaseManager")
					if manager != null and manager.has_method("mark_intro_seen"):
						manager.call("mark_intro_seen", disk)
					_continue_disk_after_success(ui, disk, str(result["text"]))
				return w)
		"abfrage":
			if _open_fullscreen_protection(ui, disk, result):
				return
			ui.close_window("win_protection")
			ui.toggle_window("win_protection", func() -> Control:
				var w: Control = ProtectionWindow.new()
				w.game_title = result["title"]
				w.software_id = disk.software_id
				w.protection = result["protection"]
				w.has_beilagen = result["has_beilagen"]
				w.missing_beilagen = result.get("missing_beilagen", [])
				w.on_result = func(ok: bool) -> void:
					if ok:
						_continue_disk_after_success(ui, disk, str(result["text"]))
					else:
						ui.toast(Loc.t("ui.ui_disk_flow.abfrage_gescheitert_nur_demomodus_lauft", "Abfrage gescheitert — nur der Demomodus läuft."))
				return w)
		"blocked":
			ui.open_info("KOPIERSCHUTZ", result["text"]
				+ "\n\nSo war das damals: Ohne Beilagen lief die nackte Kopie nicht"
				+ " — deshalb kursierten Szene-Versionen, und deshalb war das"
				+ " Original Gold wert.")
		"direct":
			_continue_disk_after_success(ui, disk, str(result["text"]))
		_:
			ui.toast(result["text"])
