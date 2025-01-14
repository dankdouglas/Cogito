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
@onready var anim_tree = $AnimationTree



# Called when the node enters the scene tree for the first time.
func _ready():
	player = CogitoSceneManager._current_player_node
	state_machine = anim_tree.get("parameters/playback")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	match state_machine.get_current_node():
		"run":
			var look_ahead := Vector3(global_position.x + velocity.x, global_position.y, global_position.z + velocity.z)
			_look_at_target_interpolated(look_ahead)
			nav_agent.set_target_position(player.global_transform.origin)
			var next_nav_point = nav_agent.get_next_path_position()
			velocity = (next_nav_point - global_transform.origin).normalized() * SPEED
			move_and_slide()
		"attack":
			_look_at_target_interpolated(player.global_transform.origin)
		"idle":
			pass
	
	anim_tree.set("parameters/conditions/attack",_target_in_range())
	#anim_tree.set("parameters/conditions/run",!_target_in_range())

	
	
	
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
	CogitoMain.debug_log(true,"cogito_basic_enemy.gd","Enemy attacks!")
	var dir = global_position.direction_to(target.global_position)
	if attack_sound:
		Audio.play_sound_3d(attack_sound).global_position = self.global_position
	
	if target is CogitoPlayer:
		target.apply_external_force(dir * attack_stagger)
		#CogitoMain.debug_log(true,"cogito_basic_enemy.gd","Enemy attack: Applying vector " + dir * attack_stagger + " to target. Target.main_velocity = " + target.main_velocity.length())
		target.decrease_attribute("health", attack_damage)

func switch_to_attack():
	anim_tree.set("parameters/conditions/spotted",true)

func _on_detection_area_body_entered(body):
		if body.is_in_group("Player"):
			switch_to_attack()

func _on_detection_area_body_exited(body):
	pass
	#anim_tree.set("parameters/conditions/lost",true)
