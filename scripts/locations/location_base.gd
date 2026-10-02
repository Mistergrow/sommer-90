class_name LocationBase
extends Control
## Gemeinsame Ortsbasis für skalierte Hotspots und die Illusionsgrafik-Pipeline.
## Sie lädt die jüngste passende `<base>_<jahr>.png`-Variante, andernfalls
## `<base>.png`; Details stehen in docs/ART_PIPELINE.md.

var virtual_size := Vector2(415.0, 194.0)
var anim_time := 0.0
## true = Cover-Projektion (wie RoomCompositor/Artwork: füllt die Fläche,
## beschneidet Ränder). false = Contain (Platzhalter-Zeichnung, Letterbox).
var cover_mode := false
## Welcher Teil eines Cover-Bilds bei abweichendem Seitenverhältnis erhalten
## bleibt: (0.5, 0.5) = zentriert, (0.5, 0.0) = oben mittig. Spezialisierte
## Räume können so wichtige Wandobjekte schützen, ohne ihre Klickgeometrie von
## der Bildprojektion zu entkoppeln.
var cover_anchor := Vector2(0.5, 0.5)

## Speicherort der per Layout-Editor (F8) verschobenen Hotspots.
const PropLayout := preload("res://scripts/locations/location_prop_layout.gd")

const HOTSPOT_OVERRIDES := "res://data/location_hotspots.json"
## Bildgenaue Laufzeit-Aktoren (z. B. der Flohmarkt-Händler) werden separat
## gespeichert, damit ihre Position nicht von optionalen Hotspot-Indizes abhängt.
const ACTOR_LAYOUT_OVERRIDES := "res://data/location_actor_layouts.json"

var _has_background := false
var _hotspot_defs: Array = []  # {rect: Rect2, button: Button} oder {corners, button}
## Orts-ID (von GameManager beim Betreten gesetzt) — für anwesende NPCs.
var location_id := ""

## Dezenter Ken-Burns-Drift; Hotspots bleiben dabei unverändert.
var ken_burns := true
var _bg_rect: TextureRect = null
var _stage_25d: Control = null
var _depth_props: Array = [] # [{node:TextureRect, shadow:TextureRect, rect:Rect2}]
var _editable_actor_defs: Array = []
var _npc_actor_defs: Array = [] # [{node:Control, rect:Rect2}]
const LocationStage25DScript := preload("res://scripts/gfx/location_stage_25d.gd")
const PresentNpcBanterScript := preload("res://scripts/ui/present_npc_banter.gd")
const NpcWorldFigureScript := preload("res://scripts/gfx/npc_world_figure.gd")
const LocationAuthoring := preload("res://scripts/locations/location_authoring_bridge.gd")

const PERSONAL_ROOM_ACTORS := {
	"friend_cellar": "npc_stefan",
	"sven_home": "npc_sven",
	"mike_home": "npc_mike",
	"alex_home": "npc_alex",
	"daniel_home": "npc_daniel",
	"lisa_home": "npc_lisa",
}
## Pro Raum auf den tatsächlich freien Boden kalibriert. Der frühere eine
## Standardpunkt lag je nach Foto auf Alex' Bett, Svens Sofa oder Mikes
## Sitzsack. Werte bleiben virtuelle 1672x941-Koordinaten und können über
## location_actor_layouts.json pro NPC weiter feinjustiert werden.
const PERSONAL_ROOM_ACTOR_RECTS := {
	"friend_cellar": Rect2(935, 530, 176, 264),
	"sven_home": Rect2(720, 450, 176, 264),
	"mike_home": Rect2(700, 540, 176, 264),
	"alex_home": Rect2(760, 515, 176, 264),
	"daniel_home": Rect2(840, 490, 176, 264),
	"lisa_home": Rect2(780, 500, 176, 264),
}


