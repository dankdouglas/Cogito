extends CogitoWieldable

@export_group("Laser Rifle Settings")
@export var firing_delay : float = 0.05
@onready var bullet_point: Node3D = %Bullet_Point
@export var laser_ray_prefab : PackedScene
@export var ray_lifespan : float = 5.0
@export var ads_fov = 65
@export var default_position : Vector3

@export_group("Audio")
@export var sound_primary_use : AudioStream
@export var sound_secondary_use : AudioStream
@export var sound_reload : AudioStream

var spawn_node : Node
var is_firing : bool = false

var firing_cooldown : float
var player_rid : RID

var inventory_item_reference : WieldableItemPD

@export_group("Recoil Settings")
@export var recoil_strength : float = 1.0
@export var recoil_recovery_speed : float = 5.0

@export var recoil_offset : Vector2 = Vector2.ZERO

func _ready():
	wieldable_mesh.hide()
	firing_cooldown = 0
	player_rid = CogitoSceneManager._current_player_node.get_rid()

func _physics_process(delta: float) -> void:
	if firing_cooldown > 0:
		firing_cooldown -= delta
		
	if is_firing:
		if firing_cooldown <= 0:
			if animation_player.is_playing():
				return
			var _camera_collision = player_interaction_component.Get_Camera_Collision()
			hit_scan_collision(_camera_collision)
			animation_player.play(anim_action_primary)
			audio_stream_player_3d.stream = sound_primary_use
			audio_stream_player_3d.play()
			inventory_item_reference.subtract(1)
			
			if inventory_item_reference.charge_current <= 0:
				is_firing = false
			
			firing_cooldown = firing_delay
	
	recover_recoil(delta)
	var camera = get_node_or_null("/root/Node3D/CogitoPlayer/Body/Neck/Head")
	#camera.rotation_degrees.x += recoil_offset.y
	#camera.rotation_degrees.y += recoil_offset.x

func action_primary(_passed_item_reference : InventoryItemPD, _is_released: bool):
	inventory_item_reference = _passed_item_reference
	
	if !_is_released and inventory_item_reference.charge_current <= 0:
		inventory_item_reference.send_empty_hint()
		return
	if _is_released and inventory_item_reference.charge_current <= 0:
		return
	
	if _is_released:
		is_firing = false
	else:
		is_firing = true
		apply_recoil()

func action_secondary(is_released: bool):
	var camera = get_viewport().get_camera_3d()
	if is_released:
		var tween_cam = get_tree().create_tween()
		tween_cam.tween_property(camera, "fov", 75, .2)
		var tween_pistol = get_tree().create_tween()
		tween_pistol.tween_property(self, "position", default_position, .2)
	else:
		var tween_cam = get_tree().create_tween()
		tween_cam.tween_property(camera, "fov", ads_fov, .2)
		var tween_pistol = get_tree().create_tween()
		tween_pistol.tween_property(self, "position", Vector3(0, default_position.y, default_position.z), .2)

func hit_scan_collision(collision_point: Vector3):
	var bullet_direction = (collision_point - bullet_point.get_global_transform().origin).normalized()
	var new_intersection = PhysicsRayQueryParameters3D.create(bullet_point.get_global_transform().origin, collision_point + bullet_direction * 2)
	new_intersection.exclude = [player_rid]
	
	var bullet_collision = get_world_3d().direct_space_state.intersect_ray(new_intersection)
	
	var instantiated_ray = laser_ray_prefab.instantiate()
	instantiated_ray.draw_ray(bullet_point.get_global_transform().origin, collision_point)
	spawn_node.add_child(instantiated_ray)
	
	if bullet_collision:
		hit_scan_damage(bullet_collision.collider)

func hit_scan_damage(collider):
	if collider.has_signal("damage_received"):
		collider.damage_received.emit(item_reference.wieldable_damage)

func reload():
	animation_player.play(anim_reload)
	audio_stream_player_3d.stream = sound_reload
	audio_stream_player_3d.play()

func equip(_player_interaction_component: PlayerInteractionComponent):
	spawn_node = get_tree().get_current_scene()
	animation_player.play(anim_equip)
	player_interaction_component = _player_interaction_component

func apply_recoil():

	var recoil_y = recoil_strength
	recoil_offset += Vector2(0, recoil_y)

func recover_recoil(delta: float):
	recoil_offset = recoil_offset.lerp(Vector2.ZERO, recoil_recovery_speed * delta)
