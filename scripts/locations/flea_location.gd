extends LocationBase
## Der Flohmarkt (nur Samstagvormittag) — der spannendste Ort: jede Woche ist
## alles anders. Persistenter Markt (FleaMarketManager): Stände verändern sich
## (verkauft/billiger/weg), Händler geben Tipps, und Mystery-Kartons bergen
## Überraschungen. Zustand gebrauchter Ware zeigt sich erst zu Hause beim Prüfen.

const DEALER_ASSET := "res://assets/backgrounds/story_props/DEALER_WITH_TEST_RIG_V01.png"
const DEALER_BLEND_SHADER := preload("res://shaders/dealer_environment_blend.gdshader")
const FLEA_ACTOR_LAYOUT: PackedScene = preload("res://scenes/editors/FleaMarketActors.tscn")
const ShopEra := preload("res://scripts/data/computer_shop_era.gd")


## Eigenes NPC-Handling → generische Ansprech-Leiste aus.
func uses_generic_npcs() -> bool:
	return false


func background_base() -> String:
	return "LOCATION_FLEA_MARKET_MASTER"


func _build() -> void:
	FleaMarketManager.ensure_current()
	if has_background():
		cover_mode = true
		virtual_size = Vector2(1672, 941)
		add_hotspot(Rect2(0, 300, 780, 605), Loc.t("place.flea_location.stande_links_stobern_kartons_durchwuhlen", "Stände links — stöbern & Kartons durchwühlen"), _market)
		add_hotspot(Rect2(1180, 300, 492, 420), Loc.t("place.flea_location.stande_rechts_elektronik_kisten", "Stände rechts — Elektronik & Kisten"), _market)
		add_hotspot(Rect2(1360, 55, 312, 280), Loc.t("place.flea_location.kaffee_bratwurst_kurze_pause", "Kaffee & Bratwurst — kurze Pause"), _food)
		# Eigene Decke am Rand: hier verkaufst du deine Kopien (beste Preise!).
		add_hotspot(Rect2(790, 300, 380, 300), Loc.t("place.flea_location.deine_decke_kopien_verkaufen", "Deine Decke — Kopien verkaufen"), UIManager.open_copy_sale)
		add_hotspot(Rect2(40, 410, 250, 320), Loc.t("place.flea_location.verkaufer_ansprechen", "Verkäufer ansprechen"), _on_krause)
		if UIManager.dealer_here():
			_add_black_market_dealer()
		if _alex_at_market():
			_decorate_alex_actor(add_npc_actor("npc_alex", Rect2(885, 560, 168, 252), _talk_alex))
		if _retired_gruber_here():
			add_npc_actor("npc_gruber", Rect2(420, 555, 168, 252), _talk_retired_gruber)
		add_hotspot(Rect2(640, 858, 410, 83), Loc.t("place.flea_location.heimweg_orte", "Heimweg (Orte)"), UIManager.open_map)
	else:
		add_hotspot(Rect2(40, 70, 140, 90), Loc.t("place.flea_location.stande_stobern_kartons", "Stände — stöbern & Kartons"), _market)
		add_hotspot(Rect2(210, 60, 90, 70), Loc.t("place.flea_location.krause_ansprechen", "Krause ansprechen"), _on_krause)
		if UIManager.dealer_here():
			add_hotspot(Rect2(310, 60, 90, 70), Loc.t("place.flea_location.zwielichtiger_typ_ansprechen", "Zwielichtiger Typ — ansprechen"), UIManager.open_dealer)
		if _alex_at_market():
			_decorate_alex_actor(add_npc_actor("npc_alex", Rect2(292, 62, 48, 72), _talk_alex))
		if _retired_gruber_here():
			add_npc_actor("npc_gruber", Rect2(248, 64, 46, 70), _talk_retired_gruber)
		add_hotspot(Rect2(360, 60, 45, 110),
			Loc.t("place.flea_location.heimweg_orte", "Heimweg (Orte)"), UIManager.open_map)
	# Wenn sich seit letztem Besuch etwas getan hat: dezenter Hinweis.
	if NarrativeManager.alex_archive_handoff_ready():
		UIManager.toast.call_deferred(Loc.t("place.flea_location.alex_waits_for_archive_handoff",
			"Alex wartet bei deiner Decke — ARCHIVPROTOKOLL ÜBERGEBEN."))
	elif not FleaMarketManager.last_changes.is_empty():
		UIManager.toast.call_deferred(Loc.t("place.flea_location.market_changed",
			"Auf dem Flohmarkt hat sich was getan — schau dich um."))
	elif _retired_gruber_here():
		UIManager.toast.call_deferred(Loc.t("place.flea_location.retired_gruber_browses",
			"Zwischen den Ständen stöbert Herr Gruber — heute ganz ohne Ladenschlüssel."))


