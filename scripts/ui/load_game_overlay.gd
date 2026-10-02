class_name LoadGameOverlay
extends CanvasLayer
## Vollbild-Overlay für Savegame-Laden. Liegt außerhalb des UIManager-
## Fensterlayers und bleibt daher sichtbar, wenn load_game() alle Fenster leert.

const VisualScript := preload("res://scripts/ui/loading_screen_visual.gd")
## Nur ein kurzer Anteil des verteilten Software-Warmups gehoert zur sichtbaren
## Ladebarriere. Restjobs bleiben in derselben residenten Queue und laufen nach
## dem Ausblenden weiter; ein grosser Spielstand haelt die UI daher nicht mehr
## bis zu 12 Sekunden fest.
const SOFTWARE_SETTLE_BUDGET_MSEC := 180

var visual: Control


func _ready() -> void:
	layer = 500
	visual = VisualScript.new()
	visual.name = "LoadingScreenVisual"
	visual.set_anchors_preset(Control.PRESET_FULL_RECT)
	visual.set("progress", 0.04)
	add_child(visual)


func show_before_blocking_load() -> void:
	visual.set("indeterminate", true)
	visual.set("progress", 0.10)
	await get_tree().process_frame
	await get_tree().process_frame


## Wartet auf alle Arbeiten, die erst DURCH den neuen Spielzustand entstehen:
## Location-_ready/Layout, kontextabhängige Softwarebilder und die ersten
## Renderer-Kommandos. Damit endet der Ladebildschirm nicht einen Frame zu früh.
func stabilize_runtime() -> void:
	visual.set("indeterminate", false)
	visual.set("progress", 0.30)
	await get_tree().process_frame
	await get_tree().process_frame
	var warmer := get_tree().root.find_child("SoftwareVisualWarmup", true, false)
	if warmer != null and warmer.has_method("request_current_context"):
		var budget_deadline_msec := Time.get_ticks_msec() + SOFTWARE_SETTLE_BUDGET_MSEC
		warmer.call("request_current_context")
		var first_snapshot: Dictionary = warmer.call("progress_snapshot")
		var initial_remaining := maxi(1, int(first_snapshot.get("pending", 0))
			+ (1 if bool(first_snapshot.get("running", false)) else 0))
		while (is_instance_valid(warmer)
				and not bool(warmer.call("is_idle"))
				and Time.get_ticks_msec() < budget_deadline_msec):
			var snapshot: Dictionary = warmer.call("progress_snapshot")
			var remaining := int(snapshot.get("pending", 0)) \
				+ (1 if bool(snapshot.get("running", false)) else 0)
			# Der Balken gehört nur zum aktuellen Ladebatch. Kumulative Jobs aus einer
			# langen Spielsession dürfen ihn nicht schon beim Öffnen vorspulen.
			initial_remaining = maxi(initial_remaining, remaining)
			var ratio := clampf(1.0 - float(remaining) / float(initial_remaining), 0.0, 1.0)
			visual.set("progress", lerpf(0.34, 0.82, ratio))
			await get_tree().process_frame
	visual.set("progress", 0.88)
	# Mindestens zwei echte Zeichenframes lassen Canvas-Texturen und
	# Shaderpipelines an den Renderthread wandern. force_sync liegt absichtlich
	# noch hinter dem Overlay: Die einmalige GPU-Synchronisation bleibt unsichtbar.
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_sync()
	visual.set("progress", 0.96)
	await get_tree().process_frame


func finish(success: bool) -> void:
	visual.set("indeterminate", false)
	visual.set("progress", 1.0 if success else 0.0)
	await get_tree().process_frame
	if success:
		await get_tree().create_timer(0.18).timeout
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(visual, "modulate:a", 0.0, 0.38)
		await tween.finished
	queue_free()