func _ready() -> void:
	# Keine Anker: Größe wird explizit vom Parent gespiegelt (siehe
	# _sync_size_to_parent) — Anker + manuelles size-Setzen warnen sonst.
	_sync_size_to_parent.call_deferred()
	var parent_control := get_parent_control()
	if parent_control != null:
		parent_control.resized.connect(_sync_size_to_parent)
	_try_load_background()
	_build_25d_stage()
	_build_atmosphere()  # Tageszeit/Licht/Partikel-Overlays (data/location_fx.json)
	_build()
	_build_present_npcs()  # anwesende NPCs als klickbare Ansprech-Chips
	_connect_world_dialogue_animation()
	_apply_hotspot_overrides()  # per F8 gespeicherte Positionen anwenden
	# Hotspots erst platzieren, wenn das Layout die echte Größe kennt.
	call_deferred("_layout_hotspots")
	resized.connect(_layout_hotspots)


## Größe dem Parent nachführen (liest zur Ausführungszeit, nie stale).
func _sync_size_to_parent() -> void:
	var parent_control := get_parent_control()
	if parent_control != null:
		position = Vector2.ZERO
		size = parent_control.size


## Von Unterklassen überschrieben: Hotspots und Extra-UI aufbauen.
func _build() -> void:
	pass


## Optionale Atmosphäre-Overlays (Grading/Licht/Partikel) pro Ort aus
## data/location_fx.json — ohne Eintrag passiert nichts. Läuft nur zur Laufzeit.
func _build_atmosphere() -> void:
	if Engine.is_editor_hint():
		return
	LocationFx.attach(self, location_key())


## Nicht-Zimmer-Orte erhalten eine optionale, datengetriebene 2,5D-Stage.
## RoomCompositor setzt _has_background ohne _bg_rect und bleibt unangetastet.
func _build_25d_stage() -> void:
	if Engine.is_editor_hint() or _bg_rect == null:
		return
	var profile: Dictionary = LocationStage25DScript.profile_for(location_key())
	if profile.is_empty() or bool(profile.get("legacy", false)):
		return
	_stage_25d = LocationStage25DScript.new()
	_stage_25d.call("configure", self, _bg_rect, location_key(), profile)
	add_child(_stage_25d)
	ken_burns = false


## Orte mit eigenem NPC-Handling (Laden/Freund/Flohmarkt) schalten die generische
## Ansprech-Leiste ab; alle anderen bekommen sie automatisch.
func uses_generic_npcs() -> bool:
	return true


## Optionales Profil fuer kurze, rein atmosphaerische Gespraeche in der
## Kontaktleiste. Orte ohne eigenes Profil behalten die bisherigen stillen Chips.
func ambient_banter_profile() -> String:
	return ""


## Klickvertrag der kompakten Portraetleiste. Spezialisierte Orte duerfen eine
## storyrelevante direkte Interaktion anbieten; der normale Fallback bleibt das
## vollstaendige NarrativeManager-Gespraech.
func present_npc_pressed(npc_id: String) -> void:
	NarrativeManager.talk(npc_id)


## Anwesende NPCs werden an normalen Orten als kompakte Kontaktleiste und in
## ihren eigenen Zimmern als anklickbare Ganzkoerperfigur dargestellt. Ist ein
## Coder da, laeuft ein Tipp-Bett (AudioManager).
func _build_present_npcs() -> void:
	if Engine.is_editor_hint() or not uses_generic_npcs() or location_id == "":
		return
	var here: Array = NPCManager.present_now(location_id)
	if here.is_empty():
		return
	var resident := str(PERSONAL_ROOM_ACTORS.get(location_id, ""))
	if resident != "" and resident in here:
		add_npc_actor(resident, _default_room_actor_rect())
		here.erase(resident)
	if here.is_empty():
		return
	var bar := HBoxContainer.new()
	bar.name = "PresentNPCs"
	bar.add_theme_constant_override("separation", 10)
	bar.position = Vector2(16, 12)
	bar.z_index = 30
	add_child(bar)
	var coder_here := false
	for npc_id: String in here:
		bar.add_child(_npc_chip(npc_id))
		if NPCManager.is_coder(npc_id):
			coder_here = true
	var banter_profile := ambient_banter_profile()
	if here.size() >= 2 and not banter_profile.is_empty():
		var banter := PresentNpcBanterScript.new()
		banter.name = "PresentNPCBanter"
		banter.position = Vector2(16, 82)
		banter.z_index = 31
		add_child(banter)
		banter.call("setup", bar, here, banter_profile)
	if coder_here:
		var am := get_node_or_null("/root/AudioManager")
		if am != null:
			am.call("start_typing")


