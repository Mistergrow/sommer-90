extends Node
## BulletinManager — die SCHWARZEN BRETTER der Stadt. Physische Aushänge je Ort
## (data/bulletin.json), era-/faktengegated wie die Timeline. Der Spieler kann
## eigene Zettel anpinnen (am Club bringt das etwas Szene-Ruf). Ergänzt — ersetzt
## NICHT — das Gerüchte-System (Boards mit "rumors" verlinken es).
##
## Spieler-Pins liegen in GameManager.flags["bulletin_pins"] (schon im Save) →
## kein Eingriff in den SaveManager nötig.

const CONFIG := "res://data/bulletin.json"

var _boards: Dictionary = {}
var _postings: Array = []


func _ready() -> void:
	if not FileAccess.file_exists(CONFIG):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if parsed is Dictionary:
		_boards = parsed.get("boards", {})
		_postings = parsed.get("postings", [])


func board(id: String) -> Dictionary:
	var source: Dictionary = _boards.get(id, {})
	var out := source.duplicate(true)
	if out.has("title"):
		out["title"] = Loc.t("board.%s.title" % id, str(source.get("title", "")))
	return out


## Sichtbare Aushänge eines Bretts: nach Jahr (year_from/year_to) und Welt-Fakt
## (needs) gefiltert — genau wie die Living Timeline.
func postings_for(board_id: String) -> Array:
	var year := int(TimeManager.year)
	var out: Array = []
	for p: Dictionary in _postings:
		if str(p.get("board", "")) != board_id:
			continue
		if year < int(p.get("year_from", 1990)):
			continue
		if p.has("year_to") and year > int(p["year_to"]):
			continue
		var needs := str(p.get("needs", ""))
		if needs != "" and not NarrativeManager.fact_true(needs):
			continue
		var visible := p.duplicate(true)
		var anchor := str(p.get("id", p.get("title", "posting")))
		var token := anchor.sha256_text().substr(0, 10)
		var stem := "board.%s.posts.%s" % [board_id, token]
		visible["title"] = Loc.t(stem + ".title", str(p.get("title", "")))
		visible["text"] = Loc.t(stem + ".text", str(p.get("text", "")))
		visible["by"] = Loc.t(stem + ".by", str(p.get("by", "")))
		out.append(visible)
	return out


# ------------------------------------------------------- Spieler-Zettel

func pins_for(board_id: String) -> Array:
	var all: Dictionary = GameManager.flags.get("bulletin_pins", {})
	return all.get(board_id, [])


## Eigenen Aushang anpinnen. Rückgabe: false = leerer Text. Am Computer-Club
## bringt ein Aushang etwas Sichtbarkeit in der Szene (Ruf +1, einmal pro Woche).
func pin(board_id: String, text: String) -> bool:
	var clean := text.strip_edges()
	if clean.is_empty():
		return false
	var all: Dictionary = GameManager.flags.get("bulletin_pins", {})
	var list: Array = all.get(board_id, [])
	list.append({
		"text": clean, "by": PlayerIdentity.player_name, "date": TimeManager.date_string(),
	})
	all[board_id] = list
	GameManager.flags["bulletin_pins"] = all
	if board_id == "club":
		var week := int(float(TimeManager.day_counter) / 7.0)
		if int(GameManager.flags.get("bulletin_ruf_week", -1)) != week:
			GameManager.flags["bulletin_ruf_week"] = week
			PlayerStats.change_stat("ruf", 1)
	return true
