extends LocationBase
## Versteckte Lichtung hinter dem Bolzplatz. Kein Karten-Pin: erreichbar nur
## über den Trampelpfad, Rückweg führt ohne Zeitkosten zum Waldrand.

const DEALER_ASSET := "res://assets/backgrounds/story_props/DEALER_WITH_TEST_RIG_V01.png"
const DEALER_BLEND_SHADER := preload("res://shaders/dealer_environment_blend.gdshader")


func uses_generic_npcs() -> bool:
	return false

func background_base() -> String:
	return "LOCATION_DEALER_CLEARING_MASTER"

func _build() -> void:
	if not has_background():
		add_hotspot(Rect2(60, 45, 160, 105), Loc.t("place.dealer_clearing_location.improvisierter_prufplatz", "Improvisierter Prüfplatz"), _inspect_rig)
		add_hotspot(Rect2(340, 55, 70, 120), Loc.t("place.dealer_clearing_location.zuruck_zum_bolzplatz", "Zurück zum Bolzplatz"), _leave)
		return
	cover_mode = true
	virtual_size = Vector2(1672, 941)
	var dealer_present := NPCManager.scheduled_place("npc_haendler") == "wald"
	if dealer_present:
		var dealer_prop := add_depth_prop(DEALER_ASSET,
			Rect2(410, 205, 205, 390), "DealerInClearing")
		if dealer_prop != null:
			# In der dunklen Waldtiefe benötigt die große Figur etwas mehr
			# optische Weichheit als der kleinere Flohmarkt-Spawn.
			var blend_material := ShaderMaterial.new()
			blend_material.shader = DEALER_BLEND_SHADER
			blend_material.set_shader_parameter("softness", 2.15)
			dealer_prop.material = blend_material
		add_hotspot(Rect2(360, 185, 330, 440), Loc.t("place.dealer_clearing_location.handler_diskret_geschafte_machen", "Der Händler — diskret Geschäfte machen"), UIManager.open_dealer)
	else:
		UIManager.toast.call_deferred(Loc.t("place.dealer_clearing_location.lichtung_ist_verlassen_prufplatz_ist_abgedeckt", "Die Lichtung ist verlassen. Der Prüfplatz ist abgedeckt."))
	add_hotspot(Rect2(280, 330, 390, 250), Loc.t("place.dealer_clearing_location.improvisierter_disketten_prufplatz", "Improvisierter Disketten-Prüfplatz"), _inspect_rig)
	add_hotspot(Rect2(540, 690, 620, 250), Loc.t("place.dealer_clearing_location.trampelpfad_zuruck_zum_bolzplatz", "Trampelpfad — zurück zum Bolzplatz"), _leave)

func _inspect_rig() -> void:
	if NPCManager.scheduled_place("npc_haendler") == "wald":
		UIManager.toast(Loc.t("place.dealer_clearing_location.referenzlaufwerk_kleinoszilloskop_kopfhorer_damit_pruft_er", "Referenzlaufwerk, Kleinoszilloskop und Kopfhörer — damit prüft er Lesefehler, ohne Fragen zu stellen."))
	else:
		UIManager.toast(Loc.t("place.dealer_clearing_location.leere_palette_hocker_druckstellen_im_boden", "Eine leere Palette, ein Hocker und Druckstellen im Boden. Jemand arbeitet hier regelmäßig."))

func _leave() -> void:
	GameManager.goto_location("wald", false)
