extends Node
## Stadtbank-Kern: Jugendsparbuch ab 1990, Girokonto ab 1994, EC-Karte,
## historischer Geldausgabeautomat und ein dauerhaftes Buchungsjournal.
##
## WICHTIGER SPIELVERTRAG:
## - Das Sparbuch existiert ab Spielbeginn. Alter und Girokonto duerfen eine
##   Bareinzahlung am Schalter niemals blockieren.
## - Jede Geldbewegung wird in Pfenniggenauigkeit mit Datum, Uhrzeit, Kanal und
##   neuem Saldo protokolliert und gespeichert.
## - Sparbuchzinsen werden beim Sprung in den NAECHSTEN spielbaren Sommer
##   gutgeschrieben, nicht an einem unsichtbaren 1. Januar.

signal bank_changed

const SAVINGS_RATE := 0.035
const GIRO_AVAILABLE_YEAR := 1994
const CARD_DELIVERY_DAYS := 5
const ATM_DAILY_LIMIT := 400.0
const COUNTER_WEEKDAYS := [0, 1, 2, 3, 4]
const COUNTER_SLOTS := [0, 1, 2] # 08:10, 13:00, 15:40; abends nur Automatenraum

var account_open := false       # Girokonto; Sparbuch ist davon unabhaengig.
var balance := 0.0              # Girokonto in DM mit Pfennig
var savings := 0.0              # Sparbuch in DM mit Pfennig
var transactions: Array = []    # unveraenderliche Buchungszeilen

var card_requested_day := -1
var card_issued := false
var card_locked := false
var card_pin := ""
var pin_failures := 0

var _parents_asked_day := -1
var _last_interest_year := 1990
var _transaction_serial := 0


func _ready() -> void:
	var tm := get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_signal("year_changed"):
		tm.year_changed.connect(_on_year_changed)


func _day() -> int:
	return int(TimeManager.day_counter)


func _cash() -> float:
	return Currency.snap(float(PlayerStats.geld))


func counter_open() -> bool:
	return TimeManager.weekday() in COUNTER_WEEKDAYS and TimeManager.slot in COUNTER_SLOTS


func counter_hours_text() -> String:
	return "Mo–Fr · 08:00–16:00 Uhr"


func giro_available() -> bool:
	return TimeManager.year >= GIRO_AVAILABLE_YEAR


func next_interest_year() -> int:
	return maxi(TimeManager.year + 1, _last_interest_year + 1)


# ------------------------------------------------------------ Buchungsjournal

func _record(account: String, kind: String, amount: float, balance_after: float,
		channel: String, note: String) -> void:
	_transaction_serial += 1
	transactions.append({
		"id": _transaction_serial,
		"account": account,
		"kind": kind,
		"amount": Currency.snap(amount),
		"balance_after": Currency.snap(balance_after),
		"channel": channel,
		"note": note,
		"year": TimeManager.year,
		"month": TimeManager.month,
		"day": TimeManager.day,
		"slot": TimeManager.slot,
		"day_counter": TimeManager.day_counter,
		"date": "%02d.%02d.%04d" % [TimeManager.day, TimeManager.month, TimeManager.year],
		"time": TimeManager.clock_string(),
	})


func ledger(account := "") -> Array:
	var rows: Array = []
	for raw: Variant in transactions:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if account.is_empty() or str(entry.get("account", "")) == account:
			rows.append(entry.duplicate(true))
	return rows


func savings_ledger() -> Array:
	return ledger("sparbuch")


func giro_ledger() -> Array:
	return ledger("giro")


# ----------------------------------------------------- Jugendsparbuch (immer)

## Bargeld direkt aufs Sparbuch. Das ist bewusst NICHT an Alter/Giro gekoppelt.
func deposit_to_savings(amount: float, channel := "schalter") -> bool:
	amount = Currency.snap(amount)
	if amount <= 0.0 or _cash() + 0.005 < amount:
		return false
	if not PlayerStats.spend_money(amount):
		return false
	savings = Currency.snap(savings + amount)
	_record("sparbuch", "deposit", amount, savings, channel,
		"Bareinzahlung ins Jugendsparbuch")
	AudioManager.play("cash_count", 0.0)
	AudioManager.play("paper", 0.0)
	bank_changed.emit()
	return true


