class_name CodeRedActions
extends RefCounted
## Datengetriebener Befehlskatalog der CODE-RED-Simulation. Der Modellkern
## wertet Kosten, Sperren, Risiken und Effekte aus; hier stehen nur Inhalte.

const ACTIONS: Dictionary = {
	"coalition": {
		"title": "KOALITION STAERKEN", "section": "summit", "budget": -8.0,
		"effects": {"coalition": 11.0, "stability": 3.0, "truth": -1.0},
		"detail": "Gemeinsame Linie, gemeinsame Aktenlage.",
	},
	"pledges": {
		"title": "ZUSAGEN VERTEILEN", "section": "summit", "budget": -14.0, "cooldown": 2,
		"effects": {"coalition": 16.0, "truth": -2.0, "burden": 1.0},
		"detail": "Finanzielle Garantien halten Partner am Tisch.",
	},
	"silence": {
		"title": "SCHWEIGEGELDER", "section": "summit", "budget": -10.0,
		"effects": {"science": 8.0, "truth": -5.0, "stability": -2.0}, "risk": "leak",
		"detail": "Wirksam, teuer und nie vollstaendig kontrollierbar.",
	},
	"joint_media": {
		"title": "MEDIENSTRATEGIE", "section": "summit", "budget": -6.0,
		"effects": {"media": 10.0, "coalition": 4.0, "truth": -2.0},
		"detail": "Alle Hauptstaedte verwenden dieselbe Erklaerung.",
	},
	"military": {
		"title": "MILITAERABSPRACHEN", "section": "summit", "budget": -12.0, "cooldown": 2,
		"effects": {"stability": 10.0, "panic": -3.0, "coalition": 3.0},
		"detail": "Versorgung, Luftraum und Bunker werden koordiniert.",
	},
	"particle_density": {
		"title": "PARTIKEL-DICHTE +", "section": "geo", "budget": -12.0,
		"effects": {"particles": 14.0, "induction": -3.0, "truth": 1.0, "burden": 2.0},
		"detail": "Mehr Reflexion, aber mehr sichtbare Spuren.",
	},
	"fleet_routes": {
		"title": "FLOTTEN-ROUTEN", "section": "geo", "budget": -8.0,
		"effects": {"routes": 12.0, "particles": 3.0, "truth": 0.5},
		"detail": "Neue Korridore verbessern die globale Abdeckung.",
	},
	"dust_cover": {
		"title": "ERKLAERUNG: SAHARASTAUB", "section": "geo", "budget": -4.0,
		"effects": {"media": 5.0, "truth": -2.0}, "set_explanation": "SAHARASTAUB",
		"detail": "Regional glaubwuerdig, bei Wiederholung auffaellig.",
	},
	"volcano_cover": {
		"title": "ERKLAERUNG: VULKAN", "section": "geo", "budget": -5.0,
		"effects": {"science": 4.0, "truth": -3.0, "panic": 1.0}, "set_explanation": "VULKANAUSBRUCH",
		"detail": "Messdaten lassen sich besser erklaeren, Angst steigt leicht.",
	},
	"climate_story": {
		"title": "KLIMA-NARRATIV", "section": "media", "budget": -5.0,
		"effects": {"media": 10.0, "truth": -4.0, "burden": 2.0},
		"detail": "Eine einheitliche Ursache bindet die Berichterstattung.",
	},
	"sky_natural": {
		"title": "HIMMELSPHAENOMEN", "section": "media", "budget": -4.0,
		"effects": {"media": 6.0, "truth": -3.0, "science": 2.0},
		"detail": "Anomalien werden als seltene Naturereignisse eingeordnet.",
	},
	"sports": {
		"title": "SPORT-GROSSEREIGNIS", "section": "media", "budget": -6.0, "cooldown": 2,
		"effects": {"panic": -8.0, "media": 3.0, "stability": 2.0},
		"detail": "Aufmerksamkeit wird fuer ein Quartal umgelenkt.",
	},
	"manufactured_crisis": {
		"title": "NEBENKRISE SETZEN", "section": "media", "budget": -3.0, "cooldown": 2,
		"effects": {"panic": -6.0, "media": 5.0, "stability": -4.0, "truth": 1.0},
		"detail": "Kurzfristig wirksam, langfristig destabilisierend.",
	},
	"fund_astronomy": {
		"title": "ASTRONOMIE FOERDERN", "section": "science", "budget": -8.0,
		"effects": {"science": 9.0, "truth": -2.0, "coalition": 2.0},
		"detail": "Zugang zu Mitteln wird an zentrale Datenwege gebunden.",
	},
	"suppress_astronomy": {
		"title": "BEOBACHTER STILLLEGEN", "section": "science", "budget": -5.0,
		"effects": {"science": 6.0, "truth": -5.0, "stability": -3.0}, "risk": "backlash",
		"detail": "Schnell, aber bei Entdeckung politisch verheerend.",
	},
	"alter_satellite": {
		"title": "SATELLITENDATEN AENDERN", "section": "science", "budget": -9.0,
		"effects": {"science": 10.0, "truth": -6.0, "media": 2.0},
		"detail": "Rohdaten und oeffentliche Produkte werden getrennt.",
	},
	"agency_report": {
		"title": "AGENTURBERICHT", "section": "science", "budget": -7.0,
		"effects": {"science": 5.0, "media": 5.0, "truth": -5.0},
		"detail": "Ein offizieller Bericht beendet einen Nachrichtenzyklus.",
	},
	"carbon_tax": {
		"title": "CO2-ABGABE", "section": "economy", "budget": 24.0, "cooldown": 2,
		"effects": {"burden": 12.0, "stability": -5.0, "coalition": 2.0, "panic": 1.0},
		"detail": "Die Operation finanziert sich, die Belastung steigt.",
	},
	"green_deal": {
		"title": "GRUENER PAKT", "section": "economy", "budget": -6.0,
		"effects": {"burden": 4.0, "stability": 5.0, "coalition": 4.0, "media": 2.0},
		"detail": "Subventionen stabilisieren Zustimmung und Koalition.",
	},
	"bunker": {
		"title": "BUNKERPROGRAMM", "section": "economy", "budget": -15.0,
		"effects": {"elite_escape": 12.0, "burden": 4.0, "truth": 2.0},
		"detail": "Evakuierungsplaetze werden vorbereitet.",
	},
	"relief": {
		"title": "ENTLASTUNGSPAKET", "section": "economy", "budget": -10.0,
		"effects": {"burden": -10.0, "stability": 8.0, "panic": -3.0},
		"detail": "Teuer, aber gesellschaftlich stabilisierend.",
	},
	"monitor_channels": {
		"title": "KANAELE BEOBACHTEN", "section": "moderation", "budget": -2.0,
		"effects": {"science": 3.0, "truth": -1.0, "credibility": 1.0},
		"detail": "Reichweiten und Quellen werden kartiert, ohne sichtbar einzugreifen.",
	},
	"open_rebuttal": {
		"title": "OFFEN WIDERLEGEN", "section": "moderation", "budget": -5.0,
		"effects": {"media": 5.0, "truth": -3.0, "credibility": 5.0},
		"detail": "Messdaten und Optik-Faelle werden oeffentlich erklaert.",
	},
	"shadow_limit": {
		"title": "REICHWEITE DROSSELN", "section": "moderation", "budget": -4.0,
		"effects": {"truth": -5.0, "credibility": -2.0, "stability": -1.0}, "risk": "streisand",
		"detail": "Unsichtbare Verteilungsgrenzen wirken leise, bis Muster auffallen.",
	},
	"platform_ban": {
		"title": "PLATTFORM-SPERRE", "section": "moderation", "budget": -3.0,
		"effects": {"truth": -7.0, "credibility": -6.0, "stability": -3.0, "panic": 1.0},
		"risk": "streisand", "cooldown": 2,
		"detail": "Ein Kanal verschwindet. Spiegel und Berichte ueber die Sperre bleiben.",
	},
	"network_seizure": {
		"title": "NETZE BESCHLAGNAHMEN", "section": "moderation", "budget": -8.0,
		"effects": {"truth": -10.0, "credibility": -10.0, "stability": -7.0, "coalition": -4.0},
		"risk": "backlash", "cooldown": 3,
		"detail": "Kurzfristig maximal wirksam, politisch und gesellschaftlich hochriskant.",
	},
}
