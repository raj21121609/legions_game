extends ProgressBar

# Keep a local reference to the custom stylebox to modify its background color directly
var fill_stylebox: StyleBoxFlat

func _ready() -> void:
	# 1. Create a duplicate of the existing stylebox so we don't accidentally edit 
	#    other progress bars globally using the same theme resource
	var base_stylebox := get_theme_stylebox("fill")
	if base_stylebox is StyleBoxFlat:
		fill_stylebox = base_stylebox.duplicate()
	else:
		fill_stylebox = StyleBoxFlat.new()
		
	# 2. Apply our local override stylebox to the fill theme property
	add_theme_stylebox_override("fill", fill_stylebox)
	
	# 3. Connect to the value_changed signal built into ProgressBar/Range nodes
	value_changed.connect(_on_value_changed)
	
	# Trigger the initial color update based on the default starting health
	_on_value_changed(value)

func _on_value_changed(new_value: float) -> void:
	# Calculate a 0.0 to 1.0 ratio based on current value vs min/max values
	var ratio: float = (new_value - min_value) / (max_value - min_value)
	
	# Linearly interpolate (lerp) from red (low health) to green (full health)
	# ratio = 0.0 results in red, ratio = 1.0 results in green
	var target_color: Color = Color.RED.lerp(Color.GREEN, ratio)
	
	# Apply the color to our stylebox fill
	fill_stylebox.bg_color = target_color
