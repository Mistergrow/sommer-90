class_name CodeRedTimeline
extends RefCounted
## Beschleunigte Kampagnenzeit: Jahrzehnte bleiben kompakt, waehrend die
## nicht mehr verbergbare Endphase bis zum August 2034 in Quartale und Monate
## zerfaellt. Ein Eintrag beschreibt den Zustand VOR den zwei Befehlen.

const PERIODS: Array[Dictionary] = [
	{"id": "1962", "year": 1962, "label": "1962", "scale": 1.0},
	{"id": "1965", "year": 1965, "label": "1965", "scale": 1.0},
	{"id": "1969", "year": 1969, "label": "1969", "scale": 1.0},
	{"id": "1973", "year": 1973, "label": "1973", "scale": 1.0},
	{"id": "1976", "year": 1976, "label": "1976", "scale": 1.0},
	{"id": "1978", "year": 1978, "label": "1978", "scale": 1.0},
	{"id": "1983", "year": 1983, "label": "1983", "scale": 1.0},
	{"id": "1988", "year": 1988, "label": "1988", "scale": 1.0},
	{"id": "1993", "year": 1993, "label": "1993", "scale": 1.0},
	{"id": "1998", "year": 1998, "label": "1998", "scale": 1.0},
	{"id": "2000", "year": 2000, "label": "2000", "scale": 1.0},
	{"id": "2003", "year": 2003, "label": "2003", "scale": 1.0},
	{"id": "2008", "year": 2008, "label": "2008", "scale": 1.0},
	{"id": "2013", "year": 2013, "label": "2013", "scale": 1.0},
	{"id": "2017", "year": 2017, "label": "2017", "scale": 1.0},
	{"id": "2020", "year": 2020, "label": "2020", "scale": 1.0},
	{"id": "2022", "year": 2022, "label": "2022", "scale": 1.0},
	{"id": "2025", "year": 2025, "label": "2025", "scale": 1.0},
	{"id": "2028", "year": 2028, "label": "2028", "scale": 1.0},
	{"id": "2030", "year": 2030, "label": "2030", "scale": 0.92},
	{"id": "2031", "year": 2031, "label": "2031", "scale": 0.88},
	{"id": "2032", "year": 2032, "label": "2032", "scale": 0.84},
	{"id": "2033-Q1", "year": 2033, "label": "2033 · Q1", "scale": 0.66},
	{"id": "2033-Q2", "year": 2033, "label": "2033 · Q2", "scale": 0.66},
	{"id": "2033-Q3", "year": 2033, "label": "2033 · Q3", "scale": 0.66},
	{"id": "2033-Q4", "year": 2033, "label": "2033 · Q4", "scale": 0.66},
	{"id": "2034-01", "year": 2034, "label": "JAN 2034", "scale": 0.46},
	{"id": "2034-02", "year": 2034, "label": "FEB 2034", "scale": 0.46},
	{"id": "2034-03", "year": 2034, "label": "MAER 2034", "scale": 0.46},
	{"id": "2034-04", "year": 2034, "label": "APR 2034", "scale": 0.46},
	{"id": "2034-05", "year": 2034, "label": "MAI 2034", "scale": 0.46},
	{"id": "2034-06", "year": 2034, "label": "JUN 2034", "scale": 0.46},
	{"id": "2034-07", "year": 2034, "label": "JUL 2034", "scale": 0.50},
	{"id": "2034-08", "year": 2034, "label": "AUG 2034", "scale": 0.50},
]

const YEARS: Array[int] = [1962, 1965, 1969, 1973, 1976, 1978, 1983, 1988,
	1993, 1998, 2000, 2003, 2008, 2013, 2017, 2020, 2022, 2025, 2028, 2030,
	2031, 2032, 2033, 2033, 2033, 2033, 2034, 2034, 2034, 2034, 2034, 2034,
	2034, 2034]
const TOTAL_ROUNDS := 33


static func at(turn: int) -> Dictionary:
	return PERIODS[clampi(turn, 0, PERIODS.size() - 1)]


static func id_at(turn: int) -> String:
	return str(at(turn).get("id", "1962"))


static func label_at(turn: int) -> String:
	return str(at(turn).get("label", "1962"))


static func year_at(turn: int) -> int:
	return int(at(turn).get("year", 1962))


static func scale_at(turn: int) -> float:
	return float(at(turn).get("scale", 1.0))
