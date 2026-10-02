extends RefCounted
## Shared time-of-day color direction. Preserve neutral materials and shadow detail.

const PRESETS := {
	"outdoor": {
		0: Color(0.82, 0.90, 1.00), 1: Color(1.00, 1.00, 0.98),
		2: Color(1.00, 0.97, 0.93), 3: Color(1.00, 0.88, 0.74), 4: Color(0.45, 0.53, 0.70),
	},
	"indoor_warm": {
		0: Color(0.90, 0.93, 0.98), 1: Color(1.00, 1.00, 0.98),
		2: Color(1.00, 0.98, 0.95), 3: Color(0.98, 0.92, 0.84), 4: Color(0.69, 0.71, 0.82),
	},
	"indoor_cool": {
		0: Color(0.88, 0.93, 1.00), 1: Color(0.98, 1.00, 1.00),
		2: Color(0.96, 0.98, 1.00), 3: Color(0.90, 0.90, 0.96), 4: Color(0.62, 0.66, 0.82),
	},
	"overcast": {
		0: Color(0.86, 0.90, 0.96), 1: Color(0.94, 0.96, 0.99),
		2: Color(0.92, 0.94, 0.98), 3: Color(0.82, 0.85, 0.92), 4: Color(0.52, 0.58, 0.74),
	},
}