func _default_room_actor_rect() -> Rect2:
	if PERSONAL_ROOM_ACTOR_RECTS.has(location_id):
		return PERSONAL_ROOM_ACTOR_RECTS[location_id]
	var actor_height := virtual_size.y * 0.31
	var actor_width := actor_height * (32.0 / 48.0)
	return Rect2(virtual_size.x * 0.76, virtual_size.y * 0.57,
		actor_width, actor_height)


## Bildverankerte, anklickbare 32x48-Pixel-Figur. Anders als die alte
## Ansprech-Chip-Leiste steht sie sichtbar im Raum und folgt Cover-Crop sowie
## der 2,5D-Tiefenprojektion pixelgenau.
func add_npc_actor(npc_id: String, virtual_rect: Rect2,
		callback: Callable = Callable(), visible_height_ratio: float = 1.0) -> Control:
	var npc: Dictionary = NPCManager.get_npc(npc_id)
	if npc.is_empty():
		return null
	var safe_visible_ratio := clampf(visible_height_ratio, 0.25, 1.0)
	# Weltgrafik und Eingabe sind absichtlich getrennt: Die Figur kann hinter
	# Vordergrundobjekten stehen und vom Raumlicht erfasst werden, waehrend eine
	# transparente Host-Klickflaeche nicht von grossen Hotspots gestohlen wird.
	var world_visual := Control.new()
	world_visual.name = "WorldFigure_%s" % npc_id
	world_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var figure_clip := Control.new()
	figure_clip.name = "FurnitureOcclusion"
	figure_clip.clip_contents = safe_visible_ratio < 0.999
	figure_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_visual.add_child(figure_clip)
	var shadow := TextureRect.new()
	shadow.name = "ContactShadow"
	shadow.texture = RoomAssets.shadow_texture()
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_SCALE
	shadow.modulate = Color(1, 1, 1, 0.34)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_visual.add_child(shadow)
	var figure := NpcWorldFigureScript.new()
	figure.name = "Figure"
	figure.set_anchors_preset(Control.PRESET_TOP_LEFT)
	figure_clip.add_child(figure)
	var animation_role := _npc_animation_role(npc_id)
	figure.call("setup", npc_id, {"location": location_id}, animation_role)
	if _stage_25d != null and is_instance_valid(_stage_25d) \
			and _stage_25d.has_method("add_world_visual"):
		_stage_25d.call("add_world_visual", world_visual)
	else:
		world_visual.z_index = 6
		add_child(world_visual)

	var holder := Control.new()
	holder.name = "PresentActor_%s" % npc_id
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 24
	add_child(holder)

	var button := Button.new()
	button.name = "Talk"
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.focus_mode = Control.FOCUS_ALL
	var role := Loc.t("npc.%s.role" % npc_id, str(npc.get("role", "")))
	button.tooltip_text = Loc.t("place.location_base.s_s_ansprechen", "%s · %s — ansprechen") % [
		str(npc.get("name", "?")), role]
	button.mouse_entered.connect(figure.set_attention.bind(true))
	button.mouse_exited.connect(figure.set_attention.bind(false))
	button.pressed.connect(func() -> void:
		figure.react_to_speech()
		if callback.is_valid():
			callback.call()
		else:
			NarrativeManager.talk(npc_id)
	)
	holder.add_child(button)

	var tag := Label.new()
	tag.name = "Nameplate"
	tag.text = str(npc.get("name", "?"))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tag.offset_top = -22.0
	tag.offset_bottom = -2.0
	tag.add_theme_color_override("font_color", Palette.LCD_AMBER)
	tag.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.035, 0.95))
	tag.add_theme_constant_override("outline_size", 4)
	tag.add_theme_font_size_override("font_size", 13)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tag)

	var resolved_rect := editable_actor_rect(npc_id, virtual_rect)
	_npc_actor_defs.append({"id": npc_id, "node": holder, "visual": world_visual,
		"figure_clip": figure_clip, "figure": figure, "shadow": shadow,
		"visible_height_ratio": safe_visible_ratio, "rect": resolved_rect})
	# Auch dynamische Zimmerfreunde sind damit im F8-Ortseditor waehlbar und
	# werden in derselben location_actor_layouts.json wie der Haendler gespeichert.
	_editable_actor_defs.append({
		"id": npc_id,
		"label": str(npc.get("name", npc_id)).to_upper(),
		"node": holder,
		"rect": resolved_rect,
		"default_rect": virtual_rect,
		"npc_actor": true,
	})
	call_deferred("_layout_npc_actors")
	return holder


