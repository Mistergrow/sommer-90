extends Node
## Fenster-, Sitz- und Monitor-Fassade; Programmstarts liegen in UiPrograms.

@warning_ignore("unused_signal") # Emission erfolgt im ausgelagerten UiWindowSupport.
signal info_logged(text: String)
signal notebook_opened
@warning_ignore("unused_signal") # Emission erfolgt im ausgelagerten UiWindowSupport.
signal notebook_attention_changed(active: bool, item_count: int)
signal crt_toggled(enabled: bool)
signal monitor_changed()
signal seat_changed(seated: bool)   # true = sitzt am Computer (Vollbild-Programm)
signal jobs_opened                  # Sidebar quittiert damit neue Jobangebote
# Zeilen-Budget-Splits (Pfad-preload statt class_name — Klassen-Cache-Race).
const UiLiveMonitor := preload("res://scripts/ui/ui_live_monitor.gd")
const UiDiskFlow := preload("res://scripts/ui/ui_disk_flow.gd")
const UiPrograms := preload("res://scripts/ui/ui_program_launcher.gd")
const UiWindowSupport := preload("res://scripts/ui/ui_window_support.gd")
const UiMinigames := preload("res://scripts/ui/ui_minigame_launcher.gd")
const SummerDiskWindowScript := preload("res://scripts/ui/summer_disk_window.gd")
const PLAYTEST_REPORT_WINDOW_PATH := "res://scripts/dev/playtest_report_window.gd"
const DevelopmentGate := preload("res://scripts/core/development_gate.gd")
const DemoMakerWindowScript := preload("res://scripts/ui/demo_maker_window.gd")
const UiTransitionFlow := preload("res://scripts/ui/ui_transition_flow.gd")
const UiComputerPower := preload("res://scripts/ui/ui_computer_power.gd")
var window_layer: Control = null
var info_log: Array = []   # jüngste Meldung zuerst
var crt_enabled: bool = false
var notebook_attention: bool = false
var notebook_attention_count: int = 0
# --- Monitor-Zustand: was die Bildröhre im Zimmer zeigt, nachdem man aufgestanden
# ist. Standbild des zuletzt genutzten Programms + dominante Farbe fürs Lichtspill.
var monitor_on: bool = false
var monitor_texture: Texture2D = null
var monitor_color: Color = Color(0.10, 0.12, 0.18)
var monitor_program: String = ""
var monitor_live: bool = false            # Röhre zeigt einen LIVE-Screen (SubViewport)
@warning_ignore("unused_private_class_variable")
var _live_vp: SubViewport = null          # rendert den Live-Inhalt (App ODER Musik)
# Die zwei folgenden Felder hält der Host für den ausgelagerten UiLiveMonitor-
# Helper (Zeilen-Budget-Split) — dort werden sie gelesen/geschrieben.
@warning_ignore("unused_private_class_variable")
var _live_view: Control = null            # Musik-Visualizer (Fallback, wenn keine App läuft)
@warning_ignore("unused_private_class_variable")
var _live_app: Control = null             # die echte, live weiterlaufende Amiga-App im Viewport
# --- Getrennter Strom für Monitor und Amiga (Spielstart: alles AUS). Wurzel der
# Kette ist der Mehrfachverteiler unterm Tisch (strip_power): ohne ihn bekommen
# Monitor und Amiga-Netzteil keinen Saft. Der Monitor wird am Gerät angeklickt
# (Warmlauf-Effekt), der Amiga am Netzteil-Brick eingeschaltet. Erst wenn beide
# laufen, bootet der Amiga. Das IdleLifeOverlay liest die Stromdomäne je Asset.
signal power_changed()
var strip_power: bool = false            # Mehrfachverteiler — Wurzel der Stromkette
var monitor_power: bool = false
var amiga_power: bool = false
var system_disk_inserted: bool = false   # Boot-Diskette drin → Werkbank statt Kickstart
var workbench_profile_id: String = ""    # Von welchem originalen Systemmedium gebootet
## Flüchtige Quelle des aktuellen Starts. Sie gehört bewusst nicht in den Save:
## nach Netz-Aus gibt es weder eine aktive DF0:- noch DH0:-Bootsequenz.
var boot_source: String = ""             # "" | "floppy" | "hdd"
var monitor_warmup_t: float = 0.0         # >0 während des Einschalt-Effekts (s. Overlay)
var wb_booted: bool = false               # Werkbank-Bootsequenz schon gezeigt?


func _ready() -> void:
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)


## Der Meldungsverlauf ist absichtlich flüchtig und enthielt historisch bereits
## fertig übersetzte Sätze statt stabiler Locale-Keys. Beim Sprachwechsel wird
## er daher geleert: So bleibt kein deutscher Alttext in einer englischen UI,
## während Quests, Aufgaben und Telefontexte weiterhin persistent bleiben.
func _on_locale_changed(_locale: String) -> void:
	if info_log.is_empty():
		return
	info_log.clear()
	info_logged.emit("")
## Stromdomäne an/aus (für LEDs): "strip" ← Verteiler, "monitor"/"amiga" hängen
## physisch am Verteiler, "mains" (Telefon o. Ä.) ist immer versorgt.
func domain_on(domain: String) -> bool:
	return UiComputerPower.domain_on(self, domain)

