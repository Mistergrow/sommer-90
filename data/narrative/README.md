# Narrative-Core — modularer Zeilen-Pool

Der Story-/Kontinuitäts-Kern liegt **modular** (statt einer 114-KB-Monolithdatei):

```
data/narrative/
├── facts.json            # Welt-Fakten: WANN etwas wahr wird (from-Jahr / Weltflag)
├── lines/
│   ├── npc_mike.json     # ein Zeilen-Pool pro NPC
│   ├── npc_stefan.json
│   └── … (21 Dateien)
└── README.md
```

## Eine Zeile
```json
{ "id": "mi_wz01", "text": "…",
  "from": 1998, "to": 1999,          // optionales Jahr-Fenster
  "needs": ["daniel_apfel"],          // Fakten, die wahr sein müssen
  "forbids": ["sven_weg"],            // Fakten, die NICHT wahr sein dürfen
  "trust_min": 10, "once": true,      // optional
  "weight": 4,                        // Auswahl-Gewicht (Default 1)
  "dialogue": "mike_orakel",          // öffnet einen Dialogbaum statt Bark
  "topic": "witz" }
```

## Regeln
- **id eindeutig je NPC.** Neue Zeilen einfach ins passende `lines/<npc>.json` einreihen.
- **Keine Fakten erfinden** — nur `facts.json`-Einträge in `needs`/`forbids` referenzieren.
- **Jedes Jahr braucht ≥1 gültige Zeile** (sonst „stummes Jahr"-Warnung); ära-neutrale
  Basiszeilen (ohne `from/to/needs`) sichern die Abdeckung, Ära-Zeilen geben Würze.

## Prüfen (Pflicht nach jeder Änderung)
```
godot --headless --path . -s res://tests/narrative_check.gd
```
Der Linter liest dieselbe modulare Struktur und meldet **hart**: unbekannte Fakten,
Anachronismen (needs-Fakt erst nach dem Fenster wahr), needs∩forbids, from>to, tote
once-Zeilen, doppelte ids. **Weich**: stumme Jahre.

Loader: [`scripts/autoload/narrative_manager.gd`](../../scripts/autoload/narrative_manager.gd)
(`_load()` liest `facts.json` + globt `lines/*.json`).
