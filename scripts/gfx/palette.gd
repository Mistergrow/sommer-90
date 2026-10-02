class_name Palette
## Zentrale 32-Farben-Palette.
## Spielwelt: DB32 (DawnBringer 32, public domain) — warm und 90er-tauglich.
## UI: Workbench-1.x-Farben (Blau/Weiß/Schwarz/Orange).

# --- Workbench-Akzentfarben (Dialog-Details, Logo) ---
const WB_BLUE := Color8(0, 85, 170)
const WB_WHITE := Color8(255, 255, 255)
const WB_BLACK := Color8(0, 0, 0)
const WB_ORANGE := Color8(255, 136, 0)
const WB_BLUE_DARK := Color8(0, 51, 119)

# --- Dunkle Bezel-UI (Layout lt. Referenz-Mockup: dunkle Panels, LCD-Werte) ---
const UI_BG := Color8(10, 10, 12)          # Rahmen um alles
const UI_PANEL := Color8(24, 24, 26)       # Panelfläche
const UI_PANEL_LIGHT := Color8(38, 38, 42) # Buttons / Slots
const UI_BORDER := Color8(110, 110, 116)   # helle Panelkante
const UI_BORDER_DARK := Color8(58, 58, 62) # dunkle Panelkante
const UI_TEXT := Color8(232, 232, 228)     # Standardtext
## Sekundaertext muss auf den fast schwarzen Panels auch mit der schmalen
## VT323-Schrift ruhig lesbar bleiben. Der alte Wert 150 sah bei 9--10 px wie
## deaktivierter Text aus. Deaktivierte Bedienelemente besitzen deshalb jetzt
## eine eigene, bewusst dunklere Farbe.
const UI_TEXT_DIM := Color8(184, 184, 178) # Sekundärtext
const UI_TEXT_DISABLED := Color8(118, 118, 116)
const LCD_GREEN := Color8(64, 255, 96)     # Geld
const LCD_CYAN := Color8(80, 200, 255)     # Ruf
const LCD_AMBER := Color8(255, 170, 40)    # Warnungen / Energie

# --- DB32-Spielweltpalette (Auswahl mit sprechenden Namen) ---
const BLACK := Color8(0, 0, 0)
const DARK_PURPLE := Color8(34, 32, 52)
const DARK_BLUE := Color8(63, 63, 116)
const STEEL := Color8(48, 96, 130)
const BROWN_DARK := Color8(69, 40, 60)
const BROWN := Color8(102, 57, 49)
const LEATHER := Color8(143, 86, 59)
const ORANGE := Color8(223, 113, 38)
const SAND := Color8(217, 160, 102)
const BEIGE := Color8(238, 195, 154)
const YELLOW := Color8(251, 242, 54)
const GREEN_DARK := Color8(75, 105, 47)
const GREEN := Color8(106, 190, 48)
const GREEN_LIGHT := Color8(153, 229, 80)
const TEAL_DARK := Color8(50, 60, 57)
const TEAL := Color8(75, 100, 105)
const CYAN := Color8(95, 205, 228)
const BLUE := Color8(99, 155, 255)
const BLUE_MID := Color8(91, 110, 225)
const INDIGO := Color8(48, 52, 109)
const GREY_DARK := Color8(89, 86, 82)
const GREY := Color8(105, 106, 106)
const GREY_MID := Color8(132, 126, 135)
const GREY_LIGHT := Color8(155, 173, 183)
const WHITE_SOFT := Color8(203, 219, 252)
const WHITE := Color8(255, 255, 255)
const RED_DARK := Color8(172, 50, 50)
const RED := Color8(217, 87, 99)
const PINK := Color8(215, 123, 186)
const VIOLET := Color8(118, 66, 138)


## Diskettenfarbe (Datenwert aus JSON) → Anzeige-Farbe.
static func disk_color(color_name: String) -> Color:
	match color_name:
		"blue": return BLUE_MID
		"black": return DARK_PURPLE
		"red": return RED_DARK
		"green": return GREEN_DARK
		"yellow": return SAND
		"purple", "violet": return VIOLET
		"white": return GREY_LIGHT
		"grey": return GREY
		_: return GREY_MID