## Boot-Zustand der Röhre: "off" (Monitor aus) · "nosignal" (Monitor an, Amiga aus)
## · "kickstart" (beide an, keine Boot-Diskette) · "booted" (Systemdiskette drin).
func boot_state() -> String:
	return UiComputerPower.boot_state(self)

## Besitzt der Spieler eine bootfähige Werkbank-Systemdiskette? Ohne sie bleibt
## jeder aktive Amiga ohne passende Festplatte an seiner Einlege-Aufforderung.
func has_system_disk() -> bool:
	return UiComputerPower.has_system_disk()

## Aktiver Amiga mit passender Festplatte? A590 ist ein A500-Seitenwagen; der
## A600 und A1200 brauchen jeweils ihre eigene interne 2,5"-IDE-Platte.
func has_hdd() -> bool:
	return bool(PlayerStats.hdd_info().get("available", false))


## Startet das zum aktiven Rechner gehörende DH0:-Volume. Die Profil-ID kommt
## vom installierten System auf der Platte, nicht pauschal vom aktuellen Jahr.
func boot_from_hdd() -> bool:
	return UiComputerPower.boot_from_hdd(self)

# --- Boot-Disketten-Wähler (Kickstart, Amiga ohne Festplatte). ----------------
## Kickstart-Diskettenwahl öffnen: zeigt ALLE Disketten der Sammlung, der Spieler
## legt eine ein und bootet von ihr. Vollbild über der Zimmeransicht.
func open_boot_selector() -> void:
	UiComputerPower.open_boot_selector(self)

## Von der gewählten Diskette booten: Werkbank-Systemdisk → Werkbank, Programm-
## Diskette (X-COPY …) → startet direkt, Spiel/Demo → Spielstart-Flow. Nicht-
## bootfähige Disketten booten nicht (Kickstart-Hand bliebe stehen).
func boot_from_disk(disk) -> void:
	UiComputerPower.boot_from_disk(self, disk)

func set_monitor_power(on: bool) -> void:
	UiComputerPower.set_monitor_power(self, on)
	power_changed.emit()

## Rechner komplett in den AUS-Zustand bringen — man sitzt beim Spielstart/Laden
## vor einem ausgeschalteten Amiga. Der Computer-/Strom-Zustand wird NICHT
## gespeichert; ohne dieses Reset erbt ein neues Spiel „Amiga an" samt eingelegter
## Diskette der vorherigen Sitzung.
func reset_computer() -> void:
	UiComputerPower.reset(self)
	power_changed.emit()

func set_amiga_power(on: bool) -> void:
	UiComputerPower.set_amiga_power(self, on)
	power_changed.emit()

func toggle_monitor_power() -> void:
	set_monitor_power(not monitor_power)

func toggle_amiga_power() -> void:
	set_amiga_power(not amiga_power)

## Mehrfachverteiler: Wurzel der Stromkette. Ausschalten reißt alles an der
## Leiste mit (Monitor + Netzteil); Einschalten weckt kein Gerät von selbst.
func set_strip_power(on: bool) -> void:
	UiComputerPower.set_strip_power(self, on)
	power_changed.emit()

func toggle_strip_power() -> void:
	set_strip_power(not strip_power)

# Vollbild-Programm-Knoten in location_host (zum Aufräumen/Einfangen).
const _FULLSCREEN_WINDOWS := ["win_diskbox", "win_bbs", "win_music"]

## CRT-Shader an/aus (F10). main.gd schaltet die Shader-Ebene entsprechend.
func toggle_crt() -> void:
	set_crt(not crt_enabled)
	toast(Loc.t("sys.ui_manager.crt_shader_s", "CRT-Shader: %s") % ("AN" if crt_enabled else "AUS"))

## CRT-Shader gezielt setzen (z. B. automatisch AN, wenn man am Monitor sitzt).
func set_crt(on: bool) -> void:
	if crt_enabled == on:
		return
	crt_enabled = on
	crt_toggled.emit(crt_enabled)

# Fensterklassen (werden aus Code instanziert, keine .tscn nötig)
const DiskBoxWindow := preload("res://scripts/ui/disk_box_window.gd")
const ShopWindow := preload("res://scripts/ui/shop_window.gd")
const DialogueWindow := preload("res://scripts/ui/dialogue_window.gd")
const EventWindow := preload("res://scripts/ui/event_window.gd")
const MapWindow := preload("res://scripts/ui/map_window.gd")
const InfoWindow := preload("res://scripts/ui/info_window.gd")
const ContactsWindow := preload("res://scripts/ui/contacts_window.gd")
const InventoryWindow := preload("res://scripts/ui/inventory_window.gd")
const SystemMenuWindow := preload("res://scripts/ui/system_menu_window.gd")
const BBSWindow := preload("res://scripts/ui/bbs_window.gd")
const RumorWindow := preload("res://scripts/ui/rumor_window.gd")
const MusicWindow := preload("res://scripts/ui/music_window.gd")
const MagazineWindow := preload("res://scripts/ui/magazine_window.gd")
const MusicClubWindow := preload("res://scripts/ui/music_club_window.gd")
const FleaWindow := preload("res://scripts/ui/flea_window.gd")
const OptionsWindow := preload("res://scripts/ui/options_window.gd")
const EndgameStatsScene := preload("res://scripts/ui/endgame_stats.gd")
const YearTransitionScreenScene := preload("res://scripts/ui/year_transition_screen.gd")
const SleepTransitionScreenScene := preload("res://scripts/ui/sleep_transition_screen.gd")
const FirstYearDemoFinaleScene := preload("res://scripts/ui/first_year_demo_finale.gd")
const ScenePatchAppScript := preload("res://scripts/ui/scene_patch_app.gd")
const BankAtmWindowScript := preload("res://scripts/ui/bank_atm_window.gd")
const CollectionCabinetWindowScript := preload("res://scripts/ui/collection_cabinet_window.gd")
const SoftwareInsertsWindowScript := preload("res://scripts/ui/software_inserts_window.gd")
const TrophyWallWindowScript := preload("res://scripts/ui/trophy_wall_window.gd")
const RetroMuseumArchiveWindowScript := preload("res://scripts/ui/retro_museum_archive_window.gd")

