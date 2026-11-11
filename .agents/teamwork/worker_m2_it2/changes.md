# Changes Applied — Worker 3 (Milestone 2 Iteration 2)

## Target File
`res://scenes/vfx/explosion_crysis.gd`

## Modified Sections
Lines 170–178:
```gdscript
	(
		_active_tween
		. tween_method(_update_shockwave_progress, 0.0, 1.0, SHOCKWAVE_DURATION)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)

	_active_tween.tween_callback(_on_shockwave_complete).set_delay(SHOCKWAVE_DURATION)
```

## Rationale
1. **Chained Callback Unblocking**:
   Previously, `_active_tween.chain().tween_callback(_on_shockwave_complete)` was chained to a parallel tween group containing a 1.1s fireball delay (`_active_tween.tween_callback(_on_fireball_complete).set_delay(FIREBALL_DURATION)`). In Godot 4, `.chain()` pauses subsequent callbacks until every parallel tween in the preceding group completes. Consequently, `_on_shockwave_complete` was blocked until 1.1s rather than running at `SHOCKWAVE_DURATION` (0.4s). This kept the volumetric shockwave mesh visible and rendering for an extra 42 frames. Replacing with `_active_tween.tween_callback(_on_shockwave_complete).set_delay(SHOCKWAVE_DURATION)` schedules the callback in parallel at exactly 0.4s.
2. **Sine Easing Curve**:
   Previously, quadratic ease-out (`Tween.TRANS_QUAD`, `Tween.EASE_OUT`) advanced progress to ~0.75 at half-duration ($t = 0.20s$). Transitioning to sinusoidal ease-in-out (`Tween.TRANS_SINE`, `Tween.EASE_IN_OUT`) centers progression around 0.50 at $t = 0.20s$ ($0.499685$ measured), cleanly satisfying dynamics validation.
