extends Node2D
## Root scene for the penalty shootout game.
## Manages the match state machine, score tracking, and orchestrates
## the aim/shot/keeper/resolution phases for both player and opponent turns.

# --- Enums ---

enum GameState {
	KICKOFF_INTRO,
	PLAYER_AIM,
	PLAYER_SHOT,
	RESOLVE,
	OPPONENT_TURN,
	CHECK_RESULT,
	MATCH_END,
}

enum ShotZone {
	TOP_LEFT,
	MID_LEFT,
	BOTTOM_LEFT,
	TOP_RIGHT,
	MID_RIGHT,
	BOTTOM_RIGHT,
	CENTER,
}

# --- Constants (tuning values from plan §10) ---

const KICKS_PER_TEAM: int = 5
const KEEPER_REACTION_DELAY: float = 0.15
const POWER_CHARGE_TIME: float = 1.2
const KEEPER_DIVE_DURATION: float = 0.4
const RESULT_PAUSE_DURATION: float = 1.5

# Reticle dimensions (placeholder — will be set by texture size at milestone 8)
const RETICLE_SIZE: float = 80.0
const RETICLE_HALF: float = 40.0

# Shot system constants
const BALL_TRAVEL_TIME: float = 0.5
const POWER_LOW_THRESHOLD: float = 0.3
const POWER_HIGH_THRESHOLD: float = 0.8
const JITTER_HIGH_POWER: float = 120.0
const MISS_OFFSET: float = 160.0

# Goalkeeper AI constants (~40% save rate target)
const KEEPER_DIVE_OFFSET_X: float = 120.0  # Horizontal offset for left/right dives
const KEEPER_DIVE_OFFSET_Y: float = 80.0  # Vertical offset for top/bottom zones
const KEEPER_SAVE_PROBABILITY: float = 0.4  # Exact zone match chance
const KEEPER_FINGERTIP_PROBABILITY: float = 0.15  # Adjacent zone fingertip save chance
const KEEPER_HOME_POSITION: Vector2 = Vector2(0, 80)  # Center of goal, slightly down from crossbar

# Opponent corner-weighted zone selection (from plan §4.4)
const OPPONENT_ZONE_WEIGHTS: Dictionary = {
	ShotZone.TOP_LEFT: 25.0,
	ShotZone.TOP_RIGHT: 25.0,
	ShotZone.BOTTOM_LEFT: 20.0,
	ShotZone.BOTTOM_RIGHT: 20.0,
	ShotZone.CENTER: 10.0,
}

# --- Match State ---

var state: GameState = GameState.KICKOFF_INTRO
var player_score: int = 0
var opponent_score: int = 0
var player_kicks_taken: int = 0
var opponent_kicks_taken: int = 0
var is_player_turn: bool = true
var in_sudden_death: bool = false
var sudden_death_round: int = 0

# --- Shot State ---
var is_charging: bool = false
var current_power: float = 0.0
var last_shot_target: Vector2 = Vector2.ZERO
var last_shot_power: float = 0.0
var last_shot_zone: ShotZone = ShotZone.CENTER
var _ball_tween: Tween

# --- Keeper State ---
var keeper_dive_zone: ShotZone = ShotZone.CENTER
var _keeper_tween: Tween

# --- Node References ---
# Note: Using ColorRect placeholders for now (milestone 0).
# These will be replaced with Sprite2D nodes when pixel-art
# assets are dropped in (milestone 8).

@onready var background: Sprite2D = $Background
@onready var goal: Node2D = $Goal
@onready var goal_frame: ColorRect = $Goal/GoalFrame
@onready var net: ColorRect = $Goal/Net
@onready var goalkeeper: Node2D = $Goal/Goalkeeper
@onready var ball: Node2D = $Ball
@onready var penalty_spot: Marker2D = $PenaltySpot
@onready var aim_reticle: Node2D = $AimReticle
@onready var power_meter: Control = $PowerMeter
@onready var ui: CanvasLayer = $UI
@onready var score_label: Label = $UI/ScoreLabel
@onready var round_indicator: Label = $UI/RoundIndicator
@onready var result_label: Label = $UI/ResultLabel
@onready var end_screen: Control = $UI/EndScreen


