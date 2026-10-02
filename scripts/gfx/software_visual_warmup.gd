extends Node
## Verteilter Start-/Kontext-Warmup für physische Softwaregrafik.
## Arbeitet absichtlich in kleinen Jobs über mehrere Frames: Titelbildzeit wird
## genutzt, ohne einen langen Ladebildschirm oder einen 883-MB-Komplettcache.

const BoxComposer := preload("res://scripts/gfx/software_box_composer.gd")
const DiskComposerScript := preload("res://scripts/gfx/disk_composer.gd")
const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")
## Weiches CPU-Budget pro Zeichenframe. Ein bereits gestarteter Composer-Job
## kann nicht mitten in einer nativen Image-Operation unterbrochen werden; nach
## jedem Job wird das Budget aber erneut geprüft und gegebenenfalls bis zum
## nächsten Frame abgegeben.
const FRAME_BUDGET_USEC := 4_000

var _jobs: Array[Dictionary] = []
var _queued := {}
var _warmed := {}
var _running := false
var _drain_scheduled := false
var _completed_jobs := 0
var _total_jobs := 0
var _active_label := ""
var _last_job_usec := 0
var _max_job_usec := 0
var _max_job_label := ""
var _max_job_usec_by_kind: Dictionary = {}


func _ready() -> void:
	name = "SoftwareVisualWarmup"
	if not DiskManager.disks_changed.is_connected(_queue_current):
		DiskManager.disks_changed.connect(_queue_current)
	if not FleaMarketManager.flea_changed.is_connected(_queue_current):
		FleaMarketManager.flea_changed.connect(_queue_current)
	if not GameManager.game_started.is_connected(_queue_current):
		GameManager.game_started.connect(_queue_current)
	if not TimeManager.day_changed.is_connected(_queue_current):
		TimeManager.day_changed.connect(_queue_current)
	if not TimeManager.year_changed.is_connected(_on_year_changed):
		TimeManager.year_changed.connect(_on_year_changed)
	call_deferred("_queue_current")


func _exit_tree() -> void:
	# Ein vor dem Reparenting nur vorgemerkter Deferred-Call darf den Drain nach
	# dem erneuten _ready() nicht dauerhaft als "schon geplant" blockieren.
	_drain_scheduled = false
	if DiskManager.disks_changed.is_connected(_queue_current):
		DiskManager.disks_changed.disconnect(_queue_current)
	if FleaMarketManager.flea_changed.is_connected(_queue_current):
		FleaMarketManager.flea_changed.disconnect(_queue_current)
	if GameManager.game_started.is_connected(_queue_current):
		GameManager.game_started.disconnect(_queue_current)
	if TimeManager.day_changed.is_connected(_queue_current):
		TimeManager.day_changed.disconnect(_queue_current)
	if TimeManager.year_changed.is_connected(_on_year_changed):
		TimeManager.year_changed.disconnect(_on_year_changed)


func _on_year_changed(_year: int) -> void:
	_queue_current()


func _queue_current() -> void:
	# Die teure erste Gehäuseumfärbung wird schon auf dem Titelbild erledigt.
	_enqueue("disk_body_red", {"kind": "disk_body", "color": "red"})
	_enqueue("disk_body_purple", {"kind": "disk_body", "color": "purple"})
	for value: Variant in ShopManager.game_stock():
		var id := str(value)
		_enqueue_set(id, false)
	var boxed: Array = DiskManager.boxed_collection()
	for value: Variant in boxed.slice(0, mini(16, boxed.size())):
		if value is Disk:
			_enqueue_set((value as Disk).software_id, true, value as Disk)
	for raw: Variant in FleaMarketManager.offers:
		if not raw is Dictionary or not (raw as Dictionary).has("software_id"):
			continue
		var offer := raw as Dictionary
		var id := str(offer["software_id"])
		var form := str(offer.get("form", "disk"))
		if form == "box":
			_enqueue("box/%s/front/used" % id,
				{"kind": "box", "id": id, "condition": "used", "side": "front"})
		elif form == "manual":
			_enqueue("manual/%s" % id, {"kind": "manual", "id": id})
		else:
			_enqueue("disk/%s/red/1" % id,
				{"kind": "disk", "id": id, "color": "red", "number": 1})
	_schedule_drain()