func withdraw_from_savings(amount: float, channel := "schalter") -> bool:
	amount = Currency.snap(amount)
	if amount <= 0.0 or savings + 0.005 < amount:
		return false
	savings = Currency.snap(savings - amount)
	PlayerStats.add_money(amount)
	_record("sparbuch", "withdrawal", -amount, savings, channel,
		"Barauszahlung aus dem Sparbuch")
	AudioManager.play("cash_count", 0.0)
	AudioManager.play("paper", 0.0)
	bank_changed.emit()
	return true


# ---------------------------------------------------------- Giro eroeffnen

func parents_asked() -> bool:
	return _parents_asked_day >= 0


func needs_parent_signature() -> bool:
	return PlayerIdentity.age() < 18


func ask_parents() -> void:
	if account_open or not giro_available() or not needs_parent_signature():
		return
	if _parents_asked_day < 0:
		_parents_asked_day = _day()
		bank_changed.emit()


func can_open() -> bool:
	if account_open or not giro_available():
		return false
	if not needs_parent_signature():
		return true
	return _parents_asked_day >= 0 and _day() > _parents_asked_day


func open_account() -> bool:
	if not can_open():
		return false
	account_open = true
	_record("giro", "opening", 0.0, balance, "schalter", "Girokonto eroeffnet")
	GameManager.flags["bank_giro_opened"] = true
	AudioManager.relay()
	bank_changed.emit()
	QuestManager.evaluate()
	return true


# ------------------------------------------------------ Giro Ein-/Auszahlung

func deposit(amount: float, channel := "schalter", note := "Bareinzahlung aufs Girokonto") -> bool:
	amount = Currency.snap(amount)
	if not account_open or amount <= 0.0 or _cash() + 0.005 < amount:
		return false
	if not PlayerStats.spend_money(amount):
		return false
	balance = Currency.snap(balance + amount)
	_record("giro", "deposit", amount, balance, channel, note)
	AudioManager.play("cash_count", 0.0)
	bank_changed.emit()
	return true


func withdraw(amount: float, channel := "schalter", note := "Barauszahlung vom Girokonto") -> bool:
	amount = Currency.snap(amount)
	if not account_open or amount <= 0.0 or balance + 0.005 < amount:
		return false
	balance = Currency.snap(balance - amount)
	PlayerStats.add_money(amount)
	_record("giro", "withdrawal", -amount, balance, channel, note)
	AudioManager.play("cash_count", 0.0)
	bank_changed.emit()
	return true


func save_to_savings(amount: float, channel := "schalter") -> bool:
	amount = Currency.snap(amount)
	if not account_open or amount <= 0.0 or balance + 0.005 < amount:
		return false
	balance = Currency.snap(balance - amount)
	savings = Currency.snap(savings + amount)
	_record("giro", "transfer_out", -amount, balance, channel, "Uebertrag aufs Sparbuch")
	_record("sparbuch", "transfer_in", amount, savings, channel, "Uebertrag vom Girokonto")
	AudioManager.play("paper", 0.0)
	bank_changed.emit()
	return true


func take_from_savings(amount: float, channel := "schalter") -> bool:
	amount = Currency.snap(amount)
	if not account_open or amount <= 0.0 or savings + 0.005 < amount:
		return false
	savings = Currency.snap(savings - amount)
	balance = Currency.snap(balance + amount)
	_record("sparbuch", "transfer_out", -amount, savings, channel, "Uebertrag aufs Girokonto")
	_record("giro", "transfer_in", amount, balance, channel, "Uebertrag vom Sparbuch")
	AudioManager.play("paper", 0.0)
	bank_changed.emit()
	return true


# ------------------------------------------------------- EC-Karte / PIN-Brief

func request_card() -> bool:
	if not account_open or card_issued or card_requested_day >= 0:
		return false
	card_requested_day = _day()
	_record("giro", "card_order", 0.0, balance, "schalter",
		"EC-Karte mit Magnetstreifen bestellt")
	bank_changed.emit()
	return true


func card_days_remaining() -> int:
	if card_requested_day < 0 or card_issued:
		return 0
	return maxi(0, CARD_DELIVERY_DAYS - (_day() - card_requested_day))


func can_collect_card() -> bool:
	return account_open and not card_issued and card_requested_day >= 0 \
		and card_days_remaining() == 0