func _npc_animation_role(npc_id: String) -> String:
	if npc_id == "npc_rocky":
		return "service"
	if npc_id == "npc_voss":
		return "teacher"
	if location_id in ["computer_shop", "kiosk"]:
		return "shop_counter"
	if location_id == "flea_market":
		return "vendor"
	if location_id in PERSONAL_ROOM_ACTORS or location_id == "schoolyard":
		return "social"
	return "idle"


## Weltfigur und Dialogfenster sind ein gemeinsamer Auftritt. Die Verbindung
## wird nach dem Ortsaufbau einmal gesetzt; Godot trennt sie beim Ortswechsel
## automatisch mit dem Empfaenger. Damit animiert kein altes Fenster im neuen
## Raum weiter.
func _connect_world_dialogue_animation() -> void:
	var manager := get_node_or_null("/root/DialogueManager")
	if manager == null or _npc_actor_defs.is_empty():
		return
	if not manager.node_changed.is_connected(_on_world_dialogue_node_changed):
		manager.node_changed.connect(_on_world_dialogue_node_changed)
	if not manager.dialogue_ended.is_connected(_on_world_dialogue_ended):
		manager.dialogue_ended.connect(_on_world_dialogue_ended)


func _on_world_dialogue_node_changed() -> void:
	var manager := get_node_or_null("/root/DialogueManager")
	if manager == null:
		return
	var node: Dictionary = manager.current_node()
	var speaker_id := str(node.get("speaker_id", ""))
	var active_npc := str(manager.get("active_npc"))
	var emotion := str(node.get("emotion", ""))
	for raw_entry: Variant in _npc_actor_defs:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var figure: Node = entry.get("figure")
		if figure == null or not is_instance_valid(figure):
			continue
		var id := str(entry.get("id", ""))
		if id == speaker_id:
			figure.call("set_dialogue_state", true, true,
				emotion if not emotion.is_empty() else "talking")
		elif id == active_npc:
			figure.call("set_dialogue_state", true, false,
				emotion if emotion in ["surprised", "shocked", "sad", "angry"] else "thinking")
		else:
			figure.call("set_dialogue_state", false)


func _on_world_dialogue_ended() -> void:
	for raw_entry: Variant in _npc_actor_defs:
		if raw_entry is Dictionary:
			var figure: Node = (raw_entry as Dictionary).get("figure")
			if figure != null and is_instance_valid(figure):
				figure.call("set_dialogue_state", false)


