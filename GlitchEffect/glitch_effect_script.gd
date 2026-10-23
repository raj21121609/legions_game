extends CanvasLayer

## GlitchVerse – Subtle Screen Glitch Effect
## =========================================
## A self-contained, modular glitch overlay.
## Lives on its own CanvasLayer (layer 10) so it sits above all 3D content.
## Only activates briefly; zero CPU/GPU cost between bursts.
##
## Exported variables let you tune everything from the Inspector without
## touching code.

class_name GlitchEffect

# ── Tunable exports ──────────────────────────────────────────────────────────

@export_group("Timing")
## Minimum seconds between glitch bursts.
@export_range(5.0, 60.0, 0.5) var interval_min: float = 20.0
## Maximum seconds between glitch bursts.
@export_range(5.0, 120.0, 0.5) var interval_max: float = 40.0
## Minimum duration of each glitch burst (seconds).
@export_range(0.05, 1.0, 0.01) var duration_min: float = 0.10
## Maximum duration of each glitch burst (seconds).
@export_range(0.05, 1.0, 0.01) var duration_max: float = 0.25

@export_group("Intensity")
## Peak intensity of the glitch (0 = invisible, 1 = maximum).
@export_range(0.0, 1.0, 0.05) var peak_intensity: float = 0.55
## Horizontal band displacement strength.
@export_range(0.0, 1.0, 0.05) var displacement_strength: float = 0.40
## RGB channel separation strength.
@export_range(0.0, 1.0, 0.05) var rgb_split_strength: float = 0.35
## Sparse digital pixel noise density.
@export_range(0.0, 1.0, 0.05) var noise_density: float = 0.15

@export_group("Control")
## Set false at runtime to completely suppress future glitch bursts.
@export var enabled: bool = true

# ── Private state ─────────────────────────────────────────────────────────────
var _mat: ShaderMaterial   # reference to the ShaderMaterial on the ColorRect
var _timer: Timer          # fires the next burst
var _active: bool = false  # true only during a burst

# ── Node references ──────────────────────────────────────────────────────────
@onready var _rect: ColorRect = $GlitchRect

func _ready() -> void:
	# Grab the shader material – it was set in the scene.
	_mat = _rect.material as ShaderMaterial

	# Ensure the overlay is invisible on start.
	_rect.visible = false
	_set_intensity(0.0)

	# Build the recurring interval timer once; never recreate it.
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)
	_schedule_next()

func _process(_delta: float) -> void:
	# Feed an ever-changing time seed so the shader noise animates during a burst.
	if _active:
		_mat.set_shader_parameter("time_seed", fmod(Time.get_ticks_msec() * 0.001, 1000.0))

# ── Glitch burst logic ───────────────────────────────────────────────────────

func _schedule_next() -> void:
	if not enabled:
		return
	var wait: float = randf_range(interval_min, interval_max)
	_timer.start(wait)

func _on_timer_timeout() -> void:
	if not enabled:
		return
	trigger_glitch()

## Trigger a single glitch burst programmatically (e.g. from another script).
func trigger_glitch(duration: float = -1.0) -> void:
	if _active:
		return  # don't stack bursts

	var burst_duration: float = duration if duration > 0.0 else randf_range(duration_min, duration_max)
	_push_shader_params()
	_rect.visible = true
	_active = true

	# Quick fade-in → hold → fade-out using a Tween.
	var t: Tween = create_tween()
	var fade_time: float = minf(0.04, burst_duration * 0.25)
	t.tween_method(_set_intensity, 0.0, peak_intensity, fade_time)
	t.tween_interval(burst_duration - fade_time * 2.0)
	t.tween_method(_set_intensity, peak_intensity, 0.0, fade_time)
	t.tween_callback(_on_burst_finished)

func _on_burst_finished() -> void:
	_active = false
	_rect.visible = false
	_set_intensity(0.0)
	_schedule_next()

# ── Helpers ──────────────────────────────────────────────────────────────────

func _set_intensity(value: float) -> void:
	_mat.set_shader_parameter("intensity", value)

func _push_shader_params() -> void:
	_mat.set_shader_parameter("displacement_str", displacement_strength)
	_mat.set_shader_parameter("rgb_split_str",    rgb_split_strength)
	_mat.set_shader_parameter("noise_density",    noise_density)