func register_window_layer(layer: Control) -> void:
	window_layer = layer

# Sitzt der Spieler gerade am Computer (ein Vollbild-Programm läuft)? Die Sidebar
# blendet darüber ihren „AUFSTEHEN"-Knopf ein — statt eines schwebenden Overlays.
var at_computer: bool = false

func _set_computer_ui(on: bool) -> void:
	if on:
		stop_live_monitor()   # zurück am Rechner → kein Live-Röhrenbild im Zimmer
	at_computer = on
	# Ein Sitzplatz, eine physische Bildröhre: CRT-Grading beginnt bereits beim
	# Kickstart-/Bootdisk-Schirm und endet erst beim Aufstehen. Einzelne Apps
	# dürfen den Effekt nicht verspätet ein- oder ausschalten.
	set_crt(on and domain_on("monitor") and bool(SettingsManager.value("crt_auto_monitor")))
	seat_changed.emit(on)

# ------------------------------------------------------- Aufstehen / Monitor

## Universelles Aufstehen vom Computer — funktioniert aus JEDEM Vollbild-Programm.
## Fängt zuerst das Bild ein, das der Spieler gerade sieht (Werkbank, X-COPY …),
## zeigt es danach auf der Zimmer-Bildröhre und lässt den Monitor in dessen
## Farbe leuchten; schließt dann alle Vollbild-Programme und kehrt ins Zimmer
## zurück (CRT aus).
func stand_up_from_computer() -> bool:
	var blocker := computer_operation_blocker()
	if blocker != "":
		toast(blocker)
		return false
	_set_computer_ui(false)
	# Nach dem Aufstehen prüfen, ob ein Anruf fällig ist (z. B. Stefan, sobald der
	# Amiga läuft) — dann klingelt es prompt, statt erst beim nächsten Zeitfenster.
	PhoneManager.ring_due_at_home.call_deferred()
	var host: Control = GameManager.location_host
	var app: Control = _top_program(host) if host != null else null
	if app != null and str(app.name) == "BootSelect":
		# Kickstarts Medienwahl ist kein pausierbares Programm. Ein Standbild oder
		# Live-Reparenting wuerde beim naechsten Monitor-Klick denselben Dialog
		# erneut oeffnen und den Spieler in einer Schleife festhalten.
		UiComputerPower.close_boot_selector()
		monitor_texture = null
		monitor_program = ""
		monitor_live = false
		monitor_on = false
		monitor_changed.emit()
	elif app != null and UiLiveMonitor.is_reparentable(app):
		# Tool/OS-App (Werkbank, X-COPY, MOD-Player, Demo …) läuft in ECHTZEIT auf der
		# Röhre weiter — in den Monitor-SubViewport umgehängt, nicht geschlossen.
		UiLiveMonitor.run_app(self, app)
		# X-COPY liegt über der Werkbank. Nach dem Umhängen in die echte
		# Monitor-Röhre darf der darunterliegende Desktop samt Diskettenfenster
		# nicht als raumfüllender Restbildschirm stehen bleiben.
		_close_all_fullscreen()
	elif app == null and MusicManager.is_playing():
		# Kein Programm offen, nur eine Sounddiskette → musik-reaktiver Demoscreen.
		UiLiveMonitor.run_music(self)
	else:
		# Vollspiel (nicht live umhängbar) oder nichts → Standbild wie bisher.
		await _capture_monitor()
		_close_all_fullscreen()
	set_crt(false)
	return true


## Einziger Navigationsweg für dauerhaft sichtbare HUD-Buttons. Dadurch kann
## kein Inventar-/Orte-Klick einen Vollbildschirm einfach überdecken und den
## CRT-Shader im Zimmer zurücklassen. Erst wird derselbe Aufstehpfad wie beim
## AUFSTEHEN-Knopf vollständig abgearbeitet, dann öffnet das gewünschte Ziel.
func navigate_from_hud(action: Callable) -> void:
	if not action.is_valid():
		return
	if at_computer:
		if not await stand_up_from_computer():
			return
	action.call()


