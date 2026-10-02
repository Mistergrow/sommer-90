class_name CodeRedEvents
extends RefCounted
## Erweiterbarer Katalog der allgemeinen Krisenereignisse. Historische
## Oeffentlichkeitssignale liegen datengetrieben in code_red_simulation.json.

const ALL: Array[Dictionary] = [
	{"id": "red_dust", "title": "ROTER STAUB", "text": "Roter Niederschlag wird in drei Staaten gemeldet.", "choices": [
		{"title": "SAHARASTAUB MELDEN", "effects": {"media": 4.0, "truth": -3.0, "panic": 1.0}},
		{"title": "PROBEN BESCHLAGNAHMEN", "effects": {"science": 5.0, "truth": -5.0, "stability": -3.0}}]},
	{"id": "astronomer", "title": "DAS TELESKOP", "text": "Eine Observatorin besitzt eine klare Bildserie des Objekts.", "choices": [
		{"title": "FORSCHUNGSVERTRAG", "budget": -9.0, "effects": {"science": 7.0, "truth": -4.0}},
		{"title": "DISKREDITIEREN", "effects": {"media": 5.0, "truth": -6.0, "stability": -2.0}}]},
	{"id": "inner_tone", "title": "DER TIEFE TON", "text": "Tausende melden denselben niederfrequenten Ton in der Nacht.", "choices": [
		{"title": "INDUSTRIELAERM", "effects": {"media": 4.0, "truth": -2.0, "panic": 2.0}},
		{"title": "GESUNDHEITSSTUDIE", "budget": -6.0, "effects": {"science": 5.0, "panic": -3.0}}]},
	{"id": "satellite", "title": "ROHDATEN IM NETZ", "text": "Ein fremder Satellitenframe zirkuliert in Mailboxen.", "choices": [
		{"title": "FAELSCHUNG BEHAUPTEN", "effects": {"media": 5.0, "truth": -3.0}},
		{"title": "NETZE ABSCHALTEN", "effects": {"truth": -6.0, "stability": -5.0, "panic": 2.0}}]},
	{"id": "summit_leak", "title": "GIPFELPROTOKOLL", "text": "Eine Seite des geheimen Protokolls fehlt im Archiv.", "choices": [
		{"title": "INTERNE SUCHE", "budget": -5.0, "effects": {"coalition": -3.0, "truth": -4.0}},
		{"title": "NEUES DOKUMENT STREUEN", "effects": {"media": 6.0, "truth": -2.0, "science": -2.0}}]},
	{"id": "eclipse", "title": "FALSCHE FINSTERNIS", "text": "Das Objekt verdunkelt die Sonne ausserhalb jeder Vorhersage.", "choices": [
		{"title": "SONNENANOMALIE", "effects": {"science": 4.0, "truth": -2.0, "panic": 3.0}},
		{"title": "TV-BILDER ERSETZEN", "budget": -8.0, "effects": {"media": 8.0, "truth": -5.0}}]},
	{"id": "harvest", "title": "ERNTEAUSFAELLE", "text": "Partikelschleier und Hitze treffen dieselben Ernten.", "choices": [
		{"title": "HILFSLIEFERUNGEN", "budget": -12.0, "effects": {"stability": 7.0, "panic": -3.0}},
		{"title": "STATISTIK AENDERN", "effects": {"media": 4.0, "truth": -2.0, "burden": 5.0}}]},
	{"id": "bunker_list", "title": "DIE LISTE", "text": "Namen aus dem Evakuierungsprogramm werden veroeffentlicht.", "choices": [
		{"title": "LISTE BESTAETIGEN", "effects": {"elite_escape": 6.0, "truth": 7.0, "panic": 4.0}},
		{"title": "MILITAERUEBUNG", "budget": -7.0, "effects": {"truth": -4.0, "stability": -2.0}}]},
	{"id": "red_sky", "title": "DER ROTE HIMMEL", "text": "Das Objekt ist bei Sonnenuntergang mit blossem Auge sichtbar.", "choices": [
		{"title": "RAUCH UND POLLEN", "effects": {"media": 5.0, "truth": 2.0, "panic": 3.0}},
		{"title": "AUSGANGSSPERRE", "effects": {"truth": -2.0, "stability": -8.0, "panic": 5.0}}]},
	{"id": "final_window", "title": "LETZTES FENSTER", "text": "Die Startkorridore sind bereit. Die Welt schaut nach oben.", "choices": [
		{"title": "EVAKUIERUNG STARTEN", "effects": {"elite_escape": 12.0, "truth": 6.0, "coalition": 4.0}},
		{"title": "OPERATION HALTEN", "effects": {"truth": -4.0, "media": 6.0, "panic": 4.0}}]},
]
