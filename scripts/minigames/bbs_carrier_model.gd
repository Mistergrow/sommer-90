class_name BbsCarrierModel
extends RefCounted
## Deterministische analoge Leitung. Zeit, Regler und Retry sind die einzigen
## Eingaben; der echte Download bleibt ausserhalb dieses Modells.

var level := 1
var run_seed := 1
var duration := 14.0
var elapsed := 0.0
var integrity := 1.0
var stable_time := 0.0
var retries := 2
var retry_guard := 0.0
var gain := 0.48
var filter := 0.38
var assisted := false
var hints := 0
var protocol:=&"v21"
var phase:=&"dial"


func configure(next_level: int, next_seed: int) -> void:
	level = clampi(next_level, 1, 5)
	run_seed = next_seed
	protocol=[&"v21",&"v22",&"v22bis",&"noisy_longline"][posmod(run_seed+level,4)];phase=&"handshake"
	duration = 12.0 + level * 2.0
	elapsed = 0.0
	integrity = 1.0
	stable_time = 0.0
	retries = maxi(1, 3 - floori(level / 2.0))
	retry_guard = 0.0
	gain = 0.48
	filter = 0.38
	assisted = false
	hints = 0


func line_sample(at_time := -1.0) -> Dictionary:
	var t := elapsed if at_time < 0.0 else at_time
	var noise_phase := float(abs(run_seed % 997)) * 0.013
	var attenuation := 0.20 + level * 0.018 + sin(t * (0.43 + level * 0.025) + noise_phase) * 0.075
	var hiss := 0.15 + level * 0.022 + (sin(t * 2.17 + noise_phase * 1.7) + 1.0) * 0.035
	var burst := maxf(0.0, sin(t * (1.37 + level * 0.07) + noise_phase * 3.1) - (0.80 - level * 0.025)) * 0.72
	var signal_level := 0.54 + gain * 0.56 - attenuation - filter * 0.12
	var noise := hiss + gain * 0.34 + burst - filter * 0.48
	var margin := signal_level - noise
	var safe := margin >= 0.28 and margin <= 0.62
	return {"signal": clampf(signal_level, 0.0, 1.0), "noise": clampf(noise, 0.0, 1.0),
		"margin": margin, "safe": safe, "burst": burst}


func step(delta: float, next_gain: float, next_filter: float) -> Dictionary:
	if finished(): return line_sample()
	gain = clampf(next_gain, 0.0, 1.0)
	filter = clampf(next_filter, 0.0, 1.0)
	var dt := minf(maxf(delta, 0.0), 1.0 / 20.0)
	elapsed = minf(duration, elapsed + dt)
	retry_guard = maxf(0.0, retry_guard - dt)
	if elapsed<1.2:phase=&"handshake"
	elif phase==&"retrain" and retry_guard>0.0:phase=&"retrain"
	else:phase=&"carrier"
	var sample := line_sample()
	if bool(sample.safe) or retry_guard > 0.0:
		stable_time += dt
		integrity = minf(1.0, integrity + dt * 0.035)
	else:
		var miss := absf(float(sample.margin) - clampf(float(sample.margin), 0.28, 0.62))
		integrity = maxf(0.0, integrity - dt * (0.20 + miss * (0.9 + level * 0.12)))
	return sample


func retry() -> bool:
	if retries <= 0 or finished(): return false
	retries -= 1
	retry_guard = 0.85
	phase=&"retrain"
	integrity = minf(1.0, integrity + 0.12)
	return true


func hint() -> Dictionary:
	hints += 1
	var s := line_sample()
	return {"gain_delta": -0.08 if float(s.margin) < 0.28 else (0.06 if float(s.margin) > 0.62 else 0.0),
		"filter_delta": 0.10 if float(s.noise) > 0.42 else -0.04}


func auto_stabilize() -> void:
	assisted = true
	# Feedback-Regler fuer Tests/Accessibility; laeuft weiterhin durch die Zeit.
	var s := line_sample()
	if float(s.margin) < 0.28: gain = clampf(gain + 0.08, 0.0, 1.0)
	elif float(s.margin) > 0.62: gain = clampf(gain - 0.08, 0.0, 1.0)
	filter = clampf(filter + (0.06 if float(s.noise) > 0.36 else -0.02), 0.0, 1.0)


func finished() -> bool:
	var done:=elapsed>=duration or integrity<=0.0
	if done:phase=&"complete"if integrity>0.0 else&"no_carrier"
	return done


func success() -> bool:
	return elapsed >= duration and integrity >= (0.42 + level * 0.025)


func score() -> int:
	if not success(): return 0
	var stability := stable_time / duration
	return maxi(250, roundi(700 + level * 120 + integrity * 420 + stability * 260
		- hints * 90 - (400 if assisted else 0)))


func details() -> Dictionary:
	return {"level": level, "integrity": integrity, "stable_ratio": stable_time / duration,
		"retries_left": retries, "hints": hints, "assisted": assisted,"protocol":str(protocol),"phase":str(phase)}