## Aktive Medienoperationen dürfen weder unsichtbar im Zimmer noch hinter einer
## anderen Location weiterlaufen. Apps melden dies über has_active_operation().
func computer_operation_blocker() -> String:
	var app: Control = null
	var host: Control = GameManager.location_host
	if host != null:
		app = _top_program(host)
	if app == null and _live_app != null and is_instance_valid(_live_app):
		app = _live_app
	if app != null and app.has_method("has_active_operation") \
			and bool(app.call("has_active_operation")):
		if app.has_method("active_operation_message"):
			return str(app.call("active_operation_message"))
		return "Ein Laufwerksvorgang arbeitet noch. Erst stoppen oder vollständig abschließen."
	return ""


## Harte Ortswechsel-Barriere: vor Reisezeit und Fahrpreis alle Computer-Layer
## synchron normalisieren. So kann der Monitor-CRT nie in einen Laden mitreisen.
func prepare_location_change() -> bool:
	var blocker := computer_operation_blocker()
	if blocker != "":
		toast(blocker)
		return false
	if at_computer:
		_set_computer_ui(false)
	stop_live_monitor()
	_close_all_fullscreen()
	set_crt(false)
	return true

func _top_program(host: Control) -> Control:
	var best: Control = null
	for child in host.get_children():
		if not (child is Control):
			continue
		if child is WbApp or child is GuruScreen or child.name == "XCopy" \
				or child.name == "Werkbank" or child.name == "BootSelect" \
				or str(child.name).begins_with("app_"):
			if best == null or child.z_index >= best.z_index:
				best = child
	return best

## Standbild des obersten Programms in eine kleine Textur einfangen (Retro-
## Auflösung) und die dominante Farbe fürs Lichtspill ableiten.
func _capture_monitor() -> void:
	var host: Control = GameManager.location_host
	if host == null:
		return
	var prog := _top_program(host)
	if prog == null:
		return
	monitor_program = str(prog.name)
	var vp := get_viewport()
	if vp == null:
		return
	await RenderingServer.frame_post_draw
	var full: Image = vp.get_texture().get_image()
	if full == null:
		return
	# Design- → Pixel-Verhältnis (Content-Scaling), um den Programmausschnitt
	# aus dem Vollbild zu schneiden.
	var design: Vector2 = vp.get_visible_rect().size
	if design.x <= 0.0 or design.y <= 0.0:
		return
	var ratio: Vector2 = Vector2(full.get_size()) / design
	var r: Rect2 = prog.get_global_rect()
	var px := Rect2i(
		Vector2i((r.position * ratio).floor()),
		Vector2i((r.size * ratio).floor()))
	px = px.intersection(Rect2i(Vector2i.ZERO, full.get_size()))
	if px.size.x < 8 or px.size.y < 8:
		return
	var shot: Image = full.get_region(px)
	shot.resize(320, 200, Image.INTERPOLATE_BILINEAR)
	monitor_texture = ImageTexture.create_from_image(shot)
	# Dominante Farbe = Durchschnitt (auf 1×1 herunterrechnen).
	var avg: Image = shot.duplicate()
	avg.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var c: Color = avg.get_pixel(0, 0)
	# etwas anheben, damit das Spill auch bei dunklen Screens trägt
	monitor_color = c.lightened(0.1)
	monitor_on = true
	monitor_changed.emit()

func _close_all_fullscreen() -> void:
	var host: Control = GameManager.location_host
	for key in _FULLSCREEN_WINDOWS:
		close_window(key)
	if host == null:
		return
	for child in host.get_children():
		if child is WbApp or child is GuruScreen or child.name == "XCopy" \
				or child.name == "Werkbank" or child.name == "BootSelect" \
				or str(child.name).begins_with("app_"):
			child.queue_free()

## Monitor manuell ausschalten (z. B. bei Bedarf) — schwarze Röhre.
func monitor_off() -> void:
	monitor_on = false
	monitor_changed.emit()

# --------------------------------------------------- Live-Monitor (Echtzeit)
# Implementierung in scripts/ui/ui_live_monitor.gd (Zeilen-Budget-Split);
# hier nur die stabile Fassade für Aufrufer und Tests.

func start_live_monitor() -> void:
	UiLiveMonitor.start(self)

func resume_live_app() -> bool:
	return UiLiveMonitor.resume(self)

func stop_live_monitor() -> void:
	UiLiveMonitor.stop(self)

## Meldung in den INFOS-Ticker schreiben (ersetzt klassische Toasts).
func toast(text: String) -> void:
	UiWindowSupport.toast(self, text)


func set_notebook_attention(active: bool, item_count: int) -> void:
	UiWindowSupport.set_notebook_attention(self, active, item_count)

# ------------------------------------------------------------- Fenster öffnen

## Fenster unter einem Schlüssel öffnen; existiert es schon, wird es
## geschlossen (Toggle-Verhalten für die Sidebar-Buttons).
func toggle_window(key: String, factory: Callable) -> void:
	if window_layer == null:
		return
	var existing := window_layer.get_node_or_null(NodePath(key))
	if existing != null:
		existing.queue_free()
		return
	var window: Control = factory.call()
	window.name = key
	window_layer.add_child(window)
	_center_window(window)

func _center_window(window: Control) -> void:
	UiWindowSupport.center(window_layer, window)

