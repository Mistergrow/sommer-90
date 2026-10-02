extends Control
## Zentraler, fluechtiger Praesentationskanal fuer Questfortschritt.
##
## Der Layer besitzt genau eine FIFO, zeigt genau eine Karte zur Zeit und ist
## vollstaendig eingabe-transparent. Questzustand bleibt allein im
## QuestManager; Laden/Reset erzeugen deshalb keine alten Einblendungen.

const QueueScript := preload("res://scripts/ui/quest_presentation_queue.gd")
const Catalog := preload("res://scripts/ui/quest_presentation_catalog.gd")
const CardScript := preload("res://scripts/ui/quest_announcement_card.gd")

var _queue: RefCounted = QueueScript.new()
var _active_card: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_to_viewport()
	get_viewport().size_changed.connect(_sync_to_viewport)
	var quest_manager := get_node_or_null("/root/QuestManager")
	if quest_manager != null:
		if quest_manager.has_signal("quest_event"):
			quest_manager.connect("quest_event", enqueue)
		if quest_manager.has_signal("quest_presentation_reset"):
			quest_manager.connect("quest_presentation_reset", clear)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	set_process(true)


func enqueue(event: Dictionary) -> bool:
	return bool(_queue.call("enqueue", event))


func pending_count() -> int:
	return int(_queue.call("size")) + (1 if is_instance_valid(_active_card) else 0)


func clear() -> void:
	_queue.call("clear")
	if is_instance_valid(_active_card):
		_active_card.queue_free()
	_active_card = null


func _on_locale_changed(_locale: String) -> void:
	var events: Array[Dictionary] = []
	if is_instance_valid(_active_card) and _active_card.has_method("event_data"):
		events.append(_active_card.call("event_data"))
	for event: Dictionary in _queue.call("snapshot"):
		events.append(event)
	clear()
	var quest_manager := get_node_or_null("/root/QuestManager")
	for event: Dictionary in events:
		var localized: Dictionary = event.duplicate(true)
		if quest_manager != null and quest_manager.has_method("presentation_event_for"):
			var rebuilt: Variant = quest_manager.call("presentation_event_for", event)
			if rebuilt is Dictionary:
				localized = (rebuilt as Dictionary).duplicate(true)
		_queue.call("enqueue", localized)


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or is_instance_valid(_active_card):
		return
	if bool(_queue.call("is_empty")):
		return
	_start_next()


func _start_next() -> void:
	var event: Dictionary = _queue.call("pop_next")
	if event.is_empty():
		return
	var style := Catalog.style_for(event)
	var card: Control = CardScript.new()
	card.call("configure", event, style)
	card.custom_minimum_size = Vector2(_card_width(), 174.0)
	card.size = card.custom_minimum_size
	card.finished.connect(_on_card_finished.bind(card))
	add_child(card)
	_active_card = card
	_layout_card(card)
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("minigame_cue"):
		audio_manager.call("minigame_cue", "quest_presentation", style.get("sound", &"focus"))


func _on_card_finished(card: Control) -> void:
	if _active_card == card:
		_active_card = null


func _sync_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	if is_instance_valid(_active_card):
		_active_card.size = Vector2(_card_width(), 174.0)
		_active_card.custom_minimum_size = _active_card.size
		_layout_card(_active_card)


func _layout_card(card: Control) -> void:
	var base := Vector2(
		roundf((size.x - card.size.x) * 0.5),
		roundf(clampf(size.y * 0.125, 94.0, 122.0))
	)
	card.call("set_base_position", base)


func _card_width() -> float:
	return roundf(clampf(size.x * 0.66, 680.0, 980.0))
