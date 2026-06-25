extends Control
## End-game overlay shown when the match concludes.
## Displays victory/defeat, final score, sudden-death detail, and a
## restart button. Fades in via a tween.

signal restart_requested

@onready var dimmer: ColorRect = $Dimmer
@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/TitleLabel
@onready var score_label: Label = $Panel/ScoreLabel
@onready var detail_label: Label = $Panel/DetailLabel
@onready var restart_button: Button = $Panel/RestartButton

const FADE_DURATION: float = 0.5
const DIM_COLOR: Color = Color(0, 0, 0, 0.6)


func _ready() -> void:
	visible = false
	dimmer.color = Color(0, 0, 0, 0)
	restart_button.pressed.connect(_on_restart_pressed)


func show_result(victory: bool, p_score: int, o_score: int, sudden_death: bool) -> void:
	if victory:
		title_label.text = "YOU WIN!"
		title_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
		if sudden_death:
			detail_label.text = "Sudden Death Victory"
		else:
			detail_label.text = "Regulation Win"
	else:
		title_label.text = "YOU LOSE"
		title_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
		if sudden_death:
			detail_label.text = "Sudden Death Defeat"
		else:
			detail_label.text = "Better luck next time"

	score_label.text = "Final Score:  YOU %d - %d OPP" % [p_score, o_score]

	visible = true
	_fade_in()


func _fade_in() -> void:
	dimmer.color = Color(0, 0, 0, 0)
	panel.modulate.a = 0.0

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(dimmer, "color", DIM_COLOR, FADE_DURATION)
	tween.tween_property(panel, "modulate:a", 1.0, FADE_DURATION)


func _on_restart_pressed() -> void:
	restart_requested.emit()


func hide_screen() -> void:
	visible = false
	dimmer.color = Color(0, 0, 0, 0)
