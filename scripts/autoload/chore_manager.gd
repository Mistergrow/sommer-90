extends Node
## ChoreManager — HAUSARBEIT FÜR TASCHENGELD. Die Eltern zahlen für Hilfe im
## Haushalt, jetzt mit echten Pfennig-Beträgen (2,50 DM usw.). Manche Aufgaben
## haben BEDINGUNGEN (Müll nur wenn welcher rumliegt, Aufräumen nur bei Unordnung,
## Auto waschen nur am Wochenende, Rasen nur im Sommer) → kein endloses Geldfarmen.
## Pro Tag zahlen die Eltern für höchstens MAX_PER_DAY Aufgaben („das reicht für
## heute"). Zustand liegt in GameManager.flags["chores"] (schon im Save; kein
## SaveManager-Eingriff → kollisionsfrei).

signal chores_changed

const MAX_PER_DAY := 3          # so viele bezahlte Aufgaben zahlen die Eltern am Tag

## id · label · reward (DM mit Pfennig) · energy · cond · effect · hint
const CHORES := [
	{"id": "muell", "label": "Müll rausbringen", "reward": 2.50, "energy": 3,
		"cond": "litter", "effect": "trash", "hint": "Leere Dosen & Verpackungen zum Container."},
	{"id": "aufraeumen", "label": "Zimmer aufräumen", "reward": 3.00, "energy": 6,
		"cond": "messy", "effect": "tidy", "hint": "Alles wieder an seinen Platz."},
	{"id": "spuelen", "label": "Geschirr spülen", "reward": 2.00, "energy": 4,
		"cond": "", "effect": "", "hint": "Der Abwasch türmt sich in der Küche."},
	{"id": "staubsaugen", "label": "Staubsaugen", "reward": 2.50, "energy": 5,
		"cond": "", "effect": "", "hint": "Wohnzimmer und Flur."},
	{"id": "einkauf", "label": "Einkaufen für Mama", "reward": 3.50, "energy": 4,
		"cond": "", "effect": "", "hint": "Kurz zum Kiosk und zurück."},
	{"id": "auto_waschen", "label": "Auto waschen", "reward": 5.00, "energy": 8,
		"cond": "weekend", "effect": "", "hint": "Papas Stolz auf Hochglanz — nur am Wochenende."},
	{"id": "rasen", "label": "Rasen mähen", "reward": 5.00, "energy": 9,
		"cond": "summer", "effect": "", "hint": "Der Garten ruft — nur im Sommer."},
]

