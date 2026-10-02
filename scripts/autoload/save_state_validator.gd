extends RefCounted
## Reine Eingangspruefung vor der ersten Save-Mutation. Fehlende additive Felder
## bleiben fuer Migrationen erlaubt; vorhandene Felder muessen ihren Typ halten.

const TimeClock := preload("res://scripts/autoload/time_clock.gd")
const BLOCKS := ["identity", "stats", "time", "inventory", "room", "disks", "npcs",
	"bbs", "orders", "rumors", "flea", "dealer", "raid", "music", "memories",
	"phone", "narrative", "postcards", "bank", "tasks", "copytrade", "scene_release",
	"jobs", "quests", "achievements", "minigames", "events", "amiga_games",
	"photos", "integrity", "game", "sommer_game", "playtest"]
# Pfade mit * pruefen jeden Eintrag eines Containers, auch bei leeren Defaults.
const CONTAINERS := {
	"identity.hints": TYPE_DICTIONARY,
	"stats.hardware": TYPE_DICTIONARY, "stats.peripherals": TYPE_DICTIONARY,
	"stats.programs": TYPE_ARRAY, "stats.hdd_volumes": TYPE_DICTIONARY,
	"stats.hdd_volumes.*": TYPE_DICTIONARY,
	"stats.hdd_volumes.*.files": TYPE_DICTIONARY,
	"stats.peripherals.*": TYPE_DICTIONARY,
	"inventory.items": TYPE_DICTIONARY,
	"room.objects": TYPE_ARRAY, "room.objects.*": TYPE_DICTIONARY,
	"room.litter": TYPE_ARRAY, "room.litter.*": TYPE_DICTIONARY,
	"disks.disks": TYPE_ARRAY, "disks.disks.*": TYPE_DICTIONARY,
	"npcs.trust": TYPE_DICTIONARY,
	"bbs.visited": TYPE_ARRAY, "bbs.assistant_history": TYPE_DICTIONARY,
	"bbs.assistant_history.*": TYPE_ARRAY,
	"orders.pending": TYPE_ARRAY, "orders.pending.*": TYPE_DICTIONARY,
	"orders.arrived": TYPE_ARRAY, "orders.arrived.*": TYPE_DICTIONARY,
	"orders.fulfilled": TYPE_ARRAY,
	"rumors.active": TYPE_ARRAY, "rumors.active.*": TYPE_DICTIONARY,
	"rumors.resolved": TYPE_ARRAY, "rumors.resolved.*": TYPE_DICTIONARY,
	"rumors.seeded": TYPE_DICTIONARY,
	"flea.offers": TYPE_ARRAY, "flea.offers.*": TYPE_DICTIONARY,
	"flea.boxes": TYPE_ARRAY, "flea.boxes.*": TYPE_DICTIONARY,
	"flea.tip": TYPE_DICTIONARY, "dealer.stock": TYPE_ARRAY,
	"dealer.stock.*": TYPE_DICTIONARY, "music.owned": TYPE_ARRAY,
	"memories.memories": TYPE_ARRAY, "memories.memories.*": TYPE_DICTIONARY,
	"memories.milestones": TYPE_ARRAY,
	"phone.messages": TYPE_ARRAY, "phone.messages.*": TYPE_DICTIONARY,
	"phone.received": TYPE_ARRAY, "phone.pending": TYPE_DICTIONARY,
	"phone.known_contacts": TYPE_ARRAY,
	"narrative.recent": TYPE_DICTIONARY, "narrative.once": TYPE_DICTIONARY,
	"postcards.inbox": TYPE_ARRAY, "postcards.inbox.*": TYPE_DICTIONARY,
	"postcards.received": TYPE_ARRAY, "postcards.replied": TYPE_DICTIONARY,
	"bank.transactions": TYPE_ARRAY, "bank.transactions.*": TYPE_DICTIONARY,
	"tasks.tasks": TYPE_ARRAY, "copytrade.sold": TYPE_DICTIONARY,
	"scene_release.releases": TYPE_DICTIONARY, "scene_release.releases.*": TYPE_DICTIONARY,
	"scene_release.uploads": TYPE_ARRAY, "scene_release.uploads.*": TYPE_DICTIONARY,
	"scene_release.group_rep": TYPE_DICTIONARY,
	"scene_release.cooperation_offers": TYPE_ARRAY,
	"scene_release.cooperation_status": TYPE_DICTIONARY,
	"scene_release.school_attempts": TYPE_DICTIONARY,
	"scene_release.school_interruptions": TYPE_DICTIONARY,
	"scene_release.alias_assignments": TYPE_DICTIONARY,
	"scene_release.sales": TYPE_ARRAY, "scene_release.sales.*": TYPE_DICTIONARY,
	"scene_release.game_distribution": TYPE_DICTIONARY,
	"jobs.last_day": TYPE_DICTIONARY, "jobs.done_today": TYPE_DICTIONARY,
	"jobs.completed_counts": TYPE_DICTIONARY,
	"quests.status": TYPE_DICTIONARY, "quests.status.*": TYPE_DICTIONARY,
	"quests.status.*.actions": TYPE_DICTIONARY,
	"achievements.unlocked": TYPE_DICTIONARY,
	"minigames.records": TYPE_DICTIONARY, "minigames.creations": TYPE_DICTIONARY,
	"minigames.creations.*": TYPE_ARRAY, "minigames.telemetry": TYPE_DICTIONARY,
	"events.cooldown_until": TYPE_DICTIONARY, "events.calendar_fired": TYPE_DICTIONARY,
	"amiga_games.records": TYPE_DICTIONARY, "amiga_games.seen_runs": TYPE_DICTIONARY,
	"photos.photos": TYPE_ARRAY, "photos.photos.*": TYPE_DICTIONARY,
	"photos.auto_ids": TYPE_DICTIONARY, "game.flags": TYPE_DICTIONARY,
	"sommer_game.unlocked": TYPE_DICTIONARY, "sommer_game.projects": TYPE_DICTIONARY,
	"sommer_game.projects.*": TYPE_DICTIONARY,
	"playtest.years": TYPE_DICTIONARY, "playtest.years.*": TYPE_DICTIONARY,
	"playtest.sessions": TYPE_ARRAY,
}
const INTEGER_PATHS := ["inventory.items.*", "npcs.trust.*", "quests.status.*.stage",
	"quests.status.*.actions.*", "events.cooldown_until.*", "jobs.completed_counts.*"]