func _layout_npc_actors() -> void:
	# Laufzeit-Akteure bestehen aus einer Klickflaeche am Ort und einer separat
	# in die 2,5D-Stage gehaengten Weltfigur. Wird eine der beiden Seiten von
	# einer Ortsaktion oder einem Editor-Test entfernt, darf der gespeicherte
	# Dictionary-Verweis vor der Gueltigkeitspruefung nicht gecastet werden.
	for index in range(_npc_actor_defs.size() - 1, -1, -1):
		var raw_entry: Variant = _npc_actor_defs[index]
		if not raw_entry is Dictionary:
			_npc_actor_defs.remove_at(index)
			continue
		var entry: Dictionary = raw_entry
		var raw_actor: Variant = entry.get("node")
		if not is_instance_valid(raw_actor) or not raw_actor is Control:
			var orphan_visual: Variant = entry.get("visual")
			var orphan_shadow: Variant = entry.get("shadow")
			if is_instance_valid(orphan_visual) and orphan_visual is Node:
				(orphan_visual as Node).queue_free()
			elif is_instance_valid(orphan_shadow) and orphan_shadow is Node:
				(orphan_shadow as Node).queue_free()
			_npc_actor_defs.remove_at(index)
			continue
		var actor: Control = raw_actor
		var rect := vrect(entry.get("rect", Rect2()))
		var center := rect.get_center()
		if _stage_25d != null and is_instance_valid(_stage_25d):
			center += _stage_25d.call("offset_for_point", center)
		actor.position = center - rect.size * 0.5
		actor.size = rect.size
		var raw_visual: Variant = entry.get("visual")
		if is_instance_valid(raw_visual) and raw_visual is Control:
			var visual: Control = raw_visual
			visual.position = center - rect.size * 0.5
			visual.size = rect.size
		elif entry.has("visual"):
			entry["visual"] = null
		var visible_ratio := clampf(float(entry.get("visible_height_ratio", 1.0)), 0.25, 1.0)
		var raw_clip: Variant = entry.get("figure_clip")
		if is_instance_valid(raw_clip) and raw_clip is Control:
			var figure_clip: Control = raw_clip
			figure_clip.position = Vector2.ZERO
			figure_clip.size = Vector2(rect.size.x, rect.size.y * visible_ratio)
		var raw_figure: Variant = entry.get("figure")
		if is_instance_valid(raw_figure) and raw_figure is Control:
			var figure: Control = raw_figure
			figure.position = Vector2.ZERO
			figure.size = rect.size
		var raw_shadow: Variant = entry.get("shadow")
		if is_instance_valid(raw_shadow) and raw_shadow is Control:
			var shadow: Control = raw_shadow
			shadow.visible = visible_ratio >= 0.999
			shadow.position = Vector2(rect.size.x * 0.18, rect.size.y * 0.895)
			shadow.size = Vector2(rect.size.x * 0.64, maxf(4.0, rect.size.y * 0.075))
		elif entry.has("shadow"):
			entry["shadow"] = null
	_prune_editable_actor_defs()


func _npc_chip(npc_id: String) -> Control:
	var npc: Dictionary = NPCManager.get_npc(npc_id)
	var col := VBoxContainer.new()
	col.name = "PresentNPC_%s" % npc_id
	col.set_meta("npc_id", npc_id)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var btn := TextureButton.new()
	btn.name = "Portrait"
	btn.set_meta("npc_id", npc_id)
	btn.texture_normal = NPCManager.portrait(npc_id)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = Vector2(54, 54)
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.tooltip_text = Loc.t("place.location_base.mit_s_reden", "Mit %s reden") % str(npc.get("name", "?"))
	btn.pressed.connect(func() -> void:
		present_npc_pressed(npc_id))   # Pool-Zeile oder ortsspezifische Storyaktion
	col.add_child(btn)
	col.add_child(Bezel.dim_label(str(npc.get("name", "?")), 11))
	return col


## Beim Verlassen des Ortes das Tipp-Bett stoppen.
func _exit_tree() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.call("stop_typing")


## Von Unterklassen überschrieben: Dateiname-Basis des Artworks ("room" ...).
func background_base() -> String:
	return ""


func has_background() -> bool:
	return _has_background


func _process(delta: float) -> void:
	anim_time += delta
	if not _has_background:
		queue_redraw()  # Platzhalter-Szenen animieren (Regen, LED, Flackern)
	elif ken_burns and _bg_rect != null:
		_apply_ken_burns()


## Langsames Zoom-Atmen + minimales Driften des Hintergrunds (skaliert um die
## Mitte, damit der Overscan die Ränder deckt).
func _apply_ken_burns() -> void:
	var t := anim_time
	var zoom := 1.016 + 0.009 * sin(t * 0.05)          # ~1.007 … 1.025, sehr langsam
	_bg_rect.pivot_offset = _bg_rect.size * 0.5
	_bg_rect.scale = Vector2(zoom, zoom)
	_bg_rect.position = Vector2(sin(t * 0.037) * 0.004, cos(t * 0.045) * 0.003) * size


# ---------------------------------------------------------------- Hintergrund

func _try_load_background() -> void:
	var base := background_base()
	if base == "":
		return
	# Orts-Hintergründe liegen unter backgrounds/locations/ und heißen wie
	# ihre asset_id (GROSSSCHREIBUNG, s. assets/backgrounds/README.md):
	#   LOCATION_<NAME>_MASTER[_<JAHR>]_Vnn.png
	# Bestes Jahr <= aktuelles Jahr gewinnt; höchste Version schlägt V01.
	var stems: Array = []
	for y in range(TimeManager.year, 1989, -1):
		stems.append("%s_%d" % [base, y])
	stems.append(base)
	var candidates: Array = []
	for stem in stems:
		for v in range(9, 0, -1):
			candidates.append("res://assets/backgrounds/locations/%s_V%02d.png" % [stem, v])
	for path in candidates:
		if ResourceLoader.exists(path):
			var rect := TextureRect.new()
			rect.texture = load(path)
			rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(rect)
			_bg_rect = rect
			_has_background = true
			return


