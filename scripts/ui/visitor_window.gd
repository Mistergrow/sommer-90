class_name VisitorWindow
extends RetroWindow
## ES KLOPFT — ein Freund steht in der Tür (VisitManager). Du entscheidest:
## reinlassen (kurzes Gespräch + er bringt was) oder keine Zeit (er zieht ab).
## visit wird vor dem Öffnen gesetzt (toggle_window-Factory).

var visit: Dictionary = {}

## Jeder Freund klopft anders (Charakterisierung, konsistent pro Person).
const KNOCK_BY_NPC := {
	"npc_mike": "knock_fast", "npc_basti": "knock_fast", "npc_sven": "knock_fast",
	"npc_lisa": "knock_soft", "npc_daniel": "knock_soft", "npc_alex": "knock_soft",
	"npc_stefan": "knock",
}


func _init() -> void:
	title = Loc.t("ui.visitor_window.es_klopft", "🚪 ES KLOPFT")
	win_size = Vector2(370, 214)


func _ready() -> void:
	super._ready()
	AudioManager.play(KNOCK_BY_NPC.get(str(visit.get("npc", "")), "knock"), 0.0)
	content.add_child(Bezel.lcd_label(Loc.t("ui.visitor_window.klopf_klopf", "Klopf, klopf …"), Color(0.55, 0.9, 1.0), 16))
	content.add_child(Bezel.dim_label(Loc.t("ui.visitor_window.s_steht_in_tur", "%s steht in der Tür.") % str(visit.get("speaker", "Jemand")), 12))
	var teaser := str(visit.get("knock", ""))
	if teaser != "":
		content.add_child(Bezel.dim_label(Loc.t("ui.visitor_window.s", "»%s«") % teaser, 11))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	var accept_button := make_button(Loc.t("ui.visitor_window.reinlassen", "Reinlassen"), func() -> void:
		if VisitManager.accept(visit):
			queue_free())
	accept_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(accept_button)
	var decline_button := make_button(Loc.t("ui.visitor_window.keine_zeit", "Keine Zeit"), func() -> void:
		VisitManager.decline(visit)
		queue_free())
	decline_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(decline_button)
