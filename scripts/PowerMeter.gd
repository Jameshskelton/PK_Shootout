extends Control
## Power meter UI element.
## Fills from 0 to 1 while the player holds the shoot button,
## then reports the final power value on release.

signal power_released(power: float)

@onready var bar: ColorRect = $Bar
@onready var fill: ColorRect = $Bar/Fill

var _charging: bool = false
var _charge_start_time: float = 0.0
var _current_power: float = 0.0

const FILL_COLOR_LOW := Color(0.2, 0.8, 0.2)
const FILL_COLOR_MID := Color(0.9, 0.8, 0.2)
const FILL_COLOR_HIGH := Color(0.9, 0.3, 0.2)


func _ready() -> void:
	visible = false
	fill.size.x = 0


func get_current_power() -> float:
	return _current_power


func _process(delta: float) -> void:
	if _charging:
		var elapsed: float = Time.get_ticks_msec() / 1000.0 - _charge_start_time
		_current_power = clampf(elapsed / 1.2, 0.0, 1.0)
		_update_fill()


func start_charging() -> void:
	_charging = true
	_charge_start_time = Time.get_ticks_msec() / 1000.0
	_current_power = 0.0
	visible = true
	_update_fill()


func release() -> float:
	_charging = false
	var power := _current_power
	_current_power = 0.0
	visible = false
	fill.size.x = 0
	power_released.emit(power)
	return power


func _update_fill() -> void:
	var fill_width: float = bar.size.x * _current_power
	fill.size.x = fill_width

	if _current_power < 0.4:
		fill.color = FILL_COLOR_LOW
	elif _current_power < 0.75:
		fill.color = FILL_COLOR_MID
	else:
		fill.color = FILL_COLOR_HIGH