const SUCCESS_LINES := {
	"muell": [
		"Der Containerdeckel faellt zu. Keine Dose blieb unter dem Schreibtisch.",
		"Sauber getrennt und nichts tropft auf der Treppe.",
		"Papier links, Wertstoff rechts, Rest weg. Sogar der Nachbar nickt anerkennend.",
		"Die letzte Coladose scheppert ins Ziel. Rekordverdaechtig unpeinlich.",
		"Muellsack dicht, Haende sauber. Das Treppenhaus hat ueberlebt."],
	"aufraeumen": [
		"Der Boden ist wieder sichtbar. Sogar die Disketten stehen richtig herum.",
		"Mama schaut durch die Tuer und findet diesmal wirklich nichts liegen.",
		"Regal, Diskbox und Waeschekorb melden: alles am richtigen Port.",
		"Der Schreibtisch hat wieder eine Oberflaeche. Fast schon Ausstellungsstueck.",
		"Kein Socken unter dem Amiga. Das grenzt an professionelle Ordnung."],
	"spuelen": [
		"Der letzte Teller quietscht sauber; die Kueche ist wieder benutzbar.",
		"Abtropfbrett voll, Spuele leer. Das zaehlt als klarer Sieg.",
		"Drei Stationen, kein Scherbenhaufen. Die Tassen stehen Parade.",
		"Der Topf gibt seinen Widerstand auf. Spuelwerk 1200 gewinnt.",
		"Schaum weg, Wasser aus, Geschirr heil. Besser endet kein Abwasch."],
	"staubsaugen": [
		"Die letzte Staubspur verschwindet am Teppichrand.",
		"Keine Kruemel mehr im Flur. Der Staubsauger darf zurueck in die Kammer.",
		"Selbst hinter dem Sessel ist Ruhe. Der Beutel klingt zufrieden.",
		"Das Kabel blieb ganz und der Teppich zeigt wieder Farbe.",
		"Kruemeljagd beendet. Nur der Staubsauger schnauft noch."],
	"einkauf": [
		"Alles vom Zettel ist in der Tuete, Wechselgeld stimmt auch.",
		"Kein Umweg am Zeitschriftenregal: Einkauf vollstaendig abgeliefert.",
		"Milch kalt, Brot heil, Wechselgeld vollstaendig. Mama ist beeindruckt.",
		"Kein falscher Artikel in der Tuete. Der Kiosk kann einpacken.",
		"Zettel leer, Vorrat voll. Und die Schokolade blieb tatsaechlich im Regal."],
	"auto_waschen": [
		"Auf der Motorhaube spiegelt sich wieder der Himmel.",
		"Felgen sauber, Scheiben streifenfrei. Papa prueft zweimal und nickt.",
		"Schaum, Wasser, Leder: Der Lack glaenzt wie im Sonntagsprospekt.",
		"Sogar die Radkappen sehen wieder nach Absicht aus.",
		"Der Wagen ist sauberer als die Einfahrt. Papa sucht vergeblich nach Streifen."],
	"rasen": [
		"Die letzte Bahn liegt gerade; nur die Kanten duften noch nach Gras.",
		"Kein Streifen ausgelassen und das Kabel lebt auch noch.",
		"Der Rasen hat jetzt Scanlines. Der Nachbar nennt es akkurat.",
		"Alle Bahnen parallel und kein Gartenzwerg verletzt.",
		"Motor aus. Im Garten bleibt nur der Geruch nach frisch geschnittenem Sommer."],
}


## Tages-Zustand {day, done:[ids], count}. Bei Tageswechsel automatisch zurückgesetzt.
func _state() -> Dictionary:
	var day := int(TimeManager.day_counter)
	var s: Dictionary = GameManager.flags.get("chores", {})
	if int(s.get("day", -1)) != day:
		s = {"day": day, "done": [], "count": 0}
		GameManager.flags["chores"] = s
	return s


func _find(id: String) -> Dictionary:
	for c: Dictionary in CHORES:
		if str(c["id"]) == id:
			return c
	return {}


func chore_by_id(id: String) -> Dictionary:
	return _find(id).duplicate(true)


func localized_field(chore: Dictionary, field: String) -> String:
	var id := str(chore.get("id", "unknown"))
	return Loc.t("chore.%s.%s" % [id, field], str(chore.get(field, "")))


## Ist die Bedingung der Aufgabe gerade erfüllt?
func _cond_ok(chore: Dictionary) -> bool:
	match str(chore.get("cond", "")):
		"litter":
			return RoomManager.litter_count() > 0
		"messy":
			return RoomManager.cleanliness() < 80
		"weekend":
			return TimeManager.weekday() >= 5      # 5=Samstag, 6=Sonntag
		"summer":
			return TimeManager.season_name() == "Sommer"
	return true


## Heute noch erledigbare Aufgaben (Bedingung erfüllt, noch nicht gemacht, unter Tageslimit).
func available() -> Array:
	var out: Array = []
	var s := _state()
	if int(s.get("count", 0)) >= MAX_PER_DAY:
		return out
	var done: Array = s.get("done", [])
	for c: Dictionary in CHORES:
		if str(c["id"]) in done:
			continue
		if _cond_ok(c):
			out.append(c)
	return out


func remaining_today() -> int:
	return maxi(0, MAX_PER_DAY - int(_state().get("count", 0)))


func is_done_today(id: String) -> bool:
	return id in (_state().get("done", []) as Array)


