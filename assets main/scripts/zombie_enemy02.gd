extends CharacterBody3D

signal damage_received(damage_value:float)

var player = null
var state_machine
var attack_cooldown : float = 0 #Value used for attack frequency

@export var SPEED = 3.0
@export var ATTACK_RANGE: float = 2.0
@export var attack_interval: float = 2.0
@export var attack_stagger: float = 8.0
@export var attack_sound : AudioStream
@export var attack_damage: int = 10

@onready var nav_agent = $NavigationAgent3D
@onready var anim_player = $AnimationPlayer
@onready var state_chart = $StateChart
@export var detection_area : Area3D
@export var detection_ray : RayCast3D


var patrol_path_nodepath : NodePath
## Reference to Patrol Path Node
@export var patrol_path : CogitoPatrolPath
## Distance threshold in which the enemy will stop (to make patrolling smoother)
@export var patrol_point_threshold : float = 0.4
## Time the enemy will wait at each patrol point
@export var patrol_point_wait_time : float = 2.0

@export var patrol_speed: float = 3.0

 #State for saving. Used to correctly load/save enemy state.
var is_waiting : bool = false
var patrol_point_index: int = 0 #Patrol point for patrolling
var chase_target : Node3D = null #Target for chasing

var knockback_force: Vector3 = Vector3.ZERO
var knockback_timer: float = 0.0
@export var knockback_duration: float = 0.5
@export var knockback_strength: float = 10.0

var can_attack = false


var last_known_position = null

# Called when the node enters the scene tree for the first time.
func _ready():
	player = CogitoSceneManager._current_player_node
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if _target_in_range():
		state_chart.send_event("start_attack")
	detection_ray.look_at(player.global_position, Vector3.UP)


	
func _handle_chasing():
	var look_ahead := Vector3(global_position.x + velocity.x, global_position.y, global_position.z + velocity.z)
	_look_at_target_interpolated(look_ahead)
	nav_agent.set_target_position(player.global_transform.origin)
	var next_nav_point = nav_agent.get_next_path_position()
	velocity = (next_nav_point - global_transform.origin).normalized() * SPEED
	move_and_slide()
	last_known_position = player.global_transform.origin
	
	if _on_vision_timer_timeout():
		state_chart.send_event("player_spotted")
	else:
			state_chart.send_event("player_out_of_sight")
	
func _handle_investigate():

	var look_ahead := Vector3(global_position.x + velocity.x, global_position.y, global_position.z + velocity.z)
	_look_at_target_interpolated(look_ahead)
	nav_agent.set_target_position(last_known_position)
	var next_nav_point = nav_agent.get_next_path_position()
	velocity = (next_nav_point - global_transform.origin).normalized() * SPEED

	move_and_slide()
	if _on_vision_timer_timeout():
		state_chart.send_event("player_spotted")
	elif global_transform.origin.distance_to(last_known_position) < 3.0:
		state_chart.send_event("player_out_of_sight")
	
	
	
func handle_patrolling(_delta: float):
	if _on_vision_timer_timeout():
		state_chart.send_event("player_spotted")
	if !patrol_path:
		CogitoGlobals.debug_log(true,"cogito_basic_enemy.gd","No patrol path found. Switching to idle.")
		state_chart.send_event("to_idle")
		return
	
	if !is_waiting:
		anim_player.play("run")
		if patrol_path.patrol_points.size() <= 0:
			CogitoGlobals.debug_log(true,"cogito_basic_enemy.gd","Patrol points array is empty. Switching to idle.")
			state_chart.send_event("to_idle")
			return
		if global_position.distance_to(patrol_path.patrol_points[patrol_point_index].global_position) < patrol_point_threshold:
			is_waiting = true
			anim_player.play("idle")
			await get_tree().create_timer(patrol_point_wait_time).timeout
			# Checking to see if we've reached the end of the patrol point list.
			if patrol_point_index == patrol_path.patrol_points.size() - 1:
				# If yes, we're starting over.
				patrol_point_index = 0
			else:
				# If no, we're going to the next point:
				patrol_point_index += 1
			is_waiting = false
		
		else:
			var look_ahead := Vector3(global_position.x + velocity.x, global_position.y, global_position.z + velocity.z)
			_look_at_target_interpolated(look_ahead)
			
			# Move towards patrol point
			move_toward_target(patrol_path.patrol_points[patrol_point_index],patrol_speed)