# Skalare Felder, die beim Laden int()/float() oder typisierte Zuweisungen nutzen.
const FIELDS := {
	"identity": {"name": "", "bd": 1, "bm": 1, "by": 1976, "seed": ""},
	"stats": {"geld": 0.0, "energie": 0, "hunger": 0, "ruf": 0, "wissen": 0, "eltern_toleranz": 0},
	"room": {"next_uid": 0}, "disks": {"uid_counter": 0, "set_uid_counter": 0, "sort_mode": 0},
	"flea": {"week": 0, "last_gen_day": 0, "next_id": 0},
	"dealer": {"trust": 0, "deals": 0, "wanted": "", "wanted_day": 0, "stock_day": 0},
	"raid": {"year_revenue": 0, "raids": 0, "warn_level": 0},
	"memories": {"last_resurface": 0},
	"phone": {"number": "", "bill_open": 0, "bill_due": 0, "bill_month": 0},
	"postcards": {"last_day": 0},
	"bank": {"balance": 0.0, "savings": 0.0, "asked_day": 0, "transaction_serial": 0,
		"last_interest_year": 0, "card_requested_day": 0, "card_pin": "", "pin_failures": 0},
	"scene_release": {"scene_handle": "", "scene_recognition": 0, "school_attention": 0, "release_counter": 0},
	"integrity": {"reason": ""}, "game": {"location": ""},
	"sommer_game": {"schema_version": 0, "active_project_id": ""},
	"amiga_games": {"version": 0},
	"playtest": {"schema_version": 0, "next_sequence": 0, "total_active_seconds": 0.0},
}


