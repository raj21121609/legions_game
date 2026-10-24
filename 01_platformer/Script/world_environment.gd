extends WorldEnvironment

# Array of high-contrast vibrant colors to cycle through against the black void
const CONTRAST_COLORS: Array[Color] = [
	Color(0.0, 0.9, 1.0),    # Electric Cyan
	Color(1.0, 0.0, 0.5),    # Hot Magenta / Pink
	Color(0.2, 1.0, 0.2),    # Neon Lime Green
	Color(1.0, 0.7, 0.0),    # Vivid Amber/Orange
	Color(0.6, 0.2, 1.0),    # Bright Violet / Purple
	Color(1.0, 0.2, 0.2)     # Crimson Red
]

var current_color_index: int = 0

func _ready() -> void:
	# Initialize the sky to pure black void and the first high-contrast accent color
	update_sky_colors(Color(0.0, 0.0, 0.0), CONTRAST_COLORS[current_color_index])

## Call this function from your player script whenever the jump counter updates
func update_jump_trigger(total_jumps: int) -> void:
	# Check if the jump count is a multiple of 7 and isn't zero
	if total_jumps > 0 and total_jumps % 3 == 0:
		# Cycle to the next color in our high-contrast preset list
		current_color_index = (current_color_index + 1) % CONTRAST_COLORS.size()
		
		# Explicitly type these variables as Color
		var next_accent_color: Color = CONTRAST_COLORS[current_color_index]
		var void_black: Color = Color(0.0, 0.0, 0.0)
		
		update_sky_colors(void_black, next_accent_color)

func update_sky_colors(void_color: Color, bright_color: Color) -> void:
	if environment and environment.sky and environment.sky.sky_material:
		# Explicitly type the material variable as ShaderMaterial
		var mat: ShaderMaterial = environment.sky.sky_material as ShaderMaterial
		
		if mat:
			# Sets the uniform values inside your custom sky shader code
			mat.set_shader_parameter("cosmic_void_color", void_color)
			mat.set_shader_parameter("energy_bright_color", bright_color)