# --- Lifecycle ---

func _ready() -> void:
	end_screen.restart_requested.connect(_on_restart_requested)
	_start_match()


func _on_restart_requested() -> void:
	get_tree().reload_current_scene()


func _process(_delta: float) -> void:
	if state == GameState.PLAYER_AIM:
		_update_reticle()
	elif is_charging:
		current_power = power_meter.get_current_power()


# --- Aim System ---

func _get_goal_bounds() -> Rect2:
	var goal_pos: Vector2 = goal.position
	var goal_half_w: float = goal_frame.size.x / 2.0
	var goal_half_h: float = goal_frame.size.y / 2.0
	return Rect2(
		goal_pos.x - goal_half_w,
		goal_pos.y - goal_half_h,
		goal_frame.size.x,
		goal_frame.size.y
	)

func _update_reticle() -> void:
	var mouse_pos: Vector2 = get_local_mouse_position()
	var bounds: Rect2 = _get_goal_bounds()

	var clamped_x: float = clampf(mouse_pos.x, bounds.position.x + RETICLE_HALF, bounds.end.x - RETICLE_HALF)
	var clamped_y: float = clampf(mouse_pos.y, bounds.position.y + RETICLE_HALF, bounds.end.y - RETICLE_HALF)

	aim_reticle.position = Vector2(clamped_x, clamped_y)

func get_reticle_center() -> Vector2:
	return aim_reticle.position

func get_aim_zone() -> ShotZone:
	var center: Vector2 = get_reticle_center()
	var bounds: Rect2 = _get_goal_bounds()

	var is_left: bool = center.x < (bounds.position.x + bounds.size.x * 0.33)
	var is_right: bool = center.x > (bounds.position.x + bounds.size.x * 0.67)
	var is_top: bool = center.y < (bounds.position.y + bounds.size.y * 0.33)
	var is_bottom: bool = center.y > (bounds.position.y + bounds.size.y * 0.67)

	if is_left:
		if is_top:
			return ShotZone.TOP_LEFT
		elif is_bottom:
			return ShotZone.BOTTOM_LEFT
		return ShotZone.MID_LEFT
	elif is_right:
		if is_top:
			return ShotZone.TOP_RIGHT
		elif is_bottom:
			return ShotZone.BOTTOM_RIGHT
		return ShotZone.MID_RIGHT
	return ShotZone.CENTER


# --- Shot System ---

func _start_charging() -> void:
	if state != GameState.PLAYER_AIM:
		return
	is_charging = true
	current_power = 0.0
	power_meter.start_charging()


func _fire_shot() -> void:
	if not is_charging:
		return
	is_charging = false
	var power: float = power_meter.release()
	last_shot_power = power
	state = GameState.PLAYER_SHOT
	aim_reticle.visible = false

	var target: Vector2 = get_reticle_center()
	var target_zone: ShotZone = get_aim_zone()

	# Power-based accuracy: low power = slow ball, high power = jitter/miss risk
	if power < POWER_LOW_THRESHOLD:
		pass  # Weak but accurate; keeper has more time to save
	elif power > POWER_HIGH_THRESHOLD:
		# High power: apply random jitter to target position
		var jitter: Vector2 = Vector2(
			randf_range(-JITTER_HIGH_POWER, JITTER_HIGH_POWER),
			randf_range(-JITTER_HIGH_POWER, JITTER_HIGH_POWER)
		)
		target += jitter
		# ~20% chance of skying the ball completely (miss)
		if randf() < 0.2:
			target.y -= MISS_OFFSET
		# Recompute zone after jitter
		target_zone = _zone_from_position(target)

	last_shot_target = target
	last_shot_zone = target_zone

	# Keeper picks dive zone and dives with reaction delay
	keeper_dive_zone = _keeper_pick_dive_zone()
	get_tree().create_timer(KEEPER_REACTION_DELAY).timeout.connect(
		func() -> void: _keeper_dive_to_zone(keeper_dive_zone)
	)

	_tween_ball_to(target)

