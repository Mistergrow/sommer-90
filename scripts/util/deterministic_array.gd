extends RefCounted
## Gemeinsamer deterministischer Fisher-Yates-Schritt fuer spielinterne Modelle.


static func shuffle(values, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = values[i]
		values[i] = values[j]
		values[j] = swap