func collect_card() -> bool:
	if not can_collect_card():
		return false
	card_issued = true
	card_locked = false
	pin_failures = 0
	if card_pin.is_empty():
		card_pin = _make_pin()
	_record("giro", "card_issue", 0.0, balance, "schalter",
		"EC-Karte und separaten PIN-Brief erhalten")
	GameManager.flags["bank_ec_card_collected"] = true
	AudioManager.play("paper", 0.0)
	bank_changed.emit()
	QuestManager.evaluate()
	return true


func _make_pin() -> String:
	var source := "%s/%d/%d/%d" % [PlayerIdentity.player_name, PlayerIdentity.birth_day,
		PlayerIdentity.birth_month, TimeManager.year]
	return "%04d" % (1000 + posmod(hash(source), 9000))


func pin_letter_text() -> String:
	return card_pin if card_issued else "----"


func verify_pin(entered: String) -> bool:
	if not card_issued or card_locked:
		return false
	if entered == card_pin:
		pin_failures = 0
		bank_changed.emit()
		return true
	pin_failures += 1
	if pin_failures >= 3:
		card_locked = true
		_record("giro", "card_lock", 0.0, balance, "geldautomat",
			"EC-Karte nach drei falschen PIN-Eingaben einbehalten")
	bank_changed.emit()
	return false


func unlock_card() -> bool:
	if not card_issued or not card_locked:
		return false
	card_locked = false
	pin_failures = 0
	_record("giro", "card_unlock", 0.0, balance, "schalter",
		"EC-Karte nach Identitaetspruefung entsperrt")
	bank_changed.emit()
	return true


# ------------------------------------------------------------ Geldautomat

func atm_withdrawn_today() -> float:
	var sum := 0.0
	for raw: Variant in transactions:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if str(entry.get("account", "")) == "giro" \
				and str(entry.get("channel", "")) == "geldautomat" \
				and str(entry.get("kind", "")) == "withdrawal" \
				and int(entry.get("day_counter", -1)) == _day():
			sum += absf(float(entry.get("amount", 0.0)))
	return Currency.snap(sum)


func atm_limit_remaining() -> float:
	return Currency.snap(maxf(0.0, ATM_DAILY_LIMIT - atm_withdrawn_today()))


## Eine einzige, UI-unabhaengige Wahrheit fuer den Automaten. Das Tageslimit
## ist nur eine Obergrenze und darf nicht als tatsaechlich verfuegbares Geld
## missverstanden werden: ausgezahlt wird ausschliesslich vom Girokonto.
func atm_availability() -> Dictionary:
	var giro := Currency.snap(maxf(0.0, balance))
	var daily_limit := atm_limit_remaining()
	var available := Currency.snap(minf(giro, daily_limit))
	return {
		"giro": giro,
		"daily_limit": daily_limit,
		"available": available,
		"savings": Currency.snap(maxf(0.0, savings)),
	}


func atm_withdraw(amount: float) -> Dictionary:
	amount = Currency.snap(amount)
	if not card_issued:
		return {"ok": false, "text": Loc.t("sys.bank_manager.keine_ec_karte", "Keine EC-Karte.")}
	if card_locked:
		return {"ok": false, "text": "Karte gesperrt — bitte zum Schalter."}
	if amount > atm_limit_remaining() + 0.005:
		return {"ok": false, "text": Loc.t("sys.bank_manager.tageslimit_noch_s_verfuegbar", "Tageslimit: noch %s verfuegbar.") % Currency.format(atm_limit_remaining())}
	if balance + 0.005 < amount:
		return {"ok": false, "text": Loc.t("sys.bank_manager.kontodeckung_reicht_nicht_aus", "Kontodeckung reicht nicht aus.")}
	if not withdraw(amount, "geldautomat", "Bargeldauszahlung am GAA"):
		return {"ok": false, "text": Loc.t("sys.bank_manager.auszahlung_nicht_moeglich", "Auszahlung nicht moeglich.")}
	return {"ok": true, "text": "%s ausgezahlt." % Currency.format(amount), "amount": amount}


## Zeittypische Automaten-Einzahlung ueber Belegumschlag/Einzahlungsfach.
func atm_deposit(amount: float) -> Dictionary:
	if not card_issued:
		return {"ok": false, "text": Loc.t("sys.bank_manager.keine_ec_karte", "Keine EC-Karte.")}
	if card_locked:
		return {"ok": false, "text": "Karte gesperrt — bitte zum Schalter."}
	if not deposit(amount, "geldautomat", "Einzahlung am GAA (Belegfach)"):
		return {"ok": false, "text": Loc.t("sys.bank_manager.einzahlung_nicht_moeglich_bargeld_pruefen", "Einzahlung nicht moeglich — Bargeld pruefen.")}
	return {"ok": true, "text": "%s zur Einzahlung angenommen." % Currency.format(amount),
		"amount": Currency.snap(amount)}


