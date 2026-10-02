extends Node
## IntegrityManager — Anti-Cheat / Spielstand-Integrität (rein defensiv, offline).
##
## Drei Schutzschichten für DIESES Einzelspieler-Spiel:
##  1) SPIELSTAND-SIGNATUR: der Save wird mit einem (obfuskierten) Schlüssel
##     signiert (SHA-256 über kanonisches JSON + Secret). Von Hand editierte
##     savegame.json fallen beim Laden auf → Erfolge werden gesperrt.
##  2) LAUFZEIT-SCHUTZ (gegen Cheat Engine & Co.): kritische Werte (Geld, Energie,
##     Ruf, Wissen, Eltern-Toleranz) werden gespiegelt mit einer Sitzungs-Maske
##     gehalten. JEDE legitime Änderung läuft über PlayerStats.stats_changed und
##     hält den Schatten synchron; ein direkter Speicher-Poke umgeht das Signal →
##     Schatten und Live-Wert driften auseinander → erkannt. Dazu Plausibilitäts-
##     grenzen (Geld/Stats).
##  3) SPEEDHACK-ERKENNUNG: aufsummierte Engine-Zeit gegen die Wanduhr
##     (Time.get_unix_time_from_system, die ein Timer-Hack NICHT mitzieht).
##
## Reaktion ist NICHT zerstörerisch: Spielstand bleibt spielbar, wird aber als
## „manipuliert" markiert (cheated) und schaltet ab da keine Erfolge mehr frei.

signal integrity_changed

const GUARDED := ["geld", "energie", "hunger", "ruf", "wissen", "eltern_toleranz"]
const MONEY_MAX := 9_999_999
const SPEED_TOL := 1.6          # Engine-Zeit darf max. 1,6× schneller als Wanduhr laufen
const CHECK_EVERY := 1.0        # s: Prüf-Intervall im Spiel
const SPEED_WINDOW := 5.0       # s Wanduhr: Fenster für die Speedhack-Messung
const WARMUP := 2.5             # s: Anlauf, bevor geprüft wird (Ladehitches ignorieren)

var _flagged := false           # aktueller Lauf hat eine Manipulation gesehen
var _cheated := false           # persistent: dieser Spielstand gilt als manipuliert
var _reason := ""
var _gm: Node = null            # GameManager-Ref, lazy — _process läuft jeden Frame

var _mask := 0                  # Sitzungs-Maske (nie gespeichert)
var _shadow: Dictionary = {}    # key -> (wert ^ _mask)

var _since := 0.0               # Zeit seit letztem Check
var _eng := 0.0                 # aufsummierte Engine-Zeit
var _uptime := 0.0
var _win_wall0 := 0.0
var _win_eng0 := 0.0
var _win_init := false


func _ready() -> void:
	_mask = randi() | 1
	var ps := get_node_or_null("/root/PlayerStats")
	if ps != null and ps.has_signal("stats_changed"):
		ps.stats_changed.connect(_resync)
	_resync()


# ---------------------------------------------------- Laufzeit-Schutz (Werte)

## Schatten aus den aktuellen (legitimen) Werten neu setzen. Läuft bei JEDER
## PlayerStats-Änderung (Signal) sowie nach dem Laden.
func _resync() -> void:
	var ps := get_node_or_null("/root/PlayerStats")
	if ps == null:
		return
	for k in GUARDED:
		_shadow[k] = _guarded_int(ps, k) ^ _mask


## Ganzzahliger Prüfwert eines geschützten Feldes. Geld ist float-DM mit Pfennig →
## als GANZE PFENNIG spiegeln, sonst würde der int-Cast die Pfennig verschlucken
## und legitime Kleinbeträge fälschlich als Poke melden (bzw. Cheats übersehen).
func _guarded_int(ps: Object, key: String) -> int:
	if key == "geld":
		return int(round(float(ps.get("geld")) * 100.0))
	return int(ps.get(key))


## Prüft Schatten↔Live und Plausibilitätsgrenzen. Liefert die Liste der Verstöße
## (leer = sauber). Verändert nichts — die Reaktion macht der Aufrufer via flag().
func verify() -> Array:
	var out: Array = []
	var ps := get_node_or_null("/root/PlayerStats")
	if ps == null:
		return out
	for k in GUARDED:
		var live := _guarded_int(ps, k)          # geld = ganze Pfennig
		if not _shadow.has(k):
			continue
		if (int(_shadow[k]) ^ _mask) != live:
			out.append("wert:%s" % k)          # außerhalb des Setters verändert (Speicher-Poke)
		elif k == "geld":
			if live < 0 or live > MONEY_MAX * 100:   # Grenze in Pfennig
				out.append("grenze:geld")
		elif live < 0 or live > 100:
			out.append("grenze:%s" % k)
	# Erfolge können nicht mehr als definiert sein
	var am := get_node_or_null("/root/AchievementManager")
	if am != null and int(am.call("unlocked_count")) > int(am.call("total")):
		out.append("erfolge:zuviele")
	return out