func _enqueue_set(id: String, full: bool, disk: Disk = null) -> void:
	if id.is_empty():
		return
	var bible := get_node_or_null("/root/SoftwareBible")
	var info: Dictionary = bible.call("entry", id) if bible != null else {}
	var condition := disk.package_condition if disk != null else "sealed"
	var color := disk.color if disk != null else (
		"purple" if str(info.get("production_tier", "standard")).to_lower() == "aaa" else "red")
	var count := disk.disk_count if disk != null else (int(bible.call("disk_count", id)) if bible != null else 1)
	_enqueue("box/%s/front/%s" % [id, condition],
		{"kind": "box", "id": id, "condition": condition, "side": "front", "color": color, "count": count})
	_enqueue("disk/%s/%s/1" % [id, color],
		{"kind": "disk", "id": id, "color": color, "number": 1})
	if full:
		_enqueue("box/%s/back/%s" % [id, condition],
			{"kind": "box", "id": id, "condition": condition, "side": "back", "color": color, "count": count})
		_enqueue("manual/%s" % id, {"kind": "manual", "id": id})


func _enqueue(key: String, job: Dictionary) -> void:
	if _queued.has(key) or _warmed.has(key):
		return
	_enqueue_source_for(job)
	job["key"] = key
	_jobs.append(job)
	_queued[key] = true
	_total_jobs += 1


## Kalte JPEG-/PNG-Dekodierung und Komposition werden getrennt budgetiert.
## Der Source-Job steht unmittelbar vor seinem Verbraucher; auch bei einem
## grossen Kontext kann der begrenzte Raw-LRU das Bild daher nicht vorher
## wieder verdraengen.
func _enqueue_source_for(job: Dictionary) -> void:
	var kind := str(job.get("kind", ""))
	if kind not in ["box", "disk", "manual"]:
		return
	var bible := get_node_or_null("/root/SoftwareBible")
	if bible == null:
		return
	var id := str(job.get("id", ""))
	var art_kind := ""
	match kind:
		"box":
			art_kind = "box_back" if str(job.get("side", "front")) == "back" else "box_front"
		"disk":
			var disk_number := int(job.get("number", 1))
			art_kind = "disk_label" if disk_number <= 1 else "disk_label_%d" % disk_number
		"manual":
			art_kind = "manual_cover"
	var path := str(bible.call("art_path", id, art_kind))
	if path.is_empty() and kind == "disk" and art_kind != "disk_label":
		path = str(bible.call("art_path", id, "disk_label"))
	if path.is_empty() and kind == "manual":
		path = str(bible.call("art_path", id, "box_front"))
	if path.is_empty():
		return
	var source_key := "source/%s" % path
	if _queued.has(source_key):
		return
	_jobs.append({"kind": "source", "path": path, "key": source_key})
	_queued[source_key] = true
	_total_jobs += 1


## Enqueue-Aufrufer sind oft Save-/Neu-Spiel-Signale. Darum darf hier nie der
## erste teure Composer noch im Signal-Stack laufen: der Drain beginnt deferred.
func _schedule_drain() -> void:
	if _running or _drain_scheduled or _jobs.is_empty() or not is_inside_tree():
		return
	_drain_scheduled = true
	call_deferred("_drain")


func _drain() -> void:
	_drain_scheduled = false
	if _running or not is_inside_tree():
		return
	_running = true
	while not _jobs.is_empty() and is_inside_tree():
		var frame_started_usec := Time.get_ticks_usec()
		var jobs_this_frame := 0
		while not _jobs.is_empty() and is_inside_tree():
			_run_next_job()
			jobs_this_frame += 1
			if jobs_this_frame > 0 \
					and Time.get_ticks_usec() - frame_started_usec >= FRAME_BUDGET_USEC:
				break
		if not _jobs.is_empty() and is_inside_tree():
			await get_tree().process_frame
	_running = false
	_active_label = ""
	# Ein Signal kann waehrend des letzten Jobs neue Arbeit eingestellt haben.
	# Der Nachlauf stellt sicher, dass kein Asset wegen eines Queue-Randfalls
	# liegen bleibt.
	_schedule_drain()