func open_diskbox() -> void:
	toggle_window("win_diskbox", func() -> Control: return DiskBoxWindow.new())


func open_collection_cabinet() -> void:
	toggle_window("win_collection_cabinet", func() -> Control: return CollectionCabinetWindowScript.new())


func open_trophy_wall() -> void:
	toggle_window("win_trophy_wall", func() -> Control: return TrophyWallWindowScript.new())


func open_retro_museum_archive(section := "years") -> void:
	if window_layer == null:
		return
	var existing := window_layer.get_node_or_null("win_retro_museum_archive")
	if existing != null:
		existing.name = "win_retro_museum_archive_closing"
		existing.queue_free()
	var window := RetroMuseumArchiveWindowScript.new()
	window.initial_section = str(section)
	window.name = "win_retro_museum_archive"
	window_layer.add_child(window)
	_center_window(window)


func open_software_inserts(software_id: String, insert_id: String = "",
		reference: Dictionary = {}) -> void:
	if window_layer == null:
		return
	var existing := window_layer.get_node_or_null("win_software_inserts")
	if existing != null:
		existing.name = "win_software_inserts_closing"
		existing.queue_free()
	var window := SoftwareInsertsWindowScript.new()
	window.software_id = software_id
	window.initial_insert_id = insert_id
	window.reference = reference.duplicate(true)
	window.name = "win_software_inserts"
	window_layer.add_child(window)
	_center_window(window)


func open_copy_tutorial(phase := "acquired") -> void:
	if window_layer == null:
		return
	var existing := window_layer.get_node_or_null("win_copy_tutorial")
	if existing != null:
		existing.name = "win_copy_tutorial_closing"
		existing.queue_free()
	var window := CopyTutorialWindow.new()
	window.phase = str(phase)
	window.name = "win_copy_tutorial"
	window_layer.add_child(window)
	_center_window(window)

## Stabile Minispiel-Fassade. Zugang, Fensterregeln und Parameterübergabe liegen
## zentral im UiMinigameLauncher, damit alle Aufrufer dieselben Verträge nutzen.
func open_box_sort() -> void:
	UiMinigames.open_box_sort(self)

func open_drive_clean() -> void:
	UiMinigames.open_drive_clean(self)

func open_joystick_repair() -> void:
	UiMinigames.open_joystick_repair(self)

func open_listing_type(listing_id := "") -> void:
	UiMinigames.open_listing_type(self, str(listing_id))

func open_cable_untangle(job_id := "job_gruber_cables") -> void:
	UiMinigames.open_cable_untangle(self, job_id)

func open_room_tidy() -> void:
	UiMinigames.open_room_tidy(self)

func open_monitor_tune() -> void:
	UiMinigames.open_monitor_tune(self)

func open_tracker_pattern() -> void:
	UiMinigames.open_tracker_pattern(self)


## Eine gemeinsame Projektwerkbank fuer Zimmer und Computerclub. Dadurch fuehrt
## der Kartenmarker des Club-Auftrags an beiden glaubwuerdigen Orten zur exakt
## selben persistenten Szene-Studio-Datei statt zu zwei auseinanderlaufenden UIs.
func open_demo_maker() -> void:
	toggle_window("win_demo", func() -> Control: return DemoMakerWindowScript.new())

func open_hardware_assembly(job_id := "") -> void:
	UiMinigames.open_hardware_assembly(self, job_id)

func open_bbs_carrier(file_entry: Dictionary) -> void:
	UiMinigames.open_bbs_carrier(self, file_entry)

func open_bargain(offer_id: int) -> void:
	UiMinigames.open_bargain(self, offer_id)

func open_disk_rescue(source: Disk) -> void:
	UiMinigames.open_disk_rescue(self, source)

func open_disk_repair(source: Disk) -> void:
	UiMinigames.open_disk_repair(self, source)

func open_printer_align() -> void:
	UiMinigames.open_printer_align(self)

func open_mixtape() -> void:
	UiMinigames.open_mixtape(self)

func open_cracktro_optimization(project: Dictionary = {}) -> void:
	UiMinigames.open_cracktro_optimization(self, project)

func open_shop_diagnosis(job_id := "job_gruber_diagnosis") -> void:
	UiMinigames.open_shop_diagnosis(self, job_id)

func open_job_shift(job_id: String) -> void:
	UiMinigames.open_job_shift(self, job_id)

func open_household_sprint(chore_id: String) -> void:
	UiMinigames.open_household_sprint(self, chore_id)