# ---------------------------------------------------------------- Koordinaten

## Skalierung virtueller Koordinaten auf die echte Ansichtsgröße.
func view_scale() -> float:
	if virtual_size.x <= 0.0:
		return 1.0
	if cover_mode:
		return maxf(size.x / virtual_size.x, size.y / virtual_size.y)
	return minf(size.x / virtual_size.x, size.y / virtual_size.y)


func view_offset() -> Vector2:
	var free_space := size - virtual_size * view_scale()
	if cover_mode:
		var safe_anchor := Vector2(
			clampf(cover_anchor.x, 0.0, 1.0),
			clampf(cover_anchor.y, 0.0, 1.0))
		return free_space * safe_anchor
	return free_space / 2.0


## Virtuelles Rechteck → Bildschirm-Rechteck.
func vrect(rect: Rect2) -> Rect2:
	var s := view_scale()
	return Rect2(view_offset() + rect.position * s, rect.size * s)


## Bildschirmpunkt → virtueller Punkt (Umkehrung von vrect, für den Editor).
func to_virtual(screen_point: Vector2) -> Vector2:
	var s := view_scale()
	if s <= 0.0:
		return screen_point
	return (screen_point - view_offset()) / s


## Hinweisschild „niemand da" über dem Artwork. Alle Freundeszimmer teilen sich
## Optik und Platzierung — nur der Text unterscheidet sie. Maus-transparent,
## damit die Hotspots darunter klickbar bleiben.
func add_away_notice(message: String) -> void:
	var lbl := Label.new()
	lbl.text = message
	lbl.add_theme_color_override("font_color", Palette.LCD_AMBER)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl.position = Vector2(-160, 30)
	lbl.custom_minimum_size = Vector2(320, 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)


# ---------------------------------------------------------------- Hotspots

## Unsichtbarer, klickbarer Bereich mit Tooltip und Hover-Rahmen.
func add_hotspot(virtual_rect: Rect2, tip: String, callback: Callable) -> void:
	var button := HotspotButton.new()
	button.tooltip_text = tip
	button.pressed.connect(callback)
	add_child(button)
	_hotspot_defs.append({"rect": virtual_rect, "button": button})


## Klickbereich als perspektivisches Viereck (4 Ecken in virtuellen
## Koordinaten) — für schräge Flächen wie Regal-Front oder Bett.
func add_hotspot_quad(corners: Array, tip: String, callback: Callable) -> void:
	var button := HotspotButton.new()
	button.tooltip_text = tip
	button.pressed.connect(callback)
	add_child(button)
	_hotspot_defs.append({"corners": corners, "button": button})


## Bildgenaues Story-Prop, das dieselbe virtuelle Koordinate und dieselbe
## Tiefenprojektion wie sein Hotspot benutzt. So rutschen Figuren/Geräte bei
## Mausparallaxe nie von ihrem Boden- oder Tischkontakt weg.
func add_depth_prop(texture_path: String, virtual_rect: Rect2, node_name: String) -> TextureRect:
	if not ResourceLoader.exists(texture_path):
		return null
	var prop := TextureRect.new()
	prop.name = node_name
	prop.texture = load(texture_path)
	prop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	prop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prop.z_index = 6
	var shadow := TextureRect.new()
	shadow.name = node_name + "ContactShadow"
	shadow.texture = RoomAssets.shadow_texture()
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_SCALE
	shadow.modulate = Color(1, 1, 1, .42)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.z_index = 5
	add_child(shadow)
	add_child(prop)
	_depth_props.append({"node": prop, "shadow": shadow, "rect": virtual_rect})
	call_deferred("_layout_story_props")
	return prop


