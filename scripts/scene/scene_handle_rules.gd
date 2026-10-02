extends RefCounted
## Eine Zeichen- und Laengenwahrheit fuer Szene-Handles.

const ALLOWED := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
static var _validator: RegEx


static func normalize(value: String) -> String:
	return value.strip_edges().to_upper()


## Eingabeeditor: ungueltige Zeichen entfernen, statt den ganzen Entwurf zu
## verwerfen. Die finale Gueltigkeit prueft weiterhin valid().
static func sanitize(value: String) -> String:
	var out := ""
	for character in value.to_upper():
		if character in ALLOWED:
			out += character
		if out.length() >= 16:
			break
	return out


static func valid(value: String) -> bool:
	var candidate := normalize(value)
	if candidate.length() < 3 or candidate.length() > 16:
		return false
	if _validator == null:
		_validator = RegEx.new()
		_validator.compile("^[A-Z0-9][A-Z0-9_-]{2,15}$")
	return _validator.search(candidate) != null