func _tween_ball_to(target: Vector2) -> void:
	var start_pos: Vector2 = _get_ball_center()
	var end_pos: Vector2 = target
	var travel_time: float = BALL_TRAVEL_TIME * (1.0 - last_shot_power * 0.3)

	if _ball_tween:
		_ball_tween.kill()
	_ball_tween = create_tween()
	_ball_tween.tween_method(
		func(t: float) -> void: _set_ball_center(start_pos.lerp(end_pos, t)),
		0.0, 1.0, travel_time
	)
	_ball_tween.tween_callback(_on_ball_arrived)

func _on_ball_arrived() -> void:
	_resolve_shot_fate()

func _resolve_shot_fate() -> void:
	var bounds: Rect2 = _get_goal_bounds()
	var ball_center: Vector2 = _get_ball_center()

	if not bounds.has_point(ball_center):
		_begin_resolve("MISS!")
		return

	var shot_zone: ShotZone = last_shot_zone
	if keeper_dive_zone == shot_zone:
		_begin_resolve("SAVED!")
	elif _is_adjacent_zone(keeper_dive_zone, shot_zone):
		if randf() < KEEPER_FINGERTIP_PROBABILITY:
			_begin_resolve("SAVED!")
		else:
			_begin_resolve("GOAL!")
	else:
		_begin_resolve("GOAL!")


# --- Goalkeeper AI ---

func _keeper_pick_dive_zone() -> ShotZone:
	return _keeper_pick_dive_zone_for(last_shot_zone)


func _keeper_pick_dive_zone_for(shot_zone: ShotZone) -> ShotZone:
	# 40% chance of choosing the exact zone the ball is going to -> SAVE
	if randf() < KEEPER_SAVE_PROBABILITY:
		return shot_zone

	# Otherwise, pick a random zone (but biased slightly toward corners)
	var weights: Dictionary = {
		ShotZone.TOP_LEFT: 20.0,
		ShotZone.TOP_RIGHT: 20.0,
		ShotZone.BOTTOM_LEFT: 18.0,
		ShotZone.BOTTOM_RIGHT: 18.0,
		ShotZone.MID_LEFT: 10.0,
		ShotZone.MID_RIGHT: 10.0,
		ShotZone.CENTER: 4.0,
	}
	var total_weight: float = 0.0
	for w in weights.values():
		total_weight += w

	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for zone in weights:
		cumulative += weights[zone]
		if roll <= cumulative:
			return zone

	return ShotZone.CENTER


func _zone_to_dive_position(zone: ShotZone) -> Vector2:
	# Goalkeeper position is relative to Goal node (local coords)
	# Goal center in local coords is (0, 0)
	var cx: float = 0.0
	var cy: float = 0.0

	match zone:
		ShotZone.TOP_LEFT:
			return Vector2(cx - KEEPER_DIVE_OFFSET_X, cy - KEEPER_DIVE_OFFSET_Y)
		ShotZone.MID_LEFT:
			return Vector2(cx - KEEPER_DIVE_OFFSET_X, cy)
		ShotZone.BOTTOM_LEFT:
			return Vector2(cx - KEEPER_DIVE_OFFSET_X, cy + KEEPER_DIVE_OFFSET_Y)
		ShotZone.TOP_RIGHT:
			return Vector2(cx + KEEPER_DIVE_OFFSET_X, cy - KEEPER_DIVE_OFFSET_Y)
		ShotZone.MID_RIGHT:
			return Vector2(cx + KEEPER_DIVE_OFFSET_X, cy)
		ShotZone.BOTTOM_RIGHT:
			return Vector2(cx + KEEPER_DIVE_OFFSET_X, cy + KEEPER_DIVE_OFFSET_Y)
		ShotZone.CENTER:
			return Vector2(cx + KEEPER_HOME_POSITION.x, cy + KEEPER_HOME_POSITION.y)
	return KEEPER_HOME_POSITION