func load_patrol_points():
	if patrol_path_nodepath:
		CogitoGlobals.debug_log(true,"cogito_basic_enemy.gd","Loading patrol path: " + str(patrol_path_nodepath))
		patrol_path = get_node(patrol_path_nodepath)

	
func move_toward_target(target: Node3D, passed_speed:float):
	if !target: return
	
	nav_agent.set_target_position(target.global_position)
	var next_nav_point = nav_agent.get_next_path_position()
	velocity = (next_nav_point - global_position).normalized() * passed_speed
	move_and_slide()
	
func _look_at_target_interpolated(look_direction: Vector3) -> void:
	var look_at_target = global_position.direction_to(look_direction)
	var look_at_target_xz := Vector3(look_at_target.x, 0, look_at_target.z)
	var target_basis= Basis.looking_at(look_at_target_xz)
	basis = basis.slerp(target_basis, 0.2)

func _target_in_range() -> bool:
	return global_position.distance_to(player.global_position) < ATTACK_RANGE
	
func _swing_finished():
	if global_position.distance_to(player.global_position) < ATTACK_RANGE+ 1.2:
		attack(player)

func attack(target: Node3D):
	attack_cooldown = attack_interval
	CogitoGlobals.debug_log(true,"cogito_basic_enemy.gd","Enemy attacks!")
	var dir = global_position.direction_to(target.global_position)
	if attack_sound:
		Audio.play_sound_3d(attack_sound).global_position = self.global_position
	
	if target is CogitoPlayer:
		target.apply_external_force(dir * attack_stagger)
		#CogitoMain.debug_log(true,"cogito_basic_enemy.gd","Enemy attack: Applying vector " + dir * attack_stagger + " to target. Target.main_velocity = " + target.main_velocity.length())
		target.decrease_attribute("health", attack_damage)
	
func _on_vision_timer_timeout() -> bool:


	var overlaps = detection_area.get_overlapping_bodies()
	if overlaps.size() > 0:
		for overlap in overlaps:
			if overlap.name == "CogitoPlayer":
				var playerPosition = overlap.global_transform.origin
				detection_ray.look_at(playerPosition, Vector3.UP)
				detection_ray.force_raycast_update()
				
				if detection_ray.is_colliding():
					var collider = detection_ray.get_collider()
					
					if collider.name == "CogitoPlayer":
						detection_ray.debug_shape_custom_color = Color(174,0,0)
						state_chart.send_event("player_spotted")
						return true
						
					else:
						detection_ray.debug_shape_custom_color = Color(0,255,0)
						
	return false

func _on_idle_state_processing(delta):
	anim_player.play("idle")

func _on_chase_state_physics_processing(delta):
	anim_player.play("run")
	_handle_chasing()

func _on_invesigate_state_physics_processing(delta):
	anim_player.play("run")
	_handle_investigate()

func _on_alert_state_processing(delta):
	anim_player.play("look around")

func _on_attack_state_processing(delta):
	anim_player.play("attack")
	if !_target_in_range():
		state_chart.send_event("player_out_of_sight")

func _on_patrol_state_physics_processing(delta):
	handle_patrolling(delta)
	
func apply_knockback(direction: Vector3):
	knockback_force = direction.normalized() * knockback_strength
	knockback_timer = knockback_duration


func _on_health_attribute_damage_taken():
	state_chart.send_event("alerted")


func _on_area_3d_body_entered(body):
	print("ambush")
	if body.name == "CogitoPlayer":
		print("ambush2")
		state_chart.send_event("player_spotted")
