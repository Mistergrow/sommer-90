class_name BargainModel
extends RefCounted
## Kontextuelle Kartenverhandlung. Keine Karte besitzt eine universelle
## Gewinnchance; Händlerprofil, Zustand, Ruf und bereits genutzte Argumente zaehlen.

const CARDS := [&"inspect", &"rapport", &"bundle", &"silence", &"cash", &"pressure"]
const LABELS := {
	&"inspect": "ZUSTAND ANSPRECHEN", &"rapport": "STAMMKUNDE",
	&"bundle": "MEHR ABNEHMEN", &"silence": "SCHWEIGEN",
	&"cash": "BAR & SOFORT", &"pressure": "HARTER PREIS",
}

var level := 1
var run_seed := 1
var seller := "Krause"
var original_price := 10
var price := 10
var reserve := 7
var patience := 5
var mood := 0
var turn_no := 0
var player_ruf := 0
var condition_unknown := true
var used: Array[StringName] = []
var closed := false
var hints := 0
var assisted := false
var archetype:=&"collector"


func configure(next_level: int, next_seed: int, next_seller: String,
		next_price: int, ruf: int, unknown_condition := true) -> void:
	level = clampi(next_level, 1, 5)
	run_seed = next_seed
	archetype=[&"collector",&"parent",&"dealer",&"casual_seller"][posmod(run_seed+level,4)]
	seller = next_seller
	original_price = maxi(1, next_price)
	price = original_price
	player_ruf = maxi(0, ruf)
	condition_unknown = unknown_condition
	var profile_floor := 0.62 if seller.to_lower().contains("krause") else 0.68
	reserve = maxi(1, ceili(original_price * (profile_floor + level * 0.018)))
	patience = maxi(3, 7 - floori(level / 2.0))
	mood = 0
	turn_no = 0
	used = []
	closed = false
	hints = 0
	assisted = false


func play(card: StringName) -> Dictionary:
	if closed or card not in CARDS:
		return {"ok": false, "text": Loc.t("game.bargain_model.verhandlung_ist_beendet", "Die Verhandlung ist beendet.")}
	if card in used:
		patience -= 1
		return _after(false, "Das Argument hat er schon gehoert.")
	used.append(card)
	turn_no += 1
	var power := _power(card)
	var discount := maxi(0, roundi(original_price * power))
	if discount > 0:
		price = maxi(reserve, price - discount)
		mood += 1
	else:
		patience -= 1 + int(card == &"pressure")
		mood -= 1
	return _after(discount > 0, _line(card, discount))


func _power(card: StringName) -> float:
	match card:
		&"inspect": return 0.10 if condition_unknown else 0.03
		&"rapport": return 0.09 if player_ruf >= 4 else 0.0
		&"bundle": return 0.08 if seller.to_lower().contains("krause") else 0.04
		&"silence": return 0.06 if mood >= 0 and turn_no >= 1 else 0.0
		&"cash": return 0.07 if turn_no >= 1 else 0.03
		&"pressure": return 0.08 if player_ruf >= 10 and patience >= 4 else 0.0
	return 0.0


func _line(card: StringName, discount: int) -> String:
	if discount <= 0:
		return "Das zieht heute nicht. Geduld %d." % maxi(0, patience)
	if card == &"inspect": condition_unknown = false
	return "%s wirkt: -%d DM, Gegenangebot %d DM." % [LABELS[card], discount, price]


func _after(ok: bool, text: String) -> Dictionary:
	if patience <= 0:
		closed = true
		text += " Der Haendler beendet das Gespraech."
	return {"ok": ok, "text": text, "price": price, "patience": maxi(0, patience),
		"closed": closed}


func hint() -> StringName:
	hints += 1
	var best := &"cash"
	var best_power := -1.0
	for card: StringName in CARDS:
		if card in used: continue
		var p := _power(card)
		if p > best_power:
			best_power = p
			best = card
	return best


func accept() -> bool:
	if closed: return false
	closed = true
	return true


func score() -> int:
	if not closed or patience <= 0: return 0
	var saving := original_price - price
	return maxi(250, 650 + saving * 35 + patience * 45 + level * 70 - hints * 100
		- (350 if assisted else 0))


func details() -> Dictionary:
	return {"level": level, "seller": seller, "archetype":str(archetype), "original_price": original_price,
		"price": price, "saving": original_price - price, "rounds": turn_no,
		"patience": maxi(0, patience), "hints": hints, "assisted": assisted}