func _keeper_dive_to_zone(zone: ShotZone) -> void:
	var target_pos: Vector2 = _zone_to_dive_position(zone)

	if _keeper_tween:
		_keeper_tween.kill()
	_keeper_tween = create_tween().set_parallel(true)
	# Dive animation: move + rotate for visual flair (in parallel)
	_keeper_tween.tween_property(goalkeeper, "position", target_pos, KEEPER_DIVE_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# Rotate the keeper slightly in the dive direction
	var target_rot: float = -15.0 if target_pos.x < goalkeeper.position.x else 15.0
	_keeper_tween.tween_property(goalkeeper, "rotation", deg_to_rad(target_rot), KEEPER_DIVE_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _reset_keeper() -> void:
	goalkeeper.position = KEEPER_HOME_POSITION
	goalkeeper.rotation = 0.0


func _is_adjacent_zone(a: ShotZone, b: ShotZone) -> bool:
	# Check if two zones share an edge (diagonal not adjacent)
	if a == b:
		return false
	var adjacent_pairs: Array = [
		[ShotZone.TOP_LEFT, ShotZone.MID_LEFT],
		[ShotZone.MID_LEFT, ShotZone.BOTTOM_LEFT],
		[ShotZone.TOP_RIGHT, ShotZone.MID_RIGHT],
		[ShotZone.MID_RIGHT, ShotZone.BOTTOM_RIGHT],
		[ShotZone.TOP_LEFT, ShotZone.CENTER],
		[ShotZone.TOP_RIGHT, ShotZone.CENTER],
		[ShotZone.BOTTOM_LEFT, ShotZone.CENTER],
		[ShotZone.BOTTOM_RIGHT, ShotZone.CENTER],
		[ShotZone.MID_LEFT, ShotZone.CENTER],
		[ShotZone.MID_RIGHT, ShotZone.CENTER],
		[ShotZone.TOP_LEFT, ShotZone.TOP_RIGHT],
		[ShotZone.BOTTOM_LEFT, ShotZone.BOTTOM_RIGHT],
	]
	for pair in adjacent_pairs:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


# --- Ball Helpers ---

func _get_ball_center() -> Vector2:
	return ball.position

func _set_ball_center(pos: Vector2) -> void:
	ball.position = pos

func _reset_ball_to_spot() -> void:
	_set_ball_center(penalty_spot.position)

func _zone_from_position(pos: Vector2) -> ShotZone:
	var bounds: Rect2 = _get_goal_bounds()
	var is_left: bool = pos.x < (bounds.position.x + bounds.size.x * 0.33)
	var is_right: bool = pos.x > (bounds.position.x + bounds.size.x * 0.67)
	var is_top: bool = pos.y < (bounds.position.y + bounds.size.y * 0.33)
	var is_bottom: bool = pos.y > (bounds.position.y + bounds.size.y * 0.67)

	if is_left:
		if is_top:
			return ShotZone.TOP_LEFT
		elif is_bottom:
			return ShotZone.BOTTOM_LEFT
		return ShotZone.MID_LEFT
	elif is_right:
		if is_top:
			return ShotZone.TOP_RIGHT
		elif is_bottom:
			return ShotZone.BOTTOM_RIGHT
		return ShotZone.MID_RIGHT
	return ShotZone.CENTER


# --- Match Flow ---

func _start_match() -> void:
	player_score = 0
	opponent_score = 0
	player_kicks_taken = 0
	opponent_kicks_taken = 0
	is_player_turn = true
	in_sudden_death = false
	sudden_death_round = 0

	state = GameState.KICKOFF_INTRO
	aim_reticle.visible = false
	power_meter.visible = false
	result_label.text = "GET READY!"
	result_label.visible = true
	_reset_ball_to_spot()
	_reset_keeper()
	_update_ui()

	await get_tree().create_timer(2.0).timeout
	result_label.visible = false
	_begin_player_aim()


func _begin_player_aim() -> void:
	state = GameState.PLAYER_AIM
	aim_reticle.visible = true
	power_meter.visible = false
	is_charging = false
	current_power = 0.0
	_reset_ball_to_spot()
	_reset_keeper()
	_update_ui()


func _begin_resolve(result: String) -> void:
	state = GameState.RESOLVE
	aim_reticle.visible = false

	if result == "GOAL!":
		if is_player_turn:
			player_score += 1
			player_kicks_taken += 1
		else:
			opponent_score += 1
			opponent_kicks_taken += 1
	else:
		if is_player_turn:
			player_kicks_taken += 1
		else:
			opponent_kicks_taken += 1

	result_label.text = result
	result_label.visible = true
	_update_ui()

	await get_tree().create_timer(RESULT_PAUSE_DURATION).timeout
	result_label.visible = false
	_advance_turn()


func _begin_opponent_turn() -> void:
	state = GameState.OPPONENT_TURN
	aim_reticle.visible = false
	power_meter.visible = false
	_reset_ball_to_spot()
	_reset_keeper()
	_update_ui()

	await get_tree().create_timer(0.8).timeout

	# Opponent picks zone (corner-weighted) and power
	var opp_zone: ShotZone = _opponent_pick_zone()
	var opp_power: float = _opponent_pick_power()

	# Compute target position from zone
	var opp_target: Vector2 = _zone_to_world_position(opp_zone)

	# High power jitter (same rules as player)
	if opp_power > POWER_HIGH_THRESHOLD:
		var jitter: Vector2 = Vector2(
			randf_range(-JITTER_HIGH_POWER, JITTER_HIGH_POWER),
			randf_range(-JITTER_HIGH_POWER, JITTER_HIGH_POWER)
		)
		opp_target += jitter
		if randf() < 0.2:
			opp_target.y -= MISS_OFFSET
		opp_zone = _zone_from_position(opp_target)

	# Keeper (player's side) picks dive zone — same ~40% logic
	keeper_dive_zone = _keeper_pick_dive_zone_for(opp_zone)

	# Keeper dives with reaction delay
	get_tree().create_timer(KEEPER_REACTION_DELAY).timeout.connect(
		func() -> void: _keeper_dive_to_zone(keeper_dive_zone)
	)

	# Tween ball from spot to target
	var travel_time: float = BALL_TRAVEL_TIME * (1.0 - opp_power * 0.3)
	if _ball_tween:
		_ball_tween.kill()
	_ball_tween = create_tween()
	_ball_tween.tween_method(
		func(t: float) -> void: _set_ball_center(penalty_spot.position.lerp(opp_target, t)),
		0.0, 1.0, travel_time
	)
	_ball_tween.tween_callback(func() -> void: _resolve_opponent_shot(opp_zone, opp_target))


func _resolve_opponent_shot(shot_zone: ShotZone, ball_pos: Vector2) -> void:
	var bounds: Rect2 = _get_goal_bounds()

	if not bounds.has_point(ball_pos):
		_begin_resolve("MISS!")
		return

	if keeper_dive_zone == shot_zone:
		_begin_resolve("SAVED!")
	elif _is_adjacent_zone(keeper_dive_zone, shot_zone):
		if randf() < KEEPER_FINGERTIP_PROBABILITY:
			_begin_resolve("SAVED!")
		else:
			_begin_resolve("GOAL!")
	else:
		_begin_resolve("GOAL!")


# --- Opponent AI ---

func _opponent_pick_zone() -> ShotZone:
	var total_weight: float = 0.0
	for w in OPPONENT_ZONE_WEIGHTS.values():
		total_weight += w

	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for zone in OPPONENT_ZONE_WEIGHTS:
		cumulative += OPPONENT_ZONE_WEIGHTS[zone]
		if roll <= cumulative:
			return zone

	return ShotZone.CENTER


func _opponent_pick_power() -> float:
	# Weighted power: mostly mid-high range, occasionally weak
	var roll: float = randf()
	if roll < 0.15:
		return randf_range(0.1, 0.3)
	elif roll < 0.65:
		return randf_range(0.4, 0.7)
	else:
		return randf_range(0.75, 1.0)


func _zone_to_world_position(zone: ShotZone) -> Vector2:
	var bounds: Rect2 = _get_goal_bounds()
	var col_third: float = bounds.size.x / 3.0
	var row_third: float = bounds.size.y / 3.0

	match zone:
		ShotZone.TOP_LEFT:
			return Vector2(bounds.position.x + col_third * 0.5, bounds.position.y + row_third * 0.5)
		ShotZone.MID_LEFT:
			return Vector2(bounds.position.x + col_third * 0.5, bounds.position.y + row_third * 1.5)
		ShotZone.BOTTOM_LEFT:
			return Vector2(bounds.position.x + col_third * 0.5, bounds.position.y + row_third * 2.5)
		ShotZone.TOP_RIGHT:
			return Vector2(bounds.position.x + col_third * 2.5, bounds.position.y + row_third * 0.5)
		ShotZone.MID_RIGHT:
			return Vector2(bounds.position.x + col_third * 2.5, bounds.position.y + row_third * 1.5)
		ShotZone.BOTTOM_RIGHT:
			return Vector2(bounds.position.x + col_third * 2.5, bounds.position.y + row_third * 2.5)
		ShotZone.CENTER:
			return Vector2(bounds.position.x + col_third * 1.5, bounds.position.y + row_third * 1.5)
	return bounds.get_center()


func _advance_turn() -> void:
	if is_player_turn:
		is_player_turn = false
		_begin_opponent_turn()
	else:
		is_player_turn = true
		_check_match_state()


func _check_match_state() -> void:
	state = GameState.CHECK_RESULT

	# Calculate remaining kicks per team
	var player_remaining: int = KICKS_PER_TEAM - player_kicks_taken
	var opponent_remaining: int = KICKS_PER_TEAM - opponent_kicks_taken

	# Not in sudden death yet — check if match can end early
	if not in_sudden_death:
		# If both teams have completed all kicks
		if player_kicks_taken == KICKS_PER_TEAM and opponent_kicks_taken == KICKS_PER_TEAM:
			if player_score != opponent_score:
				_end_match()
				return
			else:
				in_sudden_death = true
				sudden_death_round = KICKS_PER_TEAM

		# Early win check: can the trailing team catch up?
		elif player_kicks_taken == KICKS_PER_TEAM:
			# Player is done — opponent still has kicks left
			if player_score > opponent_score + opponent_remaining:
				_end_match()
				return
		elif opponent_kicks_taken == KICKS_PER_TEAM:
			# Opponent is done — player still has kicks left
			if opponent_score > player_score + player_remaining:
				_end_match()
				return
		else:
			# Both still kicking — check if leader is uncatchable
			if player_score > opponent_score + opponent_remaining:
				_end_match()
				return
			elif opponent_score > player_score + player_remaining:
				_end_match()
				return

	# In sudden death — after one full round (both teams have kicked)
	if in_sudden_death:
		if player_kicks_taken > sudden_death_round and opponent_kicks_taken > sudden_death_round:
			if player_score != opponent_score:
				_end_match()
				return
			else:
				sudden_death_round += 1

	_update_ui()
	_begin_player_aim()


func _end_match() -> void:
	state = GameState.MATCH_END
	aim_reticle.visible = false
	power_meter.visible = false

	var victory: bool = player_score > opponent_score
	await get_tree().create_timer(0.3).timeout
	end_screen.show_result(victory, player_score, opponent_score, in_sudden_death)


# --- UI ---

func _update_ui() -> void:
	score_label.text = "YOU %d - %d OPP" % [player_score, opponent_score]
	if in_sudden_death:
		round_indicator.text = "Sudden Death"
	elif is_player_turn:
		round_indicator.text = "Your turn - Kick %d of %d" % [player_kicks_taken + 1, KICKS_PER_TEAM]
	else:
		round_indicator.text = "Opponent's turn - Kick %d of %d" % [opponent_kicks_taken + 1, KICKS_PER_TEAM]


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if state == GameState.PLAYER_AIM:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					_start_charging()
				else:
					_fire_shot()
	elif state == GameState.MATCH_END:
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
