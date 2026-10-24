
extends CanvasLayer

@onready var dialogue_text: Label = $Panel/DialogueText
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer

var dialogue_lines: Array[Dictionary] = [
	{
		"text": "Badiya kal se tehelna shuru",
		"audio": "res://audi/l11.ogg"
	},
	{
		"text": "sir band keh raha he 8 kadam chal 7 samose haye hisaab kuch mil nahi Raha hai ",
		"audio": "res://audi/l12.ogg"
	}
]

var current_line := 0
var is_playing_dialogue := false


func _ready() -> void:
	hide()
	audio_player.finished.connect(_on_audio_finished)


func start_dialogue() -> void:
	if is_playing_dialogue:
		return

	is_playing_dialogue = true
	current_line = 0
	show_line()


func show_line() -> void:
	if current_line >= dialogue_lines.size():
		end_dialogue()
		return

	var line: Dictionary = dialogue_lines[current_line]
	dialogue_text.text = line["text"]

	var audio_path: String = line["audio"]
	var audio_file: AudioStream = load(audio_path) as AudioStream

	if audio_file == null:
		push_error("Could not load dialogue audio: " + audio_path)
		current_line += 1
		show_line()
		return

	audio_player.stream = audio_file
	audio_player.play()


func _on_audio_finished() -> void:
	current_line += 1
	show_line()


func end_dialogue() -> void:
	audio_player.stop()
	hide()
	is_playing_dialogue = false
