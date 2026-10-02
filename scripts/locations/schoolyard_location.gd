extends LocationBase
## Der Schulhof (LOCATION_SCHOOLYARD_*) — soziales Zentrum des Spiels.
##
## Zwei Zustände nach Tageszeit:
##  • Pause/vormittags (voller Hof, MASTER): Gesprächszonen → Gerüchte-Netzwerk
##    (RumorManager). Jede Gruppe kennt/verzerrt nur ihren Teil.
##  • Nach der Schule (leerer Hof, AFTER_SCHOOL): wer da ist, entscheidet der
##    NPC-Tagesplan (NPCManager). „Mal sehen, ob Sven auftaucht" — das Gefühl
##    der Zeit ohne Handy. Manchmal ist niemand da.

func uses_generic_npcs() -> bool:
	# Der Schulhof setzt seine Gruppen und Nachmittags-Freunde selbst als
	# bildgenaue Akteure. Zusaetzliche generische NPC-Chips waeren Duplikate.
	return false


## Der volle Hof (Kinder in der Pause) nur zur SCHULZEIT: Werktag-Vormittag und
## keine Ferien. Nachmittags, am Wochenende und in den Ferien ist der Hof leer.
func _is_break_time() -> bool:
	return TimeManager.slot < NPCManager.AFTERNOON_SLOT \
		and not TimeManager.is_weekend() \
		and not TimeManager.is_school_holiday()


func background_base() -> String:
	return "LOCATION_SCHOOLYARD_MASTER" if _is_break_time() else "LOCATION_SCHOOLYARD_AFTER_SCHOOL"


func _build() -> void:
	if not has_background():
		add_hotspot(Rect2(60, 60, 80, 90), Loc.t("place.schoolyard_location.schuler_ansprechen", "Schüler ansprechen"), _talk.bind("freunde"))
		add_hotspot(Rect2(360, 60, 50, 110), Loc.t("place.schoolyard_location.heimweg_orte", "Heimweg (Orte)"), UIManager.open_map)
		return
	cover_mode = true
	virtual_size = Vector2(1672, 941)
	if _is_break_time():
		_build_break()
	else:
		_build_afterschool()
	_build_exam_access()


# ------------------------------------------------------ Pause (voller Hof)

func _build_break() -> void:
	add_hotspot(Rect2(1180, 470, 490, 435), Loc.t("place.schoolyard_location.altere_am_fahrradstander_neuigkeiten", "Ältere am Fahrradständer — Neuigkeiten?"), _talk.bind("aeltere"))
	add_hotspot(Rect2(175, 585, 545, 205), Loc.t("place.schoolyard_location.freunde_auf_bank_quatschen", "Freunde auf der Bank — quatschen"), _talk.bind("freunde"))
	add_hotspot(Rect2(440, 375, 245, 190), Loc.t("place.schoolyard_location.klassenkameraden_vorm_eingang", "Klassenkameraden vorm Eingang"), _talk.bind("klasse"))
	add_hotspot(Rect2(1380, 405, 235, 120), Loc.t("place.schoolyard_location.jungere_an_mauer", "Jüngere an der Mauer"), _talk.bind("juengere"))
	# Kopien-Handel: hinter der Turnhalle wechseln Disketten den Besitzer.
	add_hotspot(Rect2(720, 375, 430, 180), Loc.t("place.schoolyard_location.hinter_turnhalle_kopien_verkaufen", "Hinter der Turnhalle — Kopien verkaufen"), UIManager.open_copy_sale)
	add_hotspot(Rect2(10, 300, 190, 180), Loc.t("place.schoolyard_location.schwarzes_brett_was_sich_bestatigt_hat", "Schwarzes Brett — was sich bestätigt hat"), _board)
	add_hotspot(Rect2(485, 275, 165, 120), Loc.t("place.schoolyard_location.schuleingang", "Schuleingang"), _entrance)
	add_hotspot(Rect2(690, 855, 430, 86), Loc.t("place.schoolyard_location.vom_hof_gehen_orte", "Vom Hof gehen (Orte)"), UIManager.open_map)


# ------------------------------------------------ Nach der Schule (leer)

## Bildgenaue Standflaechen wartender Freunde. Die abnehmenden Groessen sind
## Teil der Komposition: Vordergrundbank, mittlerer Fahrradbereich und ferne
## Eingangstreppe erhalten eine glaubhafte 2,5D-Tiefenstaffelung. Echte
## 32x48-Weltfiguren ersetzen die frueheren schwebenden Portraetquadrate und
## teilen mit ihrer Klickzone exakt dieselbe Projektion.
const FRIEND_ACTOR_RECTS := [
	Rect2(305, 495, 112, 170),
	Rect2(1190, 440, 96, 146),
	Rect2(548, 300, 88, 134),
]