## Entfernt ein Story-Prop als atomare Lebenszyklus-Operation. Unterklassen
## duerfen nicht nur das sichtbare Control queue_free()'en: Der getrennte
## Kontaktschatten sowie Editor-/Layout-Referenzen wuerden sonst bis zum
## naechsten Parallaxen-Frame als verwaiste Eintraege weiterleben.
func remove_depth_prop(node_name: String) -> bool:
	var removed := false
	for index in range(_depth_props.size() - 1, -1, -1):
		var raw_entry: Variant = _depth_props[index]
		if not raw_entry is Dictionary:
			_depth_props.remove_at(index)
			continue
		var entry: Dictionary = raw_entry
		var raw_prop: Variant = entry.get("node")
		if not is_instance_valid(raw_prop):
			var orphan_shadow: Variant = entry.get("shadow")
			if is_instance_valid(orphan_shadow) and orphan_shadow is Node:
				(orphan_shadow as Node).queue_free()
			_depth_props.remove_at(index)
			continue
		if not raw_prop is TextureRect or (raw_prop as TextureRect).name != node_name:
			continue
		for actor_index in range(_editable_actor_defs.size() - 1, -1, -1):
			var raw_actor_def: Variant = _editable_actor_defs[actor_index]
			if raw_actor_def is Dictionary \
					and (raw_actor_def as Dictionary).get("node") == raw_prop:
				_editable_actor_defs.remove_at(actor_index)
		var raw_shadow: Variant = entry.get("shadow")
		if is_instance_valid(raw_shadow) and raw_shadow is Node:
			(raw_shadow as Node).queue_free()
		(raw_prop as TextureRect).queue_free()
		_depth_props.remove_at(index)
		removed = true
	_prune_editable_actor_defs()
	return removed


func _layout_story_props() -> void:
	PropLayout.story_props(self)


func _layout_hotspots() -> void:
	PropLayout.hotspots(self)

## Hook fuer bildverankerte Darsteller/Objekte spezialisierter Orte. Die Stage
## ruft ihn zusammen mit den Hotspots auf, damit beide im selben Raum bleiben.
func _layout_depth_actors() -> void:
	_layout_story_props()
	_layout_npc_actors()


## Test-/Tool-Zugang ohne Abhängigkeit auf die konkrete Stage-Klasse.
func depth_stage_25d() -> Control:
	return _stage_25d


# ---------------------------------------------------------------- Layout-Daten
# Die Hotspots eines Ortes werden NICHT im Spiel justiert, sondern in einer
# eigenen Editor-Szene (scenes/previews/<Ort>Preview.tscn, öffnen + F6). Dort verschiebt/
# skaliert man die Klickflächen; gespeichert wird nach data/location_hotspots.json
# pro Ort-Schlüssel. Im Spiel lädt der Ort diese Positionen nur noch (siehe
# _apply_hotspot_overrides). Diese Accessoren nutzt der HotspotEditor.

## Eindeutiger Schlüssel des Ortes für die Override-Datei.
func location_key() -> String:
	return LocationAuthoring.location_key(self)


## Verschiebbare (rechteckige) Hotspots — Quads und an einen sichtbaren Akteur
## gebundene Klickzonen bleiben außen vor. Letztere folgen immer ihrem Akteur.
func rect_hotspots() -> Array:
	return LocationAuthoring.rect_hotspots(self)


## Setzt das virtuelle Rechteck eines Hotspots und richtet ihn neu aus (Live).
func set_hotspot_rect(def: Dictionary, r: Rect2) -> void:
	LocationAuthoring.set_hotspot_rect(self, def, r)


## Beschriftung eines Hotspots (aus dem Button-Tooltip).
func hotspot_label(def: Dictionary) -> String:
	return LocationAuthoring.hotspot_label(def)


## Nimmt eine dynamische Klickzone aus dem normalen, indexbasierten
## Hotspot-Editor. So kann ein optional anwesender NPC niemals die gespeicherte
## Position des nachfolgenden Heimweg-Hotspots übernehmen.
func mark_hotspot_actor_managed(def: Dictionary) -> void:
	LocationAuthoring.mark_hotspot_actor_managed(def)