func can_do_chore(id: String) -> Dictionary:
	var s := _state()
	if int(s.get("count", 0)) >= MAX_PER_DAY:
		return {"ok": false, "reason": Loc.t("sys.chore_manager.enough_today", "Fuer heute ist genug geholfen.")}
	var chore := _find(id)
	if chore.is_empty():
		return {"ok": false, "reason": Loc.t("sys.chore_manager.diese_aufgabe_gibt_es_nicht", "Diese Aufgabe gibt es nicht.")}
	if id in (s.get("done", []) as Array):
		return {"ok": false, "reason": Loc.t("sys.chore_manager.hast_du_heute_schon_erledigt", "Das hast du heute schon erledigt.")}
	if not _cond_ok(chore):
		return {"ok": false, "reason": Loc.t("sys.chore_manager.dafur_gibt_es_gerade_nichts_zu", "Dafuer gibt es gerade nichts zu tun.")}
	if PlayerStats.energie < int(chore.get("energy", 0)):
		return {"ok": false, "reason": Loc.t("sys.chore_manager.zu_mude_fur_hausarbeit_erst_mal", "Zu muede fuer Hausarbeit — erst mal ausruhen.")}
	return {"ok": true, "reason": "", "chore": chore}


## Aufgabe erledigen: Energie kostet, Effekt greift, Eltern zahlen (Pfennig) und
## freuen sich ein bisschen (eltern_toleranz +1). Rückgabe {ok, text, reward}.
func do_chore(id: String) -> Dictionary:
	# Kompatibilitaetsadapter fuer alte Szenen und Save-Vertraege. Die sichtbare
	# Spieler-UI startet immer den HouseholdSprint und zahlt niemals hier per Klick.
	return _commit_chore(id)


func complete_chore_minigame(id: String, score: int, details: Dictionary) -> Dictionary:
	if score < 500 or int(details.get("cleared", 0)) < int(details.get("targets", 1)):
		return {"ok": false, "text": Loc.t("sys.chore_manager.sprint_incomplete",
			"Die Aufgabe ist noch nicht vollstaendig erledigt.")}
	return _commit_chore(id)


func _commit_chore(id: String) -> Dictionary:
	var s := _state()
	if int(s.get("count", 0)) >= MAX_PER_DAY:
		return {"ok": false, "text": Loc.t("sys.chore_manager.reicht_fur_heute_schatz_geh_spielen", "„Das reicht für heute, Schatz. Geh spielen.")}
	var chore := _find(id)
	if chore.is_empty():
		return {"ok": false, "text": Loc.t("sys.chore_manager.diese_aufgabe_gibt_es_nicht", "Diese Aufgabe gibt es nicht.")}
	if id in (s.get("done", []) as Array):
		return {"ok": false, "text": Loc.t("sys.chore_manager.hast_du_heute_schon_erledigt", "Das hast du heute schon erledigt.")}
	if not _cond_ok(chore):
		return {"ok": false, "text": Loc.t("sys.chore_manager.dafur_gibt_es_gerade_nichts_zu", "Dafür gibt es gerade nichts zu tun.")}
	if not PlayerStats.use_energy(int(chore.get("energy", 0))):
		return {"ok": false, "text": Loc.t("sys.chore_manager.zu_mude_fur_hausarbeit_erst_mal", "Zu müde für Hausarbeit — erst mal ausruhen.")}

	match str(chore.get("effect", "")):
		"trash":
			RoomManager.take_out_trash()
		"tidy":
			RoomManager.tidy()

	var reward: float = float(chore.get("reward", 0.0))
	PlayerStats.add_money(reward)
	PlayerStats.change_stat("eltern_toleranz", 1)   # Helfen bessert die elterliche Laune
	AudioManager.play("coins", 0.0)
	s["done"] = (s.get("done", []) as Array) + [id]
	s["count"] = int(s.get("count", 0)) + 1
	GameManager.flags["chores"] = s
	MemoryManager.record_once("first_chore", "zum ersten Mal im Haushalt geholfen und Taschengeld verdient")
	chores_changed.emit()
	var variants: Array = SUCCESS_LINES.get(id, ["Aufgabe sauber erledigt."])
	var variant_index := posmod(TimeManager.day_counter + hash(id), variants.size())
	var completion := Loc.t("chore.%s.success.%d" % [id, variant_index], str(variants[variant_index]))
	return {"ok": true, "reward": reward,
		"text": Loc.t("sys.chore_manager.sprint_reward", "%s · +%s") % [completion, Currency.format(reward)]}


func reset() -> void:
	chores_changed.emit()