const RECORDS := {
	"stats.hardware": {"chip_ram_kb": 0, "slow_ram_kb": 0, "fast_ram_kb": 0,
		"ram_mb": 0.0, "drive_dirt": 0.0, "drive_alignment": 0.0,
		"joystick_condition": 0.0, "printer_visual_schema": 0, "hardware_schema": 0,
		"computer_model": "", "monitor_model": "", "mouse_model": "", "modem_model": "",
		"printer_model": "", "stereo_model": "", "ram_profile": ""},
	"stats.hdd_volumes.*": {"schema": 0, "capacity_kb": 0, "system_kb": 0,
		"installed_profile": "", "device": "", "model": "", "controller": ""},
	"room.objects.*": {"uid": 0, "id": "", "zone": ""},
	"room.litter.*": {"uid": 0, "kind": "", "target": "", "created_day": 0, "source": ""},
	"playtest.years.*": {"active_seconds": 0.0, "summer_active_seconds": 0.0,
		"non_summer_active_seconds": 0.0},
}


static func validate(state: Dictionary, max_minute: int) -> String:
	for block: String in BLOCKS:
		if state.has(block) and not state[block] is Dictionary:
			return block
	for path: String in CONTAINERS:
		if not _matches_path(state, path.split("."), int(CONTAINERS[path])):
			return path
	for block: String in FIELDS:
		var invalid := _matches_fields(state.get(block, {}), FIELDS[block])
		if not invalid.is_empty():
			return block + "." + invalid
	for path: String in RECORDS:
		if not _matches_path(state, path.split("."), TYPE_DICTIONARY, RECORDS[path]):
			return path
	for path: String in INTEGER_PATHS:
		if not _matches_path(state, path.split("."), TYPE_INT):
			return path
	var time: Dictionary = state.get("time", {})
	for key in ["year", "month", "day", "slot", "day_counter", "minute"]:
		if time.has(key) and not _integer(time[key]):
			return "time." + key
	var year := int(time.get("year", 1990))
	var month := int(time.get("month", 7))
	var day := int(time.get("day", 6))
	var slot := int(time.get("slot", 0))
	if year < 1900 or year > 2200 or month < 1 or month > 12:
		return "time.date"
	var days: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if year % 400 == 0 or (year % 4 == 0 and year % 100 != 0):
		days[1] = 29
	if day < 1 or day > days[month - 1] or slot < 0 or slot > TimeClock.NIGHT_SLOT \
			or int(time.get("day_counter", 0)) < 0:
		return "time.date"
	var minute := int(time.get("minute", TimeClock.slot_start(slot)))
	if minute < TimeClock.slot_start(0) or minute > max_minute:
		return "time.minute"
	# Disk.from_dict weist viele Felder direkt typisiert zu. Sein Defaultobjekt
	# ist die gemeinsame Felddefinition; alte, fehlende Felder bleiben migrierbar.
	var disk_defaults := Disk.new().to_dict()
	for disk: Dictionary in state.get("disks", {}).get("disks", []):
		var error := _matches_fields(disk, disk_defaults)
		if not error.is_empty():
			return "disks.disks." + error
	return ""


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) == floorf(float(value))


static func _matches_fields(value: Dictionary, defaults: Dictionary) -> String:
	for key: Variant in defaults:
		if not value.has(key):
			continue
		var kind := typeof(defaults[key])
		if not _matches_type(value[key], kind):
			return str(key)
	return ""


static func _matches_type(value: Variant, kind: int) -> bool:
	if kind == TYPE_INT:
		return _integer(value)
	if kind == TYPE_FLOAT:
		return (value is int or value is float) and is_finite(float(value))
	return typeof(value) == kind


static func _matches_path(value: Variant, parts: PackedStringArray, kind: int, fields: Dictionary = {}) -> bool:
	if parts.is_empty():
		return _matches_type(value, kind) and (fields.is_empty() or _matches_fields(value, fields).is_empty())
	var next := parts.slice(1)
	if parts[0] == "*":
		if not (value is Array or value is Dictionary):
			return false
		var entries: Array = value.values() if value is Dictionary else value
		for entry: Variant in entries:
			if not _matches_path(entry, next, kind, fields):
				return false
		return true
	if not value is Dictionary:
		return false
	return not value.has(parts[0]) or _matches_path(value[parts[0]], next, kind, fields)