func _run_next_job() -> void:
	var job := _jobs.pop_front() as Dictionary
	var key := str(job.get("key", ""))
	var kind := str(job.get("kind", ""))
	_active_label = _job_label(job)
	var started_usec := Time.get_ticks_usec()
	_queued.erase(key)
	match kind:
		"source":
			RuntimeImages.warm_raw_image(str(job.get("path", "")))
		"disk_body":
			DiskComposerScript.composed_disk("", false, 256, 1, str(job.get("color", "red")))
		"disk":
			DiskComposerScript.composed_disk(str(job.get("id", "")), true, 256,
				int(job.get("number", 1)), str(job.get("color", "red")))
		"manual":
			BoxComposer.manual_texture(str(job.get("id", "")), 384)
		"box":
			BoxComposer.box_texture(str(job.get("id", "")), str(job.get("condition", "sealed")),
				384, str(job.get("side", "front")), str(job.get("color", "red")),
				int(job.get("count", 0)))
	# Source-Jobs spiegeln den begrenzten Raw-LRU und werden deshalb nicht
	# dauerhaft als erledigt markiert. Der eigentliche Visual-Key bleibt
	# resident/dedupliziert.
	if kind != "source":
		_warmed[key] = true
	_completed_jobs += 1
	_last_job_usec = Time.get_ticks_usec() - started_usec
	if _last_job_usec > _max_job_usec:
		_max_job_usec = _last_job_usec
		_max_job_label = _active_label
	_max_job_usec_by_kind[kind] = maxi(
		int(_max_job_usec_by_kind.get(kind, 0)), _last_job_usec)


func pending_jobs() -> int:
	return _jobs.size()


## Öffentliche Ladebarriere: Save-/Neu-Spiel-Pfade dürfen den sichtbaren
## Ladebildschirm erst schließen, wenn der neue Markt-/Sammlungszustand seine
## tatsächlich benötigten OVP-, Handbuch- und Diskettentexturen im Cache hat.
func request_current_context() -> void:
	_queue_current()


func is_idle() -> bool:
	return _jobs.is_empty() and not _running


## Der StartupLoader verwendet dieselbe Queue vor dem Hauptmenü. Die Werte sind
## echte Composer-Jobs und damit als Fortschrittsquelle belastbarer als ein
## zeitgesteuerter Scheinbalken.
func progress_snapshot() -> Dictionary:
	return {
		"completed": _completed_jobs,
		"total": _total_jobs,
		"pending": _jobs.size(),
		"running": _running,
		"label": _active_label,
		"last_job_usec": _last_job_usec,
		"max_job_usec": _max_job_usec,
		"max_job_label": _max_job_label,
		"max_job_usec_by_kind": _max_job_usec_by_kind.duplicate(),
	}


## QA-Messfenster zur getrennten Beurteilung von Boot- und Savegame-Jobs.
## Cache-/Queue-Zustand bleibt dabei unveraendert.
func reset_timing_metrics() -> void:
	_last_job_usec = 0
	_max_job_usec = 0
	_max_job_label = ""
	_max_job_usec_by_kind.clear()


func _job_label(job: Dictionary) -> String:
	match str(job.get("kind", "")):
		"source": return "Bildquelle dekodieren · %s" % str(job.get("path", "")).get_file()
		"disk_body": return "Diskettengehäuse vorbereiten"
		"disk": return "Diskettenetikett · %s" % str(job.get("id", "Software"))
		"manual": return "Handbuchseiten · %s" % str(job.get("id", "Software"))
		"box": return "OVP-Ansicht · %s" % str(job.get("id", "Software"))
	return "Softwaregrafik vorbereiten"
