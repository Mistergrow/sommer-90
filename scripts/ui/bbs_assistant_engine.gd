extends RefCounted
## Regelbasierter BBS-Helfer. Er ist absichtlich kein moderner Cloud-Dienst:
## In der Spielwelt antwortet der lokale SysOp bzw. ab 1999 ein kleines
## »AMI-BOT«-Expertensystem. Dadurch bleibt der komplette Spielstand offline,
## deterministisch und ohne API-Schluessel spielbar.


static func answer(prompt: String, context: Dictionary) -> String:
	var query := prompt.strip_edges().to_lower()
	var sysop := str(context.get("sysop", "SYSOP"))
	var board := str(context.get("board", "Mailbox"))
	var year := int(context.get("year", 1990))
	var blanks := int(context.get("blank_disks", 0))
	var baud := int(context.get("baud", 0))
	var bill := int(context.get("phone_bill", 0))

	if query.is_empty():
		return Loc.t("ui.bbs_assistant_engine.empty_prompt",
			"Schreib eine kurze Frage. Beispiele: AUFTRAG, DOWNLOAD, KOSTEN oder VIRUS.")
	if _mentions(query, ["auftrag", "mission", "was soll", "weiter", "objective", "what next"]):
		var mission := str(context.get("mission_hint", ""))
		return mission if not mission.is_empty() else (
			Loc.t("ui.bbs_assistant_engine.no_mission",
				"Im Moment ist hier kein Pflichtauftrag offen. NEWS und NACHRICHTEN erklären, was auf %s neu ist.") % board)
	if _mentions(query, ["download", "datei", "programm", "wie lade", "file", "program", "how do i download"]):
		if blanks <= 0:
			return Loc.t("ui.bbs_assistant_engine.blank_disk_required",
				"Für Dateien fehlt eine Leerdiskette. Erst eine DD-Disk in der Diskettenbox bereitlegen. Programme aus dem Archiv werden dagegen direkt auf der Werkbank installiert.")
		return Loc.t("ui.bbs_assistant_engine.download_steps",
			"DATEIEN öffnen, Eintrag wählen und den Carrier stabilisieren. Du hast %d Leerdiskette(n); Daten belegen eine davon, installierbare Programme landen auf der Werkbank.") % blanks
	if _mentions(query, ["upload", "release", "demo", "eigene", "own releases"]):
		return Loc.t("ui.bbs_assistant_engine.upload_rules",
			"EIGENE RELEASES zeigt nur verifizierte Master mit gesehenem Intro. Der Upload spiegelt die Serie; deine physische Masterdisk bleibt in der Box.")
	if _mentions(query, ["virus", "nicht lesbar", "x-copy", "xcopy", "pruefen", "prüfen", "fehler", "unreadable", "check", "error"]):
		return Loc.t("ui.bbs_assistant_engine.virus_explanation",
			"X-COPY prüft Tracks und Kopierfehler; der VIRUS-CHECKER untersucht den Bootblock. Eine Disk kann deshalb in X-COPY fehlerfrei und trotzdem infiziert sein. Nicht lesbare Medien zuerst physisch stabilisieren, dann erneut prüfen.")
	if _mentions(query, ["hdd", "festplatte", "hard disk", "dh0", "workbench", "boot"]):
		if bool(context.get("has_hdd", false)):
			return Loc.t("ui.bbs_assistant_engine.hdd_ready",
				"Deine Festplatte ist vorhanden. Nach Partitionierung und einer vollständigen Workbench-Installation wird DH0: bootfähig; danach ohne Systemdisk starten.")
		return Loc.t("ui.bbs_assistant_engine.hdd_setup",
			"Eine Festplatte allein reicht nicht: passendes Laufwerk einbauen, partitionieren, formatieren und Workbench installieren. Erst dann ist DH0: bootfähig.")
	if _mentions(query, ["kost", "rechnung", "telefon", "geld", "gebuehr", "gebühr", "preis", "cost", "bill", "phone", "money", "fee", "price"]):
		return Loc.t("ui.bbs_assistant_engine.cost_explanation",
			"Die Sitzung läuft mit %d Baud. Einwahl und Transfer landen auf der Telefonrechnung; aktuell sind %d DM fällig. Schnellere Verbindungen senken vor allem die Transferdauer.") % [baud, bill]
	if _mentions(query, ["modem", "baud", "schnell", "carrier", "fast"]):
		return Loc.t("ui.bbs_assistant_engine.carrier_speed",
			"%s meldet aktuell CONNECT %d. Es gilt immer das langsamere Ende aus deinem Modem und dem Board-Modem.") % [board, baud]
	if _mentions(query, ["hilfe", "befehle", "menue", "menü", "bereich", "help", "commands", "menu", "area"]):
		return Loc.t("ui.bbs_assistant_engine.area_help",
			"NEWS zeigt die Begrüßung, DATEIEN sind Downloads, NACHRICHTEN enthalten Threads, EIGENE RELEASES nimmt deine Demos an, KLEINANZEIGEN ist der Tauschmarkt. AUFLEGEN beendet die Gebühren.")
	return Loc.t("ui.bbs_assistant_engine.unknown_topic",
		"%s hier. Zu »%s« habe ich keinen sicheren Eintrag. Frag kürzer nach AUFTRAG, DOWNLOAD, UPLOAD, VIRUS, HDD oder KOSTEN.") % [
		sysop if year < 1999 else "AMI-BOT/" + sysop, _compact(prompt, 34)]


static func _mentions(text: String, needles: Array[String]) -> bool:
	for needle in needles:
		if needle in text:
			return true
	return false


static func _compact(text: String, limit: int) -> String:
	var clean := text.strip_edges().replace("\n", " ").replace("\r", " ")
	return clean if clean.length() <= limit else clean.left(limit - 3) + "..."