func _alex_at_market() -> bool:
	# Eine abgabebereite Quest oder spätere Mystery-Disk darf nie an der
	# 15-%-Tagesunschärfe hängen.
	return NarrativeManager.alex_market_handoff_ready() \
		or NPCManager.is_here_now("npc_alex", "flea_market")


func _decorate_alex_actor(actor: Control) -> void:
	if actor == null or not NarrativeManager.alex_archive_handoff_ready():
		return
	var talk_button := actor.find_child("Talk", true, false) as Button
	if talk_button != null:
		talk_button.tooltip_text = Loc.t("place.flea_location.alex_archivprotokoll_uebergeben", "Alex — Archivprotokoll übergeben")
	var nameplate := actor.find_child("Nameplate", true, false) as Label
	if nameplate != null:
		nameplate.text = Loc.t("place.flea_location.alex_protokoll", "ALEX · PROTOKOLL")


func _talk_alex() -> void:
	NarrativeManager.talk("npc_alex")


func _retired_gruber_here() -> bool:
	return ShopEra.market_visit(TimeManager.day_counter)


func _talk_retired_gruber() -> void:
	var visit := posmod(floori(float(TimeManager.day_counter) / 7.0), 3)
	DialogueManager.start_dialogue("gruber_retired_market", "npc_gruber",
		["n1", "n2", "n3"][visit])

## Der Schwarzhändler am Marktrand. Standardposition, Größe und Klickzone kommen
## ausschließlich aus FleaMarketActors.tscn — im Code steht dazu bewusst keine
## Zahlenkopie mehr. Zur Laufzeit bleibt er im F6/F8-Ortseditor verschiebbar; ein
## Eintrag in location_actor_layouts.json entsteht erst, wenn er wirklich vom
## Editor-Default abweicht.
func _add_black_market_dealer() -> void:
	var layout := _dealer_layout()
	if layout.is_empty():
		push_error("FleaMarketActors.tscn liefert keinen BlackMarketDealer; der Händler bleibt heute unsichtbar.")
		return
	var default_rect: Rect2 = layout["visual_rect"]
	var default_hotspot: Rect2 = layout["hotspot_rect"]
	var dealer_rect := editable_actor_rect("black_market_dealer", default_rect)
	var dealer_hotspot := _remap_actor_hotspot(default_hotspot, default_rect, dealer_rect)
	add_hotspot(dealer_hotspot, Loc.t("place.flea_location.zwielichtiger_typ_am_rand_er_winkt", "Zwielichtiger Typ am Rand — er winkt dich zu sich"), UIManager.open_dealer)
	var dealer_hotspot_def: Dictionary = _hotspot_defs.back()
	mark_hotspot_actor_managed(dealer_hotspot_def)
	var dealer_prop := add_depth_prop(DEALER_ASSET, dealer_rect, "DealerAtMarketEdge")
	if dealer_prop == null:
		return
	# Die Editor-Skalierung darf X/Y unabhängig verändern. Deshalb wird das
	# berechnete Rechteck exakt gefüllt statt erneut eingepasst.
	dealer_prop.stretch_mode = TextureRect.STRETCH_SCALE
	var blend_material := ShaderMaterial.new()
	blend_material.shader = DEALER_BLEND_SHADER
	dealer_prop.material = blend_material
	register_editable_depth_actor("black_market_dealer", "SCHWARZHÄNDLER",
		dealer_prop, dealer_rect, default_rect,
		dealer_hotspot_def, default_hotspot)


## Liest die im Godot-Editor gesetzten virtuellen Rechtecke aus der Defaults-
## Szene. Sie wird nur kurz als Datenquelle instanziiert; im Spiel rendert
## LocationBase das Prop weiterhin mit gemeinsamer 2,5D-Projektion und
## Kontakt-Schatten. Position, Pivot und Skalierung werden dabei exakt wie im
## 2D-Editor ausgewertet. Ein leeres Ergebnis heißt: Die Szene ist kaputt oder
## der Knoten wurde umbenannt — dann fehlt der Händler sichtbar, statt sich
## hinter einem hartkodierten Ersatzwert als „richtig" zu tarnen.
func _dealer_layout() -> Dictionary:
	var layout := FLEA_ACTOR_LAYOUT.instantiate() as Control
	if layout == null:
		return {}
	var dealer := layout.get_node_or_null("BlackMarketDealer") as Control
	if dealer == null:
		layout.free()
		return {}
	var dealer_scale := _editor_scale(dealer)
	var dealer_rect := _scaled_local_rect(dealer)
	var hotspot_rect := dealer_rect
	var interaction := dealer.get_node_or_null("DealerInteractionArea") as Control
	if interaction != null:
		var interaction_rect := _scaled_local_rect(interaction)
		hotspot_rect = Rect2(
			dealer_rect.position + interaction_rect.position * dealer_scale,
			interaction_rect.size * dealer_scale
		)
	layout.free()
	return {"visual_rect": dealer_rect, "hotspot_rect": hotspot_rect}


