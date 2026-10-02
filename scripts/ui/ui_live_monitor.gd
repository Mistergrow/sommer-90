extends RefCounted
## Live-Monitor (Echtzeit-Röhre): aus UIManager ausgelagert (Zeilen-Budget).
## Statische Funktionen nach Projekt-Splitmuster; `ui` ist der UIManager-Host
## (untypisiert, hält die Zustände _live_vp/_live_view/_live_app + monitor_*).
## BEWUSST ohne class_name: Konsumenten binden per Pfad-preload — der globale
## Klassen-Cache raced sonst mit dem parallel laufenden Editor (Projekt-Falle).

const MonitorProfile := preload("res://scripts/ui/monitor_profile.gd")


## Render-to-Texture-SubViewport für den Live-Inhalt — einmalig, bleibt erhalten.
static func _ensure_live_vp(ui) -> void:
	if ui._live_vp != null and is_instance_valid(ui._live_vp):
		return
	ui._live_vp = SubViewport.new()
	ui._live_vp.size = MonitorProfile.live_canvas_size()
	ui._live_vp.transparent_bg = false
	ui._live_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	ui._live_vp.disable_3d = true
	ui.add_child(ui._live_vp)


## Was gerade auf dem Amiga läuft, auf der Röhre weiterzeigen. Sicher umhängbare
## Tools/OS-Apps werden in den SubViewport verschoben und rendern dort live;
## Vollspiele behalten wegen ihres Audio-Lifecycles ein Standbild. Läuft nur eine
## Sounddiskette, übernimmt der Musik-Visualizer. Wird beim Aufstehen aufgerufen.
static func start(ui) -> void:
	var host: Control = GameManager.location_host
	var app: Control = ui._top_program(host) if host != null else null
	if app != null and is_reparentable(app):
		run_app(ui, app)
	else:
		run_music(ui)


## Ist die App sicher live umhängbar? Selbstbootende VOLLSPIELE (app_game_*) NICHT:
## ihr _exit_tree stoppt beim Umhängen Motor-/Musik-Sound (und _enter_tree startet
## ihn nicht neu) → sie würden stumm laufen. Für Spiele bleibt es beim Standbild;
## Tools/OS-Apps (Werkbank, X-COPY, MOD-Player, Demo) laufen live. Der
## Boot-Selektor ist nur ein physischer Eingabedialog und wird beim Aufstehen
## geschlossen, damit er nicht als scheinbar laufendes Programm wiederkehrt.
static func is_reparentable(app: Control) -> bool:
	return app != null and str(app.name) != "BootSelect" \
		and not str(app.name).begins_with("app_game_")


## Die reale App in den SubViewport umhängen — sie läuft dort unverändert weiter
## (gleiche Größe wie im Zimmer, damit Layout/Viewport-Maße stimmen).
static func run_app(ui, app: Control) -> void:
	_ensure_live_vp(ui)
	if ui._live_view != null and is_instance_valid(ui._live_view):
		ui._live_view.visible = false
	var host: Control = GameManager.location_host
	var vp := Vector2i(host.size) if host != null and host.size.x > 4.0 else Vector2i(1440, 810)
	ui._live_vp.size = vp
	if app.get_parent() != ui._live_vp:
		app.reparent(ui._live_vp)
	# Ein Aufruf setzt Anker UND Offsets atomar. Separate size-Zuweisungen bei
	# gegenüberliegenden Ankern erzeugen in Godot 4.6 eine Layoutwarnung.
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui._live_app = app
	ui._live_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ui.monitor_texture = ui._live_vp.get_texture()
	ui.monitor_color = Color(0.32, 0.5, 0.9)
	ui.monitor_program = app.name
	ui.monitor_live = true
	ui.monitor_on = true
	ui.monitor_changed.emit()


## Kein Programm offen, aber Musik läuft → selbstlaufender Musik-Visualizer.
static func run_music(ui) -> void:
	if not MusicManager.is_playing():
		return
	_ensure_live_vp(ui)
	detach(ui)
	var profile_id := MonitorProfile.active_model_id()
	ui._live_vp.size = MonitorProfile.live_canvas_size(profile_id)
	if ui._live_view == null or not is_instance_valid(ui._live_view):
		ui._live_view = load("res://scripts/ui/monitor_live_view.gd").new()
		ui._live_vp.add_child(ui._live_view)
	if ui._live_view.has_method("set_monitor_profile"):
		ui._live_view.call("set_monitor_profile", profile_id)
	ui._live_view.visible = true
	if ui._live_view.has_method("set_track"):
		var t: Dictionary = MusicManager.playback_track(MusicManager.current)
		ui._live_view.call("set_track", str(t.get("title", "")))
	ui._live_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ui.monitor_texture = ui._live_vp.get_texture()
	ui.monitor_color = Color(0.45, 0.35, 0.85)
	ui.monitor_program = "live"
	ui.monitor_live = true
	ui.monitor_on = true
	ui.monitor_changed.emit()


## Zurück an den Rechner: die live weiterlaufende App aus dem SubViewport zurück ins
## Zimmer (Vollbild) holen — du machst nahtlos weiter. true = es lief eine App.
static func resume(ui) -> bool:
	if ui._live_app == null or not is_instance_valid(ui._live_app):
		return false
	var host: Control = GameManager.location_host
	if host == null:
		return false
	var app: Control = ui._live_app
	ui._live_app = null
	ui.monitor_live = false
	ui.monitor_texture = null
	if ui._live_vp != null and is_instance_valid(ui._live_vp):
		ui._live_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	app.reparent(host)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui._set_computer_ui(true)
	ui.monitor_changed.emit()
	return true


## App im SubViewport schließen (bei Strom-Aus/Reset — nicht beim Hinsetzen).
static func detach(ui) -> void:
	if ui._live_app != null and is_instance_valid(ui._live_app):
		ui._live_app.queue_free()
	ui._live_app = null


static func stop(ui) -> void:
	if not ui.monitor_live and ui._live_app == null:
		return
	ui.monitor_live = false
	ui.monitor_texture = null
	ui.monitor_on = false
	if ui._live_vp != null and is_instance_valid(ui._live_vp):
		ui._live_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED  # nicht mehr rendern
	detach(ui)   # die live gezeigte App schließen (Strom-Aus/Reset/Neustart)
	ui.monitor_changed.emit()