## BYTEWERK P-8 — Vollbild-Werkstatt für eine geprüfte Gen-1-Arbeitskopie.
## Der Manager entscheidet allein über die Eignung; die UI kann dadurch weder
## Originale noch bereits fertige Releases versehentlich verändern.
func open_scene_patch(disk: Disk) -> void:
	if disk == null:
		toast(Loc.t("sys.ui_manager.erst_arbeitskopie_auswahlen", "Erst eine Arbeitskopie auswählen."))
		return
	var manager := get_node_or_null("/root/SceneReleaseManager")
	if manager == null or not manager.has_method("eligibility"):
		toast(Loc.t("sys.ui_manager.bytewerk_ist_noch_nicht_geladen", "BYTEWERK ist noch nicht geladen."))
		return
	var eligibility = manager.call("eligibility", disk)
	if typeof(eligibility) != TYPE_DICTIONARY or not bool(eligibility.get("ok", false)):
		toast(str(eligibility.get("text", "Diese Diskette ist nicht für BYTEWERK geeignet.")) if typeof(eligibility) == TYPE_DICTIONARY
			else "Diese Diskette ist nicht für BYTEWERK geeignet.")
		return
	var host: Control = GameManager.location_host
	if host == null:
		return
	var existing := host.get_node_or_null("ScenePatch")
	if existing != null:
		existing.queue_free()
		return
	close_window("win_diskbox")
	var app := ScenePatchAppScript.new()
	app.name = "ScenePatch"
	app.disk = disk
	host.add_child(app)
	_set_computer_ui(true)

## Etikett-Designer (Minispiel) für eine bestimmte Diskette öffnen.
func open_label_designer(disk) -> void:
	if disk == null:
		toast(Loc.t("sys.ui_manager.erst_diskette_wahlen", "Erst eine Diskette wählen."))
		return
	close_window("win_label_designer")
	toggle_window("win_label_designer", func() -> Control:
		var w := LabelDesigner.new()
		w.disk = disk
		return w)

## Jahres-Rückblick am Jahreswechsel (vom MemoryManager ausgelöst).
func open_year_review(review_year: int) -> void:
	close_window("win_year_review")
	toggle_window("win_year_review", func() -> Control:
		var w := YearReviewWindow.new()
		w.year = review_year
		return w)

## Vollbild-Silvestersequenz VOR dem eigentlichen Kalender-Commit.
## Rueckgabe ist absichtlich der Screen selbst: Der Kampagnenkalender verbindet
## dessen `finished(from_year, to_year, skipped)` und setzt TimeManager erst dann
## atomar auf das neue Jahr. Mehrfaches Oeffnen derselben Sequenz ist idempotent.
func open_year_transition(from_year: int, to_year: int, review: Dictionary = {}) -> Control:
	return UiTransitionFlow.open_year(self, YearTransitionScreenScene, from_year, to_year, review)


## Eigenstaendiger Demoabschluss. Im Gegensatz zum normalen Jahresbildschirm
## besitzt er bewusst kein `finished(from,to)`-Signal: Es gibt keinen Weg, ueber
## diese Oberflaeche einen Kalender-Commit nach 1991 auszuloesen.
func open_first_year_demo_finale(review: Dictionary = {}) -> Control:
	if window_layer == null:
		return null
	var existing := window_layer.get_node_or_null("win_first_year_demo_finale") as Control
	if existing != null:
		existing.move_to_front()
		return existing
	close_window("win_year_transition")
	close_window("win_sleep_transition")
	var screen := FirstYearDemoFinaleScene.new() as Control
	screen.name = "win_first_year_demo_finale"
	screen.call("configure", review)
	screen.set_meta("no_center", true)
	window_layer.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return screen


## Vollbild-Tageswechsel NACH dem atomaren Kalender-Commit. Datumsevents und
## Lieferungen duerfen sich darunter bereits vorbereiten; der Spieler sieht sie
## erst, nachdem die Morgenkarte bewusst mit WEITER geschlossen wurde.
func open_sleep_transition(from_date: Dictionary) -> Control:
	return UiTransitionFlow.open_sleep(self, SleepTransitionScreenScene, from_date)


## Kuratierter Morgen-Aufmacher. Datumsfeste Events haben Vorrang; danach folgen
## die echten wiederkehrenden Termine Flohmarkt und Computerclub. Diese Daten
## werden nur praesentiert – EventManager bleibt allein fuer Folgen/Choices zustaendig.
func _morning_feature() -> Dictionary:
	return UiTransitionFlow.morning_feature()


## Stabile, bewusst dünne Fassade für Daten- und Questaufrufer.
func open_werkbank() -> void: UiPrograms.open_werkbank(self)
func open_hdd_setup() -> void: UiPrograms.open_named(self, "HddSetup", "hdd_setup")
func open_modem_config() -> void: UiPrograms.open_named(self, "ModemConfig", "modem")
func open_printer_config() -> void: UiPrograms.open_named(self, "PrinterConfig", "printer")
func open_mod_player() -> void: UiPrograms.open_named(self, "ModPlayer", "mod_player")
func open_virus_checker() -> void: UiPrograms.open_named(self, "VirusChecker", "virus")
func open_summer_disk() -> void: toggle_window("win_summer_disk",
	func() -> Control: return SummerDiskWindowScript.new())
func open_paint() -> void: UiPrograms.open_named(self, "Paint", "paint")

func open_program(id: String) -> bool:
	PlaytestTelemetry.note_program_open(id)
	return UiPrograms.open_program(self, id)
func open_program_from_media(id: String) -> bool:
	PlaytestTelemetry.note_program_open(id)
	return UiPrograms.open_program_from_media(self, id)
func open_sysinfo() -> void: UiPrograms.open_named(self, "SysInfo", "sysinfo")
func open_wb_prefs() -> void: UiPrograms.open_named(self, "WbPrefs", "prefs")
func open_screenmode() -> void: UiPrograms.open_named(self, "ScreenMode", "screenmode")
func show_guru(code := "") -> void: UiPrograms.show_guru(self, str(code))
func reboot_from_guru() -> void:
	await UiPrograms.reboot_from_guru(self)