## Positive Editor-Skalierung mit Schutz gegen versehentliches Nullskalieren.
## Spiegeln ist für diesen freigestellten Darsteller bewusst nicht vorgesehen.
func _editor_scale(control: Control) -> Vector2:
	return Vector2(
		maxf(absf(control.scale.x), 0.01),
		maxf(absf(control.scale.y), 0.01)
	)


## Transformiert das lokale Control-Rechteck um seinen Editor-Pivot. Damit bleibt
## bei einem Pivot an den Füßen der Bodenkontakt auch beim Skalieren erhalten.
func _scaled_local_rect(control: Control) -> Rect2:
	var editor_scale := _editor_scale(control)
	var scaled_position := control.position + control.pivot_offset \
		- control.pivot_offset * editor_scale
	return Rect2(scaled_position, control.size * editor_scale)


## Überträgt die editorseitige Klickzone relativ auf das gespeicherte
## Laufzeit-Rechteck. Auch bei neuer Größe bleibt sie an derselben Körperzone.
func _remap_actor_hotspot(hotspot: Rect2, from_rect: Rect2, to_rect: Rect2) -> Rect2:
	if from_rect.size.x <= 0.0 or from_rect.size.y <= 0.0:
		return hotspot
	var relative := Rect2(
		(hotspot.position - from_rect.position) / from_rect.size,
		hotspot.size / from_rect.size
	)
	return Rect2(
		to_rect.position + relative.position * to_rect.size,
		relative.size * to_rect.size
	)


func _market() -> void:
	UIManager.open_flea()


func _on_krause() -> void:
	DialogueManager.start_dialogue("krause_greet", "npc_krause")
	if not FleaMarketManager.tip.is_empty():
		UIManager.toast.call_deferred(FleaMarketManager.tip.get("text", ""))


func _food() -> void:
	if PlayerStats.energie < 100:
		PlayerStats.change_stat("energie", 8)
		UIManager.toast(Loc.t("place.flea_location.bratwurst_kaffee_tut_gut_energie", "Eine Bratwurst und ein Kaffee. Tut gut. (+Energie)"))
	else:
		UIManager.toast(Loc.t("place.flea_location.duft_von_bratwurst_kaffee_liegt_uber", "Der Duft von Bratwurst und Kaffee liegt über dem Markt."))


func _draw() -> void:
	if has_background():
		return
	var s := view_scale()
	draw_set_transform(view_offset(), 0.0, Vector2(s, s))
	# Samstagmorgen: heller Himmel, Kopfsteinpflaster
	draw_rect(Rect2(0, 0, 415, 110), Palette.GREY_LIGHT.lightened(0.1))
	draw_rect(Rect2(0, 110, 415, 84), Palette.GREY)
	for i in 20:
		draw_rect(Rect2((i * 23) % 415, 118 + (i * 13) % 70, 10, 4), Palette.GREY_MID)
	# Stand mit Bananenkiste und normaler Gebrauchtware
	draw_rect(Rect2(40, 100, 130, 8), Palette.SAND)
	draw_rect(Rect2(46, 108, 8, 30), Palette.BROWN)
	draw_rect(Rect2(150, 108, 8, 30), Palette.BROWN)
	draw_rect(Rect2(60, 84, 60, 18), Palette.LEATHER)
	for i in 6:
		draw_rect(Rect2(64 + i * 9, 86, 7, 12),
			[Palette.BLUE_MID, Palette.RED_DARK, Palette.GREY, Palette.GREEN_DARK, Palette.SAND, Palette.DARK_PURPLE][i])
	# Sonnenschirm
	draw_line(Vector2(100, 100), Vector2(100, 40), Palette.GREY_DARK, 2.0)
	draw_rect(Rect2(60, 30, 80, 12), Palette.RED)
	draw_rect(Rect2(60, 42, 80, 4), Palette.WHITE_SOFT)