# ---------------------------------------------------- Speedhack-Erkennung

## Reines Verhältnis Engine-Zeit/Wanduhr (für Test + _process). >SPEED_TOL = Hack.
func speed_ratio(engine_s: float, wall_s: float) -> float:
	if wall_s <= 0.01:
		return 1.0
	return engine_s / wall_s


func is_speedhack(engine_s: float, wall_s: float) -> bool:
	return wall_s >= 1.0 and speed_ratio(engine_s, wall_s) > SPEED_TOL


func _process(delta: float) -> void:
	_eng += delta
	_uptime += delta
	if _uptime < WARMUP:
		return
	if _gm == null:
		_gm = get_node_or_null("/root/GameManager")
	if _gm == null or int(_gm.get("state")) != _gm.get("State").PLAYING:
		return
	if _cheated:
		return
	# Speedhack-Fenster (Wanduhr vs. Engine-Zeit)
	var wall := Time.get_unix_time_from_system()
	if not _win_init:
		_win_wall0 = wall; _win_eng0 = _eng; _win_init = true
	elif wall - _win_wall0 >= SPEED_WINDOW:
		if is_speedhack(_eng - _win_eng0, wall - _win_wall0):
			flag("speedhack")
		_win_wall0 = wall; _win_eng0 = _eng
	# Wert-Prüfung (gedrosselt)
	_since += delta
	if _since >= CHECK_EVERY:
		_since = 0.0
		var v := verify()
		if not v.is_empty():
			flag(v[0])


# ---------------------------------------------------- Reaktion / Status

## Manipulation markieren (idempotent, nicht zerstörerisch). Ab jetzt keine
## Erfolge mehr für diesen Spielstand.
func flag(flag_reason: String) -> void:
	_flagged = true
	if not _cheated:
		_cheated = true
		_reason = flag_reason
		var ui := get_node_or_null("/root/UIManager")
		if ui != null:
			ui.call("toast", "⚠ Ungültiger Spielzustand erkannt (%s). Erfolge für diesen Spielstand deaktiviert." % flag_reason)
		integrity_changed.emit()


func ok() -> bool:
	return not _cheated


func reason() -> String:
	return _reason


# ---------------------------------------------------- Spielstand-Signatur

## Obfuskiertes Secret (nicht als Klartext im Skript). Absolute Sicherheit ist
## clientseitig unmöglich — das hier hält Gelegenheits-Editoren ab.
func _secret() -> PackedByteArray:
	var secret_seed := [0x09, 0x6A, 0x37, 0x37, 0x69, 0x28, 0x63, 0x6A, 0x7B, 0x1E, 0x09, 0x09, 0x38, 0x30]
	var b := PackedByteArray()
	for x in secret_seed:
		b.append(int(x) ^ 0x5A)
	return b


func _digest(msg: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var buf := msg.to_utf8_buffer()
	buf.append_array(_secret())
	ctx.update(buf)
	return ctx.finish().hex_encode()


## Signatur über den Spielstand (kanonisches JSON, sortierte Keys).
## WICHTIG: erst durch einen JSON-Roundtrip normalisieren. Beim Speichern läuft
## sign_state über das lebende Objekt (mit int-Keys, typisierten Zahlen), beim
## Laden über den bereits geparsten Baum (int-Keys sind dann String-Keys, andere
## Sortierung/Präzision). Ohne Normalisierung wäre die Signatur beider Seiten
## verschieden und ein sauberer Spielstand würde fälschlich als manipuliert gelten.
## Nach EINEM Roundtrip ist die Form ein Fixpunkt → beide Seiten stimmen überein.
func sign_state(state: Dictionary) -> String:
	var normalized: Variant = JSON.parse_string(JSON.stringify(state, "", true))
	return _digest(JSON.stringify(normalized, "", true))


func verify_state(state: Dictionary, sig: String) -> bool:
	return sign_state(state) == sig


# ---------------------------------------------------- Persistenz

func to_dict() -> Dictionary:
	return {"cheated": _cheated, "reason": _reason}


func from_dict(d: Dictionary) -> void:
	_cheated = bool(d.get("cheated", false))
	_reason = str(d.get("reason", ""))
	_flagged = _cheated
	_resync()


func reset() -> void:
	_cheated = false
	_flagged = false
	_reason = ""
	_since = 0.0
	_win_init = false
	_resync()