func open_text_editor() -> void: UiPrograms.open_named(self, "TextEditor", "text")
func open_sommer_basic() -> void: UiPrograms.open_named(self, "SommerBasic", "sommer_basic")
func open_sommer_suite() -> void: UiPrograms.open_named(self, "SommerSuite", "sommer_suite")
func open_sommer_game() -> void: UiPrograms.open_named(self, "SommerGame", "sommer_game")
func open_disk_copy(source: Disk = null, operation_kind := "copy") -> void:
	UiPrograms.open_xcopy(self, false, source, operation_kind)
func open_xcopy_pro() -> void: UiPrograms.open_xcopy(self, true)
func open_sommer_copy() -> void: UiPrograms.open_xcopy(self, false, null, "copy", "sommer")
## Sortiment öffnen. mode "catalog" springt direkt in den Bestellkatalog
## (Theke), "stock" ins Regal.
func open_shop(mode := "stock") -> void:
	toggle_window("win_shop", func() -> Control:
		var w: Control = ShopWindow.new()
		w.start_mode = mode
		return w)

## Aufrüst-Baum (GDD §7) — HardwareManager über den bestehenden Kaufwegen.
func open_upgrade_tree() -> void:
	toggle_window("win_upgrades", func() -> Control:
		return load("res://scripts/ui/upgrade_tree_window.gd").new())

func open_map(target: String = "", preferred_mode: String = "", job_id: String = "") -> void:
	# Normale Sidebar-Nutzung behaelt das bekannte Toggle-Verhalten. Ein gezielter
	# Arbeitsweg fokussiert dagegen ein bereits offenes Fenster oder erzeugt eine
	# Karte mit gesetztem Ziel, Verkehrsmittel und Schichtvertrag.
	if target.is_empty() and preferred_mode.is_empty() and job_id.is_empty():
		toggle_window("win_map", func() -> Control: return MapWindow.new())
		return
	if window_layer == null:
		return
	var existing := window_layer.get_node_or_null("win_map")
	if existing != null:
		existing.call("focus_destination", target, preferred_mode, job_id)
		return
	var window: Control = MapWindow.new()
	window.set("initial_target", target)
	window.set("initial_mode", preferred_mode)
	window.set("initial_job_id", job_id)
	window.name = "win_map"
	window_layer.add_child(window)
	_center_window(window)

func open_contacts() -> void:
	toggle_window("win_contacts", func() -> Control: return ContactsWindow.new())

func open_answering_machine() -> void:
	toggle_window("win_answering_machine", func() -> Control: return AnsweringMachineWindow.new())

func open_postcards() -> void:
	toggle_window("win_postcards", func() -> Control: return PostcardWindow.new())

func open_bank(tab := "sparbuch") -> void:
	toggle_window("win_bank", func() -> Control:
		var window := BankWindow.new()
		window.start_tab = tab
		return window)


func open_bank_atm() -> void:
	toggle_window("win_bank_atm", func() -> Control: return BankAtmWindowScript.new())

## Telefon — zu Hause am eigenen Anschluss, unterwegs als Telefonzelle (booth).
func open_phone(booth := false) -> void:
	close_window("win_phone")
	toggle_window("win_phone", func() -> Control:
		var w := PhoneWindow.new()
		w.booth = booth
		return w)

func open_tasks() -> void:
	notebook_opened.emit()
	toggle_window("win_tasks", func() -> Control: return TaskBoardWindow.new())

func open_playtest_report() -> void:
	if not DevelopmentGate.enabled():
		return
	var report_script: Script = load(PLAYTEST_REPORT_WINDOW_PATH) as Script
	if report_script == null:
		return
	toggle_window("win_playtest_report", func() -> Control: return report_script.new())

func open_calendar() -> void:
	toggle_window("win_calendar", func() -> Control: return CalendarWindow.new())

func open_jobs() -> void:
	jobs_opened.emit()
	toggle_window("win_jobs", func() -> Control: return JobBoardWindow.new())

func open_achievements() -> void:
	toggle_window("win_achievements", func() -> Control: return AchievementWindow.new())

## Foto-Album / Erinnerungen (Systemmenü → 📷).
func open_photos() -> void:
	toggle_window("win_photos", func() -> Control: return PhotoAlbumWindow.new())

## Eingehender Anruf (klingelt zu Hause) — Live rangehen oder klingeln lassen.
func open_incoming_call(call_def: Dictionary) -> void:
	toggle_window("win_incoming", func() -> Control:
		var w := IncomingCallWindow.new()
		w.call_def = call_def
		return w)

## Etikett-Druck (Kopien-Handel) für eine Diskette.
func open_label_print(disk) -> void:
	if disk == null:
		toast(Loc.t("sys.ui_manager.erst_diskette_wahlen", "Erst eine Diskette wählen."))
		return
	if not PlayerStats.has_printer():
		toast(Loc.t("sys.ui_manager.kein_drucker_angeschlossen_von_hand_beschriften", "Kein Drucker angeschlossen. Von Hand beschriften geht in der Diskettenbox über »Etikett«."))
		return
	close_window("win_label_print")
	toggle_window("win_label_print", func() -> Control:
		var w := LabelPrintWindow.new()
		w.disk = disk
		return w)