## Liest das gespeicherte virtuelle Rechteck eines sichtbaren Laufzeit-Aktors.
## Ohne Override bleibt die Position aus seiner Editor-Defaults-Szene erhalten.
func editable_actor_rect(actor_id: String, default_rect: Rect2) -> Rect2:
	return LocationAuthoring.editable_actor_rect(
		self, actor_id, default_rect, ACTOR_LAYOUT_OVERRIDES)


## Meldet einen bereits gerenderten 2,5D-Aktor beim F6-Level-Editor an. Seine
## Klickzone wird relativ zum Default-Rechteck gespeichert und folgt dadurch
## beim Verschieben und Skalieren pixelgenau.
func register_editable_depth_actor(actor_id: String, label: String,
		prop: TextureRect, current_rect: Rect2, default_rect: Rect2,
		hotspot_def: Dictionary, default_hotspot_rect: Rect2) -> void:
	LocationAuthoring.register_editable_depth_actor(
		self, actor_id, label, prop, current_rect, default_rect,
		hotspot_def, default_hotspot_rect)


func editable_depth_actors() -> Array:
	return LocationAuthoring.editable_depth_actors(self)


## Interner Kompatibilitaetsadapter fuer Laufzeitbereinigung und alte Tools.
func _prune_editable_actor_defs() -> void:
	LocationAuthoring.prune_editable_actor_definitions(self)


## Live-Änderung aus dem Level-Editor. Sichtbild, Kontakt-Schatten und Klickzone
## werden in einem Zug aktualisiert; es kann kein unsichtbarer alter Trefferraum
## zurückbleiben.
func set_editable_actor_rect(def: Dictionary, rect: Rect2) -> void:
	LocationAuthoring.set_editable_actor_rect(self, def, rect)


func reset_editable_actor_rect(def: Dictionary) -> void:
	LocationAuthoring.reset_editable_actor_rect(self, def)


## Persistiert nur die sichtbaren Aktoren dieses Orts. Andere Orte und
## unbekannte Einträge bleiben unangetastet.
##
## Zwei Regeln halten die Defaults-Szenen am Leben:
## 1. Wer exakt auf seinem Editor-Default steht, bekommt KEINEN Eintrag. Ein
##    Override, der nur den Default wiederholt, würde die Defaults-Szene
##    stillschweigend abschalten — spätere Änderungen dort kämen nie im Spiel an.
## 2. Nur anwesende Aktoren werden angefasst. Ein Händler, der heute nicht auf
##    dem Markt steht, fehlt in _editable_actor_defs und darf dabei nicht
##    seine gespeicherte Position verlieren.
func save_editable_actor_layouts() -> bool:
	return LocationAuthoring.save_editable_actor_layouts(
		self, ACTOR_LAYOUT_OVERRIDES)


func _apply_hotspot_overrides() -> void:
	LocationAuthoring.apply_hotspot_overrides(self, HOTSPOT_OVERRIDES)


## Kompatibilitaetsadapter fuer HotspotEditor und bestehende Tool-Skripte.
static func _read_overrides() -> Dictionary:
	return LocationAuthoring.read_overrides(HOTSPOT_OVERRIDES)


static func _read_actor_overrides() -> Dictionary:
	return LocationAuthoring.read_overrides(ACTOR_LAYOUT_OVERRIDES)


## Klick-Buttons ruhigstellen/aktivieren (der Editor braucht die Maus für sich).
func set_hotspots_interactive(active: bool) -> void:
	LocationAuthoring.set_hotspots_interactive(self, active)


## Transparenter Button, der beim Hover einen dezenten Rahmen zeichnet.
## Optional mit normiertem Polygon (0-1): dann zählen nur Klicks im
## Viereck und der Hover-Umriss folgt der schrägen Form.
class HotspotButton:
	extends Button

	var polygon_norm := PackedVector2Array()

	func _init() -> void:
		flat = true
		add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _has_point(point: Vector2) -> bool:
		if polygon_norm.size() < 3 or size.x <= 0.0 or size.y <= 0.0:
			return Rect2(Vector2.ZERO, size).has_point(point)
		return Geometry2D.is_point_in_polygon(point / size, polygon_norm)

	func _draw() -> void:
		if not is_hovered():
			return
		if polygon_norm.size() < 3:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.45), false, 1.0)
			return
		var pts := PackedVector2Array()
		for p in polygon_norm:
			pts.append(p * size)
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.45), 1.0, true)