func _build_afterschool() -> void:
	add_hotspot(Rect2(10, 300, 190, 180), Loc.t("place.schoolyard_location.schwarzes_brett", "Schwarzes Brett"), _board)
	add_hotspot(Rect2(690, 855, 430, 86), Loc.t("place.schoolyard_location.nach_hause_orte", "Nach Hause (Orte)"), UIManager.open_map)

	var present: Array = NPCManager.present_at("schoolyard")
	# Der verabredete Pruefungstermin bekommt unten eine eigene, vollwertige
	# Figur mit echtem NPC-Dialog statt des allgemeinen Geruechtefensters.
	if _exam_due():
		present.erase("npc_voss")
	if present.is_empty():
		if not _exam_due():
			# Niemand da — das gehörte damals dazu.
			UIManager.toast.call_deferred(
				Loc.t("place.schoolyard.empty_afternoon",
					"Der Hof liegt leer in der Nachmittagssonne. Heute ist niemand von deinen Freunden da."))
		return
	for i in mini(present.size(), FRIEND_ACTOR_RECTS.size()):
		var id: String = present[i]
		add_npc_actor(id, FRIEND_ACTOR_RECTS[i], _talk_friend.bind(id))
	var names := present.map(func(id: String) -> String: return NPCManager.get_npc(id).get("name", "?"))
	UIManager.toast.call_deferred(Loc.t("place.schoolyard_location.auf_dem_hof_s_geh_ruhig", "Auf dem Hof: %s. Geh ruhig hin.") % ", ".join(names))


## Die Abschlusspruefung ist eine feste Verabredung und darf nicht von Voss'
## normalem Mittwochsplan, Ferien oder der 15-%-Abwesenheit blockiert werden.
## Tagsueber steht er gut sichtbar am Schuleingang; abends erklaert derselbe
## Eingang praezise, wann der Spieler wiederkommen soll.
func _build_exam_access() -> void:
	if not _exam_due():
		return
	if TimeManager.slot > NPCManager.AFTERNOON_SLOT:
		add_hotspot(
			Rect2(440, 270, 310, 245),
			Loc.t("place.schoolyard.exam_entrance_daytime",
				"Schuleingang · Abschlussprüfung tagsüber"),
			_exam_closed)
		return
	add_npc_actor(
		"npc_voss",
		Rect2(565, 405, 145, 230),
		_talk_voss_exam)
	add_hotspot(
		Rect2(485, 275, 230, 145),
		Loc.t("place.schoolyard.voss_waits_for_exam",
			"Herr Voss wartet am Eingang · Abschlussprüfung"),
		_talk_voss_exam)
	UIManager.toast.call_deferred(
		Loc.t("place.schoolyard.voss_exam_prompt",
			"Herr Voss wartet am Schuleingang. Sprich ihn für die Abschlussprüfung an."))


# ------------------------------------------------------------- Aktionen

func _talk(group_id: String) -> void:
	UIManager.open_rumors("group", group_id)


func _board() -> void:
	UIManager.toggle_window("win_bulletin", func() -> Control:
		var w := BulletinBoardWindow.new()
		w.board_id = "schoolyard"
		return w)


func _entrance() -> void:
	UIManager.toast(Loc.t("place.schoolyard_location.ferien_tur_ist_zu_draussen_auf", "Ferien — die Tür ist zu. Draußen auf dem Hof ist eh mehr los."))


func _exam_due() -> bool:
	return QuestManager.is_active("q_schulabschluss") \
		and QuestManager.stage("q_schulabschluss") == 1


func _talk_voss_exam() -> void:
	DialogueManager.start_dialogue("voss_default", "npc_voss")


func _exam_closed() -> void:
	UIManager.open_info(
		"PRÜFUNGSTERMIN",
		"Für heute ist die Schule zu.\n\nHerr Voss wartet am nächsten Spieltag zwischen 08:10 und 15:40 am Schuleingang.")


## Einen wartenden Freund ansprechen: Begrüßung + ein Gerücht, das er kennt —
## unter Freunden zuverlässig weitererzählt.
func _talk_friend(id: String) -> void:
	var npc := NPCManager.get_npc(id)
	var npc_name: String = npc.get("name", "?")
	NPCManager.change_trust(id, 1)
	var lines := ["„Hey! Schön, dass du vorbeikommst.“", ""]
	var heard := RumorManager.rumors_for_group("freunde")
	if heard.is_empty():
		lines.append("„Viel Neues gibt's grad nicht. Aber cool, dass du da bist.“")
	else:
		lines.append("„Ach, haste schon gehört?“")
		lines.append("»%s«" % heard[0])
	# Szene-Kultur: manchmal legt der Freund einem einen Musiker ans Herz (MOD-Bible).
	if randf() < 0.5:
		var tip := MODBible.friend_recommendation()
		if tip != "":
			lines.append("")
			lines.append("„%s“" % tip)
	# Stefan lässt sich auch hier das Weltraumspiel zeigen (Quest bleibt möglich).
	if id == "npc_stefan" and QuestManager.is_active("q_stefan_space") \
			and QuestManager.stage("q_stefan_space") in [1, 2] \
			and DiskManager.has_template("game_space_lemming"):
		lines.append("")
		lines.append("„Moment — DU hast das Weltraumspiel dabei?! Zeig her!“ (Frag ihn zu Hause.)")
	if id == "npc_stefan" and QuestManager.is_active("q_stefan_turbo") \
			and QuestManager.stage("q_stefan_turbo") == 3 \
			and DiskManager.has_player_copy_of("turbo_kart_deluxe"):
		lines.append("")
		lines.append("„Die Turbo-Kart-Kopie ist fertig? Komm nachher zu mir — Geld und Ersatzdisk liegen bereit.“")
	UIManager.open_info(npc_name.to_upper(), "\n".join(lines))