## Kopien-Verkauf am aktuellen Ort (Schulhof/Club/Flohmarkt).
func open_copy_sale() -> void:
	close_window("win_copy_sale")
	toggle_window("win_copy_sale", func() -> Control:
		var w := CopySaleWindow.new()
		w.location_id = GameManager.current_location_id
		return w)

## Ist der Händler heute HIER (Wald oder Flohmarkt)?
func dealer_here() -> bool:
	return NPCManager.scheduled_place("npc_haendler") == GameManager.current_location_id

func open_dealer() -> void:
	toggle_window("win_dealer", func() -> Control: return DealerWindow.new())

func open_inventory() -> void:
	toggle_window("win_inventory", func() -> Control: return InventoryWindow.new())

func open_system_menu() -> void:
	toggle_window("win_system", func() -> Control: return SystemMenuWindow.new())

func open_options() -> void:
	toggle_window("win_options", func() -> Control: return OptionsWindow.new())

## Modem-Terminal (BBS-Welt). Zeigt selbst den „kein Modem"-Hinweis, wenn
## noch keins gekauft ist — man weiß dann, worauf man sparen kann.
func open_bbs() -> void:
	toggle_window("win_bbs", func() -> Control: return BBSWindow.new())

## Die Anlage — MOD-Player. Musik läuft weiter, wenn das Fenster zugeht.
func open_music() -> void:
	toggle_window("win_music", func() -> Control: return MusicWindow.new())

## Heftansicht — Amiga-Joker-Ausgaben durchblättern (Titel/Berichte/Rückseite).
func open_magazines() -> void:
	toggle_window("win_magazine", func() -> Control: return MagazineWindow.new())

## Computerclub — MOD-Bibliothek (stöbern, vorhören, auf Diskette kopieren).
func open_music_club() -> void:
	toggle_window("win_music_club", func() -> Control: return MusicClubWindow.new())

## Flohmarkt — Stände + Mystery-Kartons.
func open_flea() -> void:
	toggle_window("win_flea", func() -> Control: return FleaWindow.new())

## Schulhof-Gespräch (Gruppe) oder Schwarzes Brett. Immer frisch öffnen, damit
## der Wechsel zwischen Gruppen kein Toggle-Zu ist.
func open_rumors(mode: String, group_id := "") -> void:
	close_window("win_rumor")
	toggle_window("win_rumor", func() -> Control:
		var w: Control = RumorWindow.new()
		w.mode = mode
		w.group_id = group_id
		return w)

## „Diskette starten" — Kopierschutz-Erlebnis + Vollspiel-Start. Implementierung
## in scripts/ui/ui_disk_flow.gd (Zeilen-Budget-Split); hier die stabile Fassade.
func play_disk_flow(disk: Disk) -> void:
	UiDiskFlow.play(self, disk)

func open_dialogue() -> void:
	# Ein bereits sichtbares Dialogfenster weiterverwenden. start_dialogue()/
	# start_bark() emittieren direkt danach node_changed; dadurch aktualisiert sich
	# dieselbe Instanz atomar, ohne ein zum Frame-Ende noch lebendes queue_free()-
	# Fenster mit einem zweiten Fenster gleichen Namens zu überholen.
	if window_layer == null:
		return
	var existing := window_layer.get_node_or_null("win_dialogue")
	if existing != null:
		existing.move_to_front()
		return
	toggle_window("win_dialogue", func() -> Control: return DialogueWindow.new())

func open_event(event: Dictionary) -> Control:
	if window_layer == null:
		return null
	var existing: Control = window_layer.get_node_or_null("win_event")
	if existing != null and not existing.is_queued_for_deletion():
		existing.move_to_front()
		return existing
	if existing != null:
		return null
	var window: Control = EventWindow.new()
	window.name = "win_event"
	window.event = event
	window_layer.add_child(window)
	_center_window(window)
	return window

## Abspann-Statistik (Dekaden-Ende): Vollbild-Overlay über der Fensterebene.
func open_endgame_stats() -> void:
	if window_layer == null:
		return
	var existing := window_layer.get_node_or_null("win_endgame")
	if existing != null:
		return
	var screen := EndgameStatsScene.new()
	screen.name = "win_endgame"
	screen.set_meta("no_center", true)
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	window_layer.add_child(screen)

func open_info(title: String, text: String, image_path: String = "") -> void:
	close_window("win_info")
	toggle_window("win_info", func() -> Control:
		var w: Control = InfoWindow.new()
		w.title = title
		w.body_text = text
		w.image_path = image_path   # optionales Titelbild (z. B. Zeitungs-Cover)
		return w)

func open_help() -> void:
	open_info("HILFE", UiWindowSupport.HELP_TEXT)

func close_window(key: String) -> void:
	if window_layer == null:
		return
	var existing := window_layer.get_node_or_null(NodePath(key))
	if existing != null:
		existing.queue_free()

func close_all_windows() -> void:
	if window_layer == null:
		return
	for child in window_layer.get_children():
		child.queue_free()
