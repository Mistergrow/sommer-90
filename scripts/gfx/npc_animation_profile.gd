class_name NpcAnimationProfile
## Kanonische Bewegungsprofile fuer Welt-NPCs.
##
## Die Profile veraendern niemals Identitaet oder Kleidung. Sie bestimmen nur
## Tempo, Blick, Gesten und Koerpersprache. Benannte Overrides sind bewusst
## sparsam: Eine Figur bleibt wiedererkennbar, ohne dass alle Menschen wie
## dieselbe automatisch gewippte Schablone wirken.

const BASE := {
	"profile_id": "balanced",
	"tempo": 1.0,
	"motion": 1.0,
	"breath_rate": 1.0,
	"blink_min": 2.7,
	"blink_max": 5.3,
	"gaze_min": 1.8,
	"gaze_max": 4.2,
	"work_min": 5.8,
	"work_max": 10.5,
	"gesture_min": 4.8,
	"gesture_max": 8.5,
	"talk_rate": 10.5,
	"nod": 1.0,
	"double_blink_chance": 0.13,
	"idle_tilt": 0.004,
	"work_emotion": "thinking",
}

const ARCHETYPES := {
	"calm": {
		"tempo": 0.78, "motion": 0.62, "breath_rate": 0.86,
		"blink_min": 3.2, "blink_max": 6.4, "gaze_min": 2.8, "gaze_max": 5.8,
		"gesture_min": 7.0, "gesture_max": 12.0, "talk_rate": 8.4,
		"nod": 0.65, "idle_tilt": 0.0025, "double_blink_chance": 0.08,
	},
	"precise": {
		"tempo": 0.94, "motion": 0.72, "breath_rate": 0.95,
		"blink_min": 2.9, "blink_max": 5.4, "gaze_min": 2.1, "gaze_max": 4.4,
		"work_min": 3.8, "work_max": 7.0, "gesture_min": 5.7,
		"gesture_max": 9.8, "talk_rate": 9.5, "nod": 0.8,
	},
	"warm": {
		"tempo": 1.02, "motion": 0.9, "breath_rate": 1.0,
		"blink_min": 2.4, "blink_max": 4.8, "gaze_min": 1.7, "gaze_max": 3.8,
		"gesture_min": 4.4, "gesture_max": 7.8, "talk_rate": 10.8,
		"nod": 1.15, "double_blink_chance": 0.18,
	},
	"lively": {
		"tempo": 1.2, "motion": 1.16, "breath_rate": 1.08,
		"blink_min": 2.1, "blink_max": 4.2, "gaze_min": 1.2, "gaze_max": 3.0,
		"gesture_min": 3.2, "gesture_max": 6.1, "talk_rate": 12.4,
		"nod": 1.35, "double_blink_chance": 0.2, "idle_tilt": 0.006,
	},
	"guarded": {
		"tempo": 0.88, "motion": 0.7, "breath_rate": 0.92,
		"blink_min": 3.0, "blink_max": 5.7, "gaze_min": 1.4, "gaze_max": 3.5,
		"gesture_min": 6.0, "gesture_max": 10.5, "talk_rate": 9.0,
		"nod": 0.55, "idle_tilt": 0.003,
	},
	"scene": {
		"tempo": 1.1, "motion": 1.04, "breath_rate": 1.04,
		"blink_min": 2.3, "blink_max": 4.7, "gaze_min": 1.35, "gaze_max": 3.2,
		"gesture_min": 3.8, "gesture_max": 6.9, "talk_rate": 11.8,
		"nod": 1.2, "idle_tilt": 0.0055,
	},
}

const PERSONALITY_ARCHETYPE := {
	"teal": "scene", "red": "lively", "blue": "precise",
	"green": "warm", "orange": "warm", "violet": "scene",
	"mustard": "guarded",
}

const NPC_OVERRIDES := {
	"npc_gruber": {"archetype": "calm", "profile_id": "measured_shopkeeper"},
	"npc_jan_gruber": {"archetype": "precise", "profile_id": "attentive_shopkeeper"},
	"npc_rocky": {"archetype": "precise", "profile_id": "workshop_precision",
		"work_min": 2.8, "work_max": 5.6, "work_emotion": "thinking"},
	"npc_oez": {"archetype": "warm", "profile_id": "warm_kiosk_owner"},
	"npc_krause": {"archetype": "guarded", "profile_id": "watchful_trader"},
	"npc_voss": {"archetype": "calm", "profile_id": "teacher"},
	"npc_mike": {"archetype": "lively", "profile_id": "animated_friend"},
	"npc_sven": {"archetype": "lively", "profile_id": "quick_friend"},
	"npc_stefan": {"archetype": "scene", "profile_id": "best_friend"},
	"npc_basti": {"archetype": "scene", "profile_id": "beat_driven"},
	"npc_pixie": {"archetype": "lively", "profile_id": "expressive_artist"},
	"npc_daniel": {"archetype": "precise", "profile_id": "focused_coder"},
	"npc_lisa": {"archetype": "warm", "profile_id": "creative_warmth"},
}


static func profile_for(npc_id: String, role: String, npc: Dictionary = {}) -> Dictionary:
	var out: Dictionary = BASE.duplicate(true)
	var personality := str(npc.get("portrait_dna", {}).get("personality", ""))
	var archetype := str(PERSONALITY_ARCHETYPE.get(personality, "balanced"))
	var override: Dictionary = NPC_OVERRIDES.get(npc_id, {})
	if override.has("archetype"):
		archetype = str(override["archetype"])
	if ARCHETYPES.has(archetype):
		_merge(out, ARCHETYPES[archetype])
	out["archetype"] = archetype
	_merge(out, override)
	if role in ["shop_counter", "service", "vendor"]:
		out["work_min"] = minf(float(out["work_min"]), 4.8)
		out["work_max"] = minf(float(out["work_max"]), 8.2)
	if role == "teacher":
		out["nod"] = float(out["nod"]) * 0.72
		out["gesture_min"] = float(out["gesture_min"]) * 1.25
	return out


static func _merge(target: Dictionary, values: Dictionary) -> void:
	for key: Variant in values:
		if key != "archetype":
			target[key] = values[key]
