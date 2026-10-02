extends RefCounted
## Handgepixelte Rueckkopf-Silhouetten des 32x32-Avatars. Formen und Auswahl
## leben getrennt vom Gesichtsrenderer, damit Kleidung, Emotion und Alterung
## nicht erneut eine zweite Haardatenbank aufbauen.

const SHORT_BACK := [
	[3, 11, 21], [4, 9, 23], [5, 8, 24], [6, 7, 25],
	[7, 7, 25], [8, 7, 26], [9, 7, 26], [10, 7, 25],
	[11, 7, 24], [12, 7, 23], [13, 7, 22], [14, 7, 10],
	[15, 7, 10], [16, 8, 10], [17, 8, 10],
]

const BOB_BACK := [
	[3, 12, 21], [4, 9, 24], [5, 7, 25], [6, 6, 26],
	[7, 6, 27], [8, 5, 27], [9, 5, 27], [10, 5, 27],
	[11, 5, 27], [12, 5, 27], [13, 5, 27], [14, 5, 27],
	[15, 5, 27], [16, 5, 27], [17, 5, 27], [18, 6, 27],
	[19, 6, 27], [20, 7, 26], [21, 7, 26], [22, 8, 25],
	[23, 8, 25], [24, 9, 24],
]

const AFRO_BACK := [
	[1, 11, 20], [2, 7, 24], [3, 5, 26], [4, 4, 27],
	[5, 3, 28], [6, 3, 28], [7, 2, 28], [8, 3, 29],
	[9, 2, 29], [10, 2, 29], [11, 3, 29], [12, 2, 28],
	[13, 3, 29], [14, 3, 28], [15, 4, 28], [16, 4, 27],
	[17, 5, 27], [18, 5, 27], [19, 6, 26], [20, 6, 25],
	[21, 7, 25], [22, 8, 24], [23, 9, 23],
]

const LONG_BACK := [
	[3, 11, 21], [4, 8, 24], [5, 7, 25], [6, 6, 26],
	[7, 6, 26], [8, 6, 27], [9, 6, 27], [10, 6, 27],
	[11, 6, 27], [12, 6, 27], [13, 6, 27], [14, 6, 27],
	[15, 6, 27], [16, 6, 27], [17, 6, 27], [18, 6, 27],
	[19, 6, 27], [20, 6, 27], [21, 6, 27], [22, 6, 27],
	[23, 6, 27], [24, 7, 26], [25, 7, 26], [26, 8, 25],
	[27, 8, 25], [28, 9, 24],
]

## Huete wie Stirnband, Bandana, Visor oder Kopfhoerer verdecken die Frisur
## nicht vollstaendig. Alle anderen Huttypen beanspruchen dagegen den oberen
## Silhouettenraum. Diese Entscheidung muss fuer Portraet und Ganzfigur exakt
## gleich sein, sonst wechselt dieselbe DNA beim Umschalten die Frisur.
const NON_COVERING_HATS := ["", "none", "headband", "bandana", "visor", "headphones"]
const COVERED_FRONT_COLLAPSE := ["spiky", "messy", "quiff", "mohawk", "afro", "curly", "flattop"]
const COVERED_BACK_COLLAPSE := ["mohawk", "afro", "curly", "bun"]


static func has_back(style: String) -> bool:
	return style in ["short", "parted", "messy", "curly", "straight", "medium",
		"long", "ponytail", "mullet", "bob", "afro", "bun", "pigtails",
		"spiky", "quiff", "flattop"]


static func is_covering_hat(hat: String) -> bool:
	return hat not in NON_COVERING_HATS


## Deckende Huete komprimieren nur das obere Volumen. Lange Haare, Bob,
## Pferdeschwanz und Zoepfe bleiben seitlich beziehungsweise hinten sichtbar.
static func style_for_front(style: String, hat: String) -> String:
	if is_covering_hat(hat) and style in COVERED_FRONT_COLLAPSE:
		return "short"
	return style


static func style_for_back(style: String, hat: String) -> String:
	if is_covering_hat(hat) and style in COVERED_BACK_COLLAPSE:
		return "short"
	return style