# --------------------------------------------------------------- Verzinsung

func _on_year_changed(new_year: int) -> void:
	if new_year <= _last_interest_year:
		return
	# Normalerweise genau ein Jahr. Die Schleife macht auch importierte/alte
	# Spielstaende robust und verzinst jeden fehlenden Sommer nachvollziehbar.
	for interest_year in range(_last_interest_year + 1, new_year + 1):
		if savings > 0.0:
			var interest := Currency.snap(savings * SAVINGS_RATE)
			if interest > 0.0:
				savings = Currency.snap(savings + interest)
				_record("sparbuch", "interest", interest, savings, "zinslauf",
					"Zinsgutschrift Sommer %d (%.2f %%)" % [interest_year, SAVINGS_RATE * 100.0])
	_last_interest_year = new_year
	bank_changed.emit()
	if savings > 0.0:
		UIManager.toast(Loc.t("sys.bank_manager.stadtbank_zinsen_wurden_ins_sparbuch_eingetragen", "Stadtbank: Die Zinsen wurden ins Sparbuch eingetragen."))


func total() -> float:
	return Currency.snap(balance + savings)


# --------------------------------------------------------------- Save / Load

func to_dict() -> Dictionary:
	return {
		"open": account_open,
		"balance": balance,
		"savings": savings,
		"asked_day": _parents_asked_day,
		"transactions": transactions,
		"transaction_serial": _transaction_serial,
		"last_interest_year": _last_interest_year,
		"card_requested_day": card_requested_day,
		"card_issued": card_issued,
		"card_locked": card_locked,
		"card_pin": card_pin,
		"pin_failures": pin_failures,
	}


func from_dict(d: Dictionary) -> void:
	account_open = bool(d.get("open", false))
	balance = Currency.snap(float(d.get("balance", 0.0)))
	savings = Currency.snap(float(d.get("savings", 0.0)))
	_parents_asked_day = int(d.get("asked_day", -1))
	var stored_transactions: Variant = d.get("transactions", [])
	transactions = stored_transactions.duplicate(true) if stored_transactions is Array else []
	_transaction_serial = int(d.get("transaction_serial", transactions.size()))
	_last_interest_year = int(d.get("last_interest_year", TimeManager.year))
	card_requested_day = int(d.get("card_requested_day", -1))
	card_issued = bool(d.get("card_issued", false))
	card_locked = bool(d.get("card_locked", false))
	card_pin = str(d.get("card_pin", ""))
	pin_failures = int(d.get("pin_failures", 0))
	# Migration alter Spielstaende: vorhandene Salden bleiben erhalten und
	# bekommen eine sichtbare erste Journalzeile statt spaeter "aus dem Nichts".
	if transactions.is_empty():
		if savings > 0.0:
			_record("sparbuch", "opening", savings, savings, "migration",
				"Uebernommener Sparbuchstand")
		if account_open or balance > 0.0:
			_record("giro", "opening", balance, balance, "migration",
				"Uebernommener Girostand")
	bank_changed.emit()


## Fortschrittsflags sind Teil der Quest-Schnittstelle. Der Abgleich macht auch
## Spielstaende von vor dem Bankausbau kompatibel, in denen Konto/Karte bereits
## vorhanden waren, die neuen Marker aber noch nicht gespeichert werden konnten.
func sync_progress_flags() -> void:
	if account_open:
		GameManager.flags["bank_giro_opened"] = true
	if card_issued:
		GameManager.flags["bank_ec_card_collected"] = true


func reset() -> void:
	account_open = false
	balance = 0.0
	savings = 0.0
	transactions = []
	card_requested_day = -1
	card_issued = false
	card_locked = false
	card_pin = ""
	pin_failures = 0
	_parents_asked_day = -1
	_last_interest_year = TimeManager.year
	_transaction_serial = 0
	GameManager.flags.erase("bank_giro_opened")
	GameManager.flags.erase("bank_ec_card_collected")
	bank_changed.emit()
