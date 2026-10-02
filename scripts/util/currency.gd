class_name Currency
extends RefCounted
## Währungs-Helfer: DM mit Pfennig. Geld wird intern als float-DM geführt, aber bei
## jeder Änderung auf 0,01 gerundet (PlayerStats.snappedf) — so gibt es keinen
## Float-Drift und trotzdem echte Pfennig (20,44 DM, 14,50 DM, 1,20 DM).
##
## `format` erzeugt die deutsche Schreibweise „X,XX DM"; `to_pf`/`from_pf` rechnen
## in ganze Pfennig (für exakte Vergleiche, z.B. den Anti-Cheat-Schatten).

const PF_PER_DM := 100


## „20,44 DM" — immer mit zwei Nachkommastellen und deutschem Komma.
static func format(dm: float) -> String:
	var pf := to_pf(dm)
	var neg := "-" if pf < 0 else ""
	pf = absi(pf)
	@warning_ignore("integer_division")  # DM-Teil per Ganzzahl-Division ist gewollt (exakt)
	return "%s%d,%02d DM" % [neg, pf / PF_PER_DM, pf % PF_PER_DM]


## Kurzform ohne Einheit („20,44") — für enge HUD-Felder.
static func amount(dm: float) -> String:
	var pf := to_pf(dm)
	var neg := "-" if pf < 0 else ""
	pf = absi(pf)
	@warning_ignore("integer_division")  # DM-Teil per Ganzzahl-Division ist gewollt (exakt)
	return "%s%d,%02d" % [neg, pf / PF_PER_DM, pf % PF_PER_DM]


## DM (float) → ganze Pfennig (int), kaufmännisch gerundet.
static func to_pf(dm: float) -> int:
	return int(round(dm * PF_PER_DM))


## Ganze Pfennig → DM (float), auf 0,01 gerundet.
static func from_pf(pf: int) -> float:
	return snappedf(float(pf) / PF_PER_DM, 0.01)


## Betrag sauber auf Pfennig runden (kein Float-Drift durch Multiplikation/Zins).
static func snap(dm: float) -> float:
	return snappedf(dm, 0.01)
