extends RefCounted
## Benutzertexte fuer die physische Diskdiagnose.

static func summary(diagnosis: Dictionary, result: Dictionary, service_action: String) -> String:
	if diagnosis.is_empty():
		return str(result.get("text", "Prueflauf beendet."))
	var condition := int(diagnosis.get("condition", 0))
	if service_action.is_empty() and condition <= 0:
		return "DIAGNOSE: READ ERROR · MEDIUM 0%% · NICHT REPARIERBAR · ORIGINAL ERSETZEN"
	if service_action == "rescue":
		return "DIAGNOSE: READ ERROR · TRACK/CRC FEHLER · MEDIUM UNLESBAR · NAECHSTER SCHRITT: DATEN RETTEN"
	if service_action == "repair":
		var track_state := "TRACK/CRC OK" if bool(diagnosis.get("tracks_ok", false)) else "CRC-FEHLER"
		return "DIAGNOSE: %s · MEDIUM %d%% · VIREN NICHT GEPRUEFT · NAECHSTER SCHRITT: PHYSISCH REPARIEREN" % [track_state, condition]
	return "DIAGNOSE: TRACK/CRC OK · MEDIUM STABIL %d%% · VIRUSSTATUS NICHT GEPRUEFT" % condition

